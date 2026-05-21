// Tech-debt audit 2026-05-20 / T1: signup + onboarding device-CI flow.
//
// Drives the full new-user funnel:
//   1. Cold-start in signed-out state.
//   2. Sign up via Google OAuth (native consent screen — Patrol's
//      $.native is the only Flutter test tool that can drive this).
//   3. Walk the 4 stepped onboarding screens (Goal → Stats → Details
//      → Plan).
//   4. Assert profileBox is populated (writer side).
//   5. Assert Supabase `users` row + OneSignal `player_id` upward sync
//      fired (reader side / cross-device).
//   6. Assert terms_accepted backfill ran.
//   7. Assert AuthSessionBootstrapper lands on the correct post-signup
//      route (HomeScreen for completed onboarding, RestoringScreen
//      for partial — see lib/features/auth/CLAUDE.md routing matrix).
//
// Run via runner script:
//   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh
//
// Test-user prep (founder): provision a fresh Google account for
// each run, OR sign out + delete account post-flow (uses the same
// path as delete_account_patrol_test). Reuses the @ICANBEFITTER.QA1
// throwaway Google account family — see docs/operations/
// DEVICE_TESTING.md §3.

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'signup + onboarding: new Google user lands on home with profile populated',
    ($) async {
      // Step 1: Launch in signed-out state.
      await $.pumpWidgetAndSettle(
        const MaterialApp(home: Scaffold(body: Text('TODO: real entry'))),
      );

      // Step 2: Tap "Continue with Google". The native OAuth picker
      // appears — Patrol drives via $.native.
      // await $('Continue with Google').tap();
      // await $.native.tap(Selector(text: 'icanbefitter.qa1@gmail.com'));
      // await $.native.tap(Selector(text: 'Continue'));  // consent

      // Step 3: Walk onboarding. The stepped flow lives in
      // lib/features/onboarding/screens/stepped_onboarding_screen.dart;
      // each step's "Continue" button advances.
      //   Goal step:
      // await $('Build muscle').tap();
      // await $('Continue').tap();
      //   Stats step:
      // await $(#height).enterText('178');
      // await $(#weight).enterText('72');
      // await $('Continue').tap();
      //   Details step:
      // await $('Male').tap();
      // await $(#dob).enterText('1995-06-15');
      // await $('Continue').tap();
      //   Plan step:
      // await $('Generate plan').tap();
      // await $.waitUntilVisible(find.text('Phase 1'),
      //   timeout: const Duration(seconds: 30));

      // Step 4: Assert profileBox writer side.
      // final profile = Hive.box('profileBox');
      // expect(profile.get('goal'), 'build_muscle');
      // expect(profile.get('heightCm'), 178);
      // expect(profile.get('weightKg'), 72.0);
      // expect(profile.get('terms_accepted_at'), isNotNull);

      // Step 5: Reader / cross-device side. Validate via Supabase MCP
      // post-run. The test asserts the WRITE happened locally; the
      // runner script's tear-down step inspects the `users` row to
      // confirm `lifestyle_activity` + `protein_g_per_kg` are present.

      // Step 6: OneSignal upward sync. The player_id write fires from
      // SubscriptionService initWithFlavor → registerOneSignalPlayerId.
      // expect(Hive.box('configBox').get('onesignal_player_id'), isNotEmpty);

      // Step 7: Assert post-onboarding route = HomeScreen, NOT
      // RestoringScreen and NOT a re-loop into MissionBrief.
      // expect(find.text('Home'), findsOneWidget);
    },
    // T1 scaffold needs physical device + throwaway Google account.
    // Patrol 3.x's `skip:` is bool? — flip to false once first local
    // Pixel pass is green. See docs/operations/DEVICE_TESTING.md.
    skip: true,
  );
}
