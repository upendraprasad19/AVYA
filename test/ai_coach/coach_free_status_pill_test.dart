// OI-348 walk P4 (founder 2026-11-22): the FREE account's coach-header pill.
// A build that sells nothing draws "PRO" as a dim grey outline (it read as a
// PRO status badge in gold); a selling build keeps the gold UPGRADE pill. The
// tap is the same in both.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';

void main() {
  tearDown(() => PurchaseMode.debugOverrideForTests = null);

  Future<void> pump(WidgetTester tester, VoidCallback onTap) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: CoachFreeStatusPill(onTap: onTap))),
      ));

  BoxDecoration deco(WidgetTester tester) => tester
      .widget<Container>(find.descendant(
          of: find.byType(CoachFreeStatusPill),
          matching: find.byType(Container)))
      .decoration! as BoxDecoration;

  testWidgets('no-purchase build: dim grey outline, PRO, same tap',
      (tester) async {
    PurchaseMode.debugOverrideForTests = PurchaseMode.none;
    var taps = 0;
    await pump(tester, () => taps++);
    expect(find.text(PurchaseCopy.proInfo), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(tester.widget<Text>(find.text(PurchaseCopy.proInfo)).style!.color,
        AppColors.textDim);
    expect((deco(tester).border! as Border).top.color, AppColors.textMute);
    expect(deco(tester).color, isNull, reason: 'no gold fill');
    expect(find.bySemanticsLabel(PurchaseCopy.proPillFreeLabel), findsOneWidget);
    await tester.tap(find.byType(CoachFreeStatusPill));
    expect(taps, 1);
  });

  testWidgets('selling build: gold UPGRADE pill unchanged', (tester) async {
    PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
    var taps = 0;
    await pump(tester, () => taps++);
    expect(find.text('UPGRADE'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(tester.widget<Text>(find.text('UPGRADE')).style!.color,
        AppColors.accent);
    expect((deco(tester).border! as Border).top.color, AppColors.accent);
    expect(deco(tester).color, AppColors.accentSoft);
    await tester.tap(find.byType(CoachFreeStatusPill));
    expect(taps, 1);
  });
}
