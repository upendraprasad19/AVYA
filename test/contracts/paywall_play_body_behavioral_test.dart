// OI-519 (+51, ADR-0022), plan docs/plans/2026-11-23-revenuecat-play-billing-51.md section 5: the REAL PaywallSheet
// in a Google Play build, with a fake store (no SDK), a fake confirm step and a fake uid.
//
// Pins: every price comes from the store (never AppConstants: no 349 / 2999 / save 28%), no promo box, no website;
// the store's user is set BEFORE any buy button exists; each purchase outcome lands in its own state; RESTORE is the
// confirm step (sync + verify), never a store restore; an active paid plan shows "PRO until" and no buy button; a Play
// row gets MANAGE IN GOOGLE PLAY.
//
// Harness as paywall_mode_none_behavioral_test.dart (fonts warmed first, root CLAUDE.md 4.9).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/play_billing_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_play_body.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

const _uid = '11111111-2222-3333-4444-555555555555';

class _Store implements PlayStore {
  final List<String> calls = [];
  bool key = true;
  Object? loadError;
  PlayPurchaseOutcome outcome =
      const PlayPurchaseOutcome(PlayPurchaseStatus.purchased);
  PlayPlanOffer? bought;
  String? boughtFor;

  static const monthly = PlayPlanOffer(
      period: PlayPlanPeriod.monthly, priceString: '₹449.00', price: 449);
  static const yearly = PlayPlanOffer(
      period: PlayPlanPeriod.yearly, priceString: '₹3,499.00', price: 3499);

  @override
  bool get hasKey => key;

  @override
  Future<void> identify(String uid) async => calls.add('identify:$uid');

  @override
  Future<List<PlayPlanOffer>> loadPlans() async {
    calls.add('loadPlans');
    final e = loadError;
    if (e != null) {
      loadError = null; // the retry succeeds
      throw e;
    }
    return const [monthly, yearly];
  }

  @override
  Future<PlayPurchaseOutcome> purchase(PlayPlanOffer offer,
      {required String expectedUid}) async {
    calls.add('purchase:${offer.planId}');
    bought = offer;
    boughtFor = expectedUid;
    return outcome;
  }

  @override
  Future<void> releaseIdentity() async => calls.add('release');
}

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.data);
  final SubscriptionInfoData data;
  @override
  SubscriptionInfoData build() => data;
}

class _NoSubs implements SubscriptionService {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('the Play body never calls ${i.memberName}');
}

class _NoRazorpay implements RazorpayService {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('a Play build never touches Razorpay: ${i.memberName}');
}

late _Store _store;
late List<String> _events;
late List<bool> _confirms;
late bool _confirmAnswer;
late int _manageOpens;

Future<void> _open(
  WidgetTester tester, {
  SubscriptionInfoData info = const SubscriptionInfoData(),
  String? uid = _uid,
  String feature = PaywallSheet.genericUpgrade,
}) async {
  PurchaseMode.debugOverrideForTests = PurchaseMode.playBilling;
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionInfoProvider.overrideWith(() => _Sub(info)),
      subscriptionServiceProvider.overrideWithValue(_NoSubs()),
      razorpayServiceProvider.overrideWithValue(_NoRazorpay()),
      playStoreProvider.overrideWithValue(_store),
      playBuyerUidProvider.overrideWithValue(uid),
      playProConfirmerProvider.overrideWithValue(
          ({required bool afterPurchase}) async {
        _confirms.add(afterPurchase);
        return _confirmAnswer;
      }),
      playManageOpenerProvider.overrideWithValue(() async => _manageOpens++),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => PaywallSheet(feature: feature),
              ),
              child: const Text('open-paywall'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open-paywall'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    final navs = find.byType(Navigator);
    if (navs.evaluate().isEmpty) return;
    final nav = tester.state<NavigatorState>(navs.first);
    if (nav.canPop()) nav.pop();
    await tester.pumpAndSettle();
  });
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

