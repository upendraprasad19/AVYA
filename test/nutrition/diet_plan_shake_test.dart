// test/nutrition/diet_plan_shake_test.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 5): the protein
// shake post-process. Real food rows (F0823 whey isolate, F0831 pea protein)
// come from the shipped asset.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_shake.dart';

Map<String, Map<String, dynamic>> _rows() => {
      for (final r in (jsonDecode(
              File('assets/data/food_database.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>())
        r['id'] as String: r,
    };

DietPlanFoodItem _item(String id, int cal, int prot) => DietPlanFoodItem(
      foodId: id,
      name: id,
      servingDesc: '1',
      servingG: 100,
      calories: cal,
      protein: prot,
      carbs: 0,
      fat: 0,
      category: 'x',
    );

DietMealPlan _meal(String slot, List<DietPlanFoodItem> items) => DietMealPlan(
      name: slot,
      slotKey: slot,
      items: items,
      targetCalories: 0,
      targetProtein: 0,
    );

/// A day of [totalCal] kcal and [totalProt] g protein: the evening slot holds
/// [eveningItems], the rest is one filler item in lunch.
List<DietMealPlan> _day(List<DietPlanFoodItem> eveningItems,
    {required int lunchCal, required int lunchProt}) {
  return [
    _meal('lunch', [_item('LUNCH', lunchCal, lunchProt)]),
    _meal('evening', eveningItems),
  ];
}

void main() {
  final rows = _rows();
  final whey = rows['F0823']!;
  final pea = rows['F0831']!;

  test('the two shake ids are the real supplement rows', () {
    expect(kSupplementShakeFoodIds, {'F0823', 'F0831'});
    expect(whey['category'], 'supplements');
    expect(pea['category'], 'supplements');
    expect(shakeFoodIdFor(FoodType.vegan), 'F0831');
    for (final t in FoodType.values.where((t) => t != FoodType.vegan)) {
      expect(shakeFoodIdFor(t), 'F0823', reason: t.name);
    }
    expect(isSupplementShake('F0823'), isTrue);
    expect(isSupplementShake('F0831'), isTrue);
    expect(isSupplementShake('F0001'), isFalse);
  });

  test('shake item carries the row\'s numbers', () {
    final s = shakeItem(whey);
    expect(s.foodId, 'F0823');
    expect(s.protein, 27);
    expect(s.calories, 108);
    expect(s.category, 'supplements');
  });

  group('the gap boundary (kShakeMinProteinGapG = 15)', () {
    // day = 100 protein, 1500 kcal; ceiling plenty.
    List<DietMealPlan> run(int target) => addProteinShake(
        meals: _day([_item('E1', 200, 10)], lunchCal: 1300, lunchProt: 90),
        proteinTarget: target,
        calorieTarget: 2400,
        row: whey);

    test('gap 14: no shake', () {
      expect(run(114).last.items.map((i) => i.foodId), ['E1']);
    });
    test('gap 15: shake added', () {
      expect(run(115).last.items.map((i) => i.foodId), ['E1', 'F0823']);
    });
    test('gap 16: shake added', () {
      expect(run(116).last.items.map((i) => i.foodId), ['E1', 'F0823']);
    });
  });

  test('the vegan row is added for a pea-protein request', () {
    final out = addProteinShake(
        meals: _day([_item('E1', 100, 5)], lunchCal: 1000, lunchProt: 60),
        proteinTarget: 150,
        calorieTarget: 2400,
        row: pea);
    expect(out.last.items.last.foodId, 'F0831');
  });

  test('a missing row (stale food box) returns the input itself', () {
    final meals =
        _day([_item('E1', 100, 5)], lunchCal: 1000, lunchProt: 60);
    expect(
        identical(
            addProteinShake(
                meals: meals,
                proteinTarget: 150,
                calorieTarget: 2400,
                row: null),
            meals),
        isTrue);
    expect(
        identical(
            addProteinShake(
                meals: meals,
                proteinTarget: 150,
                calorieTarget: 2400,
                row: {'name': 'no id'}),
            meals),
        isTrue);
  });

  test('no evening slot returns the input itself', () {
    final meals = [
      _meal('lunch', [_item('L', 500, 20)])
    ];
    expect(
        identical(
            addProteinShake(
                meals: meals,
                proteinTarget: 150,
                calorieTarget: 2400,
                row: whey),
            meals),
        isTrue);
  });

  test('a plan that already holds a shake is returned unchanged', () {
    final meals = _day([_item('F0823', 108, 27)], lunchCal: 1000, lunchProt: 60);
    expect(
        identical(
            addProteinShake(
                meals: meals,
                proteinTarget: 200,
                calorieTarget: 2400,
                row: whey),
            meals),
        isTrue);
  });

  test('the input is never mutated', () {
    final meals = _day([_item('E1', 100, 5)], lunchCal: 1000, lunchProt: 60);
    final before = meals.last.items.length;
    addProteinShake(
        meals: meals, proteinTarget: 150, calorieTarget: 2400, row: whey);
    expect(meals.last.items.length, before);
  });

  group('over the calorie ceiling: replace by lowest protein density', () {
    // calorie target 1000, ceiling 1080. Day = 1000 kcal.
    // evening: LOW (400 kcal, 4 g: density .01), MID (300, 15: .05),
    // HIGH (100, 30: .30). lunch 200 kcal, 30 g. Day protein = 79.
    List<DietMealPlan> day() => _day([
          _item('LOW', 400, 4),
          _item('MID', 300, 15),
          _item('HIGH', 100, 30),
        ], lunchCal: 200, lunchProt: 30);

    test('takes out the lowest-density item first, only as many as needed', () {
      // + shake 108 => 1108 > 1080: drop LOW (-400) => 708 fits.
      final out = addProteinShake(
          meals: day(), proteinTarget: 150, calorieTarget: 1000, row: whey);
      expect(out.last.items.map((i) => i.foodId), ['MID', 'HIGH', 'F0823']);
    });

    test('keeps the slot\'s original order for what stays', () {
      final out = addProteinShake(
          meals: day(), proteinTarget: 150, calorieTarget: 1000, row: whey);
      expect(out.last.items.first.foodId, 'MID');
    });

    test('net protein gain must exceed 8 g, else the plan is unchanged', () {
      // Replace a 25 g item to make room for a 27 g shake: net +2 only.
      final meals = _day([_item('BIG', 600, 25)], lunchCal: 400, lunchProt: 20);
      final out = addProteinShake(
          meals: meals, proteinTarget: 150, calorieTarget: 1000, row: whey);
      expect(identical(out, meals), isTrue);
    });

    test('net gain of exactly 8 g is not enough, 9 g is', () {
      DietMealPlan eve(int prot) => _meal('evening', [_item('X', 600, prot)]);
      List<DietMealPlan> m(int prot) =>
          [_meal('lunch', [_item('L', 400, 20)]), eve(prot)];
      // shake protein 27: net = 27 - prot. prot 19 => 8 (no), prot 18 => 9.
      expect(
          addProteinShake(
                  meals: m(19),
                  proteinTarget: 150,
                  calorieTarget: 1000,
                  row: whey)
              .last
              .items
              .map((i) => i.foodId),
          ['X']);
      expect(
          addProteinShake(
                  meals: m(18),
                  proteinTarget: 150,
                  calorieTarget: 1000,
                  row: whey)
              .last
              .items
              .map((i) => i.foodId),
          ['F0823']);
    });

    test('a slot that cannot make room even when emptied is unchanged', () {
      final meals = [
        _meal('lunch', [_item('L', 1100, 40)]),
        _meal('evening', [_item('E', 50, 2)]),
      ];
      final out = addProteinShake(
          meals: meals, proteinTarget: 200, calorieTarget: 1000, row: whey);
      expect(identical(out, meals), isTrue);
    });
  });
}
