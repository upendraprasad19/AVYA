import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';

/// Tests for PlanGenerator V2 — data models, effectiveLevel, copyWith,
/// and structural guarantees.
///
/// Note: The full pipeline (SplitSelector → ExerciseSelector →
/// PeriodizationEngine → SupersetPairer) requires Hive to be seeded with
/// exercise data. These unit tests validate:
/// 1. effectiveLevel() progression logic
/// 2. Data model construction + serialization
/// 3. PlannedExercise.copyWith() supports all fields
/// 4. WeekPlan model with weekCharacter
/// 5. Phase model with weekPlans + preferredDays
///
/// Full end-to-end tests with Hive run in integration_test/.
void main() {
  group('effectiveLevel()', () {
    test('advanced always returns advanced', () {
      for (final phase in [1, 2, 3, 4, 5, 6, 12]) {
        expect(PlanGenerator.effectiveLevel('advanced', phase), 'advanced');
      }
    });

    test('intermediate returns intermediate for phases 1-3', () {
      expect(PlanGenerator.effectiveLevel('intermediate', 1), 'intermediate');
      expect(PlanGenerator.effectiveLevel('intermediate', 2), 'intermediate');
      expect(PlanGenerator.effectiveLevel('intermediate', 3), 'intermediate');
    });

    test('intermediate returns advanced from phase 4+', () {
      expect(PlanGenerator.effectiveLevel('intermediate', 4), 'advanced');
      expect(PlanGenerator.effectiveLevel('intermediate', 8), 'advanced');
      expect(PlanGenerator.effectiveLevel('intermediate', 12), 'advanced');
    });

    test('beginner returns beginner for phases 1-2', () {
      expect(PlanGenerator.effectiveLevel('beginner', 1), 'beginner');
      expect(PlanGenerator.effectiveLevel('beginner', 2), 'beginner');
    });

    test('beginner returns intermediate for phases 3-4', () {
      expect(PlanGenerator.effectiveLevel('beginner', 3), 'intermediate');
      expect(PlanGenerator.effectiveLevel('beginner', 4), 'intermediate');
    });

    test('beginner returns advanced from phase 5+', () {
      expect(PlanGenerator.effectiveLevel('beginner', 5), 'advanced');
      expect(PlanGenerator.effectiveLevel('beginner', 10), 'advanced');
    });
  });

  group('PlannedExercise model', () {
    test('stores all fields correctly', () {
      const exercise = PlannedExercise(
        exerciseId: 'abc',
        exerciseName: 'Squat',
        loggingType: 'weight_reps',
        sets: 4,
        reps: '8-10',
        restSeconds: 120,
        supersetGroup: null,
        intensityProfile: 'strength',
        weightCue: 'Find working weight',
        variant: 'A',
        primaryMuscles: ['Quads', 'Glutes'],
      );
      expect(exercise.sets, 4);
      expect(exercise.reps, '8-10');
      expect(exercise.restSeconds, 120);
      expect(exercise.supersetGroup, isNull);
      expect(exercise.intensityProfile, 'strength');
      expect(exercise.weightCue, 'Find working weight');
      expect(exercise.variant, 'A');
      expect(exercise.primaryMuscles, ['Quads', 'Glutes']);
    });

    test('defaults: intensityProfile=hypertrophy, variant=A', () {
      const exercise = PlannedExercise(
        exerciseId: 'abc',
        exerciseName: 'Push-up',
        loggingType: 'bodyweight_reps',
        sets: 3,
        reps: '12',
        restSeconds: 60,
      );
      expect(exercise.intensityProfile, 'hypertrophy');
      expect(exercise.variant, 'A');
      expect(exercise.weightCue, isNull);
      expect(exercise.primaryMuscles, isNull);
    });

    test('toMap() includes V2 fields', () {
      const exercise = PlannedExercise(
        exerciseId: 'test-id',
        exerciseName: 'Bench Press',
        loggingType: 'weight_reps',
        sets: 4,
        reps: '5',
        restSeconds: 150,
        intensityProfile: 'strength',
        weightCue: '+2.5 kg',
        variant: 'B',
        primaryMuscles: ['Chest'],
        supersetGroup: 1,
      );
      final map = exercise.toMap();
      expect(map['intensity_profile'], 'strength');
      expect(map['weight_cue'], '+2.5 kg');
      expect(map['variant'], 'B');
      expect(map['primary_muscles'], ['Chest']);
      expect(map['superset_group'], 1);
    });

    test('toMap() omits null optional fields', () {
      const exercise = PlannedExercise(
        exerciseId: 'abc',
        exerciseName: 'Squat',
        loggingType: 'weight_reps',
        sets: 3,
        reps: '10',
        restSeconds: 75,
      );
      final map = exercise.toMap();
      expect(map.containsKey('superset_group'), isFalse);
      expect(map.containsKey('weight_cue'), isFalse);
      expect(map.containsKey('notes'), isFalse);
      expect(map.containsKey('duration_seconds'), isFalse);
      // intensity_profile and variant always present (have defaults)
      expect(map['intensity_profile'], 'hypertrophy');
      expect(map['variant'], 'A');
    });
  });

  group('PlannedExercise.copyWith()', () {
    const base = PlannedExercise(
      exerciseId: 'abc',
      exerciseName: 'Squat',
      loggingType: 'weight_reps',
      sets: 4,
      reps: '5',
      restSeconds: 150,
      intensityProfile: 'strength',
      variant: 'A',
      primaryMuscles: ['Quads'],
    );

    test('updates sets', () {
      final updated = base.copyWith(sets: 5);
      expect(updated.sets, 5);
      expect(updated.reps, '5'); // unchanged
      expect(updated.exerciseName, 'Squat'); // unchanged
    });

    test('updates reps', () {
      final updated = base.copyWith(reps: '8-10');
      expect(updated.reps, '8-10');
      expect(updated.sets, 4); // unchanged
    });

    test('updates restSeconds', () {
      final updated = base.copyWith(restSeconds: 90);
      expect(updated.restSeconds, 90);
    });

    test('updates supersetGroup', () {
      final updated = base.copyWith(supersetGroup: 0);
      expect(updated.supersetGroup, 0);
    });

    test('updates intensityProfile', () {
      final updated = base.copyWith(intensityProfile: 'hypertrophy');
      expect(updated.intensityProfile, 'hypertrophy');
    });

    test('updates weightCue', () {
      final updated = base.copyWith(weightCue: 'Recovery');
      expect(updated.weightCue, 'Recovery');
    });

    test('updates variant', () {
      final updated = base.copyWith(variant: 'B');
      expect(updated.variant, 'B');
    });

    test('updates primaryMuscles', () {
      final updated = base.copyWith(primaryMuscles: ['Chest', 'Triceps']);
      expect(updated.primaryMuscles, ['Chest', 'Triceps']);
    });

    test('updates notes', () {
      final updated = base.copyWith(notes: 'Focus on form');
      expect(updated.notes, 'Focus on form');
    });

    test('preserves unchanged fields', () {
      final updated = base.copyWith(sets: 5);
      expect(updated.exerciseId, 'abc');
      expect(updated.exerciseName, 'Squat');
      expect(updated.loggingType, 'weight_reps');
      expect(updated.reps, '5');
      expect(updated.restSeconds, 150);
      expect(updated.intensityProfile, 'strength');
      expect(updated.variant, 'A');
      expect(updated.primaryMuscles, ['Quads']);
    });
  });

  group('WeekPlan model', () {
    test('stores weekCharacter', () {
      const plan = WeekPlan(
        weekNumber: 1,
        weekInPhase: 1,
        overloadNotes: 'Baseline week',
        weekCharacter: 'baseline',
        workoutDays: [],
      );
      expect(plan.weekCharacter, 'baseline');
    });

    test('weekCharacter defaults to baseline', () {
      const plan = WeekPlan(
        weekNumber: 1,
        weekInPhase: 1,
        overloadNotes: 'test',
        workoutDays: [],
      );
      expect(plan.weekCharacter, 'baseline');
    });

    test('toMap() includes weekCharacter', () {
      const plan = WeekPlan(
        weekNumber: 4,
        weekInPhase: 4,
        overloadNotes: 'Deload week',
        weekCharacter: 'deload',
        workoutDays: [],
      );
      final map = plan.toMap();
      expect(map['week_character'], 'deload');
      expect(map['week_number'], 4);
      expect(map['week_in_phase'], 4);
    });

    test('valid week characters: baseline, overreach, peak, deload', () {
      const characters = ['baseline', 'overreach', 'peak', 'deload'];
      for (int i = 0; i < characters.length; i++) {
        final plan = WeekPlan(
          weekNumber: i + 1,
          weekInPhase: i + 1,
          overloadNotes: 'Week ${i + 1}',
          weekCharacter: characters[i],
          workoutDays: [],
        );
        expect(plan.weekCharacter, characters[i]);
      }
    });
  });

  group('WorkoutDay model', () {
    test('dayNumber starts from 1', () {
      const day = WorkoutDay(
        dayNumber: 1,
        name: 'Push Day',
        focus: 'Chest & Shoulders',
        exercises: [],
      );
      expect(day.dayNumber, 1);
    });

    test('stores exercises list', () {
      final exercises = [
        const PlannedExercise(
          exerciseId: 'test-id',
          exerciseName: 'Push-up',
          loggingType: 'bodyweight_reps',
          sets: 3,
          reps: '12',
          restSeconds: 60,
        ),
      ];
      final day = WorkoutDay(
        dayNumber: 1,
        name: 'Test',
        focus: 'Test',
        exercises: exercises,
      );
      expect(day.exercises.length, 1);
      expect(day.exercises.first.exerciseName, 'Push-up');
    });

    test('toMap() serializes exercises', () {
      const day = WorkoutDay(
        dayNumber: 2,
        name: 'Pull',
        focus: 'Back',
        exercises: [
          PlannedExercise(
            exerciseId: 'id1',
            exerciseName: 'Lat Pulldown',
            loggingType: 'weight_reps',
            sets: 3,
            reps: '10',
            restSeconds: 75,
          ),
        ],
      );
      final map = day.toMap();
      expect(map['day_number'], 2);
      expect(map['name'], 'Pull');
      expect((map['exercises'] as List).length, 1);
    });
  });

  group('Phase model', () {
    test('stores all required fields', () {
      const phase = Phase(
        phase: 1,
        name: 'Foundation',
        focus: 'Movement patterns',
        weeks: '1-4',
        dailyCalories: 2200,
        proteinGrams: 150,
        workouts: [],
        weekPlans: [],
      );
      expect(phase.phase, 1);
      expect(phase.name, 'Foundation');
      expect(phase.focus, isNotEmpty);
      expect(phase.weeks, '1-4');
      expect(phase.dailyCalories, 2200);
      expect(phase.proteinGrams, 150);
      expect(phase.preferredDays, isNull);
    });

    test('stores preferredDays', () {
      const phase = Phase(
        phase: 1,
        name: 'Foundation',
        focus: 'Movement patterns',
        weeks: '1-4',
        dailyCalories: 0,
        proteinGrams: 0,
        workouts: [],
        weekPlans: [],
        preferredDays: [0, 2, 4],
      );
      expect(phase.preferredDays, [0, 2, 4]);
    });

    test('toMap() includes weekPlans and preferredDays', () {
      const phase = Phase(
        phase: 2,
        name: 'Adaptation',
        focus: 'Building work capacity',
        weeks: '5-8',
        dailyCalories: 2400,
        proteinGrams: 160,
        workouts: [],
        weekPlans: [
          WeekPlan(
            weekNumber: 5,
            weekInPhase: 1,
            overloadNotes: 'Baseline',
            weekCharacter: 'baseline',
            workoutDays: [],
          ),
        ],
        preferredDays: [0, 1, 3, 5],
      );
      final map = phase.toMap();
      expect(map['phase'], 2);
      expect(map['week_plans'], isList);
      expect((map['week_plans'] as List).length, 1);
      expect(map['preferred_days'], [0, 1, 3, 5]);
    });

    test('toMap() omits preferredDays when null', () {
      const phase = Phase(
        phase: 1,
        name: 'Foundation',
        focus: 'test',
        weeks: '1-4',
        dailyCalories: 0,
        proteinGrams: 0,
        workouts: [],
        weekPlans: [],
      );
      final map = phase.toMap();
      expect(map.containsKey('preferred_days'), isFalse);
    });

    test('workouts = backward compatibility (week 1 exercises)', () {
      const exercises = [
        PlannedExercise(
          exerciseId: 'e1',
          exerciseName: 'Bench Press',
          loggingType: 'weight_reps',
          sets: 4,
          reps: '5',
          restSeconds: 150,
        ),
      ];
      const week1Day = WorkoutDay(
        dayNumber: 1,
        name: 'Push',
        focus: 'Chest',
        exercises: exercises,
      );

      // workouts should mirror week 1 for backward compat
      const phase = Phase(
        phase: 1,
        name: 'Foundation',
        focus: 'test',
        weeks: '1-4',
        dailyCalories: 0,
        proteinGrams: 0,
        workouts: [week1Day],
        weekPlans: [],
      );
      expect(phase.workouts.length, 1);
      expect(phase.workouts[0].exercises[0].exerciseName, 'Bench Press');
    });
  });

  group('Phase with 4 distinct WeekPlans', () {
    final weekPlans = List.generate(4, (i) {
      const characters = ['baseline', 'overreach', 'peak', 'deload'];
      return WeekPlan(
        weekNumber: i + 1,
        weekInPhase: i + 1,
        overloadNotes: 'Week ${i + 1} notes',
        weekCharacter: characters[i],
        workoutDays: [
          WorkoutDay(
            dayNumber: 1,
            name: 'Push',
            focus: 'Chest',
            exercises: [
              PlannedExercise(
                exerciseId: 'e_w${i}_1',
                exerciseName: 'Exercise W${i + 1}',
                loggingType: 'weight_reps',
                sets: 3 + (i == 1 ? 1 : 0), // overreach: +1 set
                reps: '${10 - (i == 2 ? 2 : 0)}', // peak: -2 reps
                restSeconds: 75,
                variant: i % 2 == 0 ? 'A' : 'B',
                weightCue: [
                  'Find working weight', 'Same weight, more volume',
                  '+2.5 kg if Week 2 felt good', 'Recovery week',
                ][i],
              ),
            ],
          ),
        ],
      );
    });

    test('4 weeks have distinct characters', () {
      final characters = weekPlans.map((w) => w.weekCharacter).toSet();
      expect(characters.length, 4);
      expect(characters, containsAll(['baseline', 'overreach', 'peak', 'deload']));
    });

    test('A/B alternation: weeks 1,3 = A; weeks 2,4 = B', () {
      for (int i = 0; i < 4; i++) {
        final variant = weekPlans[i].workoutDays[0].exercises[0].variant;
        expect(variant, i % 2 == 0 ? 'A' : 'B',
            reason: 'Week ${i + 1} should be variant ${i % 2 == 0 ? "A" : "B"}');
      }
    });

    test('overreach week has +1 set vs baseline', () {
      final baselineSets = weekPlans[0].workoutDays[0].exercises[0].sets;
      final overreachSets = weekPlans[1].workoutDays[0].exercises[0].sets;
      expect(overreachSets, baselineSets + 1);
    });

    test('peak week has fewer reps than baseline', () {
      final baselineReps = int.parse(weekPlans[0].workoutDays[0].exercises[0].reps);
      final peakReps = int.parse(weekPlans[2].workoutDays[0].exercises[0].reps);
      expect(peakReps, lessThan(baselineReps));
    });

    test('each week has a weightCue', () {
      for (final week in weekPlans) {
        final cue = week.workoutDays[0].exercises[0].weightCue;
        expect(cue, isNotNull);
        expect(cue, isNotEmpty);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════
  // WARM-UP & COOL-DOWN
  // ════════════════════════════════════════════════════════════════

  group('WorkoutDay warmup/cooldown model', () {
    test('default warmup and cooldown are empty', () {
      const day = WorkoutDay(
        dayNumber: 1,
        name: 'Push',
        focus: 'Chest & Triceps',
        exercises: [],
      );
      expect(day.warmup, isEmpty);
      expect(day.cooldown, isEmpty);
    });

    test('toMap omits warmup/cooldown when empty (backward compat)', () {
      const day = WorkoutDay(
        dayNumber: 1,
        name: 'Push',
        focus: 'Chest & Triceps',
        exercises: [],
      );
      final map = day.toMap();
      expect(map.containsKey('warmup'), isFalse);
      expect(map.containsKey('cooldown'), isFalse);
    });

    test('toMap includes warmup/cooldown when non-empty', () {
      final day = WorkoutDay(
        dayNumber: 1,
        name: 'Push',
        focus: 'Chest & Triceps',
        exercises: const [],
        warmup: [
          PlannedExercise(
            exerciseId: 'Spot Jogging',
            exerciseName: 'Spot Jogging',
            loggingType: 'timed',
            sets: 1,
            reps: '300s',
            restSeconds: 0,
            category: 'warmup',
          ),
        ],
        cooldown: [
          PlannedExercise(
            exerciseId: 'Slow Walking',
            exerciseName: 'Slow Walking',
            loggingType: 'timed',
            sets: 1,
            reps: '300s',
            restSeconds: 0,
            category: 'cooldown',
          ),
        ],
      );
      final map = day.toMap();
      expect(map.containsKey('warmup'), isTrue);
      expect(map.containsKey('cooldown'), isTrue);
      expect((map['warmup'] as List).length, 1);
      expect((map['cooldown'] as List).length, 1);
    });

    test('warmup exercises have correct category', () {
      final warmup = PlannedExercise(
        exerciseId: 'Arm Circles',
        exerciseName: 'Arm Circles',
        loggingType: 'timed',
        sets: 1,
        reps: '60s',
        restSeconds: 0,
        category: 'warmup',
      );
      expect(warmup.category, 'warmup');
      expect(warmup.sets, 1);
      expect(warmup.restSeconds, 0);
    });

    test('cooldown exercises have correct category', () {
      final cooldown = PlannedExercise(
        exerciseId: 'Standing Toe Touch',
        exerciseName: 'Standing Toe Touch',
        loggingType: 'timed',
        sets: 1,
        reps: '30s',
        restSeconds: 0,
        category: 'cooldown',
      );
      expect(cooldown.category, 'cooldown');
      expect(cooldown.sets, 1);
    });

    test('warmup/cooldown serializes correctly in toMap', () {
      final warmup = PlannedExercise(
        exerciseId: 'Jumping Jacks',
        exerciseName: 'Jumping Jacks',
        loggingType: 'timed',
        sets: 1,
        reps: '300s',
        restSeconds: 0,
        category: 'warmup',
      );
      final map = warmup.toMap();
      expect(map['exercise_name'], 'Jumping Jacks');
      expect(map['logging_type'], 'timed');
      expect(map['sets'], 1);
      expect(map['reps'], '300s');
      expect(map['rest_seconds'], 0);
      expect(map['category'], 'warmup');
    });

    test('activation exercise uses bodyweight_reps logging', () {
      final activation = PlannedExercise(
        exerciseId: 'Wall Push Up',
        exerciseName: 'Wall Push Up',
        loggingType: 'bodyweight_reps',
        sets: 1,
        reps: '10',
        restSeconds: 0,
        category: 'warmup',
      );
      expect(activation.loggingType, 'bodyweight_reps');
      expect(activation.reps, '10');
    });
  });
}
