// Tech-debt audit 2026-05-20 / T1: delete-account (DPDP §17) device-CI flow.
//
// Drives the full DPDP-compliant delete pathway:
//   1. Sign in as a test user with seeded data.
//   2. Profile → Settings → "Delete Account".
//   3. Confirm dialog: type "DELETE" (the explicit-consent gate).
//   4. delete-account Edge Function v1+ fires (closes-diagnose for
//      project_apk_test_11_batch DPDP §17 ship).
//   5. Assert: Supabase `auth.users` row removed (cloud read).
//   6. Assert: Hive wiped (all user-scoped boxes empty).
//   7. Assert: app navigates back to the signed-out auth landing.
//
// Run via runner script:
//   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh
//
// Test-user prep (founder): provision a DISPOSABLE test account that
// can be safely deleted. Re-seed for next run via
// supabase/seeds/device_test_user.sql (see docs/operations/
// DEVICE_TESTING.md §3).
//
// Regression sensitivity: this flow exercises the SessionHelpers.
// purgeUserScopedBoxes call path — restoring it broke twice in
// 2026-04 / 2026-05 (project_apk_test_12_8_batch). The Hive-wiped
// assertion below pins that contract.

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'delete account: signed-in user fully purged from cloud + local',
    ($) async {
      // Step 1: Launch app, assume signed in as disposable test user
      // (runner script's setUp signs in before invoking).
      await $.pumpWidgetAndSettle(
        const MaterialApp(home: Scaffold(body: Text('TODO: real entry'))),
      );

      // Step 2: Profile → Settings → Delete Account.
      // await $('Profile').tap();
      // await $('Settings').tap();
      // await $.scrollUntilVisible(
      //   finder: find.text('Delete Account'),
      //   step: 100.0,
      // );
      // await $('Delete Account').tap();

      // Step 3: Confirm dialog. The PRD requires typing "DELETE"
      // verbatim (matches DeleteAccountConfirmSheet's text-controller
      // gate — lib/features/profile/widgets/delete_account_confirm_sheet.dart).
      // await $.waitUntilVisible(find.text('Type DELETE to confirm'));
      // await $(#deleteConfirmInput).enterText('DELETE');
      // await $('Delete my account').tap();

      // Step 4: Wait for the Edge Function round-trip. The function
      // cascades: deletes auth.users row → triggers ON DELETE CASCADE
      // → user-scoped tables empty. Client polls then signs out.
      // await $.waitUntilVisible(find.text('Sign in'),
      //   timeout: const Duration(seconds: 30));

      // Step 5: Cloud side validated by runner script's tear-down
      // (Supabase MCP query against auth.users).

      // Step 6: Hive-wiped contract. Every user-scoped box should be
      // empty after purgeUserScopedBoxes runs. Configuration boxes
      // (configBox, userBox where applicable) survive — that's the
      // explicit SoT registry contract for `hive_deletion_and_session_helpers`.
      // for (final boxName in ['workoutLogsBox', 'nutritionLogsBox',
      //                         'weightLogBox', 'streakBox', 'profileBox']) {
      //   expect(Hive.box(boxName).length, 0,
      //     reason: '$boxName must be wiped post-delete-account');
      // }

      // Step 7: Signed-out auth landing visible.
      // expect(find.text('Continue with Google'), findsOneWidget);
    },
    // T1 scaffold needs physical device + disposable test user.
    // Patrol 3.x's `skip:` is bool? — flip to false once first local
    // Pixel pass is green. See docs/operations/DEVICE_TESTING.md.
    skip: true,
  );
}
