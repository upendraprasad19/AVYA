import '../../../core/services/hive_service.dart';
import '../../../core/utils/ist_date.dart';
import '../../../shared/repositories/plan_generator.dart';

/// One day in a generated hotel workout plan.
class HotelWorkoutDay {
  final String date; // YYYY-MM-DD
  final String workoutName;
  final List<HotelWorkoutExercise> exercises;

  /// True if this date currently has a non-completed workout that will be
  /// overwritten.
  final bool replacing;

  /// True if this date is currently a completed workout — will be SKIPPED
  /// (not overwritten). Sacred.
  final bool willSkip;

  const HotelWorkoutDay({
    required this.date,
    required this.workoutName,
    required this.exercises,
    required this.replacing,
    required this.willSkip,
  });
}

/// One exercise row inside a hotel workout day (display-only).
class HotelWorkoutExercise {
  final String name;
  final int sets;

  /// Either reps ("10-15") or duration ("30s") depending on the exercise's
  /// logging type.
  final String repsOrDuration;

  const HotelWorkoutExercise({
    required this.name,
    required this.sets,
    required this.repsOrDuration,
  });
}

/// Plans a bodyweight-only workout for travel/hotel days.
///
/// Two-phase contract (mirrors [InjurySwapPlanner] / [RescheduleWeekPlanner]):
///   1. Diff widget calls [plan] in `initState`, then [cache].
///   2. On user Confirm, dispatcher reads [getCachedRawSchedules] and
///      writes the schedule entries to Hive.
///   3. [clearCache] runs after execution.
///
/// Strategy:
///   - Calls [PlanGenerator.generate] with `equipment='bodyweight'` and
///     `daysPerWeek=days` so we get N distinct workout types.
///   - User profile drives `goal` and `experienceLevel`.
///   - Completed scheduled workouts in the target window are NEVER
///     overwritten (they're flagged `willSkip` in the diff and excluded
///     from the raw-schedule cache).
///
/// Note: PlanGenerator itself is not modified — only invoked. Per
/// CLAUDE.md rule #14, `lib/shared/repositories/plan_generator.dart` and
/// `plan_engine/` are untouchable without explicit user approval.
class HotelWorkoutPlanner {
  HotelWorkoutPlanner._();
  static final HotelWorkoutPlanner instance = HotelWorkoutPlanner._();

  final Map<String, List<HotelWorkoutDay>> _planCache = {};
  final Map<String, List<Map<String, dynamic>>> _rawScheduleCache = {};

  /// Returns a `(displayDays, rawSchedules)` record. The caller caches both
  /// via [cache] keyed on `intent.id`, and the dispatcher reads the raw
  /// schedules from [getCachedRawSchedules] when applying the change.
  Future<({List<HotelWorkoutDay> days, List<Map<String, dynamic>> rawSchedules})>
      plan({
    required int days,
    String? startDate,
  }) async {
    final n = days.clamp(1, 7);

    final start = startDate != null
        ? DateTime.parse(startDate)
        : _today();

    // Read user profile for PlanGenerator inputs. Falls back to
    // sensible defaults if profile fields are missing — a hotel plan is
    // generic enough that defaults are fine.
    final rawProfile = HiveService.instance.userBox.get('profile');
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile)
        : <String, dynamic>{};

    final goal =
        (profile['primary_goal'] as String?) ?? 'general_fitness';
    final experience =
        (profile['fitness_experience'] as String?) ?? 'beginner';

    // Call the existing PlanGenerator with bodyweight equipment.
    final phase = PlanGenerator.instance.generate(
      goal: goal,
      equipment: 'bodyweight',
      daysPerWeek: n,
      experienceLevel: experience,
      // phase=1 (foundation) — hotel plans aren't progression cycles.
    );

    final workouts = phase.workouts;
    if (workouts.isEmpty) {
      throw StateError(
        'PlanGenerator returned no workout days for the hotel plan.',
      );
    }

    final box = HiveService.instance.workoutBox;
    final result = <HotelWorkoutDay>[];
    final rawSchedules = <Map<String, dynamic>>[];

    for (var i = 0; i < n; i++) {
      final d = start.add(Duration(days: i));
      final dateStr = _fmt(d);

      final existing = box.get('schedule_$dateStr');
      final isCompleted =
          existing is Map && existing['status'] == 'completed';
      final replacing = existing is Map && !isCompleted;

      // Pick the workout for this day from the generated plan.
      final workout = workouts[i % workouts.length];
      final workoutName = workout.name.isEmpty
          ? 'Hotel Workout ${i + 1}'
          : workout.name;

      // Build the display + raw schedule rows.
      final displayExercises = <HotelWorkoutExercise>[];
      final rawExerciseMaps = <Map<String, dynamic>>[];

      for (final ex in workout.exercises) {
        final repsOrDuration = ex.durationSeconds != null
            ? '${ex.durationSeconds}s'
            : ex.reps;

        displayExercises.add(HotelWorkoutExercise(
          name: ex.exerciseName,
          sets: ex.sets,
          repsOrDuration: repsOrDuration,
        ));

        rawExerciseMaps.add(ex.toMap());
      }

      result.add(HotelWorkoutDay(
        date: dateStr,
        workoutName: workoutName,
        exercises: displayExercises,
        replacing: replacing,
        willSkip: isCompleted,
      ));

      // Don't queue completed days for write — preserve them.
      if (!isCompleted) {
        rawSchedules.add({
          'date': dateStr,
          'week': 1,
          'day_of_week': d.weekday,
          'type': 'workout',
          'workout_name': workoutName,
          'workout_focus': workout.focus,
          'exercises': rawExerciseMaps,
          if (workout.warmup.isNotEmpty)
            'warmup': workout.warmup.map((e) => e.toMap()).toList(),
          if (workout.cooldown.isNotEmpty)
            'cooldown': workout.cooldown.map((e) => e.toMap()).toList(),
          'week_character': 'baseline',
          'status': 'planned',
          'completed_at': null,
          'is_swapped': false,
          'original_date': null,
          'generated_via': 'ai_coach_hotel',
          'generated_at': DateTime.now().toIso8601String(),
        });
      }
    }

    return (days: result, rawSchedules: rawSchedules);
  }

  void cache(
    String intentId,
    List<HotelWorkoutDay> displayPlan,
    List<Map<String, dynamic>> rawSchedules,
  ) {
    _planCache[intentId] = displayPlan;
    _rawScheduleCache[intentId] = rawSchedules;
  }

  List<HotelWorkoutDay>? getCachedPlan(String intentId) =>
      _planCache[intentId];

  List<Map<String, dynamic>>? getCachedRawSchedules(String intentId) =>
      _rawScheduleCache[intentId];

  void clearCache(String intentId) {
    _planCache.remove(intentId);
    _rawScheduleCache.remove(intentId);
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _fmt(DateTime d) => istDateStr(d);
}
