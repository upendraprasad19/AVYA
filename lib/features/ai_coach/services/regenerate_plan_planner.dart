import '../../../core/services/hive_service.dart';
import '../../../core/utils/injury_vocab.dart';
import '../../../core/utils/ist_date.dart';
import '../../../core/services/seed_service.dart';
import '../../../shared/repositories/plan_generator.dart';
import 'package:icanbefitter/core/constants/equipment_defaults.dart';

/// One day in a regenerated plan block (display-only).
class RegeneratePlanDay {
  /// YYYY-MM-DD calendar date this entry maps to.
  final String date;

  /// Workout name from the generated plan (e.g. "Push Day", "Lower Power").
  final String workoutName;

  /// Display rows for the diff card (name + sets + reps/duration).
  final List<RegeneratePlanExercise> exercises;

  /// True if this date currently has a non-completed workout that will be
  /// overwritten on confirm.
  final bool replacing;

  /// True if this date is currently a completed workout — will be SKIPPED
  /// (not overwritten). Sacred history.
  final bool willSkip;

  const RegeneratePlanDay({
    required this.date,
    required this.workoutName,
    required this.exercises,
    required this.replacing,
    required this.willSkip,
  });
}

/// One exercise row inside a regenerated-plan day (display-only).
class RegeneratePlanExercise {
  final String name;
  final int sets;

  /// Either reps ("8-12") or duration ("30s") depending on logging type.
  final String repsOrDuration;

  const RegeneratePlanExercise({
    required this.name,
    required this.sets,
    required this.repsOrDuration,
  });
}

/// Full plan result returned by [RegeneratePlanPlanner.plan].
class RegeneratePlanResult {
  /// First-week details for diff display (typically 3-7 days depending on
  /// daysPerWeek; rest days are excluded from the display rows).
  final List<RegeneratePlanDay> firstWeek;

  /// Count of additional workout days that will land in weeks 2..N (sum of
  /// non-completed workout-day rows beyond the first week).
  final int additionalDaysCount;

  /// Total weeks in the regenerated block (1-12, matches the user request).
  final int totalWeeks;

  /// Effective goal used for generation (resolved from arg or profile).
  final String resolvedGoal;

  /// Effective equipment tier used for generation.
  final String resolvedEquipment;

  /// Effective training frequency used for generation.
  final int resolvedDaysPerWeek;

  const RegeneratePlanResult({
    required this.firstWeek,
    required this.additionalDaysCount,
    required this.totalWeeks,
    required this.resolvedGoal,
    required this.resolvedEquipment,
    required this.resolvedDaysPerWeek,
  });
}

/// Plans a fresh N-week workout block for the AI coach `regeneratePlanBlock`
/// tool (Phase D.3).
///
/// Two-phase contract (mirrors B.5 [HotelWorkoutPlanner]):
///   1. Diff widget calls [plan] in `initState`, then [cache].
///   2. On user Confirm, dispatcher reads [getCachedRawSchedules] and writes
///      the schedule entries to Hive.
///   3. [clearCache] runs after execution.
///
/// Strategy:
///   - Calls [PlanGenerator.generate] with resolved goal/equipment/days.
///     User-supplied overrides win; otherwise pulled from `userBox.profile`.
///   - Mirrors [WorkoutScheduleService.generateAndScheduleFromDate]'s write
///     shape (workout vs rest entries, week numbering, weekCharacter,
///     warmup/cooldown/finisher merge) so the dashboard + Train screen
///     readers don't see a regression.
///   - Day-of-week pattern matches [WorkoutScheduleService._getDayPattern]
///     exactly so the rest-day distribution stays consistent with manual
///     plan generation.
///   - Completed scheduled workouts in the target window are NEVER
///     overwritten (flagged `willSkip` in the diff and excluded from the
///     raw-schedule cache).
///
/// CLAUDE.md rule #14: PlanGenerator itself is not modified — only invoked.
class RegeneratePlanPlanner {
  RegeneratePlanPlanner._();
  static final RegeneratePlanPlanner instance = RegeneratePlanPlanner._();

  final Map<String, RegeneratePlanResult> _cache = {};
  final Map<String, List<Map<String, dynamic>>> _rawScheduleCache = {};

