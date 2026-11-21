// Behavioral contract test: workout_receipt_rendering
//
// Writer: WorkoutWriteService.logExercise  (lib/core/services/workout_write_service.dart)
// Reader: WorkoutReceiptData.fromExerciseLogs  (lib/features/train/widgets/workout_receipt_card.dart)
//
// Asserts:
//   - Receipt dedupes by name across two calls with the same exercise name.
//   - Receipt sums sets (set_number), sums reps (reps_completed), takes max weight.
//   - Receipt is scoped to today's IST date — a log on a different date does NOT bleed in.
//
// This test FAILS if:
//   - WorkoutWriteService renames `set_number`, `reps_completed`, or `weight_kg`.
//   - WorkoutReceiptData changes its deduplication or aggregation logic.
//   - The index key formula drifts between writer (istDateStr) and reader (formatDateKey).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('workout_receipt_rendering — writer → receipt reader contract', () {
    test('receipt dedupes by name and merges sets across two logExercise calls', () async {
      final date = DateTime(2026, 6, 15);

      // First log: 2 sets
      final r1 = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: const [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 65, reps: 8),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r1.success, isTrue, reason: 'first logExercise must succeed');

      // Second log of same exercise in same session: 1 extra set.
      // WriterService MERGES (appends) new sets to the same exlog key (same date+name → same key).
      // 60s dedup window: new set has different weight → not a duplicate → appended.
      // Post-merge: set_number=3, weight_kg=max(60,65,70)=70, reps_completed=10+8+5=23.
      final r2 = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: const [
          ExerciseSet(weightKg: 70, reps: 5),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r2.success, isTrue, reason: 'second logExercise must succeed');

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull,
          reason: 'receipt reader must reconstruct from writer output');

      // Same exercise name, same date → same exlogKey. Writer merges sets (not overwrites).
      // Post-merge: set_number=3, reps_completed=23, weight_kg=70.
      expect(receipt!.exercises, hasLength(1),
          reason: 'receipt must have exactly 1 exercise entry (deduped by name+date key)');
      final ex = receipt.exercises.first;
      expect(ex.name.toLowerCase(), 'bench press');

      // set_number is recomputed from merged sets.length = 3.
      expect(ex.sets, 3,
          reason: 'sets must equal set_number = total merged sets (2 original + 1 new) '
              '— if this fails, set_number field was renamed in the writer');
      // reps_completed = 10+8+5 = 23.
      expect(ex.totalReps, 23,
          reason: 'totalReps maps to reps_completed (sum of merged sets: 10+8+5=23)');
      // weight_kg = max across all merged sets = 70.
      expect(ex.maxWeightKg, 70.0,
          reason: 'maxWeightKg maps to weight_kg (max of merged sets: max(60,65,70)=70)');
    });

    test('receipt is scoped to the IST date — log from another date does NOT appear', () async {
      final targetDate = DateTime(2026, 6, 15);
      final otherDate = DateTime(2026, 6, 14); // previous day

      // Write on the other date — must NOT appear in targetDate receipt.
      final rOther = await WorkoutWriteService.instance.logExercise(
        date: otherDate,
        exerciseName: 'Squat',
        sets: const [ExerciseSet(weightKg: 80, reps: 5)],
        source: WriteSource.activeWorkout,
      );
      expect(rOther.success, isTrue);

      // Write on the target date.
      final rTarget = await WorkoutWriteService.instance.logExercise(
        date: targetDate,
        exerciseName: 'Deadlift',
        sets: const [ExerciseSet(weightKg: 100, reps: 3)],
        source: WriteSource.activeWorkout,
      );
      expect(rTarget.success, isTrue);

      final receipt = WorkoutReceiptData.fromExerciseLogs(targetDate);
      expect(receipt, isNotNull);
      expect(receipt!.exercises, hasLength(1),
          reason: 'only the targetDate log must appear — date-scoping must work');
      expect(receipt.exercises.first.name.toLowerCase(), 'deadlift');
    });

    test('receipt field names: totalSets=set_number, totalReps=reps_completed, maxWeightKg=weight_kg', () async {
      final date = DateTime(2026, 6, 15);
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Overhead Press',
        sets: const [
          ExerciseSet(weightKg: 40, reps: 8),
          ExerciseSet(weightKg: 42.5, reps: 6),
          ExerciseSet(weightKg: 45, reps: 4),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r.success, isTrue);

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull);
      final ex = receipt!.exercises.first;

      // If writer renames `set_number` → test fails here.
      expect(ex.sets, 3,
          reason: 'ReceiptExercise.sets reads set_number from writer');
      // If writer renames `reps_completed` → test fails here.
      expect(ex.totalReps, 18,
          reason: 'ReceiptExercise.totalReps reads reps_completed (8+6+4=18)');
      // If writer renames `weight_kg` (max) → test fails here.
      expect(ex.maxWeightKg, 45.0,
          reason: 'ReceiptExercise.maxWeightKg reads weight_kg (max of sets)');
      // perSetBreakdown reads the `sets` array — if key is renamed, length drops to 0.
      expect(ex.perSetBreakdown, hasLength(3),
          reason: 'perSetBreakdown reads sets[] array written by logExercise');
    });
  });
}
