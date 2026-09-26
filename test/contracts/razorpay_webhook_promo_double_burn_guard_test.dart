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
  });
}
