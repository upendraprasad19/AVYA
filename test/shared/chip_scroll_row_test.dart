// Diet plan observations batch (2026-11-15): the Diet Plan screen's chip
// groups take ONE horizontally scrolling row each; Edit Profile keeps its
// wrapped chips. The selected chip is brought into view, a mouse can drag the
// row, and a tap still reports the choice.
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/shared/widgets/chip_scroll_row.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_chips.dart';
import 'package:icanbefitter/shared/widgets/food_type_chips.dart';

Widget _host(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

/// A 360 dp wide phone (the MediaQuery override alone does not size the view).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _food(FoodType t) => find.byKey(ValueKey('food_type_chip_${t.storageKey}'));
Finder _strat(DietStrategy s) =>
    find.byKey(ValueKey('diet_strategy_chip_${s.storageKey}'));

void main() {
  testWidgets('default: the wrapped chips (Edit Profile), no scroll row',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(
        FoodTypeChips(value: FoodType.veg, onChanged: (_) {})));
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(ChipScrollRow), findsNothing);
    await tester.pumpWidget(_host(DietStrategyChips(
        value: DietStrategy.balanced, isPro: true, onChanged: (_) {})));
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(ChipScrollRow), findsNothing);
  });

  testWidgets('food type, scrollable: ONE line, and the selected chip at the '
      'far end is brought into view', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(FoodTypeChips(
        scrollable: true, value: FoodType.vegan, onChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byType(Wrap), findsNothing);
    final tops = {
      for (final t in FoodType.values) tester.getTopLeft(_food(t)).dy
    };
    expect(tops.length, 1, reason: 'all five chips on one line');
    // 360 dp wide, 16 dp padding: Vegan is the fifth chip and would sit past
    // the edge without the reveal.
    expect(tester.getTopRight(_food(FoodType.vegan)).dx, lessThanOrEqualTo(360));
    expect(tester.getTopLeft(_food(FoodType.veg)).dx, lessThan(16),
        reason: 'the row scrolled, the first chip is partly or fully out');
  });

  testWidgets('food type, scrollable: a selection at the start stays at the '
      'start', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(FoodTypeChips(
        scrollable: true, value: FoodType.veg, onChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_food(FoodType.veg)).dx, 16);
  });

  testWidgets('the reveal follows a change of the selection', (tester) async {
    _phone(tester);
    var value = FoodType.veg;
    late StateSetter set;
    await tester.pumpWidget(_host(StatefulBuilder(builder: (c, s) {
      set = s;
      return FoodTypeChips(
          scrollable: true, value: value, onChanged: (_) {});
    })));
    await tester.pumpAndSettle();
    set(() => value = FoodType.vegan);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(_food(FoodType.vegan)).dx, lessThanOrEqualTo(360));
  });

  testWidgets('a tap in the scrolling row reports the choice', (tester) async {
    _phone(tester);
    FoodType? picked;
    await tester.pumpWidget(_host(FoodTypeChips(
        scrollable: true, value: FoodType.veg, onChanged: (t) => picked = t)));
    await tester.pumpAndSettle();
    await tester.tap(_food(FoodType.nonVeg));
    expect(picked, FoodType.nonVeg);
  });

  testWidgets('a mouse can drag the row (web desktop)', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(FoodTypeChips(
        scrollable: true, value: FoodType.veg, onChanged: (_) {})));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(_food(FoodType.veg)).dx;
    final g = await tester.startGesture(tester.getCenter(_food(FoodType.nonVeg)),
        kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(-60, 0));
    await tester.pump();
    await g.moveBy(const Offset(-60, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_food(FoodType.veg)).dx, lessThan(before));
  });

  testWidgets('strategy, scrollable: one line, PRO badge and disabled Keto '
      'keep working', (tester) async {
    _phone(tester);
    final taps = <DietStrategy>[];
    await tester.pumpWidget(_host(DietStrategyChips(
      scrollable: true,
      value: DietStrategy.balanced,
      isPro: false,
      disabled: const {DietStrategy.keto},
      onChanged: taps.add,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(Wrap), findsNothing);
    final tops = {
      for (final s in DietStrategy.values) tester.getTopLeft(_strat(s)).dy
    };
    expect(tops.length, 1);
    expect(find.byKey(const ValueKey('diet_strategy_pro_badge_low_carb')),
        findsOneWidget);
    await tester.tap(_strat(DietStrategy.keto));
    await tester.tap(_strat(DietStrategy.lowCarb));
    expect(taps, [DietStrategy.lowCarb]);
  });

  testWidgets('strategy, scrollable: a selected chip is revealed too',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(DietStrategyChips(
      scrollable: true,
      value: DietStrategy.keto,
      isPro: true,
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(tester.getTopRight(_strat(DietStrategy.keto)).dx,
        lessThanOrEqualTo(360));
  });
}
