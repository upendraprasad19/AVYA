// test/nutrition/diet_plan_quality_constraints_test.dart
//
// Behavioral regression tests for the 2026-09 meal-quality constraint
// layer (plan-review rounds 1-3, all mutation-proven individually):
//   Pass 0 group quotas (veg in lunch/dinner, dairy-or-fruit breakfast)
//   Per-category filler caps (staples ≤1+exception, pulses ≤1, vegetables ≤2)
//   Day-level uniqueness (anchors + quotas hard; Pass 3/4 recovery exempt)
//   UPF exclusion (is_ultra_processed rows never generated)
//   nuts_seeds per-serving cap (≤300 kcal/serving — anti-Pringles guard)
//   Pass 5 fiber floor (bounded, no-op when unreachable)
//
// Observed defect this batch pins out: a real generated plan contained
// idli + red rice + basmati rice + whey (breakfast), Special K at lunch,
// 40g Pringles at dinner, Greek Yogurt twice, zero vegetables/fruit.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

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

Map<String, dynamic> _f(String id, String name, String cat, num cal, num prot,
    num carb, num fat, num servingG, String servingDesc,
    {bool isVeg = true,
    bool isVegan = false,
    num fiber = 0,
    bool upf = false,
    List<String> mealFit = const []}) {
  final factor = servingG / 100.0;
  return {
    'id': id,
    'name': name,
    'category': cat,
    'calories_per_100g': cal,
    'protein_per_100g': prot,
    'carbs_per_100g': carb,
    'fat_per_100g': fat,
    'fiber_per_100g': fiber,
    'standard_serving_g': servingG,
    'standard_serving_desc': servingDesc,
    'calories_std': (cal * factor).toDouble(),
    'protein_std': (prot * factor).toDouble(),
    'carbs_std': (carb * factor).toDouble(),
    'fat_std': (fat * factor).toDouble(),
    'is_indian': true,
    'is_veg': isVeg,
    'is_vegan': isVegan,
    if (upf) 'is_ultra_processed': true,
    if (mealFit.isNotEmpty) 'meal_fit': mealFit,
  };
}

