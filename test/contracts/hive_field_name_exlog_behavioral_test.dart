// Behavioral contract test: hive_field_name_exlog
//
// Writer: WorkoutWriteService.logExercise
// Reader: WorkoutReceiptData.fromExerciseLogs + WorkoutRepository.getExerciseLogsForDate
//         + EditWorkoutLogSheet (via EditLogExerciseRow.fromLog)
//
// Asserts the EXACT field key names that the writer emits and that readers consume:
//   exercise_name, set_number, reps_completed, weight_kg, volume_kg, logging_type
//
// This test FAILS if:
//   - Writer renames any of those 6 keys (write-side rename = reader gets null/default).
//   - A future refactor changes the key spelling on either side.
//
// Pin: exact string equality on Map keys — not just presence.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
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

  group('hive_field_name_exlog — exact field-name contract', () {
    test('writer emits all 6 canonical field names', () async {
      final date = DateTime(2026, 6, 15);
      final r = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Barbell Row',
        sets: const [
          ExerciseSet(weightKg: 80, reps: 8),
          ExerciseSet(weightKg: 80, reps: 8),
          ExerciseSet(weightKg: 80, reps: 8),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(r.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final entry = box.get(WorkoutWriteService.exlogKey(date, 'Barbell Row')) as Map;

      // Each assertion: the KEY spelling must match exactly.
      // Rename either side → assertion fails with null.
      expect(entry.containsKey('exercise_name'), isTrue,
          reason: 'field "exercise_name" missing — writer renamed it');
      expect(entry['exercise_name'], 'Barbell Row');

      expect(entry.containsKey('set_number'), isTrue,
          reason: 'field "set_number" missing — writer renamed it');
      expect(entry['set_number'], 3,
          reason: 'set_number = number of sets logged');

      expect(entry.containsKey('reps_completed'), isTrue,
          reason: 'field "reps_completed" missing — writer renamed it');
      expect(entry['reps_completed'], 24,
          reason: 'reps_completed = sum of all sets reps (8+8+8=24)');

      expect(entry.containsKey('weight_kg'), isTrue,
          reason: 'field "weight_kg" missing — writer renamed it');
      expect((entry['weight_kg'] as num).toDouble(), 80.0,
          reason: 'weight_kg = max weight across sets');

      expect(entry.containsKey('volume_kg'), isTrue,
          reason: 'field "volume_kg" missing — writer renamed it');
      expect((entry['volume_kg'] as num).toDouble(), 1920.0,
          reason: 'volume_kg = sum(weight * reps) = 80*8 + 80*8 + 80*8 = 1920');

      expect(entry.containsKey('logging_type'), isTrue,
          reason: 'field "logging_type" missing — writer renamed it');
      expect(entry['logging_type'], 'weight_reps',
          reason: 'logging_type defaults to weight_reps for weighted exercises');
    });

    test('reader WorkoutRepository.getExerciseLogsForDate reads the exact writer keys', () async {
      final date = DateTime(2026, 6, 15);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Lat Pulldown',
        sets: const [
          ExerciseSet(weightKg: 50, reps: 12),
          ExerciseSet(weightKg: 55, reps: 10),
        ],
        source: WriteSource.activeWorkout,
      );

      final logs = WorkoutRepository.instance.getExerciseLogsForDate(date);
      expect(logs, hasLength(1));
      final log = logs.first;

      // Reader must surface the same key names the writer wrote.
      expect(log['exercise_name'], 'Lat Pulldown',
          reason: 'reader must read exercise_name — rename breaks AI coach + receipt');
      expect(log['set_number'], 2,
          reason: 'reader must read set_number — rename breaks receipt sets count');
      expect(log['reps_completed'], 22,
          reason: 'reader must read reps_completed — rename breaks receipt totalReps');
      expect((log['weight_kg'] as num).toDouble(), 55.0,
          reason: 'reader must read weight_kg — rename breaks receipt maxWeight');
      expect((log['volume_kg'] as num).toDouble(), closeTo(1150.0, 0.01),
          reason: 'reader must read volume_kg — 50*12 + 55*10 = 600+550=1150');
      expect(log['logging_type'], 'weight_reps',
          reason: 'reader must read logging_type — rename breaks edit-sheet UI branching');
    });

    test('reader WorkoutReceiptData.fromExerciseLogs maps writer keys to ReceiptExercise fields', () async {
      final date = DateTime(2026, 6, 15);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Incline Press',
        sets: const [
          ExerciseSet(weightKg: 55, reps: 10),
          ExerciseSet(weightKg: 60, reps: 8),
        ],
        source: WriteSource.activeWorkout,
      );

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull);
      final ex = receipt!.exercises.first;

      // ReceiptExercise.sets reads `set_number` from Hive.
      expect(ex.sets, 2,
          reason: 'ReceiptExercise.sets must read set_number — rename on writer side '
              'means receipt shows 0 sets');

      // ReceiptExercise.totalReps reads `reps_completed`.
      expect(ex.totalReps, 18,
          reason: 'ReceiptExercise.totalReps must read reps_completed (10+8=18)');

      // ReceiptExercise.maxWeightKg reads `weight_kg`.
      expect(ex.maxWeightKg, 60.0,
          reason: 'ReceiptExercise.maxWeightKg must read weight_kg (max=60)');

      // loggingType reads `logging_type`.
      expect(ex.loggingType, 'weight_reps',
          reason: 'ReceiptExercise.loggingType must read logging_type');
    });

    test('sets array field name: writer writes "sets", reader reads "sets"', () async {
      final date = DateTime(2026, 6, 15);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Hip Thrust',
        sets: const [
          ExerciseSet(weightKg: 90, reps: 12),
          ExerciseSet(weightKg: 90, reps: 10),
        ],
        source: WriteSource.activeWorkout,
      );

      // Raw Hive check: writer must use key "sets" (not "sets_detail" for new logs).
      final box = HiveService.instance.workoutBox;
      final entry = box.get(WorkoutWriteService.exlogKey(date, 'Hip Thrust')) as Map;
      expect(entry.containsKey('sets'), isTrue,
          reason: 'writer must write per-set data under key "sets" — '
              'rename to sets_detail or sets_data breaks perSetBreakdown in receipt');
      final sets = entry['sets'] as List;
      expect(sets, hasLength(2),
          reason: 'sets[] must have 2 entries matching logExercise input');

      // Receipt perSetBreakdown reads the `sets` array.
      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt!.exercises.first.perSetBreakdown, hasLength(2),
          reason: 'perSetBreakdown reads sets[] — if key changed, length = 0');
    });
  });
}
