import '../services/hive_service.dart';
import '../services/seed_service.dart';
import '../utils/date_utils.dart';
import '../../shared/repositories/plan_generator.dart';
import '../../shared/repositories/plan_engine/warmup_cooldown.dart';

/// Result returned by [WorkoutScheduleService.swapExerciseInDay].
///
/// Holds enough metadata for the AI coach dispatcher (Phase A.8) to
/// render a "Swapped X for Y in today's workout" success state without
/// re-reading Hive.
class SwapExerciseResult {
  /// `YYYY-MM-DD` date string the swap was applied to.
  final String date;

  /// Library `id` of the exercise that was removed.
  final String fromExerciseId;

  /// Display name of the exercise that was removed.
  final String fromExerciseName;

  /// Library `id` of the exercise that was inserted.
  final String toExerciseId;

  /// Display name of the exercise that was inserted.
  final String toExerciseName;

  /// 0-based position in the day's `exercises` array where the swap occurred.
  final int positionInWorkout;

  const SwapExerciseResult({
    required this.date,
    required this.fromExerciseId,
    required this.fromExerciseName,
    required this.toExerciseId,
    required this.toExerciseName,
    required this.positionInWorkout,
  });
}

/// Typed failure modes for [WorkoutScheduleService.swapExerciseInDay].
///
/// The dispatcher inspects [code] to map to a user-facing message:
///   - `no_schedule` — no `schedule_<date>` entry exists for the date.
///   - `exercise_not_in_workout` — the source exercise isn't in that day.
///   - `exercise_not_found` — the target exercise isn't in exerciseBox or
///     customBox. Catches typos and stale ids.
///   - `workout_completed` — the day is already marked completed; swap is
///     refused so history stays sacred. Use [EditWorkoutLogSheet] instead
///     for post-completion changes.
///   - `other` — anything else (defensive catch-all).
class SwapExerciseException implements Exception {
  final String code;
  final String message;
  const SwapExerciseException(this.code, this.message);
  @override
  String toString() => 'SwapExerciseException($code): $message';
}

/// Result returned by [WorkoutScheduleService.shortenDay].
///
/// Carries enough metadata for the AI coach dispatcher to render a
/// "Shortened today's workout from N exercises to M (≈X min)" snackbar
/// without re-reading Hive.
class ShortenDayResult {
  /// `YYYY-MM-DD` date string the trim was applied to.
  final String date;

  /// Exercise count before trimming.
  final int originalExerciseCount;

  /// Exercise count after trimming.
  final int trimmedExerciseCount;

  /// Estimated session minutes before trimming.
  final int estimatedOriginalMinutes;

  /// Estimated session minutes after trimming.
  final int estimatedTrimmedMinutes;

  /// Display names of the exercises that were dropped (in priority order,
  /// lowest priority first — i.e. accessory work first).
  final List<String> droppedExerciseNames;

  const ShortenDayResult({
    required this.date,
    required this.originalExerciseCount,
    required this.trimmedExerciseCount,
    required this.estimatedOriginalMinutes,
    required this.estimatedTrimmedMinutes,
    required this.droppedExerciseNames,
  });
}

/// Typed failure modes for [WorkoutScheduleService.shortenDay].
///
/// Codes:
///   - `no_schedule` — no `schedule_<date>` entry exists for the date.
///   - `workout_completed` — the day is already marked completed; trim is
///     refused so history stays sacred.
///   - `target_too_low` — even keeping just the 2 highest-priority
///     compounds would exceed the requested target. User needs to extend
///     the time budget.
///   - `other` — anything else (defensive catch-all).
class ShortenDayException implements Exception {
  final String code;
  final String message;
  const ShortenDayException(this.code, this.message);
  @override
  String toString() => 'ShortenDayException($code): $message';
}

/// Maps generated plan days to real calendar dates and persists to Hive.
///
/// This is the glue between PlanGenerator (logical days) and the UI
/// (calendar dates). It writes `scheduled_workouts` into Hive workoutBox
/// so both Dashboard calendar and Workout screen read from the same source.
class WorkoutScheduleService {
  WorkoutScheduleService._();
  static final WorkoutScheduleService _instance = WorkoutScheduleService._();
  static WorkoutScheduleService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  // ── Keys ────────────────────────────────────────────────────────

  static const String _planKey = 'current_plan';
  static const String _schedulePrefix = 'schedule_'; // schedule_2026-03-24
  static const String _displacedPrefix = 'displaced_'; // displaced_2026-03-24
  static const String _planStartKey = 'plan_start_date';
  static const String _planEndKey = 'plan_end_date';
  static const String _swapsThisWeekKey = 'swaps_this_week';
  static const String _swapWeekStartKey = 'swap_week_start';
  static const String _travelStartKey = 'travel_start';
  static const String _travelEndKey = 'travel_end';

  // ── Generate & Schedule ─────────────────────────────────────────

  /// Generates a plan and maps it to calendar dates starting from [startDate].
  ///
  /// [daysPerWeek]: How many workout days per week (3-6).
  /// [startDate]: First day of Week 1. Should be a Monday.
  ///
  /// Returns the generated [Phase] for the animation screen to display.
  Future<Phase> generateAndSchedule({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime startDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    // V3 parameters (optional — callers thread when profile has them)
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    // Guard: ensure exercise data is seeded before generation.
    // If exerciseBox is empty, PlanGenerator will produce 0-exercise workouts.
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    // 1. Generate the plan
    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );

    // 2. Get the day assignment pattern for the week
    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);

    // 3. Map to calendar dates (4 weeks × 7 days = 28 days)
    final workoutBox = _hive.workoutBox;
    final configBox = _hive.configBox;

    // Normalize startDate to Monday
    final monday = _normalizeToMonday(startDate);
    final endDate = monday.add(const Duration(days: 27)); // 4 weeks

    // Save plan metadata
    await configBox.put(_planStartKey, monday.toIso8601String());
    await configBox.put(_planEndKey, endDate.toIso8601String());
    await workoutBox.put(_planKey, plan.toMap());
    if (preferredDays != null) {
      await configBox.put('preferred_training_days', preferredDays);
    }