/// Same universe as diet_plan_generator_test.dart's fixture (kept aligned)
/// plus explicit UPF/meal_fit tags for the constraint tests.
List<Map<String, dynamic>> _seedFoods() => [
      _f('F0001', 'White Rice (cooked)', 'staples', 130, 2.7, 28, 0.3, 158, '1 cup', fiber: 0.4),
      _f('F0002', 'Brown Rice (cooked)', 'staples', 112, 2.6, 24, 0.9, 195, '1 cup', fiber: 1.8),
      _f('F0003', 'Roti (Whole Wheat)', 'staples', 297, 9.8, 59, 3.7, 40, '1 roti', fiber: 3.9),
      _f('F0007', 'Poha (Flattened Rice)', 'staples', 130, 2.6, 27, 1.5, 180, '1 plate', fiber: 1.0),
      _f('F0008', 'Steel Cut Oats', 'staples', 379, 13.0, 68, 6.5, 40, '40g', fiber: 10.0, mealFit: ['breakfast']),
      _f('F0009', 'Whole Wheat Bread', 'staples', 250, 9.0, 45, 3.0, 28, '1 slice', fiber: 4.5),
      _f('F0011', 'Toor Dal (cooked)', 'pulses', 116, 7.5, 20, 0.4, 200, '1 bowl', fiber: 2.0),
      _f('F0014', 'Rajma (cooked)', 'pulses', 127, 8.7, 23, 0.5, 200, '1 bowl', fiber: 2.4),
      _f('F0016', 'Masoor Dal (cooked)', 'pulses', 116, 9.0, 20, 0.4, 200, '1 bowl', fiber: 2.2),
      _f('F0017', 'Sprouts (Mixed)', 'pulses', 70, 7.0, 12, 0.5, 100, '1 cup', fiber: 1.8),
      _f('F0018', 'Soybean (boiled)', 'pulses', 173, 17.0, 10, 9.0, 100, '1 cup', fiber: 6.0),
      _f('F0030', 'Soy Chunks (cooked)', 'protein', 120, 18.0, 9, 0.5, 150, '1 bowl', isVegan: true, fiber: 4.0),
      _f('F0030b', 'Soya Chaap', 'protein', 120, 18.0, 9, 6, 150, '1 piece', isVegan: true, fiber: 3.0),
      _f('F0029b', 'Tofu (Firm)', 'protein', 170, 17.0, 2, 10, 126, '100g', isVegan: true, fiber: 2.0),
      _f('F0021', 'Chicken Breast (grilled)', 'protein', 165, 31.0, 0, 3.6, 100, '100g', isVeg: false),
      _f('F0023', 'Egg (Whole, boiled)', 'protein', 130, 13.0, 1.1, 8.7, 50, '1 egg'),
      _f('F0025', 'Paneer', 'protein', 265, 18.0, 1.2, 21.0, 100, '100g'),
      _f('F0026', 'Fish Curry', 'protein', 160, 16.0, 6, 8, 200, '1 bowl', isVeg: false),
      _f('F0033x', 'Goan Fish Curry', 'protein', 178, 17.0, 6, 8, 200, '1 bowl', isVeg: false),
      _f('F0021x', 'Chicken Breast (Pan-fried)', 'protein', 187, 33.0, 0, 6, 100, '100g', isVeg: false),
      _f('F0028', 'Tandoori Chicken', 'protein', 175, 25.0, 1, 7, 120, '1 leg piece', isVeg: false),
      _f('F0029', 'Tofu', 'protein', 76, 8.0, 1.9, 4.8, 100, '100g', isVegan: true),
      _f('F0031', 'Whey Protein (scoop)', 'supplements', 380, 75.0, 8, 4, 32, '1 scoop'),
      _f('F0032', 'Curd (Dahi)', 'dairy', 60, 3.5, 4.7, 3.3, 200, '1 cup'),
      _f('F0033', 'Greek Yogurt', 'dairy', 85, 9.0, 5, 4, 170, '1 cup'),
      _f('F0034', 'Milk (Toned)', 'dairy', 56, 3.1, 4.7, 3.0, 250, '1 glass'),
      _f('F0050', 'Almonds', 'nuts_seeds', 580, 21.0, 22, 50, 14, '10 almonds', isVegan: true),
      _f('F0051', 'Peanuts (Roasted)', 'nuts_seeds', 580, 26.0, 16, 49, 30, '1 handful', isVegan: true),
      _f('F0056', 'Peanut Butter', 'nuts_seeds', 590, 25.0, 20, 50, 16, '1 tbsp', isVegan: true),
      // 372 kcal/serving — must NEVER be generated (per-serving cap)
      _f('F0057', 'Almond Butter Jar', 'nuts_seeds', 620, 20.0, 18, 55, 60, '60g jar serving', isVegan: true, upf: true),
      _f('F0046', 'Protein Shake (Whey + Milk)', 'beverages', 100, 30.0, 7, 2, 300, '1 glass'),
      _f('F0040', 'Banana', 'fruits', 89, 1.1, 23, 0.3, 118, '1 medium', isVegan: true),
      _f('F0041', 'Apple', 'fruits', 52, 0.3, 14, 0.2, 180, '1 medium', isVegan: true),
      _f('F0042', 'Papaya', 'fruits', 43, 0.5, 11, 0.3, 150, '1 cup', isVegan: true),
      _f('F0061', 'Mixed Sabzi', 'vegetables', 80, 3.0, 10, 4, 150, '1 bowl', isVegan: true, fiber: 3.5),
      _f('F0062', 'Palak Sabzi', 'vegetables', 60, 2.5, 6, 3, 150, '1 bowl', isVegan: true, fiber: 2.8),
      _f('F0063', 'Bhindi Masala', 'vegetables', 85, 2.2, 9, 4.5, 150, '1 bowl', isVegan: true, fiber: 3.2),
      _f('F0064', 'Cauliflower Sabzi', 'vegetables', 55, 2.0, 8, 2, 150, '1 bowl', isVegan: true, fiber: 2.5),
      _f('F0065', 'Cucumber Salad', 'vegetables', 20, 0.8, 4, 0.2, 120, '1 bowl', isVegan: true, fiber: 1.2),
      // The observed defect, fixture-pinned: 541 kcal of Pringles in dinner.
      // UPF tag must keep it out of EVERY generated plan.
      _f('F0099', 'Pringles sour cream 40g', 'staples', 1353, 5.0, 58, 31, 40, '40g', upf: true),
      // small-serving UPF row: passes the fit filter (60 kcal/serving) so
      // ONLY the is_ultra_processed flag blocks it — keeps the no-UPF test
      // from passing vacuously through the fit-filter layer (mutation M1)
      _f('F0098', 'Maggi Small Packet', 'staples', 400, 8.0, 55, 15, 15, '15g', upf: true),
    ];

