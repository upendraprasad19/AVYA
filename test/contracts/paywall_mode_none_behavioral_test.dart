// ADR-0022 / plan section 7 test 2: the REAL PaywallSheet in a binary that
// sells nothing, and (same file) in the Razorpay binary it must leave alone.
//
// Harness as test/widgets/paywall_trial_stacking_notice_test.dart: the first
// test warms GoogleFonts (root CLAUDE.md 4.9); the sheet is opened through the
// real `showPaywallSheet` from a button, so `Navigator.pop` has a route to pop.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

class _Sub extends SubscriptionInfoNotifier {
  @override
  SubscriptionInfoData build() => const SubscriptionInfoData();
}

/// `SubscriptionService` has a private constructor: implement it and answer
/// only the two calls the sheet makes.
class _FakeSubscriptions implements SubscriptionService {
  int refreshCalls = 0;
  bool pro = false;
  Object? refreshError;
  Completer<void>? refreshGate;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #refreshFromSupabase) {
      refreshCalls++;
      if (refreshError != null) return Future<void>.error(refreshError!);
      if (refreshGate != null) return refreshGate!.future;
      return Future<void>.value();
    }
    if (i.memberName == #isPro) return pro;
    return super.noSuchMethod(i);
  }
}

class _FakeRazorpay implements RazorpayService {
  int openCheckoutCalls = 0;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #openCheckout) {
      openCheckoutCalls++;
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

late _FakeSubscriptions _subs;
late _FakeRazorpay _razorpay;
late List<String> _events;

Future<void> _open(WidgetTester tester, PurchaseMode mode,
    {String feature = PaywallSheet.genericUpgrade}) async {
  PurchaseMode.debugOverrideForTests = mode;
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionInfoProvider.overrideWith(() => _Sub()),
      subscriptionServiceProvider.overrideWithValue(_subs),
      razorpayServiceProvider.overrideWithValue(_razorpay),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              // `showPaywallSheet` itself builds an AnimationController that
              // the finalising test tree reports as a leaked ticker, so the
              // harness opens the same widget the same way minus that
              // controller.
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
  // The route's slide-in needs frames, not one long pump.
  await tester.pumpAndSettle();
  _settleSheetAtEnd(tester);
}

/// A sheet still open at the end of a test leaves its route ticker active when
/// the tree is finalised, which Flutter reports as a leak. Close it first.
void _settleSheetAtEnd(WidgetTester tester) {
  addTearDown(() async {
    final navs = find.byType(Navigator);
    if (navs.evaluate().isEmpty) return;
    final nav = tester.state<NavigatorState>(navs.first);
    if (nav.canPop()) nav.pop();
    await tester.pumpAndSettle();
  });
}

/// The test font is wide, so the sheet is taller than the window: scroll the
/// target into view before tapping it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  testWidgets('typography warmup — GoogleFonts caches every family first',
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
    _subs = _FakeSubscriptions();
    _razorpay = _FakeRazorpay();
    _events = [];
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => _events.add('$op|${message ?? ''}');
  });
  tearDown(() {
    PurchaseMode.debugOverrideForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  for (final mode in [PurchaseMode.none, PurchaseMode.playBilling]) {
    group('mode ${mode.wireName}: nothing can be bought', () {
      testWidgets('no price, plan card, promo box or purchase button',
          (tester) async {
        await _open(tester, mode);
        expect(find.byKey(const ValueKey('paywall-unavailable-body')),
            findsOneWidget);
        expect(find.textContaining('₹'), findsNothing);
        expect(find.text('UPGRADE TO PRO'), findsNothing);
        expect(find.text('GO PRO'), findsNothing);
        expect(find.text('MONTHLY'), findsNothing);
        expect(find.text('YEARLY'), findsNothing);
        expect(find.text('APPLY'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('MAYBE LATER'), findsNothing);
        expect(find.textContaining('Upgrade to PRO'), findsNothing);
        // The founder's neutral card and the two buttons.
        expect(find.text(PurchaseCopy.card), findsOneWidget);
        expect(find.text(PurchaseCopy.checkStatusButton), findsOneWidget);
        expect(find.text(PurchaseCopy.closeButton), findsOneWidget);
        expect(_razorpay.openCheckoutCalls, 0);
      });

      testWidgets('CHECK MY PRO STATUS re-reads the server row once',
          (tester) async {
        await _open(tester, mode);
        await _tap(tester, find.text(PurchaseCopy.checkStatusButton));
        await tester.pumpAndSettle();
        expect(_subs.refreshCalls, 1);
        expect(find.byKey(const ValueKey('paywall-unavailable-body')),
            findsNothing,
            reason: 'the sheet closes after the check');
        expect(
            find.text(
                'No active subscription found. Contact support if this is wrong.'),
            findsOneWidget);
      });

      testWidgets(
          'an unreachable server is reported INSIDE the card (a snackbar would '
          'sit behind the sheet), the card stays open and the button returns',
          (tester) async {
        _subs.refreshError = Exception('offline');
        await _open(tester, mode);
        expect(find.byKey(const ValueKey('paywall-unavailable-status')),
            findsNothing,
            reason: 'no failure line before anything failed');
        await _tap(tester, find.text(PurchaseCopy.checkStatusButton));
        await tester.pumpAndSettle();
        expect(_subs.refreshCalls, 1);
        expect(find.byKey(const ValueKey('paywall-unavailable-body')),
            findsOneWidget,
            reason: 'a failed check must not close the card');
        expect(find.text(PurchaseCopy.checkStatusFailed), findsOneWidget);
        expect(find.text(PurchaseCopy.checkStatusButton), findsOneWidget,
            reason: 'the button is usable again, not stuck on "..."');
        expect(find.textContaining('Could not verify purchase'), findsNothing,
            reason: 'the purchase-mode snackbar wording must not appear');
        expect(
            _events
                .where((e) => e.startsWith('paywall_restore_purchase_failed'))
                .length,
            1);
        // A second attempt clears the old line AT ONCE (while it is in
        // flight), then a success closes the card.
        _subs.refreshError = null;
        _subs.refreshGate = Completer<void>();
        await _tap(tester, find.text(PurchaseCopy.checkStatusButton));
        await tester.pump();
        expect(find.text(PurchaseCopy.checkStatusFailed), findsNothing,
            reason: 'a stale failure line must not sit beside a new attempt');
        expect(find.text('...'), findsOneWidget);
        _subs.refreshGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('paywall-unavailable-body')),
            findsNothing);
        expect(find.text(PurchaseCopy.checkStatusFailed), findsNothing);
      });

      testWidgets('a PRO account is told so', (tester) async {
        _subs.pro = true;
        await _open(tester, mode);
        await _tap(tester, find.text(PurchaseCopy.checkStatusButton));
        await tester.pumpAndSettle();
        expect(find.text('PRO restored successfully'), findsOneWidget);
      });

      testWidgets('telemetry: shown keeps its message, plus one unavailable '
          'event, and CLOSE counts as a dismissal', (tester) async {
        await _open(tester, mode);
        expect(_events.where((e) => e == 'paywall_shown|feature=PRO').length, 1);
        expect(
            _events
                .where((e) => e == 'paywall_unavailable_shown|feature=PRO')
                .length,
            1);
        await _tap(tester, find.text(PurchaseCopy.closeButton));
        await tester.pumpAndSettle();
        expect(_events.where((e) => e == 'paywall_dismissed|feature=PRO').length,
            1,
            reason: 'nothing was upgraded, so closing is a dismissal');
        expect(_events.any((e) => e.startsWith('paywall_upgrade_tapped')),
            isFalse);
      });

      testWidgets('a specific feature still names itself', (tester) async {
        await _open(tester, mode, feature: 'Progress Photos');
        expect(find.text('Progress Photos is a PRO feature'), findsOneWidget);
      });

      testWidgets('the generic subtitle no longer says upgrade',
          (tester) async {
        await _open(tester, mode);
        expect(find.text(PurchaseCopy.defaultSubtitle), findsOneWidget);
      });
    });
  }

  group('mode razorpay: the purchase sheet is unchanged', () {
    testWidgets('plan cards, promo box and the purchase button are present',
        (tester) async {
      await _open(tester, PurchaseMode.razorpay);
      expect(find.byKey(const ValueKey('paywall-unavailable-body')),
          findsNothing);
      expect(find.text('UPGRADE TO PRO'), findsOneWidget);
      expect(find.text('MONTHLY'), findsOneWidget);
      expect(find.text('YEARLY'), findsOneWidget);
      expect(find.text('APPLY'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('GO PRO'), findsOneWidget);
      // The positive pairs of the absence checks in the no-purchase groups:
      // these strings exist in the purchase sheet, so a rename there would
      // otherwise make those checks vacuous (B-pass 2026-11-20, F10).
      expect(find.text('MAYBE LATER'), findsOneWidget);
      expect(find.textContaining('₹'), findsWidgets);
      expect(find.textContaining('Upgrade to PRO'), findsWidgets);
      expect(find.text(PurchaseCopy.checkStatusButton), findsNothing);
      expect(_events.where((e) => e == 'paywall_shown|feature=PRO').length, 1);
      expect(_events.any((e) => e.startsWith('paywall_unavailable_shown')),
          isFalse);
    });
  });
}
