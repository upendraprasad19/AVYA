// test/nutrition/diet_plan_generator_test.dart
//
// Four-archetype validation that the anchor-protein-per-meal algorithm
// hits >= 95% of the daily protein target across realistic user shapes.
// Each archetype also asserts that every slot has an anchor protein from
// the appropriate set and that diet_preference is honored.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

/// Fake FoodRepository that returns a hand-curated subset of the bundled
/// food_database.json so tests don't need Hive.
class _FakeFoodRepo implements FoodRepository {
  final List<Map<String, dynamic>> _foods;
  _FakeFoodRepo(this._foods);

  @override
  List<Map<String, dynamic>> getAll() => _foods;

  @override
  List<Map<String, dynamic>> getByCategory(String category) => _foods
      .where((f) =>
          (f['category'] as String?)?.toLowerCase() == category.toLowerCase())
      .toList();

  @override
  Map<String, dynamic>? getById(String id) =>
      _foods.firstWhere((f) => f['id'] == id, orElse: () => <String, dynamic>{});

  @override
  List<String> getCategories() =>
      _foods.map((f) => f['category'] as String).toSet().toList();

  @override
  List<Map<String, dynamic>> search(String query, {int limit = 50}) =>
      _foods.where((f) => (f['name'] as String).contains(query)).take(limit).toList();