final _buy = find.byKey(const ValueKey('paywall-play-buy'));
final _status = find.byKey(const ValueKey('paywall-play-status'));
final _manage = find.byKey(const ValueKey('paywall-play-manage'));

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(_status).data ?? '';

/// Texts that may only ever come from the web build (AppConstants prices, the
/// web saving, the promo box, the website).
void _expectNoWebPurchaseText() {
  for (final t in ['349', '2999', '2,999', 'SAVE 28%', 'save 28%']) {
    expect(find.textContaining(t), findsNothing, reason: t);
  }
  expect(find.textContaining('icanbefitter.com'), findsNothing);
  expect(find.text('APPLY'), findsNothing);
  expect(find.text('PROMO CODE'), findsNothing);
  expect(find.byType(TextField), findsNothing, reason: 'no promo box');
}

void main() {
  testWidgets('typography warmup: GoogleFonts caches every family first',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.h1),
          Text('f', style: AppTypography.mono),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  setUp(() {
    _store = _Store();
    _events = [];
    _confirms = [];
    _confirmAnswer = true;
    _manageOpens = 0;
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => _events.add('$op|${message ?? ''}');
  });
  tearDown(() {
    PurchaseMode.debugOverrideForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  group('plans', () {
    testWidgets('store prices only, the saving computed from them, terms shown',
        (tester) async {
      await _open(tester);
      expect(find.byKey(const ValueKey('paywall-play-body')), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-unavailable-body')),
          findsNothing);
      expect(find.text('₹449.00'), findsOneWidget);
      expect(find.text('₹3,499.00'), findsOneWidget);
      // (449 * 12 - 3499) / (449 * 12) = 35.06 %, floored.
      expect(find.text('SAVE 35%'), findsOneWidget);
      expect(find.text(PurchaseCopy.playRenewalTerms), findsOneWidget);
      expect(_buy, findsOneWidget);
      _expectNoWebPurchaseText();
      expect(_events, contains('paywall_play_shown|feature=PRO'));
      expect(_events.where((e) => e.startsWith('paywall_unavailable_shown')),
          isEmpty);
    });

    testWidgets('the store user is set to the signed-in uid BEFORE the plans',
        (tester) async {
      await _open(tester);
      expect(_store.calls, ['identify:$_uid', 'loadPlans']);
    });

    testWidgets('no agreed uid: no identify, no plans, no buy button',
        (tester) async {
      await _open(tester, uid: null);
      expect(_store.calls, isEmpty);
      expect(_buy, findsNothing);
      expect(_statusText(tester), PurchaseCopy.playAccountNotReady);
    });

    testWidgets('plans fail to load: no price, an error with retry that works',
        (tester) async {
      _store.loadError = StateError('offline');
      await _open(tester);
      expect(_buy, findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(_statusText(tester), PurchaseCopy.playLoadFailed);
      expect(_events, contains('play_offerings_failed|type=StateError'));
      await _tap(tester, find.byKey(const ValueKey('paywall-play-retry')));
      expect(_buy, findsOneWidget);
      expect(find.text('₹3,499.00'), findsOneWidget);
    });

    testWidgets('a referral-days user may buy, told the plan starts today',
        (tester) async {
      await _open(tester,
          info: SubscriptionInfoData(
              isPro: true,
              plan: 'referral_trial',
              expiresAt: DateTime.utc(2026, 12, 1)));
      expect(_buy, findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-play-referral-today')),
          findsOneWidget);
    });
  });

  group('purchase outcomes', () {
    testWidgets('purchased: the SELECTED plan for THIS uid, then the confirm '
        'step after purchase; PRO confirmed says welcome', (tester) async {
      await _open(tester);
      await _tap(tester, find.text('₹449.00'));
      await _tap(tester, _buy);
      expect(_store.bought?.period, PlayPlanPeriod.monthly);
      expect(_store.boughtFor, _uid);
      expect(_confirms, [true]);
      expect(_statusText(tester), PurchaseCopy.playWelcome);
      expect(
          _events,
          contains(
              'paywall_upgrade_tapped|feature=PRO plan=monthly store=play'));
    });

    testWidgets('the yearly plan is pre-selected', (tester) async {
      await _open(tester);
      await _tap(tester, _buy);
      expect(_store.bought?.period, PlayPlanPeriod.yearly);
    });

    testWidgets('purchased but not yet confirmed: the slow line, buy again '
        'possible', (tester) async {
      _confirmAnswer = false;
      await _open(tester);
      await _tap(tester, _buy);
      expect(_confirms, [true]);
      expect(_statusText(tester), PurchaseCopy.playConfirmSlow);
      expect(_buy, findsOneWidget);
    });

    testWidgets('cancelled: back to the plans, no message, no confirm',
        (tester) async {
      _store.outcome = const PlayPurchaseOutcome(PlayPurchaseStatus.cancelled,
          errorCode: 'purchaseCancelledError');
      await _open(tester);
      await _tap(tester, _buy);
      expect(_confirms, isEmpty);
      expect(_status, findsNothing);
      expect(_buy, findsOneWidget);
      expect(_events.where((e) => e.startsWith('play_purchase_failed')),
          isEmpty);
    });

    testWidgets('pending: the pending line, no confirm, no buy button',
        (tester) async {
      _store.outcome = const PlayPurchaseOutcome(PlayPurchaseStatus.pending);
      await _open(tester);
      await _tap(tester, _buy);
      expect(_confirms, isEmpty);
      expect(_statusText(tester), PurchaseCopy.playPending);
      expect(_buy, findsNothing);
    });

    testWidgets('owned by another AVYA account: its line and the manage link',
        (tester) async {
      _store.outcome = const PlayPurchaseOutcome(
          PlayPurchaseStatus.ownedByOtherAccount,
          errorCode: 'productAlreadyPurchasedError');
      await _open(tester);
      expect(_manage, findsNothing);
      await _tap(tester, _buy);
      expect(_confirms, isEmpty);
      expect(_statusText(tester), PurchaseCopy.playOwnedByOtherAccount);
      await _tap(tester, _manage);
      expect(_manageOpens, 1);
    });

    testWidgets('identity mismatch: nothing charged, the account line',
        (tester) async {
      _store.outcome =
          const PlayPurchaseOutcome(PlayPurchaseStatus.identityMismatch);
      await _open(tester);
      await _tap(tester, _buy);
      expect(_confirms, isEmpty);
      expect(_statusText(tester), PurchaseCopy.playAccountNotReady);
    });

    testWidgets('failed: the failure line and the code in telemetry',
        (tester) async {
      _store.outcome = const PlayPurchaseOutcome(PlayPurchaseStatus.failed,
          errorCode: 'storeProblemError');
      await _open(tester);
      await _tap(tester, _buy);
      expect(_confirms, isEmpty);
      expect(_statusText(tester), PurchaseCopy.playPurchaseFailed);
      expect(_events, contains('play_purchase_failed|code=storeProblemError'));
    });

    testWidgets('a tried purchase is not counted as a dismissal',
        (tester) async {
      _store.outcome = const PlayPurchaseOutcome(PlayPurchaseStatus.cancelled);
      await _open(tester);
      await _tap(tester, _buy);
      await _tap(tester, find.text('MAYBE LATER'));
      expect(_events.where((e) => e.startsWith('paywall_dismissed')), isEmpty);
    });

    testWidgets('closing untouched IS a dismissal', (tester) async {
      await _open(tester);
      await _tap(tester, find.text('MAYBE LATER'));
      expect(_events, contains('paywall_dismissed|feature=PRO'));
    });
  });

  group('restore', () {
    testWidgets('RESTORE is the confirm step (not after a purchase): restored',
        (tester) async {
      await _open(tester);
      await _tap(tester, find.text('RESTORE'));
      expect(_confirms, [false]);
      expect(_store.calls.where((c) => c.startsWith('purchase')), isEmpty);
      expect(_statusText(tester), PurchaseCopy.playRestored);
    });

    testWidgets('RESTORE with nothing to restore says so', (tester) async {
      _confirmAnswer = false;
      await _open(tester);
      await _tap(tester, find.text('RESTORE'));
      expect(_confirms, [false]);
      expect(_statusText(tester), PurchaseCopy.playNothingToRestore);
      expect(_buy, findsOneWidget, reason: 'back to the plans');
    });
  });

  group('already PRO', () {
    testWidgets('a Play row: PRO until the STORE date (IST day), manage link, '
        'no plans, no store call', (tester) async {
      await _open(tester,
          info: SubscriptionInfoData(
            isPro: true,
            plan: 'yearly',
            // end_date carries the 3-hour window: 24 Dec 01:30 IST.
            expiresAt: DateTime.utc(2026, 12, 23, 20, 0),
            // The store's own expiry: 23 Dec 22:30 IST.
            displayExpiresAt: DateTime.utc(2026, 12, 23, 17, 0),
            store: 'play',
            autoRenews: true,
          ));
      expect(find.text(PurchaseCopy.proUntil('23 Dec 2026')), findsOneWidget);
      expect(_buy, findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(_store.calls, isEmpty);
      await _tap(tester, _manage);
      expect(_manageOpens, 1);
    });

    testWidgets('a web or other paid row: PRO until, no manage link',
        (tester) async {
      await _open(tester,
          info: SubscriptionInfoData(
              isPro: true,
              plan: 'monthly',
              expiresAt: DateTime.utc(2026, 12, 10, 6)));
      expect(find.text(PurchaseCopy.proUntil('10 Dec 2026')), findsOneWidget);
      expect(_manage, findsNothing);
      expect(_buy, findsNothing);
      expect(_store.calls, isEmpty);
    });
  });

  group('pure helpers', () {
    test('istShortDate is the IST calendar day', () {
      expect(istShortDate(DateTime.utc(2026, 12, 23, 18, 29)), '23 Dec 2026');
      expect(istShortDate(DateTime.utc(2026, 12, 23, 18, 30)), '24 Dec 2026');
    });

    test('playBuyerUid: only when the auth uid and the Hive owner agree', () {
      expect(playBuyerUid(authUid: 'a', hiveOwner: 'a'), 'a');
      expect(playBuyerUid(authUid: 'a', hiveOwner: 'b'), isNull);
      expect(playBuyerUid(authUid: 'a', hiveOwner: null), isNull);
      expect(playBuyerUid(authUid: null, hiveOwner: 'a'), isNull);
      expect(playBuyerUid(authUid: '', hiveOwner: ''), isNull);
    });

    test('confirmPlayPro: stops on PRO or stop, always ends with verify',
        () async {
      Future<(int, bool)> run(List<PlaySyncAnswer> answers, bool verified,
          {int attempts = 4}) async {
        var asked = 0;
        final ok = await confirmPlayPro(
          syncOnce: () async => answers[asked++],
          verify: () async => verified,
          attempts: attempts,
          wait: (_) async {},
        );
        return (asked, ok);
      }

      expect(await run([PlaySyncAnswer.pro], true), (1, true));
      expect(
          await run([PlaySyncAnswer.notPro, PlaySyncAnswer.pro], true), (2, true));
      expect(await run([PlaySyncAnswer.stop], false), (1, false));
      expect(
          await run(List.filled(4, PlaySyncAnswer.notPro), false), (4, false));
      // The sync answer alone never makes the app PRO: verify decides.
      expect(await run([PlaySyncAnswer.pro], false), (1, false));
      expect(await run([PlaySyncAnswer.notPro], true, attempts: 1), (1, true));
    });
  });
}
