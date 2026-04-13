import 'models.dart';

/// Stage 6: Appends HIIT cardio finishers to 2 workout days per week.
///
/// Only activates for lose_fat or general_fitness goals.
/// Finisher goes between main exercises and cooldown.
class CardioFinisher {
  /// Attach cardio finishers to 2 non-consecutive days per week.
  static List<WeekPlan> attach({
    required List<WeekPlan> weeks,
    required String goal,
    required String? cardioPreference,
    required List<String> equipmentList,
  }) {
    if (goal != 'lose_fat' && goal != 'general_fitness') return weeks;

    final preference = cardioPreference ?? 'hate_cardio';
    final hasGymEquipment = equipmentList.any(
      (e) => e.toLowerCase().contains('gym') || e.toLowerCase().contains('full'),
    );

    return weeks.map((week) {
      final dayCount = week.workoutDays.length;
      if (dayCount < 2) return week;

      // Pick 2 non-consecutive day indices
      final finisherDays = _pickFinisherDays(dayCount);

      final days = week.workoutDays.asMap().entries.map((entry) {
        final day = entry.value;
        if (!finisherDays.contains(entry.key)) return day;

        final finisher = _buildFinisher(preference, hasGymEquipment);

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: day.exercises,
          warmup: day.warmup,
          cooldown: day.cooldown,
          finisher: finisher,
        );
      }).toList();

      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: days,
      );
    }).toList();
  }

  /// Pick 2 non-consecutive day indices from a day count.
  /// e.g., 4 days → [0, 2], 3 days → [0, 2], 5 days → [0, 2], 6 days → [0, 3]
  static Set<int> _pickFinisherDays(int dayCount) {
    if (dayCount <= 2) return {0, 1};
    if (dayCount <= 4) return {0, 2};
    if (dayCount == 5) return {0, 3};
    return {0, 3}; // 6 days
  }

  /// Build finisher exercises based on user preference.
  static List<PlannedExercise> _buildFinisher(
    String preference, bool hasGymEquipment,
  ) {
    switch (preference) {
      case 'running':
        return _runningFinisher(hasGymEquipment);
      case 'cycling':
        return _cyclingFinisher(hasGymEquipment);
      case 'hiit':
        return _hiitFinisher();
      case 'jump_rope':
        return _jumpRopeFinisher();
      case 'hate_cardio':
      default:
        return _miniHiitFinisher();
    }
  }

  /// Treadmill Intervals: 30s sprint / 60s walk × 5 rounds (~8 min)
  /// Bodyweight fallback: Spot Jogging Intervals
  static List<PlannedExercise> _runningFinisher(bool hasGym) {
    final name = hasGym ? 'Treadmill Intervals' : 'Spot Jogging Intervals';
    return [
      _finisherExercise(
        name: name,
        sets: 5,
        reps: '30s sprint / 60s walk',
        durationSeconds: 450,
        notes: '30s sprint → 60s walk recovery × 5 rounds',
      ),
    ];
  }

  /// Stationary Bike Sprints: 30s fast / 30s slow × 8 rounds (~8 min)
  /// Bodyweight fallback: High Knees Intervals
  static List<PlannedExercise> _cyclingFinisher(bool hasGym) {
    final name = hasGym ? 'Stationary Bike Sprints' : 'High Knees Intervals';
    return [
      _finisherExercise(
        name: name,
        sets: 8,
        reps: '30s fast / 30s slow',
        durationSeconds: 480,
        notes: '30s max effort → 30s easy recovery × 8 rounds',
      ),
    ];
  }

  /// Bodyweight Circuit: burpees, mountain climbers, jump squats (3 rounds, ~10 min)
  static List<PlannedExercise> _hiitFinisher() {
    return [
      _finisherExercise(
        name: 'Burpees',
        sets: 3,
        reps: '10',
        durationSeconds: 120,
        notes: 'Part 1 of HIIT circuit — minimal rest between exercises',
      ),
      _finisherExercise(
        name: 'Mountain Climbers',
        sets: 3,
        reps: '30s',
        durationSeconds: 120,
        notes: 'Part 2 of HIIT circuit',
      ),
      _finisherExercise(
        name: 'Jump Squats',
        sets: 3,
        reps: '10',
        durationSeconds: 120,
        notes: 'Part 3 of HIIT circuit — 60s rest after each full round',
      ),
    ];
  }

  /// Jump Rope Intervals: 1 min on / 30s rest × 5 rounds (~7.5 min)
  static List<PlannedExercise> _jumpRopeFinisher() {
    return [
      _finisherExercise(
        name: 'Jump Rope Intervals',
        sets: 5,
        reps: '60s on / 30s rest',
        durationSeconds: 450,
        notes: '1 min continuous jump rope → 30s rest × 5 rounds',
      ),
    ];
  }

  /// Mini HIIT: high knees 30s + burpees 30s + mountain climbers 30s × 2 rounds (~5 min)
  /// Default for "hate_cardio" — shortest finisher.
  static List<PlannedExercise> _miniHiitFinisher() {
    return [
      _finisherExercise(
        name: 'High Knees',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 1/3 — go hard, minimal rest',
      ),
      _finisherExercise(
        name: 'Burpees',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 2/3',
      ),
      _finisherExercise(
        name: 'Mountain Climbers',
        sets: 2,
        reps: '30s',
        durationSeconds: 60,
        notes: 'Mini HIIT round 3/3 — 30s rest after each full round',
      ),
    ];
  }

  static PlannedExercise _finisherExercise({
    required String name,
    required int sets,
    required String reps,
    required int durationSeconds,
    String? notes,
  }) {
    return PlannedExercise(
      exerciseId: name.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_'),
      exerciseName: name,
      loggingType: 'timed',
      sets: sets,
      reps: reps,
      restSeconds: 0,
      durationSeconds: durationSeconds,
      notes: notes,
      category: 'finisher',
    );
  }
}
