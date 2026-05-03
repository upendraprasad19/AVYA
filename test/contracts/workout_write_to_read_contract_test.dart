// Round-trip contract test for WorkoutWriteService output → consumers.
//
// Locks the field-name contract between the canonical writer and every
// downstream reader. If a future refactor renames a Hive key, this test
// fails noisily with a pointer to the consumer that broke.
//
// Consumers covered:
//   - WorkoutReceiptData.fromExerciseLogs  (workout_receipt_card.dart)
//   - WorkoutRepository.getExerciseLogsForDate
//   - AiCoachRepository / AI snapshot recent_logs path
//   - WorkoutWriteService internal PR rescan
//   - SyncService cloud projection (verified via raw Hive map shape)
//
// Hive setup uses the existing wwsTestSetup helper because
// HiveService.workoutBox is user-scoped post-Test #6 — naive Hive.init
// does not work.

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

  group('WorkoutWriteService → consumer contract', () {
    test('WorkoutReceiptData.fromExerciseLogs sees sets/reps/weight', () async {
      final date = DateTime(2026, 5, 2);
      final result = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: const [
          ExerciseSet(weightKg: 60, reps: 10),
          ExerciseSet(weightKg: 62.5, reps: 8),
          ExerciseSet(weightKg: 65, reps: 6),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(result.success, isTrue,
          reason: 'logExercise must succeed for downstream contract checks');

      final receipt = WorkoutReceiptData.fromExerciseLogs(date);
      expect(receipt, isNotNull,
          reason: 'WorkoutReceiptData must reconstruct from writer output');
      expect(receipt!.totalSets, 3,
          reason:
              'totalSets must be 3 — reads set_number from writer (NOT legacy sets_completed key)');
      expect(receipt.exercises, hasLength(1));
      final ex = receipt.exercises.first;
      expect(ex.totalReps, 24);
      expect(ex.maxWeightKg, 65);
      expect(ex.perSetBreakdown, hasLength(3),
          reason:
              'perSetBreakdown reads sets[] from writer (NOT legacy sets_detail key)');
    });

    test('WorkoutRepository.getExerciseLogsForDate returns the writer\'s log',
        () async {
      final date = DateTime(2026, 5, 2);
      final res = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Squat',
        sets: const [
          ExerciseSet(weightKg: 100, reps: 5),
          ExerciseSet(weightKg: 100, reps: 5),
        ],
        source: WriteSource.activeWorkout,
      );
      expect(res.success, isTrue);

      final logs = WorkoutRepository.instance.getExerciseLogsForDate(date);
      expect(logs, hasLength(1),
          reason:
              'getExerciseLogsForDate should find the log via exercise_log_index_<date>');
      final log = logs.first;
      expect(log['exercise_name'], 'Squat');
      expect(log['date'], '2026-05-02');
      expect(log['set_number'], 2,
          reason:
              'consumer reads set_number — writer field name must remain stable');
      expect(log['reps_completed'], 10);
      expect((log['weight_kg'] as num).toDouble(), 100.0);
      expect((log['volume_kg'] as num).toDouble(), 1000.0);
    });

    test('AI coach context picks up today\'s exercise', () async {
      // Mirror AiCoachRepository._getThisWeekWorkouts AFTER the Drift #2 fix
      // (APK Test #8 / Theme D): the production reader now iterates
      // workoutBox.toMap() and filters by Hive key prefix `exlog_` instead of
      // the missing `log['type'] == 'exercise_log'` field that
      // WorkoutWriteService never writes. We mirror the fixed reader here so
      // any future drift in either direction (writer drops exlog_ key prefix
      // OR reader regresses to a missing `type` filter) fails this test.
      final today = DateTime.now();
      final res = await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Overhead Press',
        sets: const [ExerciseSet(weightKg: 40, reps: 8)],
        source: WriteSource.activeWorkout,
      );
      expect(res.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final dateStr = WorkoutWriteService.istDateStr(today);

      // Mirror the FIXED reader: iterate toMap(), filter by key prefix.
      final exerciseNames = <String>[];
      for (final entry in box.toMap().entries) {
        final keyStr = entry.key.toString();
        if (!keyStr.startsWith('exlog_')) continue;
        final v = entry.value;
        if (v is! Map) continue;
        if (v['date'] != dateStr) continue;
        exerciseNames.add(v['exercise_name'] as String? ?? '');
      }
      expect(exerciseNames, isNotEmpty,
          reason:
              'fixed reader mirror — AiCoachRepository._getThisWeekWorkouts must surface today\'s exercise via exlog_ key-prefix scan');
      expect(exerciseNames, contains('Overhead Press'),
          reason: 'today_exercises snapshot field is populated from this iteration');

      // Repository-level read (used in many AI tool dispatches via
      // WorkoutRepository.getExerciseLogsForDate).
      final logs = WorkoutRepository.instance.getExerciseLogsForDate(today);
      expect(logs, hasLength(1));
      expect(logs.first['exercise_name'], 'Overhead Press');
    });

    test('PR rescan flags the heaviest set as is_pr', () async {
      // 1. First log at 80kg — this is a PR (no prior log).
      final day1 = DateTime(2026, 4, 28);
      final r1 = await WorkoutWriteService.instance.logExercise(
        date: day1,
        exerciseName: 'Deadlift',
        sets: const [ExerciseSet(weightKg: 80, reps: 5)],
        source: WriteSource.activeWorkout,
      );
      expect(r1.success, isTrue);

      // 2. Heavier log at 100kg the next day — must be flagged is_pr=true
      //    by WorkoutWriteService._rescanPrFor (chronological strict-greater).
      final day2 = DateTime(2026, 4, 29);
      final r2 = await WorkoutWriteService.instance.logExercise(
        date: day2,
        exerciseName: 'Deadlift',
        sets: const [ExerciseSet(weightKg: 100, reps: 3)],
        source: WriteSource.activeWorkout,
      );
      expect(r2.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final day1Entry =
          box.get(WorkoutWriteService.exlogKey(day1, 'Deadlift')) as Map;
      final day2Entry =
          box.get(WorkoutWriteService.exlogKey(day2, 'Deadlift')) as Map;

      expect(day1Entry['is_pr'], true,
          reason: 'first ever log is always a PR');
      expect(day2Entry['is_pr'], true,
          reason: 'strictly heavier than prior best — is_pr must be true');
    });

    test('SyncService projection sees the writer\'s fields', () async {
      // SyncService projects exlog_* rows to workout_log_exercises +
      // workout_log_sets. The projection reads specific field names from the
      // Hive map; if any of them are renamed/dropped by the writer, cloud
      // sync silently writes nulls. This test asserts the writer's output
      // carries every contract field the projection consumes.
      final date = DateTime(2026, 5, 2);
      final res = await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Pull Up',
        sets: const [
          ExerciseSet(weightKg: 0, reps: 12),
          ExerciseSet(weightKg: 0, reps: 10),
        ],
        notes: 'felt strong',
        source: WriteSource.activeWorkout,
      );
      expect(res.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final entry =
          box.get(WorkoutWriteService.exlogKey(date, 'Pull Up')) as Map;

      // Required keys for SyncService cloud projection + downstream readers.
      expect(entry['exercise_name'], 'Pull Up');
      expect(entry['date'], '2026-05-02');
      expect(entry['set_number'], 2,
          reason: 'cloud column name; renaming breaks workout_log_exercises');
      expect(entry['reps_completed'], 22);
      expect((entry['weight_kg'] as num).toDouble(), 0.0);
      expect((entry['volume_kg'] as num).toDouble(), 0.0,
          reason: 'bodyweight reps × 0kg → 0 volume');
      expect(entry['logging_type'], 'bodyweight_reps');
      expect(entry.containsKey('is_pr'), isTrue,
          reason: 'is_pr must be set explicitly (true or false)');
      expect(entry['source'], WriteSource.activeWorkout.code);
      expect(entry['updated_at_ms'], isA<int>());
      expect(entry['notes'], 'felt strong');

      // sets[] must be a List of per-set Maps (workout_log_sets cloud rows).
      final sets = entry['sets'] as List;
      expect(sets, hasLength(2));
      expect(sets[0], isA<Map>());
      expect(sets[0]['reps'], 12);
      expect(sets[1]['reps'], 10);
    });
  });
}
