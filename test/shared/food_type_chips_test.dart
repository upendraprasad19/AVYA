// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md T4):
// FoodTypeChips, the one selector used by Edit Profile and the Diet Plan
// screen. Five chips in the founder's words, no Keto, selected semantics,
// taps reported, taps ignored while disabled, every chip at least 44 dp tall
// at text scale 1.0 and 2.0 with no overflow, and the chips hug their labels
// (a chip stretched across the row would be the `alignment` mistake).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/shared/widgets/food_type_chips.dart';

Widget _host(Widget child, {double scale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

void main() {
  testWidgets('five chips, founder labels, no Keto; tap reports the type',
      (tester) async {
    FoodType? picked;
    await tester.pumpWidget(_host(FoodTypeChips(
        value: FoodType.nonVeg, onChanged: (t) => picked = t)));
    for (final label in ['Veg', 'Non-veg', 'Eggetarian', 'Pescatarian', 'Vegan']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Keto'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('food_type_chip_pescatarian')));
    expect(picked, FoodType.pescatarian);
  });

  testWidgets('selected semantics on exactly the current value', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        _host(FoodTypeChips(value: FoodType.vegan, onChanged: (_) {})));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('food_type_chip_vegan'))),
        matchesSemantics(
            label: 'Vegan', isButton: true, isSelected: true, hasSelectedState: true,
            isEnabled: true, hasEnabledState: true, hasTapAction: true));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('food_type_chip_veg'))),
        matchesSemantics(
            label: 'Veg', isButton: true, isSelected: false, hasSelectedState: true,
            isEnabled: true, hasEnabledState: true, hasTapAction: true));
    handle.dispose();
  });

  testWidgets('disabled: taps are ignored', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(FoodTypeChips(
        value: FoodType.veg, enabled: false, onChanged: (_) => taps++)));
    await tester.tap(find.byKey(const ValueKey('food_type_chip_vegan')));
    expect(taps, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('every chip >= 44 dp tall, hugs its label, no overflow at '
        'text scale $scale', (tester) async {
      await tester.pumpWidget(_host(
          FoodTypeChips(value: FoodType.veg, onChanged: (_) {}),
          scale: scale));
      expect(tester.takeException(), isNull);
      for (final t in FoodType.values) {
        final size =
            tester.getSize(find.byKey(ValueKey('food_type_chip_${t.storageKey}')));
        expect(size.height, greaterThanOrEqualTo(FoodTypeChips.minChipHeight),
            reason: '${t.label} at $scale');
        expect(size.width, lessThan(328), reason: '${t.label} stretched');
      }
    });
  }
}
