// OI-341 Piece B2b — the pure decisions behind a stacked trial purchase
// (docs/plans/oi341-piece-b2b-client.md section 3, T1-T6).
//
// Expected values are LITERAL golden strings. Instants are built from local
// wall-clock times (then .toUtc() where a UTC input is wanted), so the goldens
// hold in any zone without DST; CI pins IST.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/payment_end_estimate.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';

void main() {
  // 10:00 IST on 2026-10-22, local.
  final now = DateTime(2026, 10, 22, 10);

  group('T1 estimatePaidEndDate', () {
    test('no stacks-after: now + 30 / now + 365, local shape', () {
      expect(estimatePaidEndDate(plan: 'monthly', now: now),
          '2026-11-21T10:00:00.000');
      expect(estimatePaidEndDate(plan: 'yearly', now: now),
          '2027-10-22T10:00:00.000');
    });

    test('a future trial end: trial end + plan days', () {
      // The same local wall-clock time 7 days on, as a UTC instant: the result
      // is local, so the golden holds in any zone without DST.
      final trialEnd = DateTime(2026, 10, 29, 10).toUtc();
      expect(
          estimatePaidEndDate(
              plan: 'monthly', stacksAfter: trialEnd, now: now),
          '2026-11-28T10:00:00.000');
      expect(
          estimatePaidEndDate(plan: 'yearly', stacksAfter: trialEnd, now: now),
          '2027-10-29T10:00:00.000');
    });

    test('a past trial end: now + plan days', () {
      final past = DateTime(2026, 10, 20, 10).toUtc();
      expect(estimatePaidEndDate(plan: 'monthly', stacksAfter: past, now: now),
          '2026-11-21T10:00:00.000');
    });

    test('1 ms after now still stacks; the same instant does not change it',
        () {
      final justAfter = now.add(const Duration(milliseconds: 1));
      expect(
          estimatePaidEndDate(
              plan: 'monthly', stacksAfter: justAfter, now: now),
          '2026-11-21T10:00:00.001');
      expect(estimatePaidEndDate(plan: 'monthly', stacksAfter: now, now: now),
          '2026-11-21T10:00:00.000');
    });

    test('a UTC now gives the same local shape', () {
      final utcNow = DateTime(2026, 10, 22, 10).toUtc();
      expect(estimatePaidEndDate(plan: 'monthly', now: utcNow),
          '2026-11-21T10:00:00.000');
    });
  });

  group('T2 parseStacksAfter', () {
    test('accepts offset-carrying timestamps, incl. the server shape', () {
      for (final s in [
        '2026-11-16T10:00:00.123456+00:00',
        '2026-10-29T04:30:00Z',
        '2026-10-29T10:00:00+05:30',
        '2026-10-29 04:30:00+00:00',
      ]) {
        expect(parseStacksAfter(s, now: now), isNotNull, reason: s);
      }
      expect(parseStacksAfter('2026-10-29T04:30:00Z', now: now),
          DateTime.parse('2026-10-29T04:30:00Z'));
    });

    test('refuses everything else and never throws', () {
      for (final raw in <Object?>[
        '2026-10-29T04:30:00',
        '2026-10-29',
        null,
        42,
        'garbage',
        '',
        <String, dynamic>{},
      ]) {
        expect(parseStacksAfter(raw, now: now), isNull, reason: '$raw');
      }
    });

    test('a value more than 3650 days (10 years) ahead is refused', () {
      final ok = now.add(const Duration(days: 3649)).toUtc().toIso8601String();
      final far = now.add(const Duration(days: 3651)).toUtc().toIso8601String();
      expect(parseStacksAfter(ok, now: now), isNotNull);
      expect(parseStacksAfter(far, now: now), isNull);
    });
  });

  group('T3 classifyOrderConflict', () {
    test('already_pro from a paid row', () {
      for (final plan in ['monthly', 'yearly', null]) {
        expect(
            classifyOrderConflict(
                {'error_code': 'already_pro', 'current_plan': plan}),
            OrderConflict.alreadyPro,
            reason: '$plan');
      }
    });

    test('already_pro from a trial row', () {
      expect(
          classifyOrderConflict(
              {'error_code': 'already_pro', 'current_plan': 'referral_trial'}),
          OrderConflict.trialUpgradeUnavailable);
    });

    test('any other code is other, even with a trial plan', () {
      expect(
          classifyOrderConflict({
            'error_code': 'subscription_check_unavailable',
            'current_plan': 'referral_trial',
          }),
          OrderConflict.other);
      expect(classifyOrderConflict({}), OrderConflict.other);
    });
  });

  group('T4 checkoutDescription', () {
    const notice = 'Your paid plan starts when your free days end.';
    test('no stacks-after: today exactly', () {
      expect(checkoutDescription(plan: 'monthly'), 'PRO Monthly Plan');
      expect(checkoutDescription(plan: 'yearly'), 'PRO Yearly Plan');
    });

    test('any stacks-after, past or future, appends the notice', () {
      for (final s in [
        now.add(const Duration(days: 5)),
        now.subtract(const Duration(days: 5)),
      ]) {
        expect(checkoutDescription(plan: 'monthly', stacksAfter: s),
            'PRO Monthly Plan. $notice');
        expect(checkoutDescription(plan: 'yearly', stacksAfter: s),
            'PRO Yearly Plan. $notice');
        expect(checkoutDescription(plan: 'yearly', stacksAfter: s).length,
            lessThan(255));
      }
    });
  });

  group('T5 buildRazorpayCheckoutOptions', () {
    Map<String, dynamic> build({DateTime? stacksAfter}) =>
        RazorpayService.buildRazorpayCheckoutOptions(
          keyId: 'rzp_test_x',
          orderId: 'order_1',
          amountPaise: 34900,
          plan: 'monthly',
          email: 'a@b.c',
          notes: const {'plan': 'monthly'},
          stacksAfter: stacksAfter,
        );

    test('no stacks-after: the whole map is today\'s', () {
      final m = build();
      expect(m['description'], 'PRO Monthly Plan');
      expect(m.keys.toSet(), {
        'key',
        'order_id',
        'amount',
        'name',
        'description',
        'currency',
        'prefill',
        'notes',
        'theme',
      });
      expect(m['order_id'], 'order_1');
      expect(m['amount'], 34900);
    });

    test('with stacks-after only the description differs', () {
      final a = build();
      final b = build(stacksAfter: now.add(const Duration(days: 5)));
      expect(b['description'],
          'PRO Monthly Plan. Your paid plan starts when your free days end.');
      for (final k in a.keys.where((k) => k != 'description')) {
        expect(b[k].toString(), a[k].toString(), reason: k);
      }
    });
  });

  group('T6 PendingCheckouts + resolveConfirmedCheckout', () {
    final trialEnd = DateTime.parse('2026-10-29T04:30:00Z');

    test('an earlier order confirmed after a later checkout reads its own record',
        () {
      final store = PendingCheckouts()
        ..record('order_A',
            PendingCheckout(plan: 'monthly', stacksAfter: trialEnd))
        ..record('order_B', const PendingCheckout(plan: 'yearly'));
      final r = resolveConfirmedCheckout(
          store: store, confirmedOrderId: 'order_A', pendingPlan: 'yearly');
      expect(r.plan, 'monthly');
      expect(r.stacksAfter, trialEnd);
      expect(r.matched, isTrue);
    });

    test('an unknown, null or empty id falls back to today\'s behaviour', () {
      final store = PendingCheckouts()
        ..record('order_A',
            PendingCheckout(plan: 'monthly', stacksAfter: trialEnd));
      for (final id in ['order_X', null, '']) {
        final r = resolveConfirmedCheckout(
            store: store, confirmedOrderId: id, pendingPlan: 'yearly');
        expect(r.plan, 'yearly', reason: '$id');
        expect(r.stacksAfter, isNull, reason: '$id');
        expect(r.matched, isFalse, reason: '$id');
      }
      final empty = resolveConfirmedCheckout(
          store: PendingCheckouts(), confirmedOrderId: 'order_A');
      expect(empty.plan, 'monthly');
      expect(empty.stacksAfter, isNull);
    });

    test('bounded: a fifth record evicts the oldest', () {
      final store = PendingCheckouts();
      for (var i = 1; i <= 5; i++) {
        store.record('o$i', const PendingCheckout(plan: 'monthly'));
      }
      expect(store.lookup('o1'), isNull);
      expect(store.lookup('o2'), isNotNull);
      expect(store.lookup('o5'), isNotNull);
    });

    test('clear empties the store', () {
      final store = PendingCheckouts()
        ..record('o1', const PendingCheckout(plan: 'monthly'));
      store.clear();
      expect(store.isEmpty, isTrue);
      expect(store.lookup('o1'), isNull);
    });
  });

  group('T7 orderConflictMessage', () {
    test('a trial row gets the trial copy, exact text', () {
      expect(
          orderConflictMessage(
              trialUpgradeUnavailable: true, endLabel: '29/10/2026'),
          'Your free PRO days are still running. You can subscribe once they end.');
    });

    test('a paid row keeps today\'s line byte-for-byte', () {
      expect(
          orderConflictMessage(
              trialUpgradeUnavailable: false, endLabel: '29/10/2026'),
          'You\'re already PRO \u2014 active until 29/10/2026');
    });
  });

  group('T8 isTrialRefusal', () {
    test('only a 409 with a trial row', () {
      final trial = {'error_code': 'already_pro', 'current_plan': 'referral_trial'};
      final paid = {'error_code': 'already_pro', 'current_plan': 'monthly'};
      expect(isTrialRefusal(status: 409, details: trial), isTrue);
      expect(isTrialRefusal(status: 409, details: paid), isFalse);
      expect(isTrialRefusal(status: 500, details: trial), isFalse);
      expect(isTrialRefusal(status: null, details: trial), isFalse);
      expect(isTrialRefusal(status: 409, details: 'already_pro'), isFalse);
      expect(isTrialRefusal(status: 409, details: null), isFalse);
    });
  });
}
