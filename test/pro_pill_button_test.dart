import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/pro_pill_button.dart';

void main() {
  group('ProPillButton', () {
    testWidgets('PRO state shows "PRO" label and fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProPillButton(isPro: true, onTap: () => tapped = true),
        ),
      ));

      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('GO PRO'), findsNothing);

      await tester.tap(find.byType(ProPillButton));
      expect(tapped, isTrue);
    });

    testWidgets('Free state shows "GO PRO" label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProPillButton(isPro: false, onTap: () {}),
        ),
      ));

      expect(find.text('GO PRO'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('Both states render the same pill shape', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            ProPillButton(isPro: true, onTap: () {}),
            ProPillButton(isPro: false, onTap: () {}),
          ]),
        ),
      ));

      final containers = tester.widgetList<Container>(
        find.descendant(of: find.byType(ProPillButton), matching: find.byType(Container)),
      ).toList();
      // Each ProPillButton has at least one decorated Container
      expect(containers.length, greaterThanOrEqualTo(2));
    });
  });

  // OI-348 walk P4 (founder 2026-11-22): in a build that sells nothing a FREE
  // account's pill is a dim grey outline, so "PRO" no longer reads as a PRO
  // badge; a PRO account and a selling build keep the metal pills.
  group('ProPillButton, free account in a no-purchase build (P4)', () {
    tearDown(() => PurchaseMode.debugOverrideForTests = null);

    Future<void> pump(WidgetTester tester, {required bool isPro}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ProPillButton(isPro: isPro, onTap: () {})),
        ));

    BoxDecoration outer(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(
            of: find.byType(ProPillButton), matching: find.byType(Container)))
        .first
        .decoration! as BoxDecoration;
    BoxDecoration inner(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(
            of: find.byType(ProPillButton), matching: find.byType(Container)))
        .last
        .decoration! as BoxDecoration;

    testWidgets('dim grey outline, no metal fill, same label and tap',
        (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProPillButton(isPro: false, onTap: () => tapped = true)),
      ));
      expect(find.text(PurchaseCopy.proInfo), findsOneWidget);
      expect(tester.widget<Text>(find.text(PurchaseCopy.proInfo)).style!.color,
          AppColors.textDim);
      expect((outer(tester).border! as Border).top.color, AppColors.textMute);
      expect(outer(tester).boxShadow, isNull);
      expect(inner(tester).gradient, isNull, reason: 'no metal fill');
      expect(find.bySemanticsLabel(PurchaseCopy.proPillFreeLabel),
          findsOneWidget);
      await tester.tap(find.byType(ProPillButton));
      expect(tapped, isTrue);
    });

    testWidgets('a PRO account keeps the gold metal pill', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await pump(tester, isPro: true);
      expect(inner(tester).gradient, isNotNull);
      expect(tester.widget<Text>(find.text(PurchaseCopy.proInfo)).style!.color,
          Colors.black);
    });

    testWidgets('a selling build keeps the silver GO PRO pill', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await pump(tester, isPro: false);
      expect(find.text('GO PRO'), findsOneWidget);
      expect(inner(tester).gradient, isNotNull);
      expect((outer(tester).border! as Border).top.color,
          isNot(AppColors.textMute));
    });
  });
}
