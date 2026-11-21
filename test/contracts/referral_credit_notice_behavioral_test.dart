@Timeout(Duration(minutes: 3))
library;

// Unit C (OI-336) - BEHAVIOURAL. The in-app referral credit notice: its
// decision against the real user box, its single-flight, its per-account
// state and the guards on every write. Plan: docs/plans/referral-unit-c-client.md
// (section 2.3, section 3).
//
// Real Hive (the user box), a real ProviderContainer, a fake subscription
// service. The network call is injected per `check(callForTest:)`.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';

import '../helpers/hive_test_setup.dart';

class _Token extends Notifier<String> {
  @override
  String build() => 'tokenA';
  void set(String v) => state = v;
}

final _tokenProvider = NotifierProvider<_Token, String>(_Token.new);

class _FakeSub implements SubscriptionService {
  final List<bool> forceArgs = [];

  /// When set, verifyFromServer waits for it (a verify that is still in flight).
  Completer<void>? verifyGate;

  @override
  Future<bool> verifyFromServer({bool force = false}) async {
    forceArgs.add(force);
    await verifyGate?.future;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReferrerSummary _s(int days) => ReferrerSummary(
    joined: 3, subscribed: 2, pending: 0, credited: 2, daysEarned: days);

void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late _FakeSub sub;

  Object? seenScalar() =>
      HiveService.instance.userBox.get(kReferralCreditSeenKey);

  ReferralCreditNoticeNotifier notifier() =>
      container.read(referralCreditNoticeProvider.notifier);

  ReferralCreditNotice? notice() => container.read(referralCreditNoticeProvider);

  setUp(() async {
    tempDir = await setUpHiveForTests();
    ReferrerSummaryGate.resetForTest();
    sub = _FakeSub();
    container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWith((ref) => ref.watch(_tokenProvider)),
      subscriptionServiceProvider.overrideWithValue(sub),
    ]);
    // Keep the notifier alive (and its build() run) across the whole test.
    container.listen(referralCreditNoticeProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await tearDownHiveForTests(tempDir);
  });

  group('the decision, end to end against the user box', () {
    test('first run stores a positive total SILENTLY and shows nothing',
        () async {
      await notifier().check(callForTest: () async => _s(7));
      expect(notice(), isNull);
      expect(seenScalar(), 7);
      expect(sub.forceArgs, isEmpty, reason: 'nothing was announced');
    });

    test('first run with a zero total stores 0 and shows nothing', () async {
      await notifier().check(callForTest: () async => _s(0));
      expect(notice(), isNull);
      expect(seenScalar(), 0);
    });

    test('a larger total shows ONE notice for the difference; the scalar is '
        'written only on dismiss', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 7);
      await notifier().check(callForTest: () async => _s(21));
      expect(notice(), const ReferralCreditNotice(days: 14, totalDaysEarned: 21));
      expect(seenScalar(), 7, reason: 'not written until the user acts');

      await notifier().dismiss();
      expect(notice(), isNull);
      expect(seenScalar(), 21);

      // And a repeat evaluation at the same total is silent.
      await notifier().check(callForTest: () async => _s(21));
      expect(notice(), isNull);
    });

