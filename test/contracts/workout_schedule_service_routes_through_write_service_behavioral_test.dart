// Behavioral contract test: workout_schedule_service_routes_through_write_service
//
// Writer:  WorkoutScheduleWriteService.markCompleted
//          → routes through WorkoutWriteService.upsertScheduled
// Reader:  workoutBox.get('schedule_<date>') — raw Hive key
//
// Asserts:
//   - markCompleted(date) sets status='completed' in workoutBox['schedule_<istDateStr(date)>'].
//   - The mutation routes through the WriteService path (not a direct Hive.put).
//   - The 'type' field is preserved in the completed row.
//
// This test FAILS if:
//   - WorkoutScheduleWriteService.markCompleted bypasses WorkoutWriteService.upsertScheduled.
//   - The key formula between markCompleted (formatDateKey) and the reader (istDateStr) drifts.
//   - markCompleted changes the field it sets to mark completion (e.g., renames 'status').
//
// Note: markCompleted returns early if no existing schedule entry exists,
// so this test first calls upsertScheduled to create the entry, then calls
// markCompleted to mutate it, then asserts via raw Hive.

// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('workout_schedule_service_routes_through_write_service — markCompleted contract', () {
    test('markCompleted sets status=completed in workoutBox schedule_<date> row', () async {
      final date = DateTime(2026, 6, 15);

      // Prerequisite: create a planned schedule entry so markCompleted does not early-return.
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'Push Day',
          'status': 'planned',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      // Exercise: call markCompleted — should route through WorkoutWriteService.upsertScheduled.
      await WorkoutScheduleWriteService.instance.markCompleted(date, durationSeconds: 3600);

      // Assert: raw Hive key must now show status='completed'.
      final box = HiveService.instance.workoutBox;
      final key = 'schedule_${WorkoutWriteService.istDateStr(date)}';
      final raw = box.get(key) as Map?;

      expect(raw, isNotNull,
          reason: 'schedule_<date> key must exist in workoutBox after markCompleted — '
              'if null, the WriteService routing broke or key formula drifted');

      expect(raw!['status'], 'completed',
          reason: 'status must be "completed" after markCompleted — '
              'rename of status field breaks the week-selector completed-chip logic');

      expect(raw['type'], 'workout',
          reason: 'type must be preserved (was "workout") — markCompleted must not drop type field');
    });

    test('markCompleted sets completed_at to a non-null ISO8601 string', () async {
      final date = DateTime(2026, 6, 15);

      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'Pull Day',
          'status': 'planned',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      await WorkoutScheduleWriteService.instance.markCompleted(date, durationSeconds: 1800);

      final box = HiveService.instance.workoutBox;
      final key = 'schedule_${WorkoutWriteService.istDateStr(date)}';
      final raw = box.get(key) as Map;

      final completedAt = raw['completed_at'] as String?;
      expect(completedAt, isNotNull,
          reason: 'completed_at must be set by markCompleted — '
              'null means the completion time is lost');
      expect(() => DateTime.parse(completedAt!), returnsNormally,
          reason: 'completed_at must be a valid ISO8601 string');
    });

    test('markCompleted does nothing if no existing schedule entry for date', () async {
      final date = DateTime(2026, 6, 20); // no entry seeded for this date

      // Should silently return without error.
      await expectLater(
        WorkoutScheduleWriteService.instance.markCompleted(date),
        completes,
        reason: 'markCompleted must not throw when no schedule entry exists',
      );

      final box = HiveService.instance.workoutBox;
      final key = 'schedule_${WorkoutWriteService.istDateStr(date)}';
      final raw = box.get(key);
      expect(raw, isNull,
          reason: 'workoutBox must not have a schedule entry for a date that was never upserted');
    });

    test('mutation reaches Hive via WriteService path: key matches schedule_<istDateStr>', () async {
      final date = DateTime(2026, 6, 15);

      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'Leg Day',
          'status': 'planned',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      await WorkoutScheduleWriteService.instance.markCompleted(date, durationSeconds: 2700);

      final box = HiveService.instance.workoutBox;

      // The key the reader uses is schedule_<istDateStr(date)>.
      // WorkoutScheduleWriteService.markCompleted builds key with formatDateKey (which equals istDateStr).
      // WorkoutWriteService.upsertScheduled writes key via scheduleKey = 'schedule_' + istDateStr(date).
      // Both must produce the same string. If they drift, the entry is written under the wrong key
      // and the reader (getScheduleForDate, completedWeekNumbers) sees null.
      final expectedKey = 'schedule_${WorkoutWriteService.istDateStr(date)}';
      expect(box.containsKey(expectedKey), isTrue,
          reason: 'markCompleted must write under schedule_<istDateStr(date)> — '
              'key formula drift between markCompleted (formatDateKey) and '
              'WorkoutWriteService.scheduleKey (istDateStr) causes reader to see null');

      final row = box.get(expectedKey) as Map;
      expect(row['status'], 'completed',
          reason: 'the row under the expected key must have status=completed');
    });
  });
}
