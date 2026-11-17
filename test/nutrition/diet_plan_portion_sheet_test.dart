// Diet chart v3 (2026-11-17), B-pass seats B and C: the portion sheet and the
// search sheet's room above the keyboard.
//   * a custom food whose serving is over 4000 g made the stepper throw
//     (`clamp` with the lower limit above the upper one) and started above the
//     2000 g cap;
//   * a food with no calorie number at all added a silent 0 kcal item;
//   * the sheet is a bare Column: at 360 x 640 with the keyboard up and a large
//     text scale it must scroll, not overflow.
//
// Mutations: put the old `m.clamp(rawLo, _maxM)` back (the 5000 g test
// throws); `_m = 1` unconditionally (the cap assertion reddens); make Add
// always enabled (the no-calories test reddens); take the SingleChildScrollView
// off (the 2.0 scale test reddens).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_food_search_sheet.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_portion_sheet.dart';

Map<String, dynamic> _row({
  num? stdG = 150,
  Object? kcal100 = 120,
  Object? kcalStd = 180,
  String desc = '1 bowl',
  String name = 'Test food',
}) =>
    {
      'id': 'x1',
      'name': name,
      'standard_serving_g': stdG,
      'standard_serving_desc': desc,
      'calories_per_100g': kcal100,
      'calories_std': kcalStd,
      'protein_per_100g': 5,
      'carbs_per_100g': 20,
      'fat_per_100g': 2,
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> row,
    {Size size = const Size(360, 640),
    double scale = 1.0,
    double keyboard = 0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height - keyboard),
              child: DietPlanPortionSheet(row: row, role: null),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a serving over 4000 g: the stepper does not throw and the '
      'amount never passes the 2000 g cap', (tester) async {
    await _pump(tester, _row(stdG: 5000, desc: '1 whole'));
    expect(tester.takeException(), isNull);
    final grams = tester.widget<TextField>(find.byKey(const ValueKey('diet_portion_grams')));
    expect(int.parse(grams.controller!.text), lessThanOrEqualTo(2000));
    await tester.tap(find.byKey(const ValueKey('diet_portion_plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diet_portion_minus')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(int.parse(grams.controller!.text), lessThanOrEqualTo(2000));
  });

  testWidgets('no calorie number at all: a note shows and Add is disabled',
      (tester) async {
    await _pump(tester, _row(kcal100: null, kcalStd: null));
    expect(find.byKey(const ValueKey('diet_portion_no_calories')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('diet_portion_add')))
            .onPressed,
        isNull);
  });

  testWidgets('a food with calories: no note, Add is enabled', (tester) async {
    await _pump(tester, _row());
    expect(find.byKey(const ValueKey('diet_portion_no_calories')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('diet_portion_add')))
            .onPressed,
        isNotNull);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('360 x 640 with the keyboard up, text scale $scale, a long '
        'name: no overflow (the sheet scrolls)', (tester) async {
      await _pump(tester,
          _row(name: 'A very long food name that wraps onto several lines '
              'of the sheet header for sure'),
          scale: scale, keyboard: 280);
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      // Add stays reachable by scrolling
      await tester.ensureVisible(find.byKey(const ValueKey('diet_portion_add')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('B-pass B5: the search sheet is never taller than the room the '
      'keyboard leaves', (tester) async {
    const size = Size(360, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open'),
            onPressed: () => showDietPlanFoodSearchSheet(context,
                role: null, search: (q) => const []),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DietPlanFoodSearchSheet)).height,
        lessThanOrEqualTo(size.height - 300 - 8 + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('B-pass delta 3: the notch is taken off the room, and a window '
      'smaller than the keyboard gives a zero height, not a negative one',
      (tester) async {
    const size = Size(360, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open'),
            onPressed: () => showDietPlanFoodSearchSheet(context,
                role: null, search: (q) => const []),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DietPlanFoodSearchSheet)).height,
        lessThanOrEqualTo(size.height - 300 - 47 - 8 + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('B-pass delta 4: an amount typed above ten servings stays put '
      'when + is pressed (no jump down to the cap)', (tester) async {
    await _pump(tester, _row(stdG: 5, desc: '1 pinch'));
    await tester.enterText(
        find.byKey(const ValueKey('diet_portion_grams')), '1500');
    await tester.pump();
    final grams = tester
        .widget<TextField>(find.byKey(const ValueKey('diet_portion_grams')))
        .controller!;
    await tester.tap(find.byKey(const ValueKey('diet_portion_plus')));
    await tester.pump();
    expect(int.parse(grams.text), greaterThanOrEqualTo(1500));
    await tester.tap(find.byKey(const ValueKey('diet_portion_minus')));
    await tester.pump();
    expect(int.parse(grams.text), lessThan(1500));
    expect(tester.takeException(), isNull);
  });
}