    test('an equal total and an unknown read show nothing and write nothing',
        () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 7);
      await notifier().check(callForTest: () async => _s(7));
      await notifier().check(callForTest: () async => null);
      expect(notice(), isNull);
      expect(seenScalar(), 7);
    });

    test('a lower total re-baselines silently', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 30);
      await notifier().check(callForTest: () async => _s(7));
      expect(notice(), isNull);
      expect(seenScalar(), 7);
    });

    test('a stored non-int scalar counts as no scalar (silent first run)',
        () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 'oops');
      await notifier().check(callForTest: () async => _s(14));
      expect(notice(), isNull);
      expect(seenScalar(), 14);
    });

    test('verifyFromServer(force: true) runs ONCE per detected total, before '
        'the notice, and not again for a repeat trigger', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      await notifier().check(callForTest: () async => _s(7));
      expect(sub.forceArgs, [true]);
      await notifier().check(callForTest: () async => _s(7));
      expect(sub.forceArgs, [true], reason: 'same total: no second verify');
      await notifier().check(callForTest: () async => _s(37));
      expect(sub.forceArgs, [true, true], reason: 'a new total verifies again');
    });
  });

  group('the forced verify is awaited by EVERY concurrent trigger', () {
    test('two simultaneous checks show NO card until the verify completes, '
        'then one', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      sub.verifyGate = Completer<void>();
      final a = notifier().check(callForTest: () async => _s(7));
      final b = notifier().check(callForTest: () async => _s(7));
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(sub.forceArgs, [true], reason: 'one verify for the total');
      expect(notice(), isNull,
          reason: 'the card must not precede the entitlement it announces');
      sub.verifyGate!.complete();
      await Future.wait([a, b]);
      expect(notice(), const ReferralCreditNotice(days: 7, totalDaysEarned: 7));
    });

    test('a dismissal or re-baseline that lands while the verify is in '
        'flight is not overwritten by the stale decision', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      sub.verifyGate = Completer<void>();
      final running = notifier().check(callForTest: () async => _s(7));
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // The total is recorded as seen by another path while the verify waits.
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 7);
      sub.verifyGate!.complete();
      await running;
      expect(notice(), isNull);
    });
  });

  group('single-flight and throttle', () {
    test('three simultaneous triggers make ONE network call', () async {
      var calls = 0;
      final gate = Completer<ReferrerSummary?>();
      Future<ReferrerSummary?> call() {
        calls++;
        return gate.future;
      }

      final a = notifier().check(callForTest: call);
      final b = notifier().check(callForTest: call);
      final c = notifier().check(callForTest: call);
      expect(calls, 1);
      gate.complete(_s(0));
      await Future.wait([a, b, c]);
      expect(calls, 1);
    });

    test('resume checks are throttled to one per 6 hours', () async {
      var calls = 0;
      Future<ReferrerSummary?> call() async {
        calls++;
        return _s(0);
      }

      final t0 = DateTime.utc(2026, 10, 17, 6);
      await notifier().check(fromResume: true, callForTest: call, nowForTest: t0);
      await notifier().check(
          fromResume: true,
          callForTest: call,
          nowForTest: t0.add(const Duration(hours: 5, minutes: 59)));
      expect(calls, 1);
      await notifier().check(
          fromResume: true,
          callForTest: call,
          nowForTest: t0.add(const Duration(hours: 6)));
      expect(calls, 2);
    });

    test('a resume whose read did not answer does not start the six-hour '
        'throttle', () async {
      var calls = 0;
      final t0 = DateTime.utc(2026, 10, 17, 6);
      await notifier().check(
          fromResume: true,
          callForTest: () async {
            calls++;
            return null;
          },
          nowForTest: t0);
      await notifier().check(
          fromResume: true,
          callForTest: () async {
            calls++;
            return _s(0);
          },
          nowForTest: t0.add(const Duration(minutes: 10)));
      expect(calls, 2);
    });

    test('a non-resume trigger is never throttled', () async {
      var calls = 0;
      Future<ReferrerSummary?> call() async {
        calls++;
        return _s(0);
      }

      await notifier().check(callForTest: call);
      await notifier().check(callForTest: call);
      expect(calls, 2);
    });
  });

  group('account swaps', () {
    test("A's summary completing AFTER the swap never reaches B and writes "
        'nothing', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      final gate = Completer<ReferrerSummary?>();
      final running = notifier().check(callForTest: () => gate.future);
      container.read(_tokenProvider.notifier).set('tokenB');
      gate.complete(_s(14));
      await running;
      expect(notice(), isNull);
      expect(seenScalar(), 0, reason: 'no write for the account that left');
      expect(sub.forceArgs, isEmpty);
    });

    test("B's trigger during A's in-flight call makes its OWN call", () async {
      var calls = <String>[];
      final gateA = Completer<ReferrerSummary?>();
      final a = notifier().check(callForTest: () {
        calls.add('A');
        return gateA.future;
      });
      container.read(_tokenProvider.notifier).set('tokenB');
      await notifier().check(callForTest: () async {
        calls.add('B');
        return _s(0);
      });
      expect(calls, ['A', 'B']);
      gateA.complete(_s(0));
      await a;
    });

    test("A's resume throttle does not suppress B", () async {
      var calls = 0;
      Future<ReferrerSummary?> call() async {
        calls++;
        return _s(0);
      }

      final t0 = DateTime.utc(2026, 10, 17, 6);
      await notifier().check(fromResume: true, callForTest: call, nowForTest: t0);
      container.read(_tokenProvider.notifier).set('tokenB');
      await notifier().check(
          fromResume: true,
          callForTest: call,
          nowForTest: t0.add(const Duration(minutes: 1)));
      expect(calls, 2);
    });

    test("A's verified-for memory does not skip B's forced verify", () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      await notifier().check(callForTest: () async => _s(7));
      expect(sub.forceArgs, [true]);
      container.read(_tokenProvider.notifier).set('tokenB');
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      await notifier().check(callForTest: () async => _s(7));
      expect(sub.forceArgs, [true, true]);
    });

    test("after a swap the previous account's card is gone and a dismiss() "
        'from the new account writes nothing (build() resets the state; the '
        'token check inside _writeSeen is defence in depth, unreachable '
        'between two synchronous calls)', () async {
      await HiveService.instance.userBox.put(kReferralCreditSeenKey, 0);
      await notifier().check(callForTest: () async => _s(7));
      expect(notice(), isNotNull);
      // The write path re-checks the token. Swap, then dismiss for the old state.
      final shown = notice()!;
      container.read(_tokenProvider.notifier).set('tokenB');
      // build() re-ran for B: the old notice is gone with the old account.
      expect(notice(), isNull);
      await notifier().dismiss();
      expect(seenScalar(), 0, reason: 'B tapping nothing writes nothing');
      expect(shown.totalDaysEarned, 7);
    });
  });

  group('guards', () {
    test('the anonymous token makes no call', () async {
      container.read(_tokenProvider.notifier).set('<anon>');
      var calls = 0;
      await notifier().check(callForTest: () async {
        calls++;
        return _s(7);
      });
      expect(calls, 0);
      expect(notice(), isNull);
    });

    test('the kill switch makes no call and shows nothing', () async {
      await HiveService.instance.configBox
          .put('disable_referral_credit_notice', true);
      var calls = 0;
      await notifier().check(callForTest: () async {
        calls++;
        return _s(7);
      });
      expect(calls, 0);
      expect(notice(), isNull);
    });

    test('with no session owner a silent baseline is DROPPED (the key must '
        'never land in the shared configBox)', () async {
      await HiveUserSession.closeAll();
      expect(HiveUserSession.currentOwnerFullId, isNull);
      await notifier().check(callForTest: () async => _s(7));
      expect(HiveService.instance.configBox.containsKey(kReferralCreditSeenKey),
          isFalse);
    });

    test('an unknown read (null) leaves the surface absent', () async {
      await notifier().check(callForTest: () async => null);
      expect(notice(), isNull);
      expect(seenScalar(), isNull);
    });
  });
}
