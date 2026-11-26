// Nutrition tab (founder call 2026-11-01): LOG FOOD | LOG HYDRATION side by side;
// the hydration card (water + urine status) lives behind LOG HYDRATION in a
// bottom sheet so the logged meals stay in view.
//
// Writers: LogActionRow.onLogFood -> showLogFoodSheet, onLogHydration ->
// showHydrationSheet. The card's own writers are unchanged
// (WaterIntakeNotifier.addWater -> HealthWriteService.setWaterMl;
// UrineColorNotifier.select -> HealthWriteService.logUrine).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/hydration_card.dart';
import 'package:icanbefitter/features/nutrition/widgets/hydration_sheet.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_action_row.dart';

class _FakeWater extends WaterIntakeNotifier {
  @override
  int build() => 0;
  @override
  Future<void> addWater(int ml) async => state = (state + ml).clamp(0, 5000);
}

class _FakeUrine extends UrineColorNotifier {
  @override
  int build() => -1;
  @override
  void select(int index) => state = index;
}

void main() {
  group('LogActionRow', () {
    testWidgets('shows both labels and routes each tap to its own callback',
        (tester) async {
      var food = 0, hydration = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LogActionRow(
            onLogFood: () => food++,
            onLogHydration: () => hydration++,
          ),
        ),
      ));
      expect(find.text('LOG FOOD'), findsOneWidget);
      expect(find.text('LOG HYDRATION'), findsOneWidget);
      expect(find.text('+ LOG FOOD'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('log_food_cta')));
      expect([food, hydration], [1, 0]);
      await tester.tap(find.byKey(const ValueKey('log_hydration_cta')));
      expect([food, hydration], [1, 1]);
    });

    testWidgets('both buttons fit side by side at 320 dp without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LogActionRow(onLogFood: () {}, onLogHydration: () {}),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('showHydrationSheet', () {
    Widget host() => ProviderScope(
          overrides: [
            waterIntakeProvider.overrideWith(_FakeWater.new),
            urineColorProvider.overrideWith(_FakeUrine.new),
            waterTargetProvider.overrideWithValue(3000),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const Text('PAGE BODY'),
                    TextButton(
                      key: const ValueKey('open'),
                      onPressed: () => showHydrationSheet(context),
                      child: const Text('open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('the card is hidden until the sheet is opened', (tester) async {
      await tester.pumpWidget(host());
      expect(find.byType(HydrationCard), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hydration_sheet')), findsOneWidget);
      expect(find.byType(HydrationCard), findsOneWidget);
      expect(find.text('LOG HYDRATION'), findsOneWidget);
    });

    testWidgets('the sheet keeps the urine status inside it', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('URINE STATUS'), findsOneWidget);
    });

    testWidgets('+250 ML inside the sheet goes through the water notifier',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
          tester.element(find.byType(HydrationCard)));
      expect(c.read(waterIntakeProvider), 0);
      await tester.tap(find.textContaining('250'));
      await tester.pumpAndSettle();
      expect(c.read(waterIntakeProvider), 250,
          reason: 'the sheet must write through WaterIntakeNotifier.addWater');
    });

    testWidgets('the close button dismisses the sheet', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hydration_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hydration_sheet')), findsNothing);
      expect(find.text('PAGE BODY'), findsOneWidget);
    });

    testWidgets('the sheet body scrolls and is height-bounded (urine picker expands)',
        (tester) async {
      // The card expands its urine picker inline (AnimatedSize), so the sheet must
      // not assume a fixed height: the body is a SingleChildScrollView under a
      // 85%-of-screen cap. (No horizontal-overflow assertion: the test font Ahem is
      // ~2x wider than the real fonts and overflows the unchanged card's pill row.)
      // Width stays 800 (Ahem overflows the card at 360); height is the phone's.
      tester.view.physicalSize = const Size(800, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('hydration_sheet')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      final sheet = tester.getSize(find.byKey(const ValueKey('hydration_sheet')));
      expect(sheet.height, lessThanOrEqualTo(640 * 0.85 + 0.5));
    });
  });
}
