// Review round 1 (e8f4a3) — FINDING 2 (HIGH): the `_restoreScheduledWorkouts`
// timestamp-merge only protected the local 'completed' arm. A local TERMINAL
// row ('moved'/'dropped') + a stale cloud 'planned' row fell through to the
// cloud-authoritative arm — the restore RESURRECTED the moved-away workout as
// planned (exactly the double-count the terminal rows were written to kill:
// the workout now lives on another date, or was dropped outright).
//
// THE FIX: the symmetric arm — localStatus ∈ {moved, dropped} &&
// cloudStatus == 'planned' → keep local (terminal rows are newer truth;
// the cloud row predates the move/drop — its push raced or failed).
//
// BEHAVIORAL: seeds the real workoutBox + runs the REAL merge path through
// `restoreScheduledWorkoutsForTest` (preFetched rows — no Supabase query).
// Each test FAILS against the pre-fix code (status merges to 'planned').

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  /// Cloud-shaped row as `scheduled_workouts` returns it (the columns the
  /// merge reads): scheduled_date + status. No template embed — hydration
  /// is a separate arm and must not touch these tests' local content.
  Map<String, dynamic> cloudRow(String date, String status) => {
        'scheduled_date': date,
        'status': status,
        'completed_at': null,
        'week_number': null,
        'day_of_week': null,
        'template_id': null,
      };

  Map? scheduleRow(String dateStr) =>
      HiveService.instance.workoutBox.get('schedule_$dateStr') as Map?;

  group('F2 — restore keeps local terminal rows against stale cloud planned', () {
    test('local moved + cloud planned → stays moved', () async {
      const date = '2026-09-15';
      await HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'workout_name': 'Push A',
        'status': 'moved',
        'type': 'custom_template',
        'moved_to': '2026-09-17',
        'moved_via': 'ai_coach',
        'moved_at': DateTime.now().toIso8601String(),
        'exercises': [
          {'exercise_name': 'Bench Press'},
        ],
      });

      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [cloudRow(date, 'planned')],
      );

      final row = scheduleRow(date);
      expect(row, isNotNull);
      expect(row!['status'], 'moved',
          reason: 'the local terminal row is NEWER truth — the workout lives '
              'on 2026-09-17 now. Pre-fix the cloud-authoritative arm '
              'resurrected it as planned on the old date.');
      expect(row['moved_to'], '2026-09-17',
          reason: 'the terminal metadata must survive the merge '
              '(...existingMap spread must not be clobbered)');
    });

    test('local dropped + cloud planned → stays dropped', () async {
      const date = '2026-09-16';
      await HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'workout_name': 'Legs B',
        'status': 'dropped',
        'type': 'custom_template',
        'dropped_via': 'ai_coach',
        'dropped_at': DateTime.now().toIso8601String(),
        'exercises': [
          {'exercise_name': 'Squat'},
        ],
      });

      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [cloudRow(date, 'planned')],
      );

      expect(scheduleRow(date)!['status'], 'dropped',
          reason: 'a dropped day must not resurrect from a stale cloud '
              'planned row');
    });

    test('cloud completed still wins over local planned (other arm intact)',
        () async {
      const date = '2026-09-14';
      await HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'workout_name': 'Pull C',
        'status': 'planned',
        'type': 'workout',
        'exercises': [],
      });

      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [
          {
            ...cloudRow(date, 'completed'),
            'completed_at': '2026-09-14T10:00:00Z',
          },
        ],
      );

      expect(scheduleRow(date)!['status'], 'completed',
          reason: 'the new terminal arm must NOT suppress the existing '
              'cloud-authoritative behavior for planned locals');
    });
  });
}
