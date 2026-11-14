// Source-grep contract for the razorpay-webhook double-promo-burn guard.
//
// Originally landed as T-3 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-3 razorpay-webhook double-promo-burn guard', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/razorpay-webhook/index.ts');
    });

    test('redeemPromo / increment_promo_used_count gated by !alreadyProcessed', () {
      // The redemption helper (redeemPromo internally calls
      // increment_promo_used_count RPC) must be guarded by
      // `if (!alreadyProcessed && ...)` — pre-fix a replayed webhook
      // would double-burn the promo's used_count.
      expect(
        src.contains('increment_promo_used_count'),
        isTrue,
        reason: 'webhook must reference increment_promo_used_count RPC.',
      );
      // The actual gate sits around the redeemPromo call.
      expect(
        src.contains('if (!alreadyProcessed && derived.promoApplied'),
        isTrue,
        reason: 'redeemPromo (which calls increment_promo_used_count) '
            'must be gated by `!alreadyProcessed && derived.promoApplied`. '
            'Without this, replays double-burn promo used_count.',
      );
    });

    test('a 23505 (lost insert race) marks the payment processed so it cannot re-redeem', () {
      // PRESENCE ONLY (no runtime seam for the webhook handler). The racer that
      // won the insert also redeemed (another webhook, or verify-payment via
      // weInsertedTheRow); redeeming here too double-burns used_count and the
      // second promo_code_uses insert silently hits UNIQUE(code,user_id).
      expect(src.contains('let alreadyProcessed'), isTrue,
          reason: '`const alreadyProcessed` cannot be reassigned by the 23505 arm');
      expect(
        RegExp(r'insertError\.code === "23505"\s*\)\s*\{\s*alreadyProcessed = true;')
            .hasMatch(src),
        isTrue,
        reason: 'the 23505 arm must set alreadyProcessed = true before the gate below',
      );
    });
  });
}
