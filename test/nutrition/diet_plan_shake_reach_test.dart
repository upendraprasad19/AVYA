// test/nutrition/diet_plan_shake_reach_test.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 12): the shake's
// REACH on real generated plans. A short-on-protein archetype gets a shake
// in most seeds; a well-fed one gets none; and whenever a shake is added the
// day gains protein and stays inside the calorie ceiling.
//
// The numbers are measured. 2026-11-14 (16 archetypes x 50 seeds): cut veg 47
// of 50 shaken, cut non-veg male 0 of 50. 2026-11-15, after the replacement
// rule, 400 seeds each: veg and vegan at 1500 kcal / 130 g protein were shaken
// on 400 of 400, so the screen tests, whose seed is the calendar day, never
// see a day without a shake for that profile (B-pass seat C finding 2).
// The floors for the other archetypes are looser than the measurement on
// purpose: they say the feature does something for the people it is for and
// nothing for the rest.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_shake.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

import '../helpers/hive_test_setup.dart';

typedef _Arch = ({String name, String pref, int cal, int prot});

const _seeds = 200;

void main() {
  late Directory dir;
  late Map<String, Map<String, dynamic>> shakeRows;

  setUp(() async {
    dir = await setUpHiveForTests();
    final ids = {for (final e in kDietPlanCatalog) e.foodId, 'F0823', 'F0831'};
    final rows = {
      for (final r in (jsonDecode(File('assets/data/food_database.json')
              .readAsStringSync()) as List)
          .cast<Map<String, dynamic>>())
        if (ids.contains(r['id'])) r['id'] as String: r,
    };
    await HiveService.instance.foodBox.putAll(rows);
    shakeRows = {'F0823': rows['F0823']!, 'F0831': rows['F0831']!};
  });

  tearDown(() async => tearDownHiveForTests(dir));

  ({int gapDays, int shaken, List<String> bad}) run(_Arch a) {
    var gapDays = 0, shaken = 0;
    final bad = <String>[];
    final shakeId = a.pref == 'vegan' ? 'F0831' : 'F0823';
    for (var seed = 0; seed < _seeds; seed++) {
      final built = CuratedDietPlanGenerator.instance.generatePlan(DietPlanInputs(
        calorieTarget: a.cal,
        proteinTarget: a.prot,
        dietPreference: a.pref,
        fiberTarget: 30,
        seed: seed,
        strategy: DietStrategy.balanced,
        carbTarget: null,
      ));
      int cal(List<DietMealPlan> m) => m.fold(0, (s, x) => s + x.totalCalories);
      int prot(List<DietMealPlan> m) => m.fold(0, (s, x) => s + x.totalProtein);
      final out = addProteinShake(
          meals: built.meals,
          proteinTarget: a.prot,
          calorieTarget: a.cal,
          row: FoodRepository.instance.getById(shakeId));
      final had = out.any((m) => m.items.any((i) => i.foodId == shakeId));
      if (a.prot - prot(built.meals) >= kShakeMinProteinGapG) gapDays++;
      if (had) {
        shaken++;
        if (prot(out) <= prot(built.meals)) bad.add('seed $seed: no protein gain');
        if (cal(out) > a.cal * kShakeCalorieCeiling &&
            cal(out) > cal(built.meals)) {
          bad.add('seed $seed: over the ceiling');
        }
        if (out.where((m) => m.items.any((i) => i.foodId == shakeId)).length != 1 ||
            out.expand((m) => m.items).where((i) => i.foodId == shakeId).length != 1) {
          bad.add('seed $seed: not exactly one scoop');
        }
      } else if (!identical(out, built.meals)) {
        bad.add('seed $seed: changed without a shake');
      }
    }
    return (gapDays: gapDays, shaken: shaken, bad: bad);
  }

  test('a short-on-protein vegetarian gets a shake on most plans', () {
    final r = run((name: 'cut veg', pref: 'veg', cal: 1500, prot: 130));
    expect(r.bad, isEmpty);
    expect(r.shaken, _seeds,
        reason: 'the screen tests rely on this profile shaking on EVERY day');
    expect(r.gapDays, greaterThan(_seeds * 0.6));
    expect(r.shaken, greaterThanOrEqualTo((r.gapDays * 0.8).floor()),
        reason: 'where the day falls short the shake fits (measured 47 of 47)');
  });

  test('a vegan gets the pea row', () {
    final r = run((name: 'cut vegan', pref: 'vegan', cal: 1500, prot: 130));
    expect(r.bad, isEmpty);
    expect(r.shaken, _seeds,
        reason: 'the screen tests rely on this profile shaking on EVERY day');
  });

  test('a well-fed non-veg day gets (almost) none, and never breaks a rule',
      () {
    final r = run((name: 'maintain non-veg', pref: 'non_veg', cal: 2400, prot: 150));
    expect(r.bad, isEmpty);
    expect(r.shaken, lessThanOrEqualTo(_seeds ~/ 5));
  });

  test('the shake rows used are the two the plan names', () {
    expect(shakeRows.keys.toSet(), kSupplementShakeFoodIds);
  });
}
