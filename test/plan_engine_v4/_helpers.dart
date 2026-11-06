// Shared test helpers for the plan_engine_v4 test suite.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 as part of the
// tech-debt audit B5 split (T7). Test BODIES are unchanged from V3; only the
// physical location moved. Helpers are made public (no leading underscore) so
// they can be imported across the split files.

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

/// Build a PlannedExercise with sensible defaults, overridable per-field.
PlannedExercise exercise({
  String name = 'Test Exercise',
  String loggingType = 'weight_reps',
  int sets = 3,
  String reps = '10',
  int restSeconds = 75,
  String? exerciseType,
  int? supersetGroup,
  String? category,
  String intensityProfile = 'hypertrophy',
  String variant = 'A',
  List<String>? primaryMuscles,
  bool warmupSet = false,
}) {
  return PlannedExercise(
    exerciseId: name.toLowerCase().replaceAll(' ', '_'),
    exerciseName: name,
    loggingType: loggingType,
    sets: sets,
    reps: reps,
    restSeconds: restSeconds,
    exerciseType: exerciseType,
    supersetGroup: supersetGroup,
    category: category,
    intensityProfile: intensityProfile,
    variant: variant,
    primaryMuscles: primaryMuscles,
    warmupSet: warmupSet,
  );
}

/// Build a WorkoutDay with default name/focus and given exercises.
WorkoutDay workoutDay({
  int dayNumber = 1,
  String name = 'Push',
  String focus = 'Chest & Triceps',
  List<PlannedExercise>? exercises,
  List<PlannedExercise> warmup = const [],
  List<PlannedExercise> cooldown = const [],
  List<PlannedExercise> finisher = const [],
}) {
  return WorkoutDay(
    dayNumber: dayNumber,
    name: name,
    focus: focus,
    exercises: exercises ?? [exercise()],
    warmup: warmup,
    cooldown: cooldown,
    finisher: finisher,
  );
}

/// Build a WeekPlan with given workout days.
WeekPlan weekPlan({
  int weekNumber = 1,
  int weekInPhase = 1,
  String weekCharacter = 'baseline',
  String overloadNotes = 'Test week',
  List<WorkoutDay>? workoutDays,
}) {
  return WeekPlan(
    weekNumber: weekNumber,
    weekInPhase: weekInPhase,
    overloadNotes: overloadNotes,
    weekCharacter: weekCharacter,
    workoutDays: workoutDays ?? [workoutDay()],
  );
}

/// Build a PopulatedDay for PeriodizationEngine.apply().
PopulatedDay populatedDay({
  String name = 'Push',
  String focus = 'Chest',
  String dayType = 'push',
  String intensity = 'hypertrophy',
  List<PlannedExercise>? exercisesA,
  List<PlannedExercise>? exercisesB,
}) {
  final a = exercisesA ?? [
    exercise(name: 'Bench Press', exerciseType: 'compound'),
    exercise(name: 'Incline Dumbbell Press', exerciseType: 'compound'),
    exercise(name: 'Cable Fly', exerciseType: 'isolation'),
  ];
  return PopulatedDay(
    name: name,
    focus: focus,
    dayType: dayType,
    intensity: intensity,
    exercisesA: a,
    exercisesB: exercisesB ?? a,
  );
}