    // 4. For each of the 4 weeks, assign workouts to the pattern days.
    //    V2: each week reads from its own weekPlan for distinct exercises.
    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final isWorkoutDay = dayPattern.contains(dayOfWeek);

        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await workoutBox.put('$_schedulePrefix$dateKey', {
            'date': dateKey,
            'week': week + 1,
            'day_of_week': dayOfWeek, // 0=Mon, 6=Sun
            'type': 'workout',
            'workout_day_index': workoutDayIndex,
            'workout_name': workoutDay.name,
            'workout_focus': workoutDay.focus,
            'exercises': workoutDay.exercises.map((e) => e.toMap()).toList(),
            if (workoutDay.warmup.isNotEmpty)
              'warmup': workoutDay.warmup.map((e) => e.toMap()).toList(),
            if (workoutDay.cooldown.isNotEmpty)
              'cooldown': workoutDay.cooldown.map((e) => e.toMap()).toList(),
            if (workoutDay.finisher.isNotEmpty)
              'finisher': workoutDay.finisher.map((e) => e.toMap()).toList(),
            'week_character': weekPlan.weekCharacter,
            'status': 'planned', // planned | completed | skipped | shifted
            'completed_at': null,
            'is_swapped': false,
            'original_date': null, // set if swapped from another date
          });
          workoutDayIndex++;
        } else {
          await workoutBox.put('$_schedulePrefix$dateKey', {
            'date': dateKey,
            'week': week + 1,
            'day_of_week': dayOfWeek,
            'type': 'rest',
            'workout_name': 'Rest Day',
            'workout_focus': 'Recovery & mobility',
            'exercises': <Map<String, dynamic>>[],
            'week_character': weekPlan.weekCharacter,
            'status': 'rest',
            'completed_at': null,
            'is_swapped': false,
            'original_date': null,
          });
        }
      }
    }

    return plan;
  }

  // ── Reschedule from Today ────────────────────────────────────────

  /// Regenerates the workout plan and reschedules from [fromDate] forward.
  ///
  /// Preserves all past entries (completed, skipped, etc.) and replaces
  /// future non-completed entries with the new plan. Used when the user
  /// changes days_per_week, goal, or equipment in profile settings.
  Future<Phase> generateAndScheduleFromDate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime fromDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    // V3 parameters
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    // 1. Generate new plan
    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );

    // 2. Delete future non-completed schedule entries
    final workoutBox = _hive.workoutBox;
    final today = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final planEndStr = _hive.configBox.get(_planEndKey) as String?;
    final planEnd = planEndStr != null ? DateTime.parse(planEndStr) : today.add(const Duration(days: 28));

    for (var d = today; !d.isAfter(planEnd); d = d.add(const Duration(days: 1))) {
      final dateKey = _dateKey(d);
      final key = '$_schedulePrefix$dateKey';
      final displacedKey = '$_displacedPrefix$dateKey';
      final existing = workoutBox.get(key);
      if (existing != null) {
        final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
        final status = map['status'] as String? ?? '';
        // Keep completed workouts — delete everything else
        if (status != 'completed') {
          await workoutBox.delete(key);
        }
      }
      // Stale displaced backups from the previous plan have no meaning
      // in the new plan — the auto-plan days they once protected are
      // about to be rewritten from scratch.
      if (workoutBox.containsKey(displacedKey)) {
        await workoutBox.delete(displacedKey);
      }
    }

    // 3. Calculate remaining plan duration from today to plan end
    final monday = _normalizeToMonday(today);
    final endDate = monday.add(const Duration(days: 27)); // 4 weeks from plan monday

    // Preserve plan_start_date on reschedule — only write if this is the
    // first-time generation (no existing start date). Overwriting on a
    // days-per-week change resets getCurrentWeekNumber() back to Week 1.
    final existingStart = _hive.configBox.get(_planStartKey) as String?;
    if (existingStart == null) {
      await _hive.configBox.put(_planStartKey, monday.toIso8601String());
      await _hive.configBox.put(_planEndKey, endDate.toIso8601String());
    }
    await workoutBox.put(_planKey, plan.toMap());
    if (preferredDays != null) {
      await _hive.configBox.put('preferred_training_days', preferredDays);
    }

    // 4. Assign new workouts from today forward, skipping completed dates
    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);

    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final scheduleKey = '$_schedulePrefix$dateKey';

        // Skip dates before today
        if (date.isBefore(today)) {
          if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
            workoutDayIndex++;
          }
          continue;
        }

        // Skip dates that already have a completed workout
        final existing = workoutBox.get(scheduleKey);
        if (existing != null) {
          final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
          if (map['status'] == 'completed') {
            if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
              workoutDayIndex++;
            }
            continue;
          }
        }

        final isWorkoutDay = dayPattern.contains(dayOfWeek);
        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await workoutBox.put(scheduleKey, {
            'date': dateKey,
            'week': week + 1,
            'day_of_week': dayOfWeek,
            'type': 'workout',
            'workout_day_index': workoutDayIndex,
            'workout_name': workoutDay.name,
            'workout_focus': workoutDay.focus,
            'exercises': workoutDay.exercises.map((e) => e.toMap()).toList(),
            if (workoutDay.warmup.isNotEmpty)
              'warmup': workoutDay.warmup.map((e) => e.toMap()).toList(),
            if (workoutDay.cooldown.isNotEmpty)
              'cooldown': workoutDay.cooldown.map((e) => e.toMap()).toList(),
            'week_character': weekPlan.weekCharacter,
            'status': 'planned',
            'completed_at': null,
            'is_swapped': false,
            'original_date': null,
          });
          workoutDayIndex++;
        } else {
          await workoutBox.put(scheduleKey, {
            'date': dateKey,
            'week': week + 1,
            'day_of_week': dayOfWeek,
            'type': 'rest',
            'workout_name': 'Rest Day',
            'workout_focus': 'Recovery & mobility',
            'exercises': <Map<String, dynamic>>[],
            'week_character': weekPlan.weekCharacter,
            'status': 'rest',
            'completed_at': null,
            'is_swapped': false,
            'original_date': null,
          });
        }
      }
    }

    return plan;
  }

  // ── Queries ─────────────────────────────────────────────────────

  /// Get scheduled data for a specific date.
  ///
  /// Validates that a 'completed' status actually belongs to this date —
  /// prevents stale completed_at timestamps from a previous session causing
  /// a workout to appear as done before the user has started it.
  Map<String, dynamic>? getScheduleForDate(DateTime date) {
    final key = '$_schedulePrefix${_dateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data as Map);

    // Guard against stale completion: if status is 'completed', verify that
    // completed_at date matches the requested date. If not, return as planned.
    if (map['status'] == 'completed') {
      final completedAt = map['completed_at'] as String?;
      if (completedAt != null) {
        final completedDate = DateTime.tryParse(completedAt);
        if (completedDate != null) {
          final requestedDateStr = _dateKey(date);
          final completedDateStr = _dateKey(completedDate.toLocal());
          if (requestedDateStr != completedDateStr) {
            // Stale — return as planned without writing back to Hive
            final safe = Map<String, dynamic>.from(map);
            safe['status'] = 'planned';
            safe['completed_at'] = null;
            return safe;
          }
        }
      }
    }

    return map;
  }

  /// Get all scheduled days for a given week number (1-4).
  List<Map<String, dynamic>> getWeek(int weekNumber) {
    final startStr = _hive.configBox.get(_planStartKey) as String?;
    if (startStr == null) return [];

    final planStart = DateTime.parse(startStr);
    final weekStart = planStart.add(Duration(days: (weekNumber - 1) * 7));
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      }
    }
    return days;
  }

  /// Get the current week number based on today's date.
  int getCurrentWeekNumber() {
    final startStr = _hive.configBox.get(_planStartKey) as String?;
    if (startStr == null) return 1;

    final planStart = DateTime.parse(startStr);
    final today = DateTime.now();
    final diff = today.difference(planStart).inDays;
    return (diff ~/ 7 + 1).clamp(1, 4);
  }

  /// Day number within the current Phase (1-based). Returns 0 if no plan
  /// has been generated yet, and N where N > 28 when the phase has
  /// elapsed. Used by the day-25..28 reminders and the day-29+ expired
  /// screen (audit H9).
  int getCurrentDayInPhase() {
    final start = getPlanStartDate();
    if (start == null) return 0;
    final today = DateTime.now();
    final startMidnight = DateTime(start.year, start.month, start.day);
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return todayMidnight.difference(startMidnight).inDays + 1;
  }

  /// True if the current Phase has run its course (today > plan_end_date).
  /// FREE users stay here until they upgrade or re-do Week 4; PRO users
  /// get auto-generated into the next Phase.
  bool isPhaseExpired() {
    final end = getPlanEndDate();
    if (end == null) return false;
    final today = DateTime.now();
    return today.isAfter(end);
  }

  /// Copies the last week of the current Phase (Week 4) forward by 7
  /// days starting today. Used by the free-tier "Re-do Week 4" escape
  /// valve (audit H9 / B1).
  ///
  /// Behaviour:
  ///   - Reads `schedule_<date>` keys for the 7 days ending at
  ///     `plan_end_date` (Week 4).
  ///   - Writes the same workout payloads under new date keys for the
  ///     next 7 days.
  ///   - Same exercises, same prescribed weights — no progressive
  ///     overload (that stays a PRO benefit).
  ///   - Extends `plan_end_date` by 7 days so UI + sync paths keep
  ///     working. Phase number stays at 1.
  ///
  /// Safe to call multiple times; each call extends another week.
  Future<void> redoWeek4() async {
    final planEnd = getPlanEndDate();
    if (planEnd == null) return;

    final workoutBox = _hive.workoutBox;
    final configBox = _hive.configBox;

    // Week 4 spans plan_end_date back 7 days (inclusive).
    final week4Start = planEnd.subtract(const Duration(days: 6));

    // Start the re-do at tomorrow (or today if user tapped late and plan
    // already expired). Either way, don't overwrite past days.
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final rollStart = todayMidnight.isAfter(planEnd)
        ? todayMidnight
        : planEnd.add(const Duration(days: 1));

    for (int offset = 0; offset < 7; offset++) {
      final sourceDate = week4Start.add(Duration(days: offset));
      final targetDate = rollStart.add(Duration(days: offset));
      final sourceKey = '$_schedulePrefix${_dateKey(sourceDate)}';
      final targetKey = '$_schedulePrefix${_dateKey(targetDate)}';

      final raw = workoutBox.get(sourceKey);
      if (raw is! Map) continue;

      final copy = Map<String, dynamic>.from(raw);
      // Re-stamp the date + reset completion state for the new day.
      copy['date'] = _dateKey(targetDate);
      copy['status'] = copy['type'] == 'rest' ? 'rest' : 'planned';
      copy['completed_at'] = null;
      copy['is_swapped'] = false;
      copy['original_date'] = null;

      await workoutBox.put(targetKey, copy);
    }

    // Extend the plan end by 7 days so downstream clamping stays valid.
    final newEnd = rollStart.add(const Duration(days: 6));
    await configBox.put(_planEndKey, newEnd.toIso8601String());
  }

  /// PRO-only: if the current Phase has expired, generate the next
  /// Phase (Phase N+1) starting today. Called from the app-launch
  /// bootstrap for PRO users. Free users hit the [PlanExpiredCard]
  /// instead — no auto-generation.
  ///
  /// Reads `current_phase` from the user_progress map and bumps it.
  /// Caller must have loaded profile + be signed in.
  Future<bool> autoGenerateNextPhaseIfNeeded({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    String experienceLevel = 'intermediate',
    int currentPhase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    if (!isPhaseExpired()) return false;
    if (currentPhase >= 12) return false; // 12-phase ceiling

    final today = DateTime.now();
    await generateAndSchedule(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      startDate: today,
      experienceLevel: experienceLevel,
      phase: currentPhase + 1,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );
    return true;
  }

  /// Get the plan start date.
  DateTime? getPlanStartDate() {
    final startStr = _hive.configBox.get(_planStartKey) as String?;
    if (startStr == null) return null;
    return DateTime.parse(startStr);
  }

  /// Get the plan end date (inclusive — last day of the current Phase).
  ///
  /// Written by [generateAndSchedule] and [generateAndScheduleFromDate].
  /// Template scheduling clamps writes against this value so that a
  /// user mid-Phase cannot schedule a template past the Phase boundary
  /// (which would produce orphan entries once the next Phase generates).
  DateTime? getPlanEndDate() {
    final endStr = _hive.configBox.get(_planEndKey) as String?;
    if (endStr == null) return null;
    return DateTime.tryParse(endStr);
  }

  /// Get the current plan from Hive.
  Phase? getCurrentPlan() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    // Return the raw map — callers can extract what they need
    return null; // TODO: deserialize Phase from map when needed
  }

  /// Get plan metadata (raw map).
  Map<String, dynamic>? getCurrentPlanMap() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// Check if a plan has been generated.
  bool hasPlan() {
    return _hive.workoutBox.containsKey(_planKey);
  }

  /// Get all dates in the current week (Mon-Sun) with their schedule.
  List<Map<String, dynamic>> getCurrentCalendarWeek() {
    final today = DateTime.now();
    final monday = _normalizeToMonday(today);
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      } else {
        // Date outside plan range
        days.add({
          'date': _dateKey(date),
          'day_of_week': i,
          'type': 'none',
          'workout_name': '',
          'status': 'none',
        });
      }
    }
    return days;
  }

  // ── Completion ──────────────────────────────────────────────────

  /// Mark a workout day as completed.
  ///
  /// [durationSeconds] is stored in the schedule map so the home screen
  /// can display the actual workout duration after completion.
  Future<void> markCompleted(DateTime date, {int durationSeconds = 0}) async {
    final key = '$_schedulePrefix${_dateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data as Map);
    final completionTime = DateTime.now().toLocal();
    map['status'] = 'completed';
    map['completed_at'] = completionTime.toIso8601String();
    map['duration_seconds'] = durationSeconds;
    await _hive.workoutBox.put(key, map);
  }

  /// Mark a workout day as skipped.
  Future<void> markSkipped(DateTime date) async {
    final key = '$_schedulePrefix${_dateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data as Map);
    map['status'] = 'skipped';
    await _hive.workoutBox.put(key, map);
  }

  // ── Swap ────────────────────────────────────────────────────────

  /// Swap two days within the same week.
  ///
  /// Returns null on success, or an error message string.
  Future<String?> swapDays(DateTime dateA, DateTime dateB, {required bool isPro}) async {
    // Validate same week
    final mondayA = _normalizeToMonday(dateA);
    final mondayB = _normalizeToMonday(dateB);
    if (mondayA != mondayB) {
      return 'Can only swap days within the same week';
    }

    // Check swap limit
    final swapsUsed = _getSwapsUsedThisWeek(mondayA);
    final maxSwaps = isPro ? 3 : 1;
    if (swapsUsed >= maxSwaps) {
      return isPro
          ? 'Maximum 3 swaps per week reached'
          : 'Free users can swap once per week. Upgrade to PRO for 3 swaps.';
    }

    // Get both schedules
    final keyA = '$_schedulePrefix${_dateKey(dateA)}';
    final keyB = '$_schedulePrefix${_dateKey(dateB)}';
    final dataA = _hive.workoutBox.get(keyA);
    final dataB = _hive.workoutBox.get(keyB);
    if (dataA == null || dataB == null) return 'Schedule not found';

    final mapA = Map<String, dynamic>.from(dataA as Map);
    final mapB = Map<String, dynamic>.from(dataB as Map);

    // Simulate swap and check for 3 consecutive rest days
    final simWeek = _simulateSwap(mondayA, dateA, dateB);
    if (_hasThreeConsecutiveRest(simWeek)) {
      return 'Swap would create 3+ consecutive rest days — not allowed';
    }

    // Perform swap: exchange workout data, keep date/day_of_week
    final swappedA = Map<String, dynamic>.from(mapB);
    swappedA['date'] = mapA['date'];
    swappedA['day_of_week'] = mapA['day_of_week'];
    swappedA['is_swapped'] = true;
    swappedA['original_date'] = mapB['date'];

    final swappedB = Map<String, dynamic>.from(mapA);
    swappedB['date'] = mapB['date'];
    swappedB['day_of_week'] = mapB['day_of_week'];
    swappedB['is_swapped'] = true;
    swappedB['original_date'] = mapA['date'];

    await _hive.workoutBox.put(keyA, swappedA);
    await _hive.workoutBox.put(keyB, swappedB);

    // Increment swap counter
    await _incrementSwapCount(mondayA);

    return null; // success
  }

  /// Swaps a single exercise within a scheduled workout for a different one.
  ///
  /// Called by the AI coach `swap_exercise` tool intent dispatcher (Phase
  /// A.8). The caller is responsible for invalidating Riverpod providers
  /// (CLAUDE.md §15: currentPlanProvider, workoutStatsProvider,
  /// calendarWeekProvider, streakProvider, todayWorkoutProvider,
  /// allExercisePRsProvider) and firing fire-and-forget sync — this
  /// service stays a pure data layer (matches existing methods like
  /// [swapDays] and [assignTemplateToDate], which also leave invalidation
  /// + sync to the caller).
  ///
  /// Behaviour:
  ///   1. Reads `schedule_<date>` from workoutBox; throws if absent.
  ///   2. Refuses to mutate completed workouts (history is sacred).
  ///   3. Locates [fromExerciseId] in the day's `exercises` array.
  ///   4. Resolves [toExerciseId] from exerciseBox first, then customBox.
  ///   5. Builds a replacement exercise entry that:
  ///        - Carries over `sets`, `reps`, `rest_seconds`, `superset_group`
  ///          from the swapped-out entry (so the user's prescription is
  ///          preserved).
  ///        - Pulls fresh `id`, `exercise_name`, `category`,
  ///          `equipment_needed`, `logging_type`, `exercise_type`,
  ///          `coaching_cues`, `image_*` from the new exercise's library
  ///          row.
  ///   6. Writes the updated schedule back to Hive.
  ///   7. Returns a [SwapExerciseResult] with before/after names + index.
  ///
  /// Throws [SwapExerciseException] with one of: `no_schedule`,
  /// `exercise_not_in_workout`, `exercise_not_found`, `workout_completed`.
  Future<SwapExerciseResult> swapExerciseInDay({
    required String date,
    required String fromExerciseId,
    required String toExerciseId,
  }) async {
    final scheduleKey = '$_schedulePrefix$date';
    final raw = _hive.workoutBox.get(scheduleKey);
    if (raw is! Map) {
      throw SwapExerciseException(
        'no_schedule',
        'No scheduled workout found for $date',
      );
    }
    final scheduleMap = Map<String, dynamic>.from(raw);

    if (scheduleMap['status'] == 'completed') {
      throw SwapExerciseException(
        'workout_completed',
        'Cannot swap exercise in a completed workout — use the Edit log path instead',
      );
    }

    // Locate fromExerciseId in the exercises array. Match against either
    // exercise_id (preferred — newer schedules) or exercise_name (older
    // entries may not have stored exercise_id).
    final exercisesRaw = scheduleMap['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
            .map((e) => e is Map
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    int matchIndex = -1;
    for (int i = 0; i < exercises.length; i++) {
      final ex = exercises[i];
      final id = (ex['exercise_id'] as String?) ?? '';
      final name = (ex['exercise_name'] as String?) ?? '';
      if (id == fromExerciseId || name == fromExerciseId) {
        matchIndex = i;
        break;
      }
    }
    if (matchIndex == -1) {
      throw SwapExerciseException(
        'exercise_not_in_workout',
        'Exercise "$fromExerciseId" is not scheduled on $date',
      );
    }

    // Resolve toExerciseId from exerciseBox first, then customBox.
    Map<String, dynamic>? newLib;
    final libRaw = _hive.exerciseBox.get(toExerciseId);
    if (libRaw is Map) {
      newLib = Map<String, dynamic>.from(libRaw);
    } else {
      // customBox uses keys like 'custom_exercise_<ts>' — scan for matching id or name.
      for (final key in _hive.customBox.keys) {
        if (key is! String || !key.startsWith('custom_exercise_')) continue;
        final candidate = _hive.customBox.get(key);
        if (candidate is! Map) continue;
        final candMap = Map<String, dynamic>.from(candidate);
        final candId = (candMap['id'] as String?) ?? '';
        final candName = (candMap['name'] as String?) ?? '';
        if (candId == toExerciseId || candName == toExerciseId) {
          newLib = candMap;
          break;
        }
      }
    }
    if (newLib == null) {
      throw SwapExerciseException(
        'exercise_not_found',
        'Exercise "$toExerciseId" not found in library or custom exercises',
      );
    }

    // Preserve user-prescribed volume from the swapped-out entry.
    final original = exercises[matchIndex];
    final replacement = <String, dynamic>{
      'exercise_id':
          (newLib['id'] as String?) ?? toExerciseId,
      'exercise_name': (newLib['name'] as String?) ?? toExerciseId,
      'logging_type': (newLib['logging_type'] as String?) ??
          (original['logging_type'] as String?) ??
          'weight_reps',
      // Keep prescribed sets/reps/rest from the original slot.
      'sets': original['sets'] ?? newLib['default_sets'] ?? 3,
      'reps': (original['reps'] ??
              newLib['default_reps'] ??
              '8-12')
          .toString(),
      'rest_seconds': original['rest_seconds'] ??
          newLib['default_rest_secs'] ??
          60,
      // Carry pairing if present so superset structure stays intact.
      if (original['superset_group'] != null)
        'superset_group': original['superset_group'],
      // Refresh metadata from the new library entry.
      if (newLib['category'] != null) 'category': newLib['category'],
      if (newLib['exercise_type'] != null)
        'exercise_type': newLib['exercise_type'],
      if (newLib['equipment_needed'] != null)
        'equipment_needed': newLib['equipment_needed'],
      if (newLib['target_focus'] != null)
        'target_focus': newLib['target_focus'],
      if (newLib['priority_tier'] != null)
        'priority_tier': newLib['priority_tier'],
      if (newLib['coaching_cues'] != null)
        'coaching_cues': newLib['coaching_cues'],
      if (newLib['image_start_url'] != null)
        'image_start_url': newLib['image_start_url'],
      if (newLib['image_end_url'] != null)
        'image_end_url': newLib['image_end_url'],
      // Mark this slot as user-modified so downstream periodisation /
      // analytics can treat it differently from auto-generated picks.
      'swapped_via': 'ai_coach',
    };

    exercises[matchIndex] = replacement;
    scheduleMap['exercises'] = exercises;
    await _hive.workoutBox.put(scheduleKey, scheduleMap);

    return SwapExerciseResult(
      date: date,
      fromExerciseId: (original['exercise_id'] as String?) ??
          (original['exercise_name'] as String?) ??
          fromExerciseId,
      fromExerciseName: (original['exercise_name'] as String?) ??
          (original['exercise_id'] as String?) ??
          fromExerciseId,
      toExerciseId: (newLib['id'] as String?) ?? toExerciseId,
      toExerciseName: (newLib['name'] as String?) ?? toExerciseId,
      positionInWorkout: matchIndex,
    );
  }

  /// Trims a scheduled workout to fit a target session duration in minutes.
  ///
  /// Called by the AI coach `shorten_workout` tool intent dispatcher
  /// (Phase B.1). Caller fires Riverpod invalidation + sync — this stays
  /// a pure data layer (mirrors [swapExerciseInDay]).
  ///
  /// Algorithm:
  ///   1. Read `schedule_<date>`. Throw `no_schedule` if missing,
  ///      `workout_completed` if already done.
  ///   2. Estimate per-exercise duration =
  ///        (sets * 60s work) + (sets * (rest_seconds || 60s rest)),
  ///      summed over exercises and converted to minutes.
  ///   3. If estimated <= target → return unchanged (idempotent).
  ///   4. Sort exercises by priority (compound first). Order:
  ///        a. Library `priority_tier` ascending if present (1 = primary
  ///           compound).
  ///        b. Otherwise name-based heuristic — anything containing
  ///           "squat", "bench", "deadlift", "row", "press", "pull-up",
  ///           "pullup" treated as priority 1.
  ///        c. Stable order falls back to original schedule index.
  ///   5. Drop from the END (lowest priority) until estimated <= target
  ///      OR only 2 exercises remain.
  ///   6. If even the floor of 2 exercises exceeds target → throw
  ///      `target_too_low`. User needs more time.
  ///   7. Persist the trimmed list back to the same schedule entry.
  ///
  /// Returns a [ShortenDayResult] with original/trimmed counts, estimates,
  /// and the names of the dropped exercises (in drop order — accessory
  /// work first).
  Future<ShortenDayResult> shortenDay({
    required String date,
    required int targetMinutes,
  }) async {
    final scheduleKey = '$_schedulePrefix$date';
    final raw = _hive.workoutBox.get(scheduleKey);
    if (raw is! Map) {
      throw ShortenDayException(
        'no_schedule',
        'No scheduled workout found for $date',
      );
    }
    final scheduleMap = Map<String, dynamic>.from(raw);

    if (scheduleMap['status'] == 'completed') {
      throw ShortenDayException(
        'workout_completed',
        'Cannot shorten a completed workout',
      );
    }

    // Pull exercises into a working list with stable original index.
    final exercisesRaw = scheduleMap['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
            .map((e) => e is Map
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    final originalCount = exercises.length;
    final originalEstimateSec = _estimateExerciseListSeconds(exercises);
    final originalMinutes = (originalEstimateSec / 60).ceil();

    // Already within budget — nothing to do.
    if (originalMinutes <= targetMinutes) {
      return ShortenDayResult(
        date: date,
        originalExerciseCount: originalCount,
        trimmedExerciseCount: originalCount,
        estimatedOriginalMinutes: originalMinutes,
        estimatedTrimmedMinutes: originalMinutes,
        droppedExerciseNames: const [],
      );
    }

    // Build keep/drop priority order. Lower priorityRank = keep first.
    final indexed = <_PrioritisedExercise>[
      for (int i = 0; i < exercises.length; i++)
        _PrioritisedExercise(
          originalIndex: i,
          priorityRank: _exercisePriorityRank(exercises[i]),
          entry: exercises[i],
        ),
    ];

    // Sort by priorityRank asc, then originalIndex asc (stable).
    indexed.sort((a, b) {
      final cmp = a.priorityRank.compareTo(b.priorityRank);
      if (cmp != 0) return cmp;
      return a.originalIndex.compareTo(b.originalIndex);
    });

    // Pop from the END (lowest priority) until we fit or hit floor of 2.
    final droppedNames = <String>[];
    while (indexed.length > 2) {
      final estimateSec = _estimateExerciseListSeconds(
          indexed.map((e) => e.entry).toList(growable: false));
      if ((estimateSec / 60).ceil() <= targetMinutes) break;
      final dropped = indexed.removeLast();
      final name = (dropped.entry['exercise_name'] as String?) ??
          (dropped.entry['exercise_id'] as String?) ??
          'Unknown';
      droppedNames.add(name);
    }

    // Final estimate — even with floor of 2, we may still be over budget.
    final keptEntries = indexed.map((e) => e.entry).toList(growable: false);
    final keptEstimateSec = _estimateExerciseListSeconds(keptEntries);
    final keptMinutes = (keptEstimateSec / 60).ceil();
    if (keptMinutes > targetMinutes) {
      throw ShortenDayException(
        'target_too_low',
        'Even the highest-priority compounds need ~${keptMinutes}min — '
            'requested $targetMinutes is too short',
      );
    }

    // Restore the original on-screen order (don't reshuffle compounds to
    // top — just remove the dropped slots).
    indexed.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    final trimmedExercises =
        indexed.map((e) => e.entry).toList(growable: false);

    scheduleMap['exercises'] = trimmedExercises;
    scheduleMap['shortened_via'] = 'ai_coach';
    scheduleMap['shortened_at'] = DateTime.now().toIso8601String();
    await _hive.workoutBox.put(scheduleKey, scheduleMap);

    return ShortenDayResult(
      date: date,
      originalExerciseCount: originalCount,
      trimmedExerciseCount: trimmedExercises.length,
      estimatedOriginalMinutes: originalMinutes,
      estimatedTrimmedMinutes: keptMinutes,
      droppedExerciseNames: droppedNames,
    );
  }

  /// Estimate session seconds: per exercise =
  ///   (sets * 60s work) + (sets * (rest_seconds || 60s)).
  /// Crude but consistent — we just need a comparable order of magnitude.
  int _estimateExerciseListSeconds(List<Map<String, dynamic>> exercises) {
    int total = 0;
    for (final ex in exercises) {
      final setsRaw = ex['sets'];
      final sets = setsRaw is num ? setsRaw.toInt() : 3;
      final restRaw = ex['rest_seconds'];
      final rest = restRaw is num ? restRaw.toInt() : 60;
      total += sets * 60 + sets * rest;
    }
    return total;
  }

  /// Lower rank = higher priority = keep first.
  ///   1 → primary compound (or library priority_tier == 1)
  ///   2 → library priority_tier == 2
  ///   3 → library priority_tier == 3 / accessory / unknown
  int _exercisePriorityRank(Map<String, dynamic> ex) {
    final tier = ex['priority_tier'];
    if (tier is num) {
      final t = tier.toInt();
      if (t >= 1 && t <= 3) return t;
    }
    // Name-based fallback for legacy schedule entries that don't carry
    // priority_tier (older auto-plans, custom templates).
    final name = (ex['exercise_name'] as String? ?? '').toLowerCase();
    const compoundKeywords = [
      'squat',
      'bench',
      'deadlift',
      'row',
      'press',
      'pull-up',
      'pullup',
      'pull up',
    ];
    for (final kw in compoundKeywords) {
      if (name.contains(kw)) return 1;
    }
    return 3;
  }

  int _getSwapsUsedThisWeek(DateTime monday) {
    final weekStart = _hive.configBox.get(_swapWeekStartKey) as String?;
    if (weekStart == null || weekStart != _dateKey(monday)) {
      return 0;
    }
    return _hive.configBox.get(_swapsThisWeekKey, defaultValue: 0) as int;
  }

  Future<void> _incrementSwapCount(DateTime monday) async {
    final currentWeekStart = _hive.configBox.get(_swapWeekStartKey) as String?;
    final mondayKey = _dateKey(monday);

    if (currentWeekStart != mondayKey) {
      await _hive.configBox.put(_swapWeekStartKey, mondayKey);
      await _hive.configBox.put(_swapsThisWeekKey, 1);
    } else {
      final current = _hive.configBox.get(_swapsThisWeekKey, defaultValue: 0) as int;
      await _hive.configBox.put(_swapsThisWeekKey, current + 1);
    }
  }

  List<String> _simulateSwap(DateTime monday, DateTime dateA, DateTime dateB) {
    // Build a week of types, then swap the two entries
    final types = <String>[];
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      types.add(schedule?['type'] as String? ?? 'rest');
    }

    final indexA = dateA.difference(monday).inDays;
    final indexB = dateB.difference(monday).inDays;
    if (indexA >= 0 && indexA < 7 && indexB >= 0 && indexB < 7) {
      final temp = types[indexA];
      types[indexA] = types[indexB];
      types[indexB] = temp;
    }
    return types;
  }

  bool _hasThreeConsecutiveRest(List<String> types) {
    int consecutive = 0;
    for (final t in types) {
      if (t == 'rest') {
        consecutive++;
        if (consecutive >= 3) return true;
      } else {
        consecutive = 0;
      }
    }
    return false;
  }

  // ── Travel Mode (PRO) ──────────────────────────────────────────

  /// Activate travel mode for a date range (max 7 days). PRO only.
  Future<String?> activateTravelMode(DateTime start, DateTime end) async {
    final days = end.difference(start).inDays + 1;
    if (days > 7) return 'Travel mode is limited to 7 days';
    if (days < 1) return 'Invalid date range';

    await _hive.configBox.put(_travelStartKey, _dateKey(start));
    await _hive.configBox.put(_travelEndKey, _dateKey(end));

    // Mark all workout days in range as travel
    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final key = '$_schedulePrefix${_dateKey(date)}';
      final data = _hive.workoutBox.get(key);
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        map['status'] = 'travel';
        await _hive.workoutBox.put(key, map);
      }
    }

    return null;
  }

  /// Check if a date is in travel mode.
  bool isTravelDay(DateTime date) {
    final schedule = getScheduleForDate(date);
    return schedule?['status'] == 'travel';
  }

  // ── Day pattern ─────────────────────────────────────────────────

  /// Returns which days of the week are workout days (0=Mon, 6=Sun).
  /// Evenly distributes rest days for recovery.
  List<int> _getDayPattern(int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return [0, 2, 4]; // Mon, Wed, Fri
      case 4:
        return [0, 1, 3, 5]; // Mon, Tue, Thu, Sat
      case 5:
        return [0, 1, 2, 4, 5]; // Mon, Tue, Wed, Fri, Sat
      case 6:
        return [0, 1, 2, 3, 4, 5]; // Mon–Sat
      default:
        return [0, 1, 3, 5]; // Default 4-day
    }
  }

  // ── Custom Template Assignment ───────────────────────────────────

  /// Assign a saved template to a specific calendar date.
  ///
  /// Backs up any existing non-template schedule entry into a
  /// `displaced_<date>` sibling key BEFORE overwriting. This allows
  /// [unscheduleTemplateFromDate] to restore the original workout
  /// (auto-plan day, rest day, etc.) when the template is later
  /// edited or deleted.
  ///
  /// Refuses to run if the current entry is `completed` — history
  /// is sacred and must never be overwritten by a template assignment.
  ///
  /// Only backs up entries that are NOT already `custom_template`
  /// (avoids chained displaced entries from template-over-template).
  Future<void> assignTemplateToDate(String templateId, DateTime date) async {
    final tmpl = _hive.workoutBox.get(templateId);
    if (tmpl == null) return;

    final tmplMap = Map<String, dynamic>.from(tmpl as Map);
    final dateKey = _dateKey(date);
    final scheduleKey = '$_schedulePrefix$dateKey';
    final displacedKey = '$_displacedPrefix$dateKey';

    // Inspect the current schedule entry for this date.
    final existing = _hive.workoutBox.get(scheduleKey);
    if (existing is Map) {
      final existingMap = Map<String, dynamic>.from(existing);
      // Never displace a completed workout — history is sacred.
      if (existingMap['status'] == 'completed') return;

      // Only back up if the displaced entry is an auto-plan entry, NOT
      // another custom_template. This prevents chained backups when a
      // user overwrites one template with another.
      final isAlreadyTemplate = existingMap['type'] == 'custom_template';
      final alreadyBackedUp = _hive.workoutBox.containsKey(displacedKey);
      if (!isAlreadyTemplate && !alreadyBackedUp) {
        await _hive.workoutBox.put(displacedKey, existingMap);
      }
    }

    // Calculate the correct week number for this date relative to plan start.
    final planStartStr = _hive.configBox.get(_planStartKey) as String?;
    int weekNum = 1;
    if (planStartStr != null) {
      final planStart = DateTime.tryParse(planStartStr);
      if (planStart != null) {
        final diff = date.difference(planStart).inDays;
        weekNum = (diff ~/ 7 + 1).clamp(1, 4);
      }
    }

    final workoutName = tmplMap['name'] as String? ?? 'Custom Workout';
    final normalizedExercises = _normalizeExercises(tmplMap['exercises'] as List? ?? []);

    // V4: Auto-inject warmup/cooldown for custom templates
    final templateEntry = <String, dynamic>{
      'date': dateKey,
      'week': weekNum,
      'type': 'custom_template',
      'template_id': templateId,
      'workout_name': workoutName,
      'workout_focus': 'Custom',
      'exercises': normalizedExercises,
      'status': 'planned',
      'is_swapped': false,
      'completed_at': null,
    };

    if (normalizedExercises.isNotEmpty) {
      // Detect day type from exercise categories to drive warm-up selection
      final dayType = _detectDayTypeFromExercises(normalizedExercises);

      // Get user profile for experience level and equipment
      final profile = _hive.userBox.get('profile');
      final profileMap = profile is Map ? Map<String, dynamic>.from(profile) : <String, dynamic>{};
      final experience = (profileMap['fitness_experience'] as String?) ?? 'intermediate';
      final equipmentStr = (profileMap['equipment_access'] as String?) ?? 'full_gym';

      // WarmupCooldownSelector.attach expects List<String> for equipment
      final equipmentList = [equipmentStr];

      // Build a temporary single-day WeekPlan so WarmupCooldownSelector can
      // attach exercises. The day name drives inferDayType inside the selector.
      final tempDay = WorkoutDay(
        dayNumber: 1,
        name: workoutName,
        focus: dayType,
        exercises: const [],
      );
      final tempWeek = WeekPlan(
        weekNumber: 1,
        weekInPhase: 1,
        overloadNotes: '',
        weekCharacter: 'baseline',
        workoutDays: [tempDay],
      );

      final withWarmup = WarmupCooldownSelector.attach(
        [tempWeek],
        experience,
        equipmentList,
      );

      final enrichedDay = withWarmup.first.workoutDays.first;
      if (enrichedDay.warmup.isNotEmpty) {
        templateEntry['warmup'] = enrichedDay.warmup
            .map((e) => e.toMap()..['auto_generated'] = true)
            .toList();
      }
      if (enrichedDay.cooldown.isNotEmpty) {
        templateEntry['cooldown'] = enrichedDay.cooldown
            .map((e) => e.toMap()..['auto_generated'] = true)
            .toList();
      }
    }

    await _hive.workoutBox.put(scheduleKey, templateEntry);
  }

  /// Detect workout day type from exercise categories.
  ///
  /// Returns one of: push | pull | legs | upper | full_body — matching the
  /// keys expected by [WarmupCooldownSelector].
  String _detectDayTypeFromExercises(List exercises) {
    final categories = <String>[];
    for (final ex in exercises) {
      if (ex is Map) {
        final cat = ex['category'] as String? ?? '';
        if (cat.isNotEmpty) categories.add(cat.toLowerCase());
      }
    }
    if (categories.isEmpty) return 'full_body';

    final pushCount = categories.where((c) => c == 'push').length;
    final pullCount = categories.where((c) => c == 'pull').length;
    final legsCount = categories.where((c) => c == 'legs').length;

    if (legsCount > pushCount && legsCount > pullCount) return 'legs';
    if (pushCount > pullCount) return 'push';
    if (pullCount > pushCount) return 'pull';
    if (pushCount > 0 && pullCount > 0) return 'upper';
    return 'full_body';
  }

  /// Remove a template assignment from a specific date.
  ///
  /// Restore semantics: if a `displaced_<date>` backup exists (written
  /// by [assignTemplateToDate] when this template originally displaced
  /// an auto-plan day), restore it to `schedule_<date>` and delete the
  /// backup. Otherwise simply delete the schedule entry.
  ///
  /// History guard: never touches completed entries. A completed
  /// template workout stays in history forever even if the user later
  /// deletes the template.
  Future<void> unscheduleTemplateFromDate(DateTime date) async {
    final dateKey = _dateKey(date);
    final scheduleKey = '$_schedulePrefix$dateKey';
    final displacedKey = '$_displacedPrefix$dateKey';

    final current = _hive.workoutBox.get(scheduleKey);
    if (current is Map) {
      final currentMap = Map<String, dynamic>.from(current);
      if (currentMap['status'] == 'completed') {
        // History is sacred — don't touch. Also clean up any stale
        // displaced backup so it doesn't leak into the next regen.
        if (_hive.workoutBox.containsKey(displacedKey)) {
          await _hive.workoutBox.delete(displacedKey);
        }
        return;
      }
    }

    // Restore displaced backup if one exists, otherwise delete.
    final backup = _hive.workoutBox.get(displacedKey);
    if (backup is Map) {
      await _hive.workoutBox.put(
          scheduleKey, Map<String, dynamic>.from(backup));
      await _hive.workoutBox.delete(displacedKey);
    } else {
      await _hive.workoutBox.delete(scheduleKey);
    }
  }

  /// Wipe all future non-completed schedule entries for a template.
  ///
  /// Used by edit-template and delete-template flows to clean up old
  /// scheduled instances of a template before re-writing them (edit)
  /// or before deleting the template row (delete). Iterates from today
  /// through `plan_end_date` and calls [unscheduleTemplateFromDate]
  /// for each matching entry — so displaced originals are restored.
  Future<void> cleanSyncTemplateSchedule(String templateId) async {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    // Loop ceiling — prefer real plan_end_date; fall back to 4 weeks
    // from today if no plan exists yet (defensive — should not happen
    // in practice because save flow is gated on plan existing).
    final planEnd = getPlanEndDate() ??
        todayMidnight.add(const Duration(days: 28));

    for (var d = todayMidnight;
        !d.isAfter(planEnd);
        d = d.add(const Duration(days: 1))) {
      final key = '$_schedulePrefix${_dateKey(d)}';
      final entry = _hive.workoutBox.get(key);
      if (entry is! Map) continue;

      final map = Map<String, dynamic>.from(entry);
      if (map['type'] != 'custom_template') continue;
      if (map['template_id'] != templateId) continue;
      if (map['status'] == 'completed') continue;

      await unscheduleTemplateFromDate(d);
    }
  }

  /// Normalises template exercise objects to the canonical schedule field names.
  ///
  /// Template exercises come from the exercise library and use `name`,
  /// `prescribed_sets`/`default_sets`, `prescribed_reps`/`default_reps`.
  /// The workout parser and active-workout screen expect `exercise_name`,
  /// `sets`, and `reps`. This conversion happens once at write time.
  List<Map<String, dynamic>> _normalizeExercises(List raw) {
    return raw.map((e) {
      final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
      final exerciseName =
          (m['exercise_name'] ?? m['name'] ?? 'Unknown').toString();
      return {
        'exercise_name': exerciseName,
        'sets': m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3,
        'reps': (m['reps'] ?? m['prescribed_reps'] ?? m['default_reps'] ?? '10').toString(),
        'rest_seconds': m['rest_seconds'] ?? m['default_rest_secs'] ?? 60,
        'logging_type': _resolveLoggingType(m, exerciseName),
        'category': m['category'],
        'exercise_type': m['exercise_type'],
        'equipment_needed': m['equipment_needed'],
        'superset_group': m['superset_group'],
      };
    }).toList();
  }

  /// F12 · Resolves `logging_type` robustly instead of silently defaulting
  /// to `weight_reps` when the field is missing/null. Resolution order:
  ///   1. Explicit value on the input map.
  ///   2. exerciseBox (seed library) lookup by exact name.
  ///   3. customBox lookup (for user-created exercises).
  ///   4. Fallback heuristic based on name keywords ("hold" / "plank" →
  ///      timed; "run" / "walk" → cardio; otherwise weight_reps).
  String _resolveLoggingType(
      Map<String, dynamic> m, String exerciseName) {
    final explicit = m['logging_type'];
    if (explicit is String && explicit.isNotEmpty) return explicit;

    final hive = HiveService.instance;

    // Try the seeded exercise library first.
    try {
      final libEntry = hive.exerciseBox.get(exerciseName);
      if (libEntry is Map) {
        final lt = libEntry['logging_type'];
        if (lt is String && lt.isNotEmpty) return lt;
      }
    } catch (_) {/* continue */}

    // Try customBox (user-created exercises).
    try {
      for (final key in hive.customBox.keys) {
        if (key is! String || !key.startsWith('custom_exercise_')) continue;
        final raw = hive.customBox.get(key);
        if (raw is! Map) continue;
        if (raw['name']?.toString().toLowerCase() ==
            exerciseName.toLowerCase()) {
          final lt = raw['logging_type'];
          if (lt is String && lt.isNotEmpty) return lt;
        }
      }
    } catch (_) {/* continue */}

    // Last resort — heuristic on the name.
    final n = exerciseName.toLowerCase();
    if (n.contains('hold') ||
        n.contains('plank') ||
        n.contains('handstand') ||
        n.contains('l-sit')) {
      return 'timed';
    }
    if (n.contains('run') || n.contains('row') || n.contains('bike') ||
        n.contains('cycle') || n.contains('walk')) {
      return 'cardio';
    }
    return 'weight_reps';
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Normalize a date to the Monday of its week.
  DateTime _normalizeToMonday(DateTime date) {
    final daysFromMonday = date.weekday - 1; // Monday=1 → 0, Sunday=7 → 6
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  /// Format date as 'yyyy-MM-dd' string key.
  String _dateKey(DateTime date) => formatDateKey(date);
}

/// Private helper for [WorkoutScheduleService.shortenDay] — pairs an
/// exercise entry with its priority rank and original schedule index so
/// the trim algorithm can sort by priority while still being able to
/// restore on-screen order before persisting.
class _PrioritisedExercise {
  final int originalIndex;
  final int priorityRank;
  final Map<String, dynamic> entry;

  const _PrioritisedExercise({
    required this.originalIndex,
    required this.priorityRank,
    required this.entry,
  });
}