  @override
  List<Map<String, dynamic>> getIndianFoods({int limit = 50}) =>
      _foods.where((f) => f['is_indian'] == true).take(limit).toList();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Builds a small but realistic food universe. Mirrors actual rows from
/// assets/data/food_database.json (verified 2026-04-26).
List<Map<String, dynamic>> _seedFoods() => [
      // staples
      _f('F0001', 'White Rice (cooked)', 'staples', 130, 2.7, 28, 0.3, 158, '1 cup'),
      _f('F0002', 'Brown Rice (cooked)', 'staples', 112, 2.6, 24, 0.9, 195, '1 cup'),
      _f('F0003', 'Roti (Whole Wheat)', 'staples', 297, 9.8, 59, 3.7, 40, '1 roti'),
      _f('F0007', 'Poha (Flattened Rice)', 'staples', 130, 2.6, 27, 1.5, 180, '1 plate'),
      // pulses
      _f('F0011', 'Toor Dal (cooked)', 'pulses', 116, 7.5, 20, 0.4, 200, '1 bowl'),
      _f('F0014', 'Rajma (cooked)', 'pulses', 127, 8.7, 23, 0.5, 200, '1 bowl'),
      _f('F0016', 'Masoor Dal (cooked)', 'pulses', 116, 9.0, 20, 0.4, 200, '1 bowl'),
      _f('F0017', 'Sprouts (Mixed)', 'pulses', 70, 7.0, 12, 0.5, 100, '1 cup'),
      _f('F0018', 'Soybean (boiled)', 'pulses', 173, 17.0, 10, 9.0, 100, '1 cup'),
      // protein (non-veg + paneer + tofu)
      _f('F0021', 'Chicken Breast (grilled)', 'protein', 165, 31.0, 0, 3.6, 100, '100g', isVeg: false),
      _f('F0023', 'Egg (Whole, boiled)', 'protein', 130, 13.0, 1.1, 8.7, 50, '1 egg', isVeg: true),
      _f('F0025', 'Paneer', 'protein', 265, 18.0, 1.2, 21.0, 100, '100g', isVeg: true),
      _f('F0026', 'Fish Curry', 'protein', 160, 16.0, 6, 8, 200, '1 bowl', isVeg: false),
      _f('F0027', 'Mutton Curry', 'protein', 235, 18.0, 4, 17, 200, '1 bowl', isVeg: false),
      _f('F0028', 'Tandoori Chicken', 'protein', 175, 25.0, 1, 7, 120, '1 leg piece', isVeg: false),
      _f('F0029', 'Tofu', 'protein', 76, 8.0, 1.9, 4.8, 100, '100g', isVeg: true, isVegan: true),
      // supplements
      _f('F0031', 'Whey Protein (scoop)', 'supplements', 380, 75.0, 8, 4, 32, '1 scoop', isVeg: true),
      // dairy
      _f('F0032', 'Curd (Dahi)', 'dairy', 60, 3.5, 4.7, 3.3, 200, '1 cup', isVeg: true),
      _f('F0033', 'Greek Yogurt', 'dairy', 85, 9.0, 5, 4, 170, '1 cup', isVeg: true),
      _f('F0034', 'Milk (Toned)', 'dairy', 56, 3.1, 4.7, 3.0, 250, '1 glass', isVeg: true),
      // nuts_seeds
      _f('F0050', 'Almonds', 'nuts_seeds', 580, 21.0, 22, 50, 14, '10 almonds', isVeg: true, isVegan: true),
      _f('F0051', 'Peanuts (Roasted)', 'nuts_seeds', 580, 26.0, 16, 49, 30, '1 handful', isVeg: true, isVegan: true),
      _f('F0056', 'Peanut Butter', 'nuts_seeds', 590, 25.0, 20, 50, 16, '1 tbsp', isVeg: true, isVegan: true),
      // beverages
      _f('F0046', 'Protein Shake (Whey + Milk)', 'beverages', 100, 30.0, 7, 2, 300, '1 glass', isVeg: true),
      // fruits
      _f('F0040', 'Banana', 'fruits', 89, 1.1, 23, 0.3, 118, '1 medium', isVeg: true, isVegan: true),
      _f('F0041', 'Apple', 'fruits', 52, 0.3, 14, 0.2, 180, '1 medium', isVeg: true, isVegan: true),
      // vegetables
      _f('F0061', 'Mixed Sabzi', 'vegetables', 80, 3.0, 10, 4, 150, '1 bowl', isVeg: true, isVegan: true),
    ];

Map<String, dynamic> _f(String id, String name, String cat, num cal, num prot,
    num carb, num fat, num servingG, String servingDesc,
    {bool isVeg = true, bool isVegan = false}) {
  final factor = servingG / 100.0;
  return {
    'id': id,
    'name': name,
    'category': cat,
    'calories_per_100g': cal,
    'protein_per_100g': prot,
    'carbs_per_100g': carb,
    'fat_per_100g': fat,
    'standard_serving_g': servingG,
    'standard_serving_desc': servingDesc,
    'calories_std': (cal * factor).toDouble(),
    'protein_std': (prot * factor).toDouble(),
    'carbs_std': (carb * factor).toDouble(),
    'fat_std': (fat * factor).toDouble(),
    'is_indian': true,
    'is_veg': isVeg,
    'is_vegan': isVegan,
  };
}

const _breakfastAnchors = {
  'Egg (Whole, boiled)',
  'Whey Protein (scoop)',
  'Greek Yogurt',
  'Paneer',
  'Sprouts (Mixed)',
  'Tofu',
  'Protein Shake (Whey + Milk)',
};
const _mainAnchors = {
  'Chicken Breast (grilled)',
  'Mutton Curry',
  'Fish Curry',
  'Tandoori Chicken',
  'Paneer',
  'Toor Dal (cooked)',
  'Rajma (cooked)',
  'Masoor Dal (cooked)',
  'Soybean (boiled)',
  'Tofu',
};
const _snackAnchors = {
  'Whey Protein (scoop)',
  'Almonds',
  'Peanuts (Roasted)',
  'Peanut Butter',
  'Sprouts (Mixed)',
  'Greek Yogurt',
  'Protein Shake (Whey + Milk)',
};

void main() {
  final repo = _FakeFoodRepo(_seedFoods());
  final gen = DietPlanGenerator.forTest(repo);

  void runArchetype({
    required String label,
    required int calories,
    required int protein,
    required String diet,
  }) {
    test('$label: protein hits >=95% of target with anchor in every meal', () {
      final plan = gen.generate(DietPlanInputs(
        calorieTarget: calories,
        proteinTarget: protein,
        dietPreference: diet,
        seed: 42,
      ));

      // (a) total protein in [95%, 115%] of target
      final totalProtein = plan.fold<int>(0, (s, m) => s + m.totalProtein);
      expect(
        totalProtein,
        greaterThanOrEqualTo((protein * 0.95).floor()),
        reason: '$label: protein deficit guard — total protein ${totalProtein}g '
            'must hit >= 95% of ${protein}g target',
      );
      expect(
        totalProtein,
        lessThanOrEqualTo((protein * 1.15).round()),
        reason: '$label: protein surplus guard (Option D Pass 4 trim) — '
            'total protein ${totalProtein}g must stay <= 115% of '
            '${protein}g target',
      );

      // (b) every NON-snack slot has at least one anchor item; snack is optional
      for (final meal in plan) {
        final isSnack = meal.slotKey == 'mid_morning' || meal.slotKey == 'evening';
        final anchors = isSnack
            ? _snackAnchors
            : (meal.slotKey == 'breakfast' ? _breakfastAnchors : _mainAnchors);
        final hasAnchor =
            meal.items.any((i) => anchors.contains(i.name) && i.isAnchor);
        if (!isSnack) {
          expect(hasAnchor, isTrue,
              reason:
                  '$label / ${meal.slotKey}: must contain an anchor protein '
                  'from $anchors. Got: ${meal.items.map((i) => i.name).toList()}');
        }
      }

      // (c) diet_preference honored — no non-veg in veg/vegan plans
      if (diet == 'veg' || diet == 'vegan') {
        for (final meal in plan) {
          for (final item in meal.items) {
            expect(
              {'Chicken Breast (grilled)', 'Mutton Curry', 'Fish Curry',
                  'Tandoori Chicken'}.contains(item.name),
              isFalse,
              reason: '$label ($diet): non-veg item ${item.name} leaked into '
                  '${meal.slotKey}',
            );
          }
        }
      }
      if (diet == 'vegan') {
        for (final meal in plan) {
          for (final item in meal.items) {
            expect(
              {'Egg (Whole, boiled)', 'Paneer', 'Greek Yogurt', 'Curd (Dahi)',
                  'Milk (Toned)', 'Whey Protein (scoop)',
                  'Protein Shake (Whey + Milk)'}.contains(item.name),
              isFalse,
              reason:
                  '$label (vegan): dairy/egg item ${item.name} leaked into '
                  '${meal.slotKey}',
            );
          }
        }
      }
    });
  }

  runArchetype(
    label: 'low-cal cut (1500 / 130 / vegetarian)',
    calories: 1500,
    protein: 130,
    diet: 'veg',
  );
  runArchetype(
    label: 'balanced maintain (2400 / 130 / non-veg)',
    calories: 2400,
    protein: 130,
    diet: 'non-veg',
  );
  runArchetype(
    label: 'surplus build (3000 / 200 / non-veg)',
    calories: 3000,
    protein: 200,
    diet: 'non-veg',
  );
  runArchetype(
    label: 'vegan high-protein (2200 / 150 / vegan)',
    calories: 2200,
    protein: 150,
    diet: 'vegan',
  );
}
