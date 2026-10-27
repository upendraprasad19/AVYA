// Tech-debt audit 2026-05-20 / T1: cross-device restore device-CI flow.
//
// Pins the restore-completeness regression class (project_apk_test_12_8_
// batch — "6 of 16 _restoreXxx keyed wrong" + feedback_writer_reader_
// field_drift_recurring.md — 9 instances and counting).
//
// Patrol flow:
//   1. Sign out current user (or start signed-out) — clears local Hive
//      via SessionHelpers.purgeUserScopedBoxes.
//   2. Sign in as a KNOWN test user with pre-seeded cloud data
//      (workouts, nutrition, weight log, streak, profile).
//   3. Wait for RestoringScreen to dismiss (restore-complete signal).
//   4. Assert every domain box has its expected row count.
//   5. Drill one canonical row per domain to assert field fidelity
//      (writer/reader semantic check, not just presence).
//
// Run via runner script:
//   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh
//
// Test-user prep (founder, ahead of run):
//   docs/operations/DEVICE_TESTING.md §3 lists the test account email
//   + the canonical row-count expectations. The test user is seeded
//   once via supabase/seeds/device_test_user.sql; re-seed by re-running
//   that script when the schema changes.

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'cross-device restore: sign-in restores all domain boxes',
    ($) async {
      // Step 1: Launch app. Assumes device is in signed-out state
      // (see runner script — it wipes app data before each flow).
      await $.pumpWidgetAndSettle(
        const MaterialApp(home: Scaffold(body: Text('TODO: real entry'))),
      );

      // Step 2: Sign in. The test user is provisioned ahead of time
      // (founder via /add-test-user or the seed SQL).
      // await $('Sign in').tap();
      // await $('email').enterText('device-test@avya.app');
      // await $('password').enterText('<test pw from .env.test>');
      // await $('Continue').tap();

      // Step 3: Wait for RestoringScreen to finish. The screen
      // pops itself when SyncService.restoreFromCloud completes
      // (lib/core/services/sync_service.dart). Patrol waits up to
      // 60s; the canonical p99 is ~12s.
      // await $.waitUntilVisible(find.text('Home'),
      //   timeout: const Duration(seconds: 60));

      // Step 4: Assert every domain box has the expected row counts.
      // The numbers below are pinned to docs/operations/DEVICE_TESTING.md
      // §3 "Canonical test-user data fixture". If the fixture is
      // re-seeded, update both places.
      // expect(Hive.box('workoutLogsBox').length, greaterThanOrEqualTo(20));
      // expect(Hive.box('nutritionLogsBox').length, greaterThanOrEqualTo(50));
      // expect(Hive.box('weightLogBox').length, greaterThanOrEqualTo(10));
      // expect(Hive.box('streakBox').get('current'), isNotNull);
      // expect(Hive.box('profileBox').get('weightKg'), 72.5);

      // Step 5: Field-fidelity drill on ONE workout log row — pins
      // exlog_* key drift class. The row's `set` field MUST be int
      // (writer's contract), not String (a recurring reader-side
      // coercion bug — see project_apk_test_16_1_batch).
      // final firstWorkout = Hive.box('workoutLogsBox').values.first;
      // expect(firstWorkout['set'], isA<int>());
      // expect(firstWorkout['reps'], isA<int>());
      // expect(firstWorkout['weight_kg'], isA<num>());
    },
    // T1 scaffold needs physical device + pre-seeded test user.
    // Patrol 3.x's `skip:` is bool? — flip to false once first local
    // Pixel pass is green. See docs/operations/DEVICE_TESTING.md.
    skip: true,
  );
}
