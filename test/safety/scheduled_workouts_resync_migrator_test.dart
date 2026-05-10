// APK Test #14 / Bug B.3 — pins the one-shot resync migrator.
//
// Source-grep contract test pinning:
//   • Class `ScheduledWorkoutsResyncMigrator` exists with static
//     `runIfNeeded` method.
//   • Flag key literal `'apk_test_14_completion_resync_done'` is
//     present (the `userBox` gate that makes the migrator idempotent).
//   • Migrator iterates `schedule_` prefixed keys (`'schedule_'`
//     literal).
//   • Migrator calls `SyncService.instance.syncWorkoutData()`.
//
// See docs/diagnoses/2026-05-10-resync-migrator-e3f7a8.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduledWorkoutsResyncMigrator (APK Test #14 / Bug B.3)', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/core/services/scheduled_workouts_resync_migrator.dart',
      ).readAsStringSync();
    });

    test('class declared with static runIfNeeded method', () {
      expect(src.contains('class ScheduledWorkoutsResyncMigrator'), isTrue,
          reason: 'Migrator class must be declared');
      expect(src.contains('static Future<void> runIfNeeded()'), isTrue,
          reason: 'runIfNeeded must be the static entry point');
    });

    test('flag key `apk_test_14_completion_resync_done` present', () {
      expect(
        src.contains("'apk_test_14_completion_resync_done'"),
        isTrue,
        reason:
            'Idempotency gate — flag literal must match the spec exactly',
      );
    });

    test('iterates `schedule_` prefixed Hive keys', () {
      expect(
        src.contains("'schedule_'"),
        isTrue,
        reason:
            'Migrator must scan workoutBox for schedule_ entries to identify '
            'candidates with status==completed',
      );
    });

    test('invokes SyncService.instance.syncWorkoutData()', () {
      expect(
        src.contains('SyncService.instance.syncWorkoutData()'),
        isTrue,
        reason:
            'Reuses standard fan-out — Bug B.1 hardened push handles '
            'per-row 23503 resolution',
      );
    });
  });
}
