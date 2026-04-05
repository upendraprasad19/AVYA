import '../services/hive_service.dart';
import '../services/seed_service.dart';
import '../utils/date_utils.dart';
import '../../shared/repositories/plan_generator.dart';

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
    );

    // 2. Get the day assignment pattern for the week
    final dayPattern = _getDayPattern(daysPerWeek);

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

    // 4. For each of the 4 weeks, assign workouts to the pattern days
    for (int week = 0; week < 4; week++) {
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final isWorkoutDay = dayPattern.contains(dayOfWeek);

        if (isWorkoutDay && workoutDayIndex < plan.workouts.length) {
          final workoutDay = plan.workouts[workoutDayIndex];
          await workoutBox.put('$_schedulePrefix$dateKey', {
            'date': dateKey,
            'week': week + 1,
            'day_of_week': dayOfWeek, // 0=Mon, 6=Sun
            'type': 'workout',
            'workout_day_index': workoutDayIndex,
            'workout_name': workoutDay.name,
            'workout_focus': workoutDay.focus,
            'exercises': workoutDay.exercises.map((e) => e.toMap()).toList(),
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

  /// Get the plan start date.
  DateTime? getPlanStartDate() {
    final startStr = _hive.configBox.get(_planStartKey) as String?;
    if (startStr == null) return null;
    return DateTime.parse(startStr);
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
  /// Overwrites any existing plan entry for that date (generated or rest).
  void assignTemplateToDate(String templateId, DateTime date) {
    final tmpl = _hive.workoutBox.get(templateId);
    if (tmpl == null) return;

    final tmplMap = Map<String, dynamic>.from(tmpl as Map);
    final dateKey = _dateKey(date);

    _hive.workoutBox.put('$_schedulePrefix$dateKey', {
      'date': dateKey,
      'type': 'custom_template',
      'template_id': templateId,
      'workout_name': tmplMap['name'] as String? ?? 'Custom Workout',
      'workout_focus': 'Custom',
      'exercises': _normalizeExercises(tmplMap['exercises'] as List? ?? []),
      'status': 'planned',
      'is_swapped': false,
      'completed_at': null,
    });
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
      return {
        'exercise_name': (m['exercise_name'] ?? m['name'] ?? 'Unknown').toString(),
        'sets': m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3,
        'reps': (m['reps'] ?? m['prescribed_reps'] ?? m['default_reps'] ?? '10').toString(),
        'rest_seconds': m['rest_seconds'] ?? m['default_rest_secs'] ?? 60,
        'logging_type': (m['logging_type'] ?? 'weight_reps').toString(),
        'category': m['category'],
        'exercise_type': m['exercise_type'],
        'equipment_needed': m['equipment_needed'],
        'superset_group': m['superset_group'],
      };
    }).toList();
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
