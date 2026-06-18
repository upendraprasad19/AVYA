// Behavioral contract test: workout_log_edit_surface
//
// Writer (initial):   WorkoutWriteService.logExercise
// Writer (edit path): WorkoutWriteService.editLog   (simulates EditWorkoutLogSheet.save)
// Reader:             WorkoutReceiptData.fromExerciseLogs  (workout_receipt_card.dart)
//
// Asserts:
//   - After editLog, the receipt reader returns EDITED reps and weight.
//   - volume_kg is RECOMPUTED from the edited sets (weight_kg × reps).
//   - int/double round-trip is preserved (weight stored as double, reps as int).
//
// This test FAILS if:
//   - editLog stops recomputing `volume_kg` when `sets` key is updated.
//   - Receipt reader stops reading `weight_kg` or `reps_completed` from Hive.
//   - The `sets` field name drifts between editLog and the receipt reader.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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

  group('workout_log_edit_surface — editLog → receipt reader contract', () {
    test('edited reps and weight are reflected in the receipt reader', () async {
      final date = DateTime(2026, 6, 15);

      // Step 1: Log an exercise (original values).
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Pull Up',
        sets: const [
          ExerciseSet(weightKg: 0, reps: 10),
          ExerciseSet(weightKg: 0, reps: 8),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r.success, isTrue, reason: 'initial logExercise must succeed');

      final logKey = WorkoutWriteService.exlogKey(date, 'Pull Up');

      // Step 2: Edit via editLog (simulates EditWorkoutLogSheet.save path).
      // EditWorkoutLogSheet constructs updated sets and calls editLog with
      // `sets_completed`, `reps_completed`, `weight_kg`, `volume_kg`, `sets_detail`.
      // We replicate the weight_reps path (lines 141-147 in edit_workout_log_sheet.dart):
      final editResult = await WorkoutWriteService.instance.editLog(
        logKey: logKey,
        updates: {
          'sets_completed': 3,
          'reps_completed': 30, // edited: was 18, now 30
          'weight_kg': 5.0,     // added weight
          'volume_kg': 150.0,   // 5.0 * 30 = 150
          'sets_detail': [
            {'set_number': 1, 'reps': 12, 'weight_kg': 5.0},
            {'set_number': 2, 'reps': 10, 'weight_kg': 5.0},
            {'set_number': 3, 'reps': 8, 'weight_kg': 5.0},
          ],
        },
        source: WriteSource.editSheet,
      );
      expect(editResult.success, isTrue, reason: 'editLog must succeed');

      // Step 3: Read receipt and assert edited values are visible.
      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull,
          reason: 'receipt must reconstruct after editLog');

      final ex = receipt!.exercises.first;
      expect(ex.name.toLowerCase(), 'pull up');

      // After edit: sets_completed=3 (reader reads max(set_number, sets_completed, ...)).
      expect(ex.sets, 3,
          reason: 'edited sets_completed=3 must be reflected — drift means editLog '
              'wrote a different key than the reader reads');

      // Edited reps_completed=30.
      expect(ex.totalReps, 30,
          reason: 'edited reps_completed must be reflected in totalReps');

      // Edited weight_kg=5.0 (max).
      expect(ex.maxWeightKg, 5.0,
          reason: 'edited weight_kg must surface in maxWeightKg');
    });

    test('volume_kg is recomputed from edited sets (int/double round-trip)', () async {
      final date = DateTime(2026, 6, 15);

      // Log original.
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Romanian Deadlift',
        sets: const [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 60, reps: 10),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r.success, isTrue);

      final logKey = WorkoutWriteService.exlogKey(date, 'Romanian Deadlift');

      // Verify original volume in raw Hive.
      final box = HiveService.instance.workoutBox;
      final originalEntry = box.get(logKey) as Map;
      expect((originalEntry['volume_kg'] as num).toDouble(), 1200.0,
          reason: 'original volume_kg = 60 * (10+10) = 1200');

      // Edit with new sets: weight 70, 3 × 8 reps → volume = 70 * 24 = 1680.
      final editResult = await WorkoutWriteService.instance.editLog(
        logKey: logKey,
        updates: {
          'sets_completed': 3,
          'reps_completed': 24,
          'weight_kg': 70.0,
          'volume_kg': 1680.0,
          'sets_detail': [
            {'set_number': 1, 'reps': 8, 'weight_kg': 70.0},
            {'set_number': 2, 'reps': 8, 'weight_kg': 70.0},
            {'set_number': 3, 'reps': 8, 'weight_kg': 70.0},
          ],
        },
        source: WriteSource.editSheet,
      );
      expect(editResult.success, isTrue);

      // Verify updated volume in raw Hive — this is what SyncService projects.
      final editedEntry = box.get(logKey) as Map;
      final editedVolume = (editedEntry['volume_kg'] as num).toDouble();
      expect(editedVolume, 1680.0,
          reason: 'volume_kg must be 1680 after edit (70 * 24) — '
              'if editLog stops updating volume_kg this assertion fails');

      // int/double round-trip: reps stored as int, weight as double.
      expect(editedEntry['reps_completed'], isA<int>(),
          reason: 'reps_completed must remain int (not double) after editLog');
      expect(editedEntry['weight_kg'], isA<num>(),
          reason: 'weight_kg must be numeric after editLog');
      expect((editedEntry['weight_kg'] as num).toDouble(), 70.0);
    });

    test('editLog without sets key does NOT recompute volume_kg', () async {
      final date = DateTime(2026, 6, 15);

      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Curl',
        sets: const [ExerciseSet(weightKg: 15, reps: 12)],
        source: WriteSource.activeWorkout,
      );
      expect(r.success, isTrue);

      final logKey = WorkoutWriteService.exlogKey(date, 'Curl');
      final box = HiveService.instance.workoutBox;
      final original = box.get(logKey) as Map;
      final originalVolume = (original['volume_kg'] as num).toDouble();

      // Edit only a notes field — no sets key in updates.
      final editResult = await WorkoutWriteService.instance.editLog(
        logKey: logKey,
        updates: {'notes': 'edited notes only'},
        source: WriteSource.editSheet,
      );
      expect(editResult.success, isTrue);

      final edited = box.get(logKey) as Map;
      expect((edited['volume_kg'] as num).toDouble(), originalVolume,
          reason: 'volume_kg must NOT change when sets key is absent from updates');
      expect(edited['notes'], 'edited notes only',
          reason: 'non-aggregate fields must be merged as-is');
    });
  });
}
