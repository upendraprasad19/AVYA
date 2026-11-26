// test/nutrition/diet_plan_swap_only_test.dart
//
// Diet chart v3 (docs/plans/diet-chart-v3.md §4.4, §5): the swap-only catalog
// entries. The generator never picks them (every generated plan is unchanged),
// the swap sheet offers them, and a VEGAN plan now has enough alternatives in
// the two roles that were nearly empty (measured 2026-11-17: breakfast protein
// 1 option, sides 0 for 59-68 % of items).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog_rules.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_swap.dart';
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

void main() {
  final rows = (jsonDecode(
          File('assets/data/food_database.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final repo = _Repo(rows);
  final swapOnlyIds = {
    for (final e in kDietPlanCatalog)
      if (e.swapOnly) e.foodId,
  };

  group('the entries', () {
    test('ten, appended last, never low-carb-only, vegan and not processed', () {
      expect(swapOnlyIds, hasLength(10));
      final firstSwapOnly = kDietPlanCatalog.indexWhere((e) => e.swapOnly);
      expect(
          kDietPlanCatalog.sublist(firstSwapOnly).every((e) => e.swapOnly),
          isTrue,
          reason: 'appended: the index is the swap tie-break');
      for (final e in kDietPlanCatalog.where((e) => e.swapOnly)) {
        expect(e.lowCarbOnly, isFalse, reason: e.foodId);
        final row = repo.getById(e.foodId)!;
        expect(row['is_vegan'], true, reason: e.foodId);
        expect(row['is_ultra_processed'], false, reason: e.foodId);
        expect(row['is_everyday'], true, reason: e.foodId);
      }
    });

    test('generatorOffered hides them from every strategy; the swap keeps them', () {
      for (final e in kDietPlanCatalog.where((e) => e.swapOnly)) {
        for (final s in DietStrategy.values) {
          expect(generatorOffered(e, s), isFalse, reason: '${e.foodId} $s');
        }
        expect(catalogEntryOffered(e, DietStrategy.balanced), isTrue);
      }
    });
  });

  group('the generator', () {
    test('no generated plan ever holds a swap-only food', () {
      final gen = CuratedDietPlanGenerator.forTest(repo);
      for (final (kcal, protein, pref, s) in [
        (2000, 144, 'non-veg', DietStrategy.balanced),
        (2200, 110, 'vegan', DietStrategy.balanced),
        (1800, 130, 'veg', DietStrategy.balanced),
        (2000, 144, 'non-veg', DietStrategy.lowCarb),
        (2000, 144, 'non-veg', DietStrategy.keto),
        (2200, 110, 'vegan', DietStrategy.lowCarb),
      ]) {
        for (var seed = 1; seed <= 40; seed++) {
          final plan = gen.generatePlan(DietPlanInputs(
            calorieTarget: kcal,
            proteinTarget: protein,
            dietPreference: pref,
            seed: seed,
            strategy: s,
            carbTarget: s == DietStrategy.balanced
                ? null
                : kcal * (s == DietStrategy.keto ? 0.05 : 0.2) / 4,
          ));
          for (final m in plan.meals) {
            for (final i in m.items) {
              expect(swapOnlyIds, isNot(contains(i.foodId)),
                  reason: '$pref $s seed $seed');
            }
          }
        }
      }
    });
  });

  group('vegan swap options after the new entries (Balanced, 100 seeds)', () {
    test('breakfast protein and sides: few zero-option items, a useful median', () {
      final gen = CuratedDietPlanGenerator.forTest(repo);
      final counts = <String, List<int>>{};
      for (final (kcal, protein) in [(2200, 110), (1800, 130), (2400, 150)]) {
        for (var seed = 1; seed <= 100; seed++) {
          final r = gen.generatePlan(DietPlanInputs(
              calorieTarget: kcal,
              proteinTarget: protein,
              dietPreference: 'vegan',
              seed: seed));
          final ids = [for (final m in r.meals) for (final i in m.items) i.foodId];
          for (final m in r.meals) {
            for (var idx = 0; idx < m.items.length; idx++) {
              final it = m.items[idx];
              if (it.role != 'breakfastProtein' && it.role != 'side') continue;
              (counts[it.role!] ??= []).add(swapAlternatives(
                foodId: it.foodId,
                category: it.category,
                calories: it.calories,
                role: it.role,
                slotKey: m.slotKey,
                dietPreference: 'vegan',
                planFoodIds: ids,
                slotOtherNames: [
                  for (var j = 0; j < m.items.length; j++)
                    if (j != idx) m.items[j].name,
                ],
                repo: repo,
                limit: 100,
              ).length);
            }
          }
        }
      }
      double zero(List<int> l) => l.where((x) => x == 0).length / l.length;
      int median(List<int> l) => ([...l]..sort())[l.length ~/ 2];
      final bp = counts['breakfastProtein']!;
      final side = counts['side']!;
      // ignore: avoid_print
      print('vegan breakfastProtein: zero ${(100 * zero(bp)).toStringAsFixed(1)}% '
          'median ${median(bp)} n=${bp.length}; side: zero '
          '${(100 * zero(side)).toStringAsFixed(1)}% median ${median(side)} '
          'n=${side.length}');
      expect(zero(bp), lessThanOrEqualTo(0.05));
      expect(median(bp), greaterThanOrEqualTo(3));
      expect(zero(side), lessThanOrEqualTo(0.10));
      expect(median(side), greaterThanOrEqualTo(3));
    });
  });
}
