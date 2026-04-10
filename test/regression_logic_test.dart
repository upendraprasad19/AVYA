import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// REGRESSION: Pure Logic Tests — No Hive, No Device Required
/// Run with: flutter test test/regression_logic_test.dart
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Covers the pure-Dart logic that was fixed in session 2026-04-01.
/// Tests that depend on Hive live in integration_test/flows/regression_bug_fixes_test.dart
/// and require an Android device.
///
/// R-L1  — [Bug 2]  receipt dedup: same exercise appears only once
/// R-L2  — [Bug 2]  receipt dedup: sets merged, max weight kept
/// R-L3  — [Bug 2]  receipt dedup: unique exercises are NOT deduplicated
/// R-L4  — [Bug 4]  ActiveWorkoutData defaults to isSaved=false
/// R-L5  — [Bug 4]  copyWith preserves isSaved=true (reopenWorkout path)
/// R-L6  — [Bug 4]  review state: isSaved=true, isComplete=false
/// R-L7  — [Bug 1]  SetInputValues stores all field types correctly
/// R-L8  — [Bug 1]  setInputValues map survives copyWith on timer tick
/// R-L9  — [Bug 3b] ExercisePR: bestValue and date are set correctly
/// R-L10 — [Bug 3a] WorkoutDayData: estimatedDuration calculates from sets

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // BUG 2 — WorkoutReceiptData.fromActiveWorkout deduplication
  // ─────────────────────────────────────────────────────────────────────────

  group('[Bug 2] Receipt deduplication', () {
    // Helper: builds ActiveWorkoutData with given exercises and uniform checked sets.
    ActiveWorkoutData buildData(
      List<ExerciseData> exercises, {
      Map<String, SetInputValues> overrideValues = const {},
    }) {
      final checkedSets = <String, bool>{};
      final setInputValues = <String, SetInputValues>{};
      for (int i = 0; i < exercises.length; i++) {
        final n = int.tryParse(exercises[i].sets) ?? 3;
        for (int s = 0; s < n; s++) {
          checkedSets['$i-$s'] = true;
          setInputValues['$i-$s'] = overrideValues['$i-$s'] ??
              const SetInputValues(weight: 40.0, reps: 10);
        }
      }
      final day = WorkoutDayData(
          dayNumber: 1, name: 'Test Day', exercises: exercises);
      return ActiveWorkoutData(
        workoutDay: day,
        exercises: exercises,
        elapsedSeconds: 1800,
        checkedSets: checkedSets,
        setInputValues: setInputValues,
        isComplete: true,
        isSaved: true,
      );
    }

    test('R-L1: duplicate exercise name appears exactly once', () {
      final exercises = [
        const ExerciseData(
            name: 'Tuck Planche Pushup',
            sets: '3',
            reps: '8',
            loggingType: 'bodyweight_reps'),
        const ExerciseData(
            name: 'Pull-up',
            sets: '3',
            reps: '10',
            loggingType: 'bodyweight_reps'),
        const ExerciseData(
            name: 'Tuck Planche Pushup', // duplicate
            sets: '2',
            reps: '6',
            loggingType: 'bodyweight_reps'),
      ];

      final receipt = WorkoutReceiptData.fromActiveWorkout(buildData(exercises));
      final names =
          receipt.exercises.map((e) => e.name.toLowerCase().trim()).toList();

      expect(names.toSet().length, equals(names.length),
          reason: 'No exercise name should appear more than once in the receipt');

      final plancheCount =
          names.where((n) => n.contains('tuck planche')).length;
      expect(plancheCount, equals(1),
          reason: '"Tuck Planche Pushup" must appear exactly once');
    });

    test('R-L2: duplicate exercises have sets merged and weight is max', () {
      // Bench Press appears twice: slot 0 (3 sets @ 60kg), slot 1 (2 sets @ 70kg).
      final exercises = [
        const ExerciseData(
            name: 'Bench Press', sets: '3', reps: '8', loggingType: 'weight_reps'),
        const ExerciseData(
            name: 'Bench Press', sets: '2', reps: '6', loggingType: 'weight_reps'),
      ];

      final values = <String, SetInputValues>{};
      for (int s = 0; s < 3; s++) {
        values['0-$s'] = const SetInputValues(weight: 60.0, reps: 8);
      }
      for (int s = 0; s < 2; s++) {
        values['1-$s'] = const SetInputValues(weight: 70.0, reps: 6);
      }

      final receipt =
          WorkoutReceiptData.fromActiveWorkout(buildData(exercises, overrideValues: values));

      final bench = receipt.exercises
          .firstWhere((e) => e.name.toLowerCase().contains('bench'));

      expect(bench.sets, equals(5),
          reason: 'Merged sets: 3 + 2 = 5');
      expect(bench.maxWeightKg, equals(70.0),
          reason: 'Merged weight: max(60, 70) = 70kg');
      expect(receipt.exercises.length, equals(1),
          reason: 'Only one exercise after deduplication');
    });

    test('R-L3: unique exercises are NOT collapsed', () {
      final exercises = [
        const ExerciseData(name: 'Squat', sets: '4', reps: '6', loggingType: 'weight_reps'),
        const ExerciseData(name: 'Romanian Deadlift', sets: '3', reps: '10', loggingType: 'weight_reps'),
        const ExerciseData(name: 'Leg Press', sets: '3', reps: '12', loggingType: 'weight_reps'),
      ];

      final receipt = WorkoutReceiptData.fromActiveWorkout(buildData(exercises));

      expect(receipt.exercises.length, equals(3),
          reason: 'Three unique exercises must all appear in the receipt');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 4 — isSaved flag logic
  // ─────────────────────────────────────────────────────────────────────────

  group('[Bug 4] isSaved flag state', () {
    test('R-L4: ActiveWorkoutData defaults to isSaved=false', () {
      const data = ActiveWorkoutData();
      expect(data.isSaved, isFalse,
          reason: 'Fresh workout must start with isSaved=false');
    });

    test('R-L5: copyWith(isComplete: false) preserves isSaved=true', () {
      // This is exactly the reopenWorkout() call:
      //   state = state.copyWith(isComplete: false);
      // isSaved MUST remain true so the second "Finish" tap does not re-write Hive.
      const saved = ActiveWorkoutData(isSaved: true, isComplete: true);
      final reopened = saved.copyWith(isComplete: false);

      expect(reopened.isSaved, isTrue,
          reason: 'isSaved must survive copyWith — prevents double Hive write on re-finish');
      expect(reopened.isComplete, isFalse,
          reason: 'isComplete must be false so workout form is shown again');
    });

    test('R-L6: review state is isSaved=true + isComplete=false', () {
      // Simulate the exact state the app should be in after "Review Workout" is tapped.
      const reviewState = ActiveWorkoutData(isSaved: true, isComplete: false);

      expect(reviewState.isSaved, isTrue);
      expect(reviewState.isComplete, isFalse);

      // The Finish button in this state should be disabled (greyed).
      // We verify the flag combination; UI assertion is in Tier-3 screenshot test.
    });

    test('R-L6b: copyWith on elapsedSeconds does not reset isSaved', () {
      // Timer ticks call: state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1)
      // This must not accidentally clear isSaved.
      const data = ActiveWorkoutData(isSaved: true, elapsedSeconds: 100);
      final ticked = data.copyWith(elapsedSeconds: 101);

      expect(ticked.isSaved, isTrue,
          reason: 'Timer tick (copyWith elapsedSeconds) must not clear isSaved');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 1 — SetInputValues: controller restore
  // ─────────────────────────────────────────────────────────────────────────

  group('[Bug 1] SetInputValues and controller restore', () {
    test('R-L7: SetInputValues stores weight_reps fields', () {
      const vals = SetInputValues(weight: 80.0, reps: 5);
      expect(vals.weight, equals(80.0));
      expect(vals.reps, equals(5));
      expect(vals.durationSeconds, isNull);
      expect(vals.distanceKm, isNull);
    });

    test('R-L7b: SetInputValues stores timed fields', () {
      const vals = SetInputValues(durationSeconds: 120);
      expect(vals.durationSeconds, equals(120));
      expect(vals.weight, isNull);
      expect(vals.reps, isNull);
    });

    test('R-L7c: SetInputValues stores cardio fields', () {
      const vals = SetInputValues(durationSeconds: 1800, distanceKm: 5.0);
      expect(vals.durationSeconds, equals(1800));
      expect(vals.distanceKm, equals(5.0));
      expect(vals.weight, isNull);
    });

    test('R-L8: setInputValues map survives copyWith (timer tick)', () {
      // _initControllers() restores from setInputValues after rebuild.
      // If copyWith clears this map, the controller restore will fail.
      const vals = {'0-0': SetInputValues(weight: 60.0, reps: 10)};
      const data = ActiveWorkoutData(setInputValues: vals);

      final updated = data.copyWith(elapsedSeconds: 30);

      expect(updated.setInputValues.containsKey('0-0'), isTrue,
          reason: 'setInputValues must survive copyWith — controllers restore from this');
      expect(updated.setInputValues['0-0']?.weight, equals(60.0));
      expect(updated.setInputValues['0-0']?.reps, equals(10));
    });

    test('R-L8b: setInputValues map survives checkSet copyWith', () {
      // toggleSet() calls: state = state.copyWith(checkedSets: updated, setInputValues: updated)
      // setInputValues for OTHER keys must not be lost.
      const initial = ActiveWorkoutData(
        setInputValues: {
          '0-0': SetInputValues(weight: 100.0, reps: 5),
          '0-1': SetInputValues(weight: 95.0, reps: 5),
        },
        checkedSets: {'0-0': true},
      );

      // Simulate checking set 0-1 (adds to checkedSets, extends setInputValues).
      final newChecked = Map<String, bool>.from(initial.checkedSets)
        ..['0-1'] = true;
      final newValues = Map<String, SetInputValues>.from(initial.setInputValues)
        ..['0-1'] = const SetInputValues(weight: 95.0, reps: 5);

      final updated = initial.copyWith(
        checkedSets: newChecked,
        setInputValues: newValues,
      );

      expect(updated.setInputValues['0-0']?.weight, equals(100.0),
          reason: 'First set values must be preserved when second set is checked');
      expect(updated.setInputValues['0-1']?.weight, equals(95.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 3b — ExercisePR data class (pure data, no Hive)
  // ─────────────────────────────────────────────────────────────────────────

  group('[Bug 3b] ExercisePR data class', () {
    test('R-L9: ExercisePR stores all fields correctly', () {
      final date = DateTime(2026, 4, 1);
      final pr = ExercisePR(
        exerciseName: 'Cable Fly',
        loggingType: 'weight_reps',
        bestValue: 25.0,
        date: date,
      );

      expect(pr.exerciseName, equals('Cable Fly'));
      expect(pr.loggingType, equals('weight_reps'));
      expect(pr.bestValue, equals(25.0));
      expect(pr.date, equals(date));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 3a — WorkoutDayData: estimatedDuration (adjacent logic)
  // ─────────────────────────────────────────────────────────────────────────

  group('[Bug 3a] WorkoutDayData duration', () {
    test('R-L10: estimatedDuration calculates correctly from set count', () {
      // 4 exercises × 3 sets = 12 sets × 2.5 min = 30 min.
      final day = WorkoutDayData(
        dayNumber: 1,
        name: 'Push Day',
        exercises: List.generate(
            4,
            (_) => const ExerciseData(
                name: 'Bench Press', sets: '3', loggingType: 'weight_reps')),
      );
      expect(day.estimatedDuration, equals('30 min'));
    });

    test('R-L10b: rest day returns empty duration string', () {
      final rest = WorkoutDayData(
        dayNumber: 1,
        name: 'Rest',
        isRest: true,
      );
      expect(rest.estimatedDuration, equals(''));
    });
  });
}
