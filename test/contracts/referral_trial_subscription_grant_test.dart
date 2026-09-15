// Regression contract for a1c9f4 (referral_trial subscriptions NOT-NULL, 2026-06-16).
//
// redeem_referral_atomic INSERTs a `referral_trial` subscription without the
// razorpay_* columns, which migration 052 set NOT NULL (no default) -> 23502 ->
// the redeem-referral Edge Function returned 500. Referral redemption had NEVER
// succeeded (0 referral_trial rows ever). Migration 094 drops NOT NULL on the 3
// razorpay_* columns AND hardens the shared grant trigger to a monotonic GREATEST
// expiry write.
//
// This is the CI-runnable PRESENCE guard (source-grep, SQL-comment-stripped so the
// migration's own prose / rollback comments can't satisfy it). The BEHAVIORAL
// guard — a live rollback-txn calling the RPC + the GREATEST monotonicity check —
// lives in test/sql/onconflict_live_arbiter.sql (run by
// scripts/check_onconflict_live_arbiter.dart against the live schema), pinned here
// for presence so the behavioral cases can't be silently dropped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip SQL line comments (`-- ...`) so commented prose / the rollback block
/// cannot satisfy a presence assertion (feedback_source_grep_strip_comments_first).
String _stripSql(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('--');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  final migPath = 'supabase/migrations/094_subscriptions_razorpay_nullable.sql';
  final mig = _stripSql(File(migPath).readAsStringSync());

  group('a1c9f4 — migration 094 relaxes the razorpay_* NOT NULL', () {
    test('drops NOT NULL on all 3 razorpay_* columns of subscriptions', () {
      final dropRe = RegExp(
        r'ALTER\s+TABLE\s+public\.subscriptions\s+ALTER\s+COLUMN\s+'
        r'(razorpay_order_id|razorpay_payment_id|razorpay_signature)\s+DROP\s+NOT\s+NULL',
        caseSensitive: false,
      );
      final cols = dropRe
          .allMatches(mig)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet();
      expect(
        cols,
        containsAll(
            <String>{'razorpay_order_id', 'razorpay_payment_id', 'razorpay_signature'}),
        reason:
            'all 3 razorpay_* columns must be DROP NOT NULL so redeem_referral_atomic '
            "can INSERT a referral_trial row (they're null for non-purchase grants)",
      );
    });
  });

  group('a1c9f4 — migration 094 makes the grant trigger expiry monotonic', () {
    test('update_user_subscription_status uses GREATEST on subscription_expires_at',
        () {
      expect(
        mig.contains('GREATEST(COALESCE(subscription_expires_at'),
        isTrue,
        reason:
            'the shared trigger must raise-or-keep expiry, never lower it — '
            'GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date)',
      );
    });

    test('does NOT leave the old unconditional `= NEW.end_date` expiry overwrite',
        () {
      expect(
        RegExp(r'subscription_expires_at\s*=\s*NEW\.end_date').hasMatch(mig),
        isFalse,
        reason:
            'the unconditional overwrite is the demotion foot-gun this fix closes; '
            'it must only survive inside the (stripped) rollback comment',
      );
    });
  });

  group('a1c9f4 — the live behavioral cases exist in the arbiter scaffold', () {
    final arb = File('test/sql/onconflict_live_arbiter.sql').readAsStringSync();

    test('a direct redeem_referral_atomic -> 2 referral_trial rows case exists', () {
      expect(arb.contains('redeem_referral_atomic:2_referral_trial_rows'), isTrue,
          reason:
              'the live RPC-call case (proves the INSERT succeeds + no UNIQUE-NULL '
              'collision) must stay in the arbiter SQL');
    });

    test('a GREATEST no-expiry-demotion case exists', () {
      expect(arb.contains('trigger_greatest:no_expiry_demotion'), isTrue,
          reason: 'the monotonic-expiry behavioral case must stay in the arbiter SQL');
    });
  });
}
