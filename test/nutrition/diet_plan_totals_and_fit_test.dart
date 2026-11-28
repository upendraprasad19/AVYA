// test/nutrition/diet_plan_totals_and_fit_test.dart
//
// Diet chart v3 (docs/plans/diet-chart-v3.md §4.1, §4.2, §5): the plan totals,
// the carb ceilings, the shift rule and the "back to" rule, on the real asset.
//
// The matrix test is the one that picked the fit factor: EVERY freshly
// generated Keto / Low carb plan must fit its own strategy, so a fresh plan can
// never read as broken (round 2 of the plan review measured up to 1.42 times
// the strict carb target).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/effective_macro_targets.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_pdf.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_shake.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_strategy_fit.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_totals.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

class _Repo implements FoodRepository {
  _Repo(List<Map<String, dynamic>> rows)
      : _byId = {for (final r in rows) r['id'] as String: r};
  final Map<String, Map<String, dynamic>> _byId;
  @override
  Map<String, dynamic>? getById(String id) => _byId[id];
  @override
  List<Map<String, dynamic>> getAll() => _byId.values.toList();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MacroPack _pack(int kcal, int protein) => (
      calories: kcal.toDouble(),
      protein: protein.toDouble(),
      carbs: kcal * 0.5 / 4,
      fat: 70,
    );

void main() {
  group('totals', () {
    test('sum of the four numbers; empty is zero', () {
      expect(sumDietPlanTotals(const []), DietPlanTotals.zero);
      final t = sumDietPlanTotals(const [
        (calories: 100, protein: 10, carbs: 5, fat: 2),
        (calories: 250, protein: 20, carbs: 30, fat: 9),
      ]);
      expect(t, const DietPlanTotals(calories: 350, protein: 30, carbs: 35, fat: 11));
    });

    test('off target means more than 10 percent away; a zero target never warns', () {
      expect(dietPlanTotalOffTarget(2200, 2000), isFalse); // exactly +10 %
      expect(dietPlanTotalOffTarget(2201, 2000), isTrue);
      expect(dietPlanTotalOffTarget(1799, 2000), isTrue);
      expect(dietPlanTotalOffTarget(50, 0), isFalse);
    });
  });

  group('ceilings and fit', () {
    final base = _pack(2000, 144);
    test('targets are macroSplit; ceilings are 1.5 x; Balanced has none', () {
      expect(dietStrategyCarbTarget(DietStrategy.keto, base), 25);
      expect(dietStrategyCarbTarget(DietStrategy.lowCarb, base), 100);
      expect(dietStrategyCarbCeiling(DietStrategy.keto, base), 38);
      expect(dietStrategyCarbCeiling(DietStrategy.lowCarb, base), 150);
      expect(dietStrategyCarbCeiling(DietStrategy.balanced, base), isNull);
      expect(dietStrategyCarbTarget(DietStrategy.keto, null), isNull);
    });

    test('an unusable pack judges nothing', () {
      const empty = (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0);
      expect(strictestFit(dayCarbs: 20, base: empty, allowKeto: true), isNull);
      expect(strictestFit(dayCarbs: 20, base: null, allowKeto: true), isNull);
      expect(
          shiftTargetFor(
              planStrategy: DietStrategy.keto,
              beforeCarbs: 20,
              afterCarbs: 90,
              base: null,
              allowKeto: true),
          isNull);
    });

    test('strictestFit walks Keto -> Low carb -> Balanced; allowKeto skips Keto', () {
      DietStrategy? fit(num c, {bool keto = true}) =>
          strictestFit(dayCarbs: c, base: base, allowKeto: keto);
      expect(fit(30), DietStrategy.keto);
      expect(fit(38), DietStrategy.keto);
      expect(fit(39), DietStrategy.lowCarb);
      expect(fit(150), DietStrategy.lowCarb);
      expect(fit(151), DietStrategy.balanced);
      expect(fit(10, keto: false), DietStrategy.lowCarb);
    });

    test('the shift rule: needs MORE carbs AND a less strict fit; never up', () {
      DietStrategy? shift(DietStrategy plan, num before, num after,
              {bool keto = true}) =>
          shiftTargetFor(
              planStrategy: plan,
              beforeCarbs: before,
              afterCarbs: after,
              base: base,
              allowKeto: keto);
      // oats into a Keto plan: Keto -> Low carb
      expect(shift(DietStrategy.keto, 22, 49), DietStrategy.lowCarb);
      // a second carb-heavy pick: Low carb -> Balanced
      expect(shift(DietStrategy.lowCarb, 120, 190), DietStrategy.balanced);
      // Keto straight to Balanced
      expect(shift(DietStrategy.keto, 22, 200), DietStrategy.balanced);
      // round 1 F1: a plan already over its ceiling, a pick that CUTS carbs
      expect(shift(DietStrategy.keto, 60, 55), isNull);
      // equal carbs never ask
      expect(shift(DietStrategy.keto, 60, 60), isNull);
      // adding carbs but still inside the ceiling: no shift
      expect(shift(DietStrategy.keto, 20, 36), isNull);
      // a Balanced plan never shifts, nothing moves up
      expect(shift(DietStrategy.balanced, 200, 300), isNull);
      expect(shift(DietStrategy.lowCarb, 200, 20), isNull);
      // B-pass seat C finding 2: carbs ROSE and the day fits a STRICTER level
      // than the plan (Low carb plan, 20 -> 30 g still fits Keto): never up,
      // with Keto allowed or not
      expect(shift(DietStrategy.lowCarb, 20, 30), isNull);
      expect(shift(DietStrategy.lowCarb, 20, 30, keto: false), isNull);
    });

    test('back up: only to the strategy dropped from, only while it fits', () {
      DietStrategy? back(DietStrategy? from, DietStrategy plan, num carbs,
              {bool keto = true}) =>
          backUpTargetFor(
              droppedFrom: from,
              planStrategy: plan,
              dayCarbs: carbs,
              base: base,
              allowKeto: keto);
      expect(back(DietStrategy.keto, DietStrategy.lowCarb, 30), DietStrategy.keto);
      expect(back(DietStrategy.keto, DietStrategy.lowCarb, 60), isNull);
      expect(back(null, DietStrategy.lowCarb, 30), isNull);
      expect(back(DietStrategy.lowCarb, DietStrategy.lowCarb, 30), isNull);
      // B-pass seat A finding 2: after Keto -> Balanced a day that fits only
      // Low carb again offers Low carb (the strictest level it fits)...
      expect(back(DietStrategy.keto, DietStrategy.balanced, 100),
          DietStrategy.lowCarb);
      // ...and never above where the plan came from, nor a level it still misses
      expect(back(DietStrategy.lowCarb, DietStrategy.balanced, 20),
          DietStrategy.lowCarb);
      expect(back(DietStrategy.keto, DietStrategy.balanced, 200), isNull);
      expect(back(DietStrategy.keto, DietStrategy.lowCarb, 20, keto: false),
          isNull,
          reason: 'Keto is off for this user: Low carb is where the plan is');
    });

    test('the fit line', () {
      String? line(DietStrategy s, num c) =>
          dietPlanFitLine(planStrategy: s, dayCarbs: c, base: base);
      expect(line(DietStrategy.keto, 30), 'Fits Keto (up to 38 g)');
      expect(line(DietStrategy.keto, 49),
          'Over the Keto limit (49 g, up to 38 g)');
      expect(line(DietStrategy.balanced, 300), isNull);
    });
  });

  group('PDF total line', () {
    test('the same totals and targets as the row; the caption names a '
        'strategy that is not the header\'s', () {
      const t = DietPlanTotals(calories: 2315, protein: 142, carbs: 118, fat: 96);
      expect(
          dietPlanPdfTotalLine(
              totals: t,
              calorieTarget: 2400,
              proteinTarget: 150,
              carbTarget: 120,
              fatTarget: 80),
          'Plan total: 2315 kcal  |  Protein: 142g  |  Carbs: 118g  |  Fat: 96g   '
          '(target: 2400 kcal  |  150g  |  120g  |  80g)');
      expect(
          dietPlanPdfTotalLine(
              totals: t,
              calorieTarget: 2400,
              proteinTarget: 150,
              carbTarget: 120,
              fatTarget: 80,
              caption: 'Low carb'),
          contains('(target Low carb: 2400 kcal'));
    });
  });

  group('every generated plan fits its own strategy (the fit factor)', () {
    final rows = (jsonDecode(
            File('assets/data/food_database.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final repo = _Repo(rows);
    final pea = rows.firstWhere((r) => r['id'] == 'F0831');
    const archetypes = [
      (1200, 100, 'non-veg'),
      (1500, 110, 'non-veg'),
      (1800, 130, 'veg'),
      (2000, 144, 'non-veg'),
      (2200, 110, 'vegan'),
      (2400, 128, 'eggetarian'),
      (2700, 126, 'veg'),
      (3000, 150, 'non-veg'),
      (3500, 180, 'non-veg'),
      (2600, 140, 'pescatarian'),
    ];

    test('Low carb and Keto, 10 archetypes x 100 seeds', () {
      final gen = CuratedDietPlanGenerator.forTest(repo);
      var worst = 0.0;
      var checked = 0;
      for (final (kcal, protein, pref) in archetypes) {
        final base = _pack(kcal, protein);
        for (final s in [DietStrategy.lowCarb, DietStrategy.keto]) {
          final target = dietStrategyCarbTarget(s, base)!;
          for (var seed = 1; seed <= 100; seed++) {
            final r = gen.generatePlan(DietPlanInputs(
              calorieTarget: kcal,
              proteinTarget: protein,
              dietPreference: pref,
              seed: seed,
              strategy: s,
              carbTarget: target.toDouble(),
            ));
            if (r.builtFor == DietStrategy.balanced) continue;
            final own = dietStrategyCarbTarget(r.builtFor, base)!;
            // the plan as generated, and the plan with the Supplements shake
            // the screen adds on top (the pea powder carries the most carbs:
            // B-pass seat A finding 4)
            final withShake = addProteinShake(
                meals: r.meals,
                proteinTarget: protein,
                calorieTarget: kcal,
                row: pea);
            for (final meals in [r.meals, withShake]) {
              final carbs = sumDietPlanTotals([
                for (final m in meals)
                  for (final i in m.items)
                    (calories: i.calories, protein: i.protein, carbs: i.carbs, fat: i.fat),
              ]).carbs;
              final ratio = carbs / own;
              if (ratio > worst) worst = ratio;
              checked++;
              expect(
                  strictestFit(dayCarbs: carbs, base: base, allowKeto: true)!
                      .index,
                  greaterThanOrEqualTo(r.builtFor.index),
                  reason: '$kcal/$protein $pref ${r.builtFor} seed $seed: '
                      '$carbs g vs target $own g (ratio ${ratio.toStringAsFixed(2)})');
            }
          }
        }
      }
      expect(checked, greaterThan(3000)); // plans x (as generated, with shake)
      // ignore: avoid_print
      print('fit factor: worst generated ratio ${worst.toStringAsFixed(2)} '
          'over $checked plans; factor $kStrategyFitFactor');
      expect(worst, lessThan(kStrategyFitFactor));
    });
  });
}
