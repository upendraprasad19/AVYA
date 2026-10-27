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

  group('WorkoutReceiptData.fromExerciseLogs after WorkoutWriteService.logExercise', () {
    test('renders 3 sets / 24 reps / 65kg max for weight_reps exercise', () async {
      final date = DateTime(2026, 5, 2);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 62.5, reps: 8),
          ExerciseSet(weightKg: 65, reps: 6),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue, reason: 'WorkoutWriteService.logExercise must succeed');

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull, reason: 'receipt must reconstruct from Hive index');
      expect(receipt!.totalSets, 3,
          reason: 'totalSets must read from set_number (writer) — not legacy sets_completed');
      expect(receipt.exercises, hasLength(1));
      final ex = receipt.exercises.first;
      expect(ex.sets, 3);
      expect(ex.totalReps, 24);
      expect(ex.maxWeightKg, 65);
      expect(ex.perSetBreakdown, hasLength(3),
          reason: 'perSetBreakdown must read from sets (writer) — not legacy sets_detail');
      expect(ex.perSetBreakdown[0].weightKg, 60);
      expect(ex.perSetBreakdown[2].reps, 6);
    });

    test('renders timed exercise with non-zero sets', () async {
      final date = DateTime(2026, 5, 2);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Plank',
        sets: [
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 45),
          ExerciseSet(weightKg: 0, reps: 0, durationSec: 60),
        ],
        source: WriteSource.activeWorkout,
      );

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull);
      expect(receipt!.totalSets, 2);
      expect(receipt.exercises.first.sets, 2);
      expect(receipt.exercises.first.totalDurationSeconds, 105);
    });

    test('legacy logs (sets_completed key) still render', () async {
      // Simulate a pre-Test-#6 Hive entry by writing the legacy shape directly.
      final dateKey = '2026-05-01';
      final wb = HiveService.instance.workoutBox;
      final logKey = 'exlog_${dateKey}_legacy';
      await wb.put(logKey, {
        'exercise_name': 'Squat',
        'date': dateKey,
        'sets_completed': 4,            // legacy key
        'reps_completed': 20,
        'weight_kg': 100.0,
        'volume_kg': 2000.0,
        'logging_type': 'weight_reps',
        'is_pr': false,
        'sets_detail': [                 // legacy key
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
          {'weight_kg': 100.0, 'reps': 5},
        ],
      });
      await wb.put('exercise_log_index_$dateKey', [logKey]);

      final r = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 1));
      expect(r, isNotNull);
      expect(r!.totalSets, 4, reason: 'fallback to sets_completed key must work');
      expect(r.exercises.first.perSetBreakdown, hasLength(4),
          reason: 'fallback to sets_detail key must work');
    });
  });
}
