// OI-341 Piece B2b — the paywall line a referral-trial user sees
// (docs/plans/oi341-piece-b2b-client.md 2.4, W1-W2), on the REAL PaywallSheet.
//
// Harness from test/widgets/swap_picker_sheet_test.dart: the FIRST test warms
// every GoogleFonts family the sheet renders (Fraunces, DM Sans, mono) so a
// later render degrades quietly (root CLAUDE.md 4.9); the sheet needs no Hive;
// subscriptionInfoProvider is overridden; telemetry from initState and dispose
// is swallowed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.data);
  final SubscriptionInfoData data;
  @override
  SubscriptionInfoData build() => data;
}

const _notice = 'Your paid plan starts when your free days end.';
const _key = ValueKey('paywall-trial-stacking-notice');

Future<void> _pumpSheet(WidgetTester tester, SubscriptionInfoData data) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(data))],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PaywallSheet(feature: PaywallSheet.genericUpgrade),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
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

  group('paywall stacking line', () {
    setUp(() => ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {});
    tearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

    testWidgets('W1 a referral-trial user sees the line, exact text',
        (tester) async {
      await _pumpSheet(tester,
          const SubscriptionInfoData(isPro: true, plan: 'referral_trial'));
      expect(find.byKey(_key), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(_key)).data, _notice);
    });

    // One state per testWidgets: a second pumpWidget reuses the ProviderScope
    // element, whose override does not change, so a loop here tested only its
    // first case (mutant M19 survived that version).
    for (final data in const [
      SubscriptionInfoData(isPro: true, plan: 'monthly'),
      SubscriptionInfoData(),
      SubscriptionInfoData(isPro: false, plan: 'referral_trial'),
    ]) {
      testWidgets(
          'W2 no line for isPro=${data.isPro} plan=${data.plan}',
          (tester) async {
        await _pumpSheet(tester, data);
        expect(find.text('UPGRADE TO PRO'), findsOneWidget,
            reason: 'the sheet rendered');
        expect(find.byKey(_key), findsNothing);
        expect(find.text(_notice), findsNothing);
      });
    }
  });
}
