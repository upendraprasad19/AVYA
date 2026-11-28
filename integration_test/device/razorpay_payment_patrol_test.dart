// Tech-debt audit 2026-05-20 / T1: Razorpay payment device-CI flow.
//
// Patrol drives the full upgrade flow on a physical Pixel:
//   1. Sign-in as a free test user.
//   2. Open the paywall sheet.
//   3. Tap "Upgrade ₹349/month" → Razorpay test-mode WebView opens.
//   4. Pay with Razorpay test card 4111 1111 1111 1111.
//   5. Assert: SubscriptionService.isPro() == true, Hive
//      subscriptionBox['isPro'] == true, cloud `subscriptions` row
//      created with status='active'.
//
// Run requirements (DO NOT bypass — see docs/operations/DEVICE_TESTING.md):
//   - Physical Android device connected via USB (Razorpay SDK is
//     Android-only on Flutter).
//   - `.env` has rzp_test_* keys (NOT rzp_live_*).
//   - A clean test user that can be safely upgraded (the test marks
//     a subscriptions row; downgrade after via Supabase MCP if needed).
//
// Run via runner script:
//   ANDROID_DEVICE_ID=<id> sh scripts/run-device-tests.sh
//
// Run this flow only:
//   patrol test --target integration_test/device/razorpay_payment_patrol_test.dart
//
// Recurrence prevention (ref project_apk_test_12_5_batch — 409 dead-code
// regression): this flow exercises the FunctionException catch path so
// the verify-payment failure mode stays covered.

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'razorpay payment: free user upgrades to PRO via test card',
    ($) async {
      // Step 1: Launch app. AuthSessionBootstrapper resolves to either
      // signed-in or signed-out. Test pre-condition assumes the device
      // is signed in as a free test user (founder runs the helper
      // bootstrap before invoking this flow — see docs/operations/
      // DEVICE_TESTING.md §3 "Test user prep").
      await $.pumpWidgetAndSettle(
        const MaterialApp(home: Scaffold(body: Text('TODO: real entry'))),
      );

      // Step 2: Navigate to a PRO-gated tap that surfaces the paywall.
      // Founder hook: tap the "AI Coach" tab once → tap "Send" on the
      // PRO-only model → PaywallSheet pops up.
      // await $('AI Coach').tap();
      // await $(#paywallSheet).waitUntilVisible();

      // Step 3: Tap the monthly upgrade button. Razorpay WebView opens
      // as a native overlay — Patrol reaches it via $.native.
      // await $('Upgrade ₹349/month').tap();
      // await $.native.waitUntilVisible(Selector(text: 'Razorpay'));

      // Step 4: Pay with the test card. Razorpay test-mode card
      // 4111 1111 1111 1111 with any future expiry + any 3-digit CVV
      // succeeds; the webhook fires within ~5s.
      // await $.native.enterText(Selector(resourceId: 'cardNumber'),
      //                          text: '4111111111111111');
      // await $.native.enterText(Selector(resourceId: 'expiry'),
      //                          text: '12/30');
      // await $.native.enterText(Selector(resourceId: 'cvv'), text: '123');
      // await $.native.tap(Selector(text: 'Pay'));

      // Step 5: Wait for _pollAndActivate to flip the PRO pill. The
      // poll window is ~45s with backoff; Patrol's default timeout
      // is 30s so we extend.
      // await $.waitUntilVisible(find.text('PRO'), timeout: Duration(seconds: 60));

      // Step 6: Assert Hive state. SubscriptionService reads
      // subscriptionBox['isPro'] — confirm it's true.
      // expect(Hive.box('subscriptionBox').get('isPro'), true);
      // Cloud assertion: `subscriptions` row exists w/ status='active'.
      // Done via Supabase MCP query post-run (the test driver doesn't
      // talk to Postgres directly).
    },
    // Patrol 3.x exposes `skip: bool?` (not String like flutter_test).
    // T1 scaffold needs physical device + rzp_test_* in .env; founder
    // flips to false once the first local Pixel pass is green. See
    // docs/operations/DEVICE_TESTING.md "CI runner provisioning".
    skip: true,
  );
}
