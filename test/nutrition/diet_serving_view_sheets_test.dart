// OI-517 (docs/plans/diet-grams-toggle.md section 3): the swap sheet, the
// portion sheet and the Search-any-food rows label a serving through ONE
// function. Portions is today's text; Grams adds the weight, ml for an audited
// liquid (the unit follows the food row, also in the portion sheet's Weight
// field). The font warm-up stays FIRST (the Hive group mocks path_provider).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_food_search.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_serving_label.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_food_search_sheet.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_portion_sheet.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_swap_sheet.dart';

import '../helpers/hive_test_setup.dart';

Map<String, dynamic> _row({
  String id = 'x1',
  String desc = '1 cup',
  num stdG = 158,
}) => {
  'id': id,
  'name': 'Test food',
  'standard_serving_g': stdG,
  'standard_serving_desc': desc,
  'calories_per_100g': 130,
  'calories_std': 205,
  'protein_per_100g': 3,
  'carbs_per_100g': 28,
  'fat_per_100g': 0.3,
};

DietPlanFoodItem _alt({String id = 'x1'}) => DietPlanFoodItem(
  foodId: id,
  name: 'Test food',
  servingDesc: '1 cup',
  servingG: 158,
  calories: 205,
  protein: 4,
  carbs: 44,
  fat: 1,
  category: 'staples',
);

Future<void> _pumpPortion(
  WidgetTester tester,
  Map<String, dynamic> row,
  DietServingView view,
) async {
  tester.view.physicalSize = const Size(360, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DietPlanPortionSheet(row: row, role: null, view: view),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openSwap(
  WidgetTester tester,
  DietServingView view, {
  String id = 'x1',
}) async {
  tester.view.physicalSize = const Size(360, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open'),
            onPressed: () => showDietPlanSwapSheet(
              context,
              itemName: 'Old food',
              alternatives: [_alt(id: id)],
              onPick: (_) {},
              onSearch: (_) async => null,
              view: view,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

Future<void> _pumpSearch(
  WidgetTester tester,
  DietServingView view, {
  String id = 'x1',
  String desc = '1 cup',
  num stdG = 158,
}) async {
  tester.view.physicalSize = const Size(360, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: DietPlanFoodSearchSheet(
            role: null,
            view: view,
            search: (q) => [
              DietPlanSearchHit(
                row: _row(id: id, desc: desc, stdG: stdG),
                processed: false,
                yours: false,
                powder: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.enterText(find.byType(TextField).first, 'te');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('typography warmup: GoogleFonts caches before any Hive mock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final w in [
                FontWeight.w400,
                FontWeight.w500,
                FontWeight.w700,
                FontWeight.w800,
              ])
                Text('b', style: AppTypography.body.copyWith(fontWeight: w)),
              Text('s', style: AppTypography.bodySm),
              Text(
                't',
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text('m', style: AppTypography.monoXs),
              Text('h', style: AppTypography.h3),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('b'), findsWidgets);
  });

  group('solid food (no Hive row needed)', () {
    testWidgets(
      'swap sheet: Portions is today\'s text, Grams adds the weight',
      (tester) async {
        await _openSwap(tester, DietServingView.portions);
        expect(find.text('1 cup · 205 kcal'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _openSwap(tester, DietServingView.grams);
        expect(find.text('158 g (1 cup) · 205 kcal'), findsOneWidget);
      },
    );

    testWidgets('portion sheet: the label follows the view; the unit is g', (
      tester,
    ) async {
      await _pumpPortion(tester, _row(), DietServingView.portions);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diet_portion_desc')))
            .data,
        '1 cup',
      );
      await _pumpPortion(tester, _row(), DietServingView.grams);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diet_portion_desc')))
            .data,
        '158 g (1 cup)',
      );
      expect(find.text('g'), findsWidgets);
    });

    testWidgets('search rows: Portions raw description, Grams label with the '
        'row\'s own grams', (tester) async {
      await _pumpSearch(tester, DietServingView.portions);
      expect(find.textContaining('1 cup · 205 kcal'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _pumpSearch(tester, DietServingView.grams);
      expect(find.textContaining('158 g (1 cup) · 205 kcal'), findsOneWidget);
    });
  });

  group('audited liquid (Hive food row with weight_unit ml)', () {
    late Directory dir;
    setUp(() async {
      dir = await setUpHiveForTests();
      await HiveService.instance.foodBox.put('F0031', {
        'id': 'F0031',
        'name': 'Milk',
        'weight_unit': 'ml',
      });
    });
    tearDown(() async => tearDownHiveForTests(dir));

    testWidgets('swap sheet and portion sheet read ml in Grams view', (
      tester,
    ) async {
      await _openSwap(tester, DietServingView.grams, id: 'F0031');
      expect(find.text('158 ml (1 cup) · 205 kcal'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _pumpPortion(
        tester,
        _row(id: 'F0031', desc: '1 glass', stdG: 250),
        DietServingView.grams,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diet_portion_desc')))
            .data,
        '250 ml (1 glass)',
      );
      expect(find.text('ml'), findsOneWidget);
      // Portions leaves the liquid exactly as before, grams box included.
      await _pumpPortion(
        tester,
        _row(id: 'F0031', desc: '1 glass', stdG: 250),
        DietServingView.portions,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diet_portion_desc')))
            .data,
        '1 glass',
      );
      expect(find.text('ml'), findsNothing);
    });
  });
}
