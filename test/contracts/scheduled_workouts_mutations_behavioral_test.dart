// Behavioral contract test: scheduled_workouts_mutations
//
// Writer: WorkoutWriteService.upsertScheduled
// Reader: WorkoutScheduleReadService.getScheduleForDate
//
// Asserts:
//   - After upsertScheduled(date, data), getScheduleForDate(date) returns that data.
//   - The schedule_<date> Hive row is written under the key the reader expects.
//   - Key field values survive the round-trip (status, type, workout_name, week, phase).
//
// This test FAILS if:
//   - upsertScheduled changes its Hive key formula (scheduleKey != reader's _schedulePrefix + _dateKey).
//   - getScheduleForDate changes the key it reads from.
//   - Writer and reader use different date-formatting functions that produce different strings.

// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
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

  group('scheduled_workouts_mutations — upsertScheduled → getScheduleForDate contract', () {
    test('upsertScheduled writes and getScheduleForDate reads the same row', () async {
      final date = DateTime(2026, 6, 15);

      final entry = {
        'date': '2026-06-15',
        'phase': 1,
        'week': 2,
        'day_of_week': 6,
        'type': 'workout',
        'workout_name': 'Upper Body Push',
        'workout_focus': 'Chest, Shoulders, Triceps',
        'exercises': <Map<String, dynamic>>[],
        'status': 'planned',
        'completed_at': null,
        'is_swapped': false,
        'original_date': null,
      };

      final r = await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: entry,
        source: WriteSource.planGenerator,
      );
      expect(r.success, isTrue, reason: 'upsertScheduled must succeed');

      // Reader: WorkoutScheduleReadService.getScheduleForDate.
      final read = WorkoutScheduleReadService.instance.getScheduleForDate(date);
      expect(read, isNotNull,
          reason: 'getScheduleForDate must find the row written by upsertScheduled — '
              'key formula mismatch means null');

      // Key field values must round-trip.
      expect(read!['status'], 'planned',
          reason: 'status field must survive writer→reader round-trip');
      expect(read['type'], 'workout',
          reason: 'type field must survive writer→reader round-trip');
      expect(read['workout_name'], 'Upper Body Push',
          reason: 'workout_name field must survive writer→reader round-trip');
      expect(read['week'], 2,
          reason: 'week field must survive writer→reader round-trip');
      expect(read['phase'], 1,
          reason: 'phase field must survive writer→reader round-trip');
    });

    test('upsertScheduled writes under schedule_<istDateStr> key in workoutBox', () async {
      final date = DateTime(2026, 6, 15);
      final expectedKey = 'schedule_${WorkoutWriteService.istDateStr(date)}';

      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'rest',
          'workout_name': 'Rest Day',
          'status': 'rest',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      // Verify the Hive key the writer actually used.
      final box = HiveService.instance.workoutBox;
      expect(box.containsKey(expectedKey), isTrue,
          reason: 'workoutBox must contain schedule_<istDateStr(date)> after upsertScheduled — '
              'key formula drift means reader will see null');
    });

    test('upsertScheduled preserves completed status when source is not planGenerator', () async {
      final date = DateTime(2026, 6, 15);

      // First: write a completed entry.
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'Push Day',
          'status': 'completed',
          'completed_at': '2026-06-15T08:00:00.000',
          'exercises': <dynamic>[],
        },
        source: WriteSource.schedSwap,
      );

      // Read it back — must be completed.
      final read = WorkoutScheduleReadService.instance.getScheduleForDate(date);
      expect(read, isNotNull);
      expect(read!['status'], 'completed',
          reason: 'completed status must persist in the reader');
    });

    test('upsertScheduled with planGenerator source does NOT overwrite completed entry', () async {
      final date = DateTime(2026, 6, 15);

      // First: write completed via schedSwap.
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'Push Day',
          'status': 'completed',
          'exercises': <dynamic>[],
        },
        source: WriteSource.schedSwap,
      );

      // Then: try to overwrite with planGenerator — should be skipped.
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2026-06-15',
          'type': 'workout',
          'workout_name': 'REGENERATED Push Day',
          'status': 'planned',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      // Reader must still see the completed entry.
      final read = WorkoutScheduleReadService.instance.getScheduleForDate(date);
      expect(read, isNotNull);
      expect(read!['status'], 'completed',
          reason: 'planGenerator source must NOT overwrite a completed schedule entry — '
              'this is the "protect completed workouts" invariant');
      expect(read['workout_name'], 'Push Day',
          reason: 'workout_name of completed entry must not be overwritten by planGenerator');
    });
  });
}
