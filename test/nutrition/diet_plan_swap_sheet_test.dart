// Diet chart v3 (2026-11-17): the swap sheet closes ITSELF before it hands a
// pick over, on BOTH doors (an alternative tap and a "Search any food" pick).
// The pick handler here opens a dialog SYNCHRONOUSLY, like the strategy popup
// a pick can open: were the pop to run after the handler, `Navigator.pop`
// would close that dialog instead of the sheet.
//
// Mutations: swap the two lines of either door (onPick before pop): the
// dialog is gone / the sheet stays -> red.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_swap_sheet.dart';

DietPlanFoodItem _item(String id, String name) => DietPlanFoodItem(
      foodId: id,
      name: name,
      servingDesc: '1 bowl',
      servingG: 100,
      calories: 100,
      protein: 5,
      carbs: 10,
      fat: 2,
      category: 'grain',
    );

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open'),
            onPressed: () => showDietPlanSwapSheet(
              context,
              itemName: 'Poha',
              alternatives: [_item('A1', 'Upma')],
              onPick: (_) => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                    key: ValueKey('pick_dialog'), title: Text('Popup')),
              ),
              onSearch: (_) async => _item('S1', 'Searched food'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diet_swap_search_row')), findsOneWidget);
  }

  testWidgets('an alternative tap: the sheet closes, the pick dialog stays',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Upma'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('diet_swap_search_row')), findsNothing);
  });

  testWidgets('a search pick: the sheet closes, the pick dialog stays',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('diet_swap_search_row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick_dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('diet_swap_search_row')), findsNothing);
  });
}
