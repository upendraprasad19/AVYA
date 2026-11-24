// Plan section 7 test 3: the phase pitch sheet carries its own price line and
// UPGRADE TO PRO button. In a binary that sells nothing it must hand over to
// the neutral paywall body; in the Razorpay binary it is unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/play_billing_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

class _Sub extends SubscriptionInfoNotifier {
  @override
  SubscriptionInfoData build() => const SubscriptionInfoData();
}

Future<void> _open(WidgetTester tester, PurchaseMode mode) async {
  PurchaseMode.debugOverrideForTests = mode;
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionInfoProvider.overrideWith(() => _Sub()),
      // OI-519: keyless, so the Play build here sells nothing (explicit: a
      // run with the key defined cannot flip it).
      playStoreProvider.overrideWithValue(_NoKeyStore()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPaywallSheetPhaseVariant(context),
              child: const Text('open-phase-sheet'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open-phase-sheet'));
  // The route's slide-in needs frames, not one long pump.
  await tester.pumpAndSettle();
  // A sheet still open at the end leaves its route ticker active when the tree
  // is finalised (reported as a leak): close it first.
  addTearDown(() async {
    final navs = find.byType(Navigator);
    if (navs.evaluate().isEmpty) return;
    final nav = tester.state<NavigatorState>(navs.first);
    if (nav.canPop()) nav.pop();
    await tester.pumpAndSettle();
  });
}

class _NoKeyStore implements PlayStore {
  @override
  bool get hasKey => false;
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('no store call without a key: ${i.memberName}');
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

  setUp(() => ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {});
  tearDown(() {
    PurchaseMode.debugOverrideForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  for (final mode in [PurchaseMode.none, PurchaseMode.playBilling]) {
    testWidgets('mode ${mode.wireName}: no price line, no upgrade button',
        (tester) async {
      await _open(tester, mode);
      expect(find.byKey(const ValueKey('paywall-unavailable-body')),
          findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.textContaining('UPGRADE TO PRO'), findsNothing);
      expect(find.textContaining('/ month'), findsNothing);
      expect(find.text('Phases 2-12 is a PRO feature'), findsOneWidget);
    });
  }

  testWidgets('mode razorpay: the phase pitch is unchanged', (tester) async {
    await _open(tester, PurchaseMode.razorpay);
    expect(find.byKey(const ValueKey('paywall-unavailable-body')),
        findsNothing);
    expect(find.textContaining('UPGRADE TO PRO'), findsOneWidget);
    expect(find.textContaining('/ month'), findsOneWidget);
  });
}
