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

  group('F1 (original d9b2c5 arm) — restore keeps a completed_at_ms-only '
      'local completion against a stale cloud planned row', () {
    // Recurrence of d9b2c5 (2026-05-10), found 2026-09-29 from a founder
    // report ("yesterday's completed workout shows not-done today").
    //
    // The d9b2c5 guard reads:
    //   localStatus == 'completed' && cloudStatus == 'planned' &&
    //   localCompletedAt != null && localCompletedAt.isNotEmpty
    //     -> keep local
    //
    // Pre-Task-14 (day-swapper-sync-load, commit ebddb44c, 2026-09-27),
    // localCompletedAt was existingMap['completed_at'] read DIRECTLY -- the
    // legacy ISO field. But the live completion writer
    // (WorkoutWriteService.markCompleted, workout_write_service.dart:492)
    // only ever sets completed_at_ms, never completed_at. So for every real
    // on-device completion, localCompletedAt was ALWAYS null and this
    // branch could never fire -- dead for ~4.5 months (2026-05-10 ->
    // 2026-09-27). Every test that named this guard during that whole
    // window (T3 in logout_login_round_trip_test.dart,
    // restore_non_destructive_test.dart) is a source-grep on the
    // conditional's literal text, unchanged by the eventual fix, so all of
    // them stayed green throughout.
    //
    // ⚠ NOT the first behavioral test for this arm -- Task 14 itself
    // already added one, driven by an unrelated live-timestamp audit (see
    // docs/diagnoses/2026-09-26-sync-past-timestamps-overwritten-with-now-f4c7a9.md):
    // test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart's
    // "restore carve-out uses the same resolver (plan D3)" group covers the
    // identical scenario shape and is the SoT registry's canonical pointer.
    // This group is supplementary: it additionally asserts completed_at_ms
    // and completed_via survive the merge untouched, and that the legacy
    // completed_at field gets backfilled -- none of which the Task-14 test
    // checks. The real lesson (see the diagnose-doc + debugging skill
    // catalog) is that the source-grep tests never caught the dead branch in
    // 4.5 months; it took a live-data audit of a DIFFERENT symptom
    // (wrong timestamps, not wrong status) to trip over and fix it as a
    // side effect. The founder's 2026-09-28 corruption predates the fix
    // reaching any built APK (last build 1.0.0+47, recorded 2026-09-24,
    // three days before ebddb44c) -- not a defect still present on main.
    //
    // closes-diagnose: 2026-09-29-restore-completed-guard-dead-branch-window-d83505
    test(
      'local completed via completed_at_ms only + cloud planned -> stays '
      'completed, and the legacy completed_at field is backfilled',
      () async {
        const date = '2026-09-28';
        final completedAtMs =
            DateTime.utc(2026, 9, 28, 15, 30).millisecondsSinceEpoch;
        await HiveService.instance.workoutBox.put('schedule_$date', {
          'date': date,
          'workout_name': 'Calisthenics',
          'status': 'completed',
          'type': 'custom_template',
          'template_id': 'tmpl_test',
          'completed_at_ms': completedAtMs,
          'completed_via': 'app',
          'exercises': [
            {'exercise_name': 'Pull Up'},
          ],
        });

        await SyncService.instance.restoreScheduledWorkoutsForTest(
          kTestUserId,
          preFetched: [cloudRow(date, 'planned')],
        );

        final row = scheduleRow(date);
        expect(row, isNotNull);
        expect(row!['status'], 'completed',
            reason: 'the local completion (recorded via completed_at_ms -- '
                'the field the live markCompleted writer actually sets) must '
                'survive a stale cloud planned row. This is the exact '
                'founder scenario from 2026-09-28/29.');
        expect(row['completed_at_ms'], completedAtMs,
            reason: 'completed_at_ms must survive the ...existingMap spread '
                'untouched');
        expect(row['completed_via'], 'app');
        expect(row['completed_at'], isNotNull,
            reason: 'the merge additionally backfills the legacy ISO '
                'completed_at field from the completed_at_ms-derived value, '
                'so a reader that still checks completed_at directly also '
                'sees this row as completed');
      },
    );
  });
}