  /// Day-of-week → workout-day mapping. Mirrors
  /// [WorkoutScheduleService._getDayPattern] — keep these in sync.
  /// Returns 0-indexed weekdays (0=Mon, 6=Sun).
  static List<int> _getDayPattern(int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return [0, 2, 4]; // Mon, Wed, Fri
      case 4:
        return [0, 1, 3, 5]; // Mon, Tue, Thu, Sat
      case 5:
        return [0, 1, 2, 4, 5]; // Mon, Tue, Wed, Fri, Sat
      case 6:
        return [0, 1, 2, 3, 4, 5]; // Mon-Sat
      default:
        return [0, 1, 3, 5];
    }
  }

  /// Returns a `(plan, rawSchedules)` record. The diff widget caches both
  /// via [cache] keyed on `intent.id`, and the dispatcher reads the raw
  /// schedules from [getCachedRawSchedules] when applying the change.
  Future<({RegeneratePlanResult plan, List<Map<String, dynamic>> rawSchedules})>
      plan({
    required int weeks,
    String? goal,
    int? daysPerWeek,
    String? equipment,
    String? startDate,
  }) async {
    final n = weeks.clamp(1, 12);
    final start = startDate != null
        ? DateTime.parse(startDate)
        : _today();

    // Read profile defaults.
    final rawProfile = HiveService.instance.userBox.get('profile');
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};

    final resolvedGoal =
        goal ?? (profile['primary_goal'] as String?) ?? 'general_fitness';
    final resolvedEquipment = equipment ??
        equipmentAccessOf(profile);
    final resolvedDays = daysPerWeek ??
        ((profile['days_per_week'] as num?)?.toInt() ?? 4);
    final experience =
        (profile['fitness_experience'] as String?) ?? 'beginner';
    // U4 (HIGH-3): the coach "regenerate my plan" / "switch goal" path dropped
    // injuries — a knee-injured user's coach regen included knee-contraindicated
    // exercises. Thread them (vocab canonicalized centrally in generateV4).
    final resolvedInjuries = InjuryVocab.fromProfile(profile['injuries']);

    // Item ② / G8 fix: a coach "regenerate my plan" / "switch goal" must NOT
    // demote the user to Foundation (phase 1). Thread the REAL current_phase
    // (the progress map — the same source graduation / splash / RankService
    // read) so a phase-6 user's regen produces phase-6 content, not a fresh
    // foundation block. resolvedPhase ALSO stamps the schedule-row `phase` key
    // below (COACH-1): these rows were unstamped and relied on bucketPastRows
    // carry-forward; a wrong stamp (e.g. literal 1 for a phase-6 user) would
    // mint a phantom phase block that mis-drives PhaseProgressReconciler.
    final rawProgress = HiveService.instance.userBox.get('progress');
    final resolvedPhase = (rawProgress is Map
            ? (rawProgress['current_phase'] as int?)
            : null) ??
        1;

    // Defensive: PlanGenerator silently produces empty workouts if the
    // exercise box is empty. Seed it on demand (mirrors
    // [WorkoutScheduleService.generateAndScheduleFromDate]).
    if (HiveService.instance.exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    // Generate the phase. PlanGenerator itself is untouched — we just
    // call it with the resolved params.
    final phase = PlanGenerator.instance.generate(
      goal: resolvedGoal,
      equipment: resolvedEquipment,
      daysPerWeek: resolvedDays,
      experienceLevel: experience,
      phase: resolvedPhase,
      injuries: resolvedInjuries, // U4 (HIGH-3): coach regen respects injuries
    );

    if (phase.weekPlans.isEmpty) {
      throw StateError(
        'PlanGenerator returned no week plans for the regenerated block.',
      );
    }

    final box = HiveService.instance.workoutBox;
    final dayPattern = _getDayPattern(resolvedDays);
    final firstWeekDisplay = <RegeneratePlanDay>[];
    final rawSchedules = <Map<String, dynamic>>[];
    int additionalWorkoutDayCount = 0;

    for (var weekIdx = 0; weekIdx < n; weekIdx++) {
      // PlanGenerator returns 4 weekPlans per phase. For weeks beyond the
      // 4th, repeat the last week (matches [generateAndScheduleFromDate]
      // behaviour for the 4-week block).
      final weekPlan = weekIdx < phase.weekPlans.length
          ? phase.weekPlans[weekIdx]
          : phase.weekPlans.last;

      // weekStart is the Monday of week N relative to the start date's
      // week. We don't normalise to Monday here — the start day defines
      // the day-0 anchor and the day_pattern is interpreted relative to
      // it. (Matches the spec's worked example for "regenerate from
      // today, 4 weeks, 4 days/week".)
      final weekStart = start.add(Duration(days: weekIdx * 7));
      int workoutDayIndex = 0;

      for (var dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final d = weekStart.add(Duration(days: dayOfWeek));
        final dateStr = _fmt(d);
        final scheduleKey = 'schedule_$dateStr';
        final existing = box.get(scheduleKey);
        final isCompleted =
            existing is Map && existing['status'] == 'completed';
        final replacing = existing is Map && !isCompleted;

        final isWorkoutDay = dayPattern.contains(dayOfWeek) &&
            workoutDayIndex < weekPlan.workoutDays.length;

        if (isWorkoutDay) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          workoutDayIndex++;

          final workoutName = workoutDay.name.isEmpty
              ? 'Workout $workoutDayIndex'
              : workoutDay.name;

          // Build display rows for the first week only (weeks 2..N are
          // summarised by additionalDaysCount in the diff footer).
          if (weekIdx == 0) {
            final displayExercises = <RegeneratePlanExercise>[];
            for (final ex in workoutDay.exercises) {
              final repsOrDuration = ex.durationSeconds != null
                  ? '${ex.durationSeconds}s'
                  : ex.reps;
              displayExercises.add(RegeneratePlanExercise(
                name: ex.exerciseName,
                sets: ex.sets,
                repsOrDuration: repsOrDuration,
              ));
            }
            firstWeekDisplay.add(RegeneratePlanDay(
              date: dateStr,
              workoutName: workoutName,
              exercises: displayExercises,
              replacing: replacing,
              willSkip: isCompleted,
            ));
          } else {
            // Counted toward "+ N more workouts" footer (excluding skips).
            if (!isCompleted) additionalWorkoutDayCount++;
          }

          // Don't queue completed days for write — preserve them.
          if (!isCompleted) {
            rawSchedules.add({
              'date': dateStr,
              'phase': resolvedPhase,
              'week': weekIdx + 1,
              'day_of_week': dayOfWeek,
              'type': 'workout',
              'workout_day_index': workoutDayIndex - 1,
              'workout_name': workoutName,
              'workout_focus': workoutDay.focus,
              'exercises':
                  workoutDay.exercises.map((e) => e.toMap()).toList(),
              if (workoutDay.warmup.isNotEmpty)
                'warmup': workoutDay.warmup.map((e) => e.toMap()).toList(),
              if (workoutDay.cooldown.isNotEmpty)
                'cooldown':
                    workoutDay.cooldown.map((e) => e.toMap()).toList(),
              if (workoutDay.finisher.isNotEmpty)
                'finisher':
                    workoutDay.finisher.map((e) => e.toMap()).toList(),
              'week_character': weekPlan.weekCharacter,
              'status': 'planned',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
              'generated_via': 'ai_coach_regenerate',
              'generated_at': DateTime.now().toIso8601String(),
            });
          }
        } else if (dayPattern.contains(dayOfWeek)) {
          // Pattern says workout day but the week ran out of workout
          // entries — treat as rest (matches schedule service behaviour).
          if (!isCompleted) {
            rawSchedules.add(_restEntry(
              dateStr,
              resolvedPhase,
              weekIdx + 1,
              dayOfWeek,
              weekPlan.weekCharacter,
            ));
          }
        } else {
          // Real rest day per the pattern.
          if (!isCompleted) {
            rawSchedules.add(_restEntry(
              dateStr,
              resolvedPhase,
              weekIdx + 1,
              dayOfWeek,
              weekPlan.weekCharacter,
            ));
          }
        }
      }
    }

    final result = RegeneratePlanResult(
      firstWeek: firstWeekDisplay,
      additionalDaysCount: additionalWorkoutDayCount,
      totalWeeks: n,
      resolvedGoal: resolvedGoal,
      resolvedEquipment: resolvedEquipment,
      resolvedDaysPerWeek: resolvedDays,
    );

    return (plan: result, rawSchedules: rawSchedules);
  }

  Map<String, dynamic> _restEntry(
    String dateStr,
    int phase,
    int week,
    int dayOfWeek,
    String weekCharacter,
  ) {
    return {
      'date': dateStr,
      'phase': phase,
      'week': week,
      'day_of_week': dayOfWeek,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'workout_focus': 'Recovery & mobility',
      'exercises': const <Map<String, dynamic>>[],
      'week_character': weekCharacter,
      'status': 'rest',
      'completed_at': null,
      'is_swapped': false,
      'original_date': null,
      'generated_via': 'ai_coach_regenerate',
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  void cache(
    String intentId,
    RegeneratePlanResult plan,
    List<Map<String, dynamic>> rawSchedules,
  ) {
    _cache[intentId] = plan;
    _rawScheduleCache[intentId] = rawSchedules;
  }

  RegeneratePlanResult? getCachedPlan(String intentId) => _cache[intentId];

  List<Map<String, dynamic>>? getCachedRawSchedules(String intentId) =>
      _rawScheduleCache[intentId];

  void clearCache(String intentId) {
    _cache.remove(intentId);
    _rawScheduleCache.remove(intentId);
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _fmt(DateTime d) => istDateStr(d);
}
