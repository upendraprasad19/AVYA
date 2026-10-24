// audit-2026-05-11 Phase 7 — promo code apply → payment → redemption.
//
// Critical untested flow: Paywall → APPLY PROMO → validate-promo
// Edge Function → discounted amount displayed → Razorpay checkout
// with notes.promo_code → razorpay-webhook reads notes →
// promo-aware amount validation → success → increment_promo_used_count
// + promo_code_uses audit row (gated by !alreadyProcessed per T-3).
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/promo_code_apply_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Promo code apply E2E', () {
    test('T1 — APPLY PROMO with valid code shows discounted amount', () {
      // validate-promo Edge Function returns discount_pct + applies
      // it client-side. Display the discounted ₹ amount.
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');

    test('T2 — invalid / expired code shows error, paywall unchanged', () {
      // Expired or non-existent codes → 400/404 → toast + no
      // amount change.
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');

    test('T3 — Razorpay order amount matches the discounted total', () {
      // docs/architecture/payment.md #2 — promo-aware amount validation. Server
      // recomputes expected amount from discount_pct.
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');

    test('T4 — webhook success → promo_code_uses row written + used_count++',
        () {
      // increment_promo_used_count gated by !alreadyProcessed (T-3).
      // Audit row in promo_code_uses (UNIQUE (code, user_id) per
      // docs/architecture/payment.md #7).
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');

    test('T5 — replayed webhook does NOT double-burn used_count', () {
      // T-3 contract test guards the source; this integration
      // exercises the actual replay against Razorpay test-mode.
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');

    test('T6 — same user re-applying same code next year is rejected', () {
      // UNIQUE(code, user_id) — INDEPENDENCEDAY2026 can\'t be
      // re-redeemed by the same user as INDEPENDENCEDAY2027 fork.
    }, skip: 'Phase 7 scaffold — needs Razorpay + Supabase test mode.');
  });
}