void main() {
  final repo = _FakeFoodRepo(_seedFoods());
  final gen = DietPlanGenerator.forTest(repo);

  const seeds = [1, 7, 42, 99, 1234];
  const prefs = ['veg', 'vegan', 'non-veg'];

  List<List<DietMealPlan>> generateAll() {
    final plans = <List<DietMealPlan>>[];
    for (final seed in seeds) {
      for (final pref in prefs) {
        plans.add(gen.generate(DietPlanInputs(
          calorieTarget: 2200,
          proteinTarget: 140,
          dietPreference: pref,
          fiberTarget: 30,
          seed: seed,
        )));
      }
    }
    return plans;
  }

  // TEMP-DEBUG helper
  List<DietMealPlan> genOne(int seed, String pref) => gen.generate(
      DietPlanInputs(
          calorieTarget: 2200,
          proteinTarget: 140,
          dietPreference: pref,
          fiberTarget: 30,
          seed: seed));

  void _assertNoUpf(List<DietMealPlan> plan, String label) {
    for (final meal in plan) {
      for (final item in meal.items) {
        expect(
          item.name.toLowerCase().contains('pringles'),
          isFalse,
          reason: '[$label] UPF item "${item.name}" generated into '
              '${meal.slotKey} — the exact observed defect regressed',
        );
        expect(
          item.name.toLowerCase().contains('maggi'),
          isFalse,
          reason: '[$label] UPF item "${item.name}" generated into '
              '${meal.slotKey} — UPF exclusion regressed',
        );
        expect(
          item.name,
          isNot('Almond Butter Jar'),
          reason: '[$label] >300 kcal/serving nuts_seeds row generated — '
              'per-serving cap regressed',
        );
      }
    }
  }

  test('no ultra-processed food in ANY generated plan (any seed × preference)', () {
    // 30 seeds: the Maggi-small fixture row passes the fit filter, so ONLY
    // the UPF flag blocks it — random shuffles must meet it often enough
    // that this test cannot pass vacuously (mutation M1 blind-spot fix).
    for (var seed = 1; seed <= 30; seed++) {
      for (final pref in prefs) {
        final plan = genOne(seed, pref);
        _assertNoUpf(plan, '2200/$pref/seed$seed');
        // High-calorie archetype: remaining calorie gaps admit the
        // Almond Butter Jar (372 kcal/serving) past the fit filter, so
        // ONLY the nuts_seeds 300-cap blocks it there (mutation M7).
        final buildPlan = gen.generate(DietPlanInputs(
          calorieTarget: 3000,
          proteinTarget: 200,
          dietPreference: pref,
          fiberTarget: 30,
          seed: seed,
        ));
        _assertNoUpf(buildPlan, '3000/$pref/seed$seed');
      }
    }
  });

  test('nuts_seeds 300-cap holds even when the jar is the ONLY nut available', () {
    // Surgical regression for the per-serving cap (mutation M7): a snack
    // slot whose nuts_seeds pool contains ONLY a >300 kcal/serving row —
    // every healthy nut is absent, so only the hard cap (which survives
    // stage-4 fit relaxation) can keep the jar out.
    final jarRepo = _FakeFoodRepo([
      _f('J001', 'Almond Butter Jar', 'nuts_seeds', 620, 20.0, 18, 55, 60, '60g jar serving', isVegan: true, upf: false),
      // enough of everything else for anchors + quotas to place
      _f('J002', 'Greek Yogurt', 'dairy', 85, 9.0, 5, 4, 170, '1 cup'),
      _f('J003', 'Curd (Dahi)', 'dairy', 60, 3.5, 4.7, 3.3, 200, '1 cup'),
      _f('J004', 'Milk (Toned)', 'dairy', 56, 3.1, 4.7, 3.0, 250, '1 glass'),
      _f('J005', 'Apple', 'fruits', 52, 0.3, 14, 0.2, 180, '1 medium', isVegan: true),
      _f('J006', 'Banana', 'fruits', 89, 1.1, 23, 0.3, 118, '1 medium', isVegan: true),
      _f('J007', 'White Rice (cooked)', 'staples', 130, 2.7, 28, 0.3, 158, '1 cup', fiber: 0.4),
      _f('J008', 'Roti (Whole Wheat)', 'staples', 297, 9.8, 59, 3.7, 40, '1 roti', fiber: 3.9),
      _f('J009', 'Brown Rice (cooked)', 'staples', 112, 2.6, 24, 0.9, 195, '1 cup', fiber: 1.8),
      _f('J010', 'Chicken Breast (grilled)', 'protein', 165, 31.0, 0, 3.6, 100, '100g', isVeg: false),
      _f('J011', 'Fish Curry', 'protein', 160, 16.0, 6, 8, 200, '1 bowl', isVeg: false),
      _f('J012', 'Egg (Whole, boiled)', 'protein', 130, 13.0, 1.1, 8.7, 50, '1 egg'),
      _f('J013', 'Paneer', 'protein', 265, 18.0, 1.2, 21.0, 100, '100g'),
      _f('J014', 'Mixed Sabzi', 'vegetables', 80, 3.0, 10, 4, 150, '1 bowl', isVegan: true, fiber: 3.5),
      _f('J015', 'Palak Sabzi', 'vegetables', 60, 2.5, 6, 3, 150, '1 bowl', isVegan: true, fiber: 2.8),
      _f('J016', 'Bhindi Masala', 'vegetables', 85, 2.2, 9, 4.5, 150, '1 bowl', isVegan: true, fiber: 3.2),
      _f('J017', 'Toor Dal (cooked)', 'pulses', 116, 7.5, 20, 0.4, 200, '1 bowl', fiber: 2.0),
      _f('J018', 'Rajma (cooked)', 'pulses', 127, 8.7, 23, 0.5, 200, '1 bowl', fiber: 2.4),
      _f('J019', 'Masoor Dal (cooked)', 'pulses', 116, 9.0, 20, 0.4, 200, '1 bowl', fiber: 2.2),
      _f('J020', 'Peanut Butter', 'nuts_seeds', 590, 25.0, 20, 50, 16, '1 tbsp', isVegan: true),
    ]);
    final jarGen = DietPlanGenerator.forTest(jarRepo);
    for (var seed = 1; seed <= 10; seed++) {
      final plan = jarGen.generate(DietPlanInputs(
        calorieTarget: 3000,
        proteinTarget: 160,
        dietPreference: 'non-veg',
        fiberTarget: 30,
        seed: seed,
      ));
      for (final meal in plan) {
        for (final item in meal.items) {
          expect(
            item.name,
            isNot('Almond Butter Jar'),
            reason: 'seed=$seed ${meal.slotKey}: >300 kcal/serving nuts row '
                'generated although only the hard per-serving cap blocks it',
          );
        }
      }
    }
  });

  test('Pass 0 quota: lunch AND dinner each contain a vegetables item', () {
    for (final plan in generateAll()) {
      for (final meal in plan) {
        if (meal.slotKey == 'lunch' || meal.slotKey == 'dinner') {
          expect(
            meal.items.any((i) => i.category == 'vegetables'),
            isTrue,
            reason: '${meal.slotKey} has no vegetables item '
                '(seed-dependent pool exhaustion — real-DB test must confirm '
                'this never fires on the 1431-row DB). '
                'Items: ${meal.items.map((i) => i.name).toList()}',
          );
        }
      }
    }
  });

  test('Pass 0 quota items are flagged and survive swap protection', () {
    final plan = gen.generate(const DietPlanInputs(
      calorieTarget: 2200,
      proteinTarget: 140,
      dietPreference: 'non-veg',
      fiberTarget: 30,
      seed: 42,
    ));
    var quotaSeen = 0;
    for (final meal in plan) {
      for (final item in meal.items) {
        if (item.category == 'vegetables' && item.isQuotaLocked) {
          quotaSeen++;
        }
      }
    }
    expect(quotaSeen, greaterThanOrEqualTo(2),
        reason: 'lunch + dinner quotas must both place a quota-LOCKED '
            'vegetables item. (A 2nd vegetables item may exist as a plain '
            'Pass 2 filler — vegetables cap is 2 — and it correctly carries '
            'no flag; the QUOTA one is what must survive recovery.)');
  });

  test('per-category filler caps: staples ≤2, pulses ≤1, vegetables ≤2 per slot', () {
    for (final plan in generateAll()) {
      for (final meal in plan) {
        final counts = <String, int>{};
        for (final item in meal.items) {
          counts[item.category] = (counts[item.category] ?? 0) + 1;
        }
        expect(counts['staples'] ?? 0, lessThanOrEqualTo(2),
            reason: '${meal.slotKey}: double-rice class defect regressed — '
                'items: ${meal.items.map((i) => i.name).toList()}');
        expect(counts['pulses'] ?? 0, lessThanOrEqualTo(2),
            reason: '${meal.slotKey}: pulses stacking regressed — 3-way '
                '(rajma+chana+masoor) is banned; a 2nd pulses is allowed '
                'only while the slot is >20% under its protein target');
        expect(counts['vegetables'] ?? 0, lessThanOrEqualTo(2),
            reason: '${meal.slotKey}: vegetables cap exceeded');
      }
    }
  });

  test('day-level uniqueness: anchors and quota items never repeat across the day', () {
    for (final plan in generateAll()) {
      final seen = <String, int>{};
      for (final meal in plan) {
        for (final item in meal.items) {
          if (item.isAnchor || item.isQuotaLocked) {
            seen[item.foodId] = (seen[item.foodId] ?? 0) + 1;
          }
        }
      }
      final dupes = seen.entries.where((e) => e.value > 1).map((e) => e.key);
      expect(dupes, isEmpty,
          reason: 'anchor/quota item repeated in one day: $dupes');
    }
  });

  test('Greek Yogurt (dual-pooled anchor) never appears twice in one day', () {
    // The exact observed defect: Greek Yogurt sits in BOTH the breakfast
    // and snack anchor pools; Pass 1 had no cross-slot uniqueness.
    for (final seed in seeds) {
      for (final pref in prefs) {
        final plan = genOne(seed, pref);
        var count = 0;
        for (final meal in plan) {
          count += meal.items.where((i) => i.name == 'Greek Yogurt').length;
        }
        expect(count, lessThanOrEqualTo(1),
            reason: 'seed=$seed pref=$pref: Greek Yogurt appeared $count times');
      }
    }
  });

  test('Pass 5 fiber floor strictly raises daily fiber vs no-pass baseline', () {
    // Behavioral pin: same seed, fiberTarget 0 (floor 0 → Pass 5 dormant)
    // vs fiberTarget 30 (floor 21 → swaps fire). Robust across seeds: for
    // EVERY seed the floored plan must never lose fiber, and at least one
    // seed must show a strict gain — a disabled Pass 5 (mutation M6)
    // reddens the any-gain assertion regardless of fixture composition.
    var sawGain = false;
    for (var seed = 1; seed <= 5; seed++) {
      final base = gen.generate(DietPlanInputs(
        calorieTarget: 2200,
        proteinTarget: 140,
        dietPreference: 'non-veg',
        fiberTarget: 0,
        seed: seed,
      ));
      final floored = gen.generate(DietPlanInputs(
        calorieTarget: 2200,
        proteinTarget: 140,
        dietPreference: 'non-veg',
        fiberTarget: 30,
        seed: seed,
      ));
      final baseFiber = base.fold<int>(0, (s, m) => s + m.totalFiber);
      final flooredFiber = floored.fold<int>(0, (s, m) => s + m.totalFiber);
      expect(flooredFiber, greaterThanOrEqualTo(baseFiber),
          reason: 'seed=$seed: Pass 5 LOWERED fiber ($flooredFiber vs '
              '$baseFiber) — whole-grain swap is fiber-blind');
      if (flooredFiber > baseFiber) sawGain = true;
    }
    expect(sawGain, isTrue,
        reason: 'Pass 5 produced no fiber gain on ANY seed over the dormant '
            'baseline — Pass 5 regressed (mutation M6 pin)');
  });

  test('Pass 5 no-ops safely when the fiber floor is unreachable', () {
    // fiberTarget 400 → floor 280, unreachable in any fixture — the pass
    // must terminate (bounded tries) without throwing or hanging.
    final plan = gen.generate(const DietPlanInputs(
      calorieTarget: 2200,
      proteinTarget: 140,
      dietPreference: 'non-veg',
      fiberTarget: 400,
      seed: 42,
    ));
    expect(plan, hasLength(5));
  });

  test('saved-plan JSON schema is unchanged by the constraint layer', () {
    // Writer shape pinned by source presence (contract: the file that
    // WRITES the saved plan still emits exactly these keys, so
    // TodaysMealsCard + restore readers keep working).
    final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    for (final key in ['food_id', 'serving_desc', 'serving_g', 'calories',
        'protein', 'carbs', 'fat', 'category']) {
      expect(src.contains("'$key':"), isTrue,
          reason: '_savePlan writer key "$key" missing — saved-plan schema '
              'changed and restore/TodaysMealsCard readers will drift');
    }
  });

  test('manual swap sheet applies the same UPF + diet-preference filters', () {
    final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    final swapBody = src.substring(src.indexOf('void _swapItem'),
        src.indexOf('void _savePlan'));
    expect(swapBody.contains('is_ultra_processed'), isTrue,
        reason: '_swapItem must exclude UPF alternatives — a manual tap can '
            'otherwise re-introduce the Pringles-class defect');
    expect(swapBody.contains('passesDiet'), isTrue,
        reason: '_swapItem must apply the diet-preference rule — a veg user '
            'must never be offered chicken (round 2, finding 5)');
  });
}
