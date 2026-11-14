// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md §2.1, T1): the
// food-type normaliser against the shared fixture that the server mirror
// (Unit 2b) reads too, so the two cannot drift.
//
// Mutations: map an unknown string to nonVeg (the xyz/flexitarian/paleo rows
// redden); map `vegetarian` to nonVeg; drop the `-`/space folding.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/food_types.dart';

void main() {
  final fixture = jsonDecode(File(
          'supabase/functions/_shared/testdata/food_type_vocabulary.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final rows = (fixture['rows'] as List).cast<Map<String, dynamic>>();

  test('fixture is non-trivial and covers every food type', () {
    expect(rows.length, greaterThanOrEqualTo(30));
    expect({for (final r in rows) r['expected']},
        {for (final t in FoodType.values) t.storageKey});
  });

  for (final r in rows) {
    test('foodTypeOf(${jsonEncode(r['input'])}) == ${r['expected']}', () {
      expect(foodTypeOf(r['input']).storageKey, r['expected']);
    });
  }

  test('null is the default; a non-null non-string (corrupt) value is Veg', () {
    expect(foodTypeOf(null), kDefaultFoodType);
    expect(foodTypeOf(42), FoodType.veg);
    expect(foodTypeOf(true), FoodType.veg);
    expect(foodTypeOf(const ['non_veg']), FoodType.veg);
    expect(foodTypeOfProfile(const {'diet_preference': 7}), FoodType.veg);
  });

  test('every storageKey round-trips; labels are the founder wording', () {
    for (final t in FoodType.values) {
      expect(foodTypeOf(t.storageKey), t);
      expect(t.shortLabel, t.label.toUpperCase());
    }
    expect([for (final t in FoodType.values) t.label],
        ['Veg', 'Non-veg', 'Eggetarian', 'Pescatarian', 'Vegan']);
    expect(kDefaultFoodType, FoodType.nonVeg);
  });

  test('foodTypeOfProfile reads diet_preference; null profile = default', () {
    expect(foodTypeOfProfile({'diet_preference': 'vegetarian'}), FoodType.veg);
    expect(foodTypeOfProfile(const {}), FoodType.nonVeg);
    expect(foodTypeOfProfile(null), FoodType.nonVeg);
  });
}
