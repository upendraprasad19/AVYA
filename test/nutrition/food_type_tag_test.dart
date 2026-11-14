// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md T7): the
// food-type tag on the Nutrition calorie card. Reads through the one
// normaliser (an empty profile shows the default NON-VEG; a legacy
// `vegetarian` shows VEG), announces itself as a tappable button, and the tap
// reaches the caller (the screen routes to the Diet Plan). PRESENCE pin
// (stated): the calorie card hosts it with the diet-plan route.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/features/nutrition/widgets/food_type_tag.dart';

Widget _host(Map<String, dynamic> profile, VoidCallback onTap) => MaterialApp(
      home: Scaffold(body: FoodTypeTag(profile: profile, onTap: onTap)),
    );

void main() {
  for (final (profile, label) in [
    (<String, dynamic>{'diet_preference': 'eggetarian'}, 'EGGETARIAN'),
    (<String, dynamic>{}, 'NON-VEG'),
    (<String, dynamic>{'diet_preference': 'vegetarian'}, 'VEG'),
    (<String, dynamic>{'diet_preference': 'keto'}, 'NON-VEG'),
  ]) {
    testWidgets('$profile shows $label', (tester) async {
      await tester.pumpWidget(_host(profile, () {}));
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('a button with a tap action; the tap reaches the caller',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_host({'diet_preference': 'vegan'}, () => taps++));
    final finder = find.byKey(const ValueKey('nutrition_food_type_tag'));
    expect(
        tester.getSemantics(finder),
        matchesSemantics(
            label: 'Food type Vegan. Open the diet plan',
            isButton: true,
            hasTapAction: true));
    await tester.tap(finder);
    expect(taps, 1);
    handle.dispose();
  });

  test('PRESENCE: the calorie card hosts the tag and routes to the diet plan',
      () {
    final src = File('lib/features/nutrition/screens/nutrition_screen.dart')
        .readAsStringSync();
    final card = src.substring(src.indexOf('Widget _buildCalorieCard('));
    expect(
        RegExp(r"FoodTypeTag\(\s*profile:\s*profile,\s*strategy:\s*nutrition\.strategy,\s*onTap:\s*\(\)\s*=>\s*context\.go\('/nutrition/diet-plan'\),")
            .hasMatch(card),
        isTrue,
        reason: 'diet plan Unit 3a (9b): the label takes the strategy carried '
            'WITH the card numbers (DailyNutritionData.strategy)');
  });

  // Diet plan Unit 3a (plan §4 test 9b): the strategy comes from the caller,
  // the same object as the numbers; the tag never reads `diet_strategy`.
  testWidgets('the strategy tag comes from the parameter, never the profile',
      (tester) async {
    await tester.pumpWidget(_host(
        {'diet_preference': 'non_veg', 'diet_strategy': 'keto'}, () {}));
    expect(find.text('NON-VEG'), findsOneWidget,
        reason: 'a stored keto with no carried strategy shows no tag');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FoodTypeTag(
          profile: const {'diet_preference': 'non_veg'},
          strategy: DietStrategy.keto,
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('NON-VEG \u00B7 KETO'), findsOneWidget);
  });
}
