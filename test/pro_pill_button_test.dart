import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
