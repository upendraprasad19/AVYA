// Batch 6 regression guard — 2026-06-07 comprehensive-audit, SERVER findings.
//
// Source-presence guards over the Edge-Function fixes (comments stripped except
// where the fix IS a docstring — F46). The deploy versions are recorded in:
//   docs/diagnoses/2026-06-07-payment-cron-server-hardening-b3f0d9.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

String _read(String p) => _strip(File(p).readAsStringSync());
String _raw(String p) => File(p).readAsStringSync();

void main() {
  group('verify-payment — redeem-once + honest insert-failure (F31, F33)', () {
    final s = _read('supabase/functions/verify-payment/index.ts');

    test('F31: promo redemption is gated on weInsertedTheRow', () {
      expect(s.contains('weInsertedTheRow'), isTrue);
      expect(
        s.contains('derived.promoApplied && derived.promoCode && weInsertedTheRow'),
        isTrue,
        reason: 'F31: must not redeem again when the webhook owns the row',
      );
    });

    test('F31: an idempotency pre-SELECT precedes the insert', () {
      expect(
        RegExp(r'\.eq\(\s*"razorpay_payment_id",\s*paymentId\s*\)[\s\S]{0,80}maybeSingle')
            .hasMatch(s),
        isTrue,
        reason: 'F31: pre-SELECT by payment id mirrors the webhook H-19 guard',
      );
    });

    test('review d6b736 F1: users expiry uses the canonical row, not re-anchored', () {
      expect(s.contains('subscription_expires_at: canonicalEndDateIso'), isTrue,
          reason: 'users.subscription_expires_at must match the canonical subscriptions row, not verify-time');
    });

    test('F33: a non-23505 insert failure returns verified:false (not true)', () {
      expect(s.contains('Could not record subscription'), isTrue,
          reason: 'F33: honest failure — the row was NOT written');
      expect(s.contains('Payment verified but failed to create subscription record'),
          isFalse,
          reason: 'F33: the old verified:true-without-a-row path must be gone');
    });
  });

  group('razorpay-webhook — replay age from event time (F32)', () {
    final s = _read('supabase/functions/razorpay-webhook/index.ts');
    test('F32: replay window keys off payload.created_at (event time)', () {
      expect(s.contains('payload.created_at'), isTrue,
          reason: 'F32: must measure age from the webhook EVENT time');
      expect(s.contains('paymentEntity.created_at as number'), isFalse,
          reason: 'F32: the payment-entity created_at rejected slow UPI captures forever');
    });
  });

  group('pr-detection — recency by completed_at, not sync time (F43)', () {
    final s = _read('supabase/functions/pr-detection/index.ts');
    test('F43: the PR window filters + orders by completed_at', () {
      expect(s.contains('.gte("completed_at"'), isTrue);
      expect(s.contains('.order("completed_at"'), isTrue);
      expect(s.contains('created_at'), isFalse,
          reason: 'F43: no code ref to created_at remains (only the explanatory comment)');
    });
  });

  group('proactive-coach-promotion — auth gate (F44 SECURITY)', () {
    final s = _read('supabase/functions/proactive-coach-promotion/index.ts');
    test('F44: gated by isAuthorizedCronCall before any privileged work', () {
      expect(s.contains('isAuthorizedCronCall(req)'), isTrue,
          reason: 'F44: an unauthenticated POST drove Gemini cost + push + DB writes');
    });
  });

  group('i-see-you-callout — bounded + paginated audience (F45)', () {
    final s = _read('supabase/functions/i-see-you-callout/index.ts');
    test('F45: scopes to active users and paginates the scan', () {
      expect(s.contains('last_active_at'), isTrue,
          reason: 'F45: audience scoped to recently-active users');
      expect(s.contains('.range('), isTrue, reason: 'F45: paginated scan');
      expect(s.contains('PAGE_SIZE'), isTrue);
    });
  });

  group('streak-guardian — docstring matches the live schedule (F46)', () {
    final s = _raw('supabase/functions/streak-guardian/index.ts'); // docstring = block comment
    test('F46: docstring says 20:00 IST (live jobid 20 = 30 14 = 20:00 IST)', () {
      expect(s.contains('20:00 IST'), isTrue);
      expect(s.contains('23:50'), isFalse,
          reason: 'F46: 23:50 was the stale registry value, not the live schedule');
    });
  });
}
