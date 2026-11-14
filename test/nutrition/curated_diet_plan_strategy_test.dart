// test/nutrition/curated_diet_plan_strategy_test.dart
//
// Diet plan Unit 3b-1a (2026-11-14, docs/plans/diet-strategy-3b.md §3.2-§3.4,
// §4): Low carb / Keto plans from the curated generator and the swap sheet,
// against the REAL bundled food database.
//
//   G1 Balanced generator golden (byte-identity with main 21db03c7)
//   G2 Balanced swap golden (plan items + legacy plans holding the new ids)
//   T10 strategy matrix (16 archetypes x 50 seeds x {Low carb, Keto})
//   T11 generatePlan builtFor / normalisation
//   T12 strategy swap
//
// The T10 floors are the CONTRACT measured on the built code (minimum - 0.02):
// an implementation change may raise them, never lower them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
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

class _A {
  final String label;
  final int kcal;
  final int protein;
  final String pref;
  const _A(this.label, this.kcal, this.protein, this.pref);
}

// The same 16 archetypes as curated_diet_plan_test.dart (plan §4 T5 table).
const _archetypes = [
  _A('cut male non-veg', 2000, 144, 'non-veg'),
  _A('cut male veg', 2000, 144, 'veg'),
  _A('cut female veg', 1500, 110, 'veg'),
  _A('cut female non-veg', 1500, 110, 'non-veg'),
  _A('cut vegan', 1800, 130, 'vegan'),
  _A('recomp non-veg', 2200, 160, 'non-veg'),
  _A('maintain veg', 2400, 128, 'veg'),
  _A('maintain vegan', 2200, 110, 'vegan'),
  _A('build non-veg', 2700, 126, 'non-veg'),
  _A('build veg', 3000, 150, 'veg'),
  _A('1200 floor veg', 1200, 100, 'veg'),
  _A('1200 floor non-veg', 1200, 100, 'non-veg'),
  _A('cut male eggetarian', 2000, 144, 'eggetarian'),
  _A('cut female pescatarian', 1500, 110, 'pescatarian'),
  _A('maintain eggetarian', 2400, 128, 'eggetarian'),
  _A('maintain pescatarian', 2400, 128, 'pescatarian'),
];

const _seeds = 50;

/// The Unit 3b Low carb / Keto only ids.
const _lowCarbIds = {
  'F0402', 'F0403', 'F0483', 'F0383', 'F0371', 'F0790', 'F0023', 'F0398',
  'F0394', 'F0348', 'F1022', 'F1024', 'F0040', 'F0264',
};

/// Carb target for an archetype: macroSplit over a Balanced pack whose fat
/// is 25 % of calories (the generator only ever sees the effective carbs).
double _carbTarget(_A a, DietStrategy s) => BmrCalculator.macroSplit(
      dailyCalories: a.kcal.toDouble(),
      proteinGrams: a.protein.toDouble(),
      balancedCarbs: (a.kcal - 4 * a.protein - 0.25 * a.kcal) / 4,
      strategy: s,
    ).carbGrams.toDouble();

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  final rows =
      (jsonDecode(File('assets/data/food_database.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final repo = _Repo(rows);
  final byId = {for (final r in rows) r['id'] as String: r};
  final entryOf = {for (final e in kDietPlanCatalog) e.foodId: e};

  group('G1/G2 Balanced byte-identity with main 21db03c7', () {
    test('G1 the 800 Balanced plans hash to the main golden', () {
      final gen = CuratedDietPlanGenerator.forTest(repo);
      final out = StringBuffer();
      for (final a in _archetypes) {
        for (var s = 1; s <= _seeds; s++) {
          final plan = gen.generate(DietPlanInputs(
              calorieTarget: a.kcal,
              proteinTarget: a.protein,
              dietPreference: a.pref,
              seed: s));
          for (final m in plan) {
            out.write('${m.slotKey}:');
            for (final i in m.items) {
              out.write('${i.foodId}/${i.servingG}/${i.servingDesc}/${i.role};');
            }
            out.write('|');
          }
          out.writeln();
        }
      }
      // Captured on main 21db03c7 before the Unit 3b catalog append
      // (plan §3.3); the same text there and here.
      expect(_sha(out.toString()),
          '96f7e27cb0486b18896a1758f0072af7bf99149edf05eb8c907ca59b32630810');
    });

    test('G2 Balanced swaps (plan items + legacy plans holding the new ids) '
        'hash to the main golden', () {
      final gen = CuratedDietPlanGenerator.forTest(repo);
      final out = StringBuffer();
      for (final a in _archetypes) {
        for (var s = 1; s <= 5; s++) {
          final plan = gen.generate(DietPlanInputs(
              calorieTarget: a.kcal,
              proteinTarget: a.protein,
              dietPreference: a.pref,
              seed: s));
          final ids = [for (final m in plan) for (final i in m.items) i.foodId];
          for (final m in plan) {
            for (var k = 0; k < m.items.length; k++) {
              final it = m.items[k];
              for (final role in [it.role, null]) {
                final alts = swapAlternatives(
                    foodId: it.foodId,
                    category: it.category,
                    calories: it.calories,
                    role: role,
                    slotKey: m.slotKey,
                    dietPreference: a.pref,
                    planFoodIds: ids,
                    slotOtherNames: [
                      for (var j = 0; j < m.items.length; j++)
                        if (j != k) m.items[j].name,
                    ],
                    repo: repo);
                out.writeln('${it.foodId}/$role:'
                    '${alts.map((x) => '${x.foodId}/${x.servingG}/${x.role}').join(',')}');
              }
            }
          }
        }
      }
      // A saved / legacy Balanced plan holding each Unit 3b id (round 2
      // finding 3): the role scan and the family counts must not see them.
      const legacy = [
        'F0402', 'F0403', 'F0483', 'F0383', 'F0371', 'F0790', 'F0023',
        'F0398', 'F0394', 'F0348', 'F1022', 'F1024', 'F0040', 'F0264',
        'F0268', 'F0474',
      ];
      final base = gen.generate(const DietPlanInputs(
          calorieTarget: 2000,
          proteinTarget: 144,
          dietPreference: 'non-veg',
          seed: 1));
      for (final id in legacy) {
        final row = repo.getById(id)!;
        for (final m in base) {
          final ids = [
            for (final mm in base) for (final i in mm.items) i.foodId,
            id,
          ];
          for (final pref in ['non-veg', 'veg', 'eggetarian']) {
            final alts = swapAlternatives(
                foodId: id,
                category: row['category'] as String,
                calories: (row['calories_std'] as num).round(),
                role: null,
                slotKey: m.slotKey,
                dietPreference: pref,
                planFoodIds: ids,
                slotOtherNames: [for (final i in m.items) i.name],
                repo: repo);
            out.writeln('L $id/${m.slotKey}/$pref:'
                '${alts.map((x) => '${x.foodId}/${x.servingG}/${x.role}').join(',')}');
          }
          if (m.items.isNotEmpty) {
            final it = m.items.first;
            final alts = swapAlternatives(
                foodId: it.foodId,
                category: it.category,
                calories: it.calories,
                role: it.role,
                slotKey: m.slotKey,
                dietPreference: 'non-veg',
                planFoodIds: ids,
                slotOtherNames: [for (final i in m.items.skip(1)) i.name],
                repo: repo);
            out.writeln('C $id/${m.slotKey}/${it.foodId}:'
                '${alts.map((x) => '${x.foodId}/${x.servingG}/${x.role}').join(',')}');
          }
        }
      }
      expect(_sha(out.toString()),
          '0acb6a7ddcf6eebcfd5688cd7b1da4cbf791b41a6514c3dacc4ce03fef62c1d6');
    });
  });

  group('T10 strategy matrix', () {
    final gen = CuratedDietPlanGenerator.forTest(repo);
    final fallbacksBefore = gen.lastFallbackCount;
    final plans = <DietStrategy, Map<_A, List<List<DietMealPlan>>>>{};
    final built = <DietStrategy>{};
    for (final st in [DietStrategy.lowCarb, DietStrategy.keto]) {
      plans[st] = {
        for (final a in _archetypes)
          a: [
            for (var s = 1; s <= _seeds; s++)
              () {
                final r = gen.generatePlan(DietPlanInputs(
                    calorieTarget: a.kcal,
                    proteinTarget: a.protein,
                    dietPreference: a.pref,
                    seed: s,
                    strategy: st,
                    carbTarget: _carbTarget(a, st)));
                built.add(r.builtFor);
                return r.meals;
              }(),
          ],
      };
    }
    final fallbacks = gen.lastFallbackCount - fallbacksBefore;

    test('zero fallbacks', () => expect(fallbacks, 0));

    test('every slot holds its strategy template', () {
      for (final st in plans.keys) {
        for (final e in plans[st]!.entries) {
          // Vegan Keto is built as Balanced (plan §3.3).
          final used = st == DietStrategy.keto && e.key.pref == 'vegan'
              ? DietStrategy.balanced
              : st;
          final templates = {
            for (final t in curatedTemplatesFor(used)) t.slotKey: t,
          };
          for (final plan in e.value) {
            expect(plan.map((m) => m.slotKey).toList(),
                ['breakfast', 'mid_morning', 'lunch', 'evening', 'dinner']);
            for (final m in plan) {
              final t = templates[m.slotKey]!;
              final roles = m.items.map((i) => i.role).toList();
              for (final r in t.required) {
                expect(roles.where((x) => x == r.name).length, 1,
                    reason: '$st ${e.key.label} ${m.name}: $roles');
              }
              for (final i in m.items) {
                expect(t.roles.map((r) => r.name), contains(i.role),
                    reason: '$st ${e.key.label} ${m.name}: ${i.name}');
              }
            }
          }
        }
      }
    });

    test('Keto: no grain, fruit or breakfast main; no item over the carb cap '
        '(non-vegan)', () {
      for (final e in plans[DietStrategy.keto]!.entries) {
        if (e.key.pref == 'vegan') continue;
        for (final plan in e.value) {
          for (final m in plan) {
            for (final i in m.items) {
              expect(
                  {DietRole.grain.name, DietRole.fruit.name,
                      DietRole.breakfastMain.name},
                  isNot(contains(i.role)),
                  reason: '${e.key.label} ${m.name}: ${i.name}');
              final entry = entryOf[i.foodId]!;
              final minCarbs = (byId[i.foodId]!['carbs_std'] as num) *
                  entry.portions.reduce(min);
              expect(minCarbs, lessThanOrEqualTo(kKetoItemCarbCap),
                  reason: '${e.key.label}: ${i.name}');
            }
          }
        }
      }
    });

    test('family caps hold with the Low carb override; no id twice', () {
      for (final st in plans.keys) {
        for (final e in plans[st]!.entries) {
          for (final plan in e.value) {
            final ids = [for (final m in plan) for (final i in m.items) i.foodId];
            expect(ids.toSet().length, ids.length);
            final counts = <DietFamily, int>{};
            for (final id in ids) {
              final f = entryOf[id]!.family;
              counts[f] = (counts[f] ?? 0) + 1;
            }
            counts.forEach((f, n) {
              final cap =
                  dietFamilyLowCarbCapOverride[f] ?? dietFamilyDailyCap[f];
              if (cap != null) {
                expect(n, lessThanOrEqualTo(cap),
                    reason: '$st ${e.key.label}: $f x$n');
              }
            });
          }
        }
      }
    });

    // The CONTRACT floors (measured on the built code 2026-11-14; minimum
    // over 50 seeds minus 0.02, raise only). Carbs: mean <= 1.25 x target.
    // Per archetype: measured minimum over 50 seeds on the built code
    // (2026-11-14) minus 0.02. Raise only.
    const floors = <String, (double, double)>{
      'DietStrategy.lowCarb cut male non-veg': (0.90, 0.70),
      'DietStrategy.lowCarb cut male veg': (0.83, 0.42),
      'DietStrategy.lowCarb cut female veg': (0.85, 0.38),
      'DietStrategy.lowCarb cut female non-veg': (0.90, 0.66),
      'DietStrategy.lowCarb cut vegan': (0.69, 0.43),
      'DietStrategy.lowCarb recomp non-veg': (0.87, 0.55),
      'DietStrategy.lowCarb maintain veg': (0.78, 0.56),
      'DietStrategy.lowCarb maintain vegan': (0.69, 0.71),
      'DietStrategy.lowCarb build non-veg': (0.82, 0.80),
      'DietStrategy.lowCarb build veg': (0.71, 0.56),
      'DietStrategy.lowCarb 1200 floor veg': (0.90, 0.42),
      'DietStrategy.lowCarb 1200 floor non-veg': (0.90, 0.59),
      'DietStrategy.lowCarb cut male eggetarian': (0.87, 0.51),
      'DietStrategy.lowCarb cut female pescatarian': (0.89, 0.67),
      'DietStrategy.lowCarb maintain eggetarian': (0.79, 0.59),
      'DietStrategy.lowCarb maintain pescatarian': (0.81, 0.74),
      'DietStrategy.keto cut male non-veg': (0.87, 0.87),
      'DietStrategy.keto cut male veg': (0.80, 0.51),
      'DietStrategy.keto cut female veg': (0.82, 0.59),
      'DietStrategy.keto cut female non-veg': (0.90, 0.89),
      'DietStrategy.keto recomp non-veg': (0.83, 0.70),
      'DietStrategy.keto maintain veg': (0.73, 0.63),
      'DietStrategy.keto build non-veg': (0.72, 0.92),
      'DietStrategy.keto build veg': (0.66, 0.65),
      'DietStrategy.keto 1200 floor veg': (0.87, 0.52),
      'DietStrategy.keto 1200 floor non-veg': (0.91, 0.81),
      'DietStrategy.keto cut male eggetarian': (0.85, 0.61),
      'DietStrategy.keto cut female pescatarian': (0.88, 0.79),
      'DietStrategy.keto maintain eggetarian': (0.76, 0.72),
      'DietStrategy.keto maintain pescatarian': (0.76, 0.68),
    };
    test('calories, protein and carbs per archetype', () {
      final rows = <({String label, double kMin, double pMin, double cMean})>[];
      for (final st in plans.keys) {
        for (final e in plans[st]!.entries) {
          final a = e.key;
          // Vegan Keto: the defensive generator mapping only (the screen
          // requests Low carb with the Low carb target, plan §3.5, which is
          // the Low carb row). T11 pins its builtFor.
          if (st == DietStrategy.keto && a.pref == 'vegan') continue;
          final ct = _carbTarget(a, st);
          final kr = <double>[], pr = <double>[], cr = <double>[];
          for (final plan in e.value) {
            var k = 0.0, p = 0.0, c = 0.0;
            for (final m in plan) {
              for (final i in m.items) {
                k += i.calories;
                p += i.protein;
                c += i.carbs;
              }
            }
            kr.add(k / a.kcal);
            pr.add(p / a.protein);
            cr.add(c / ct);
          }
          rows.add((
            label: '$st ${a.label}',
            kMin: kr.reduce(min),
            pMin: pr.reduce(min),
            cMean: cr.reduce((x, y) => x + y) / cr.length,
          ));
        }
      }
      // ignore: avoid_print
      print([
        for (final r in rows)
          '${r.label}: kcal min ${r.kMin.toStringAsFixed(2)} protein min '
              '${r.pMin.toStringAsFixed(2)} carbs mean '
              '${r.cMean.toStringAsFixed(2)}',
      ].join('\n'));
      expect(rows.map((r) => r.label).toSet(), floors.keys.toSet());
      for (final r in rows) {
        final f = floors[r.label]!;
        expect(r.kMin, greaterThanOrEqualTo(f.$1), reason: r.label);
        expect(r.pMin, greaterThanOrEqualTo(f.$2), reason: r.label);
        expect(r.cMean, lessThanOrEqualTo(1.25), reason: r.label);
      }
    });

    test('every Low carb / Keto only food is reachable (round 3 finding 2)',
        () {
      final seen = <String>{};
      for (final st in plans.keys) {
        for (final e in plans[st]!.entries) {
          for (final plan in e.value) {
            for (final m in plan) {
              for (final i in m.items) {
                seen.add(i.foodId);
              }
            }
          }
        }
      }
      expect(_lowCarbIds.difference(seen), isEmpty);
      // ... and every non-fat one is reachable in Keto itself.
      final keto = <String>{
        for (final e in plans[DietStrategy.keto]!.entries)
          if (e.key.pref != 'vegan')
            for (final plan in e.value)
              for (final m in plan)
                for (final i in m.items) i.foodId,
      };
      expect(_lowCarbIds.difference(keto), isEmpty);
    });

    test('no Low carb / Keto only food in a Balanced plan', () {
      final g = CuratedDietPlanGenerator.forTest(repo);
      for (final a in _archetypes) {
        for (var s = 1; s <= _seeds; s++) {
          for (final m in g.generate(DietPlanInputs(
              calorieTarget: a.kcal,
              proteinTarget: a.protein,
              dietPreference: a.pref,
              seed: s))) {
            for (final i in m.items) {
              expect(_lowCarbIds, isNot(contains(i.foodId)),
                  reason: '${a.label} ${m.name}');
            }
          }
        }
      }
    });
  });

  group('T11 generatePlan builtFor', () {
    final gen = CuratedDietPlanGenerator.forTest(repo);
    DietStrategy builtFor(DietStrategy s, double? carbs, String pref) =>
        gen.generatePlan(DietPlanInputs(
                calorieTarget: 2000,
                proteinTarget: 144,
                dietPreference: pref,
                seed: 1,
                strategy: s,
                carbTarget: carbs))
            .builtFor;

    test('the strategy asked for when it can be built', () {
      expect(builtFor(DietStrategy.balanced, null, 'non-veg'),
          DietStrategy.balanced);
      expect(builtFor(DietStrategy.lowCarb, 100, 'non-veg'),
          DietStrategy.lowCarb);
      expect(builtFor(DietStrategy.keto, 25, 'veg'), DietStrategy.keto);
    });

    test('no carb target -> Balanced, and the Balanced plan itself', () {
      for (final c in [null, 0.0, -5.0]) {
        expect(builtFor(DietStrategy.keto, c, 'non-veg'),
            DietStrategy.balanced);
      }
      final asked = gen.generate(const DietPlanInputs(
          calorieTarget: 2000,
          proteinTarget: 144,
          dietPreference: 'non-veg',
          seed: 3,
          strategy: DietStrategy.keto));
      final balanced = gen.generate(const DietPlanInputs(
          calorieTarget: 2000,
          proteinTarget: 144,
          dietPreference: 'non-veg',
          seed: 3));
      expect(asked.map((m) => m.items.map((i) => i.foodId).toList()).toList(),
          balanced.map((m) => m.items.map((i) => i.foodId).toList()).toList());
    });

    test('vegan Keto (with only the Keto carb target) is built as Balanced, '
        'never a starved plan (round 3 finding 3)', () {
      final before = gen.lastFallbackCount;
      expect(builtFor(DietStrategy.keto, 23, 'vegan'), DietStrategy.balanced);
      expect(gen.lastFallbackCount, before);
      expect(builtFor(DietStrategy.lowCarb, 90, 'vegan'),
          DietStrategy.lowCarb);
    });

    test('a forced fallback reports Balanced', () {
      // A catalog with no main protein cannot fill lunch.
      final g = CuratedDietPlanGenerator.forTest(repo, catalog: [
        for (final e in kDietPlanCatalog)
          if (!e.roles.contains(DietRole.mainProtein)) e,
      ]);
      final r = g.generatePlan(const DietPlanInputs(
          calorieTarget: 2000,
          proteinTarget: 144,
          dietPreference: 'non-veg',
          seed: 1,
          strategy: DietStrategy.keto,
          carbTarget: 25));
      expect(r.builtFor, DietStrategy.balanced);
      expect(g.lastFallbackCount, 1);
    });
  });

  group('T12 strategy swap', () {
    final gen = CuratedDietPlanGenerator.forTest(repo);
    test('Keto alternatives respect the cap and resolve fat without a role',
        () {
      final plan = gen.generate(const DietPlanInputs(
          calorieTarget: 2000,
          proteinTarget: 144,
          dietPreference: 'non-veg',
          seed: 2,
          strategy: DietStrategy.keto,
          carbTarget: 25));
      final ids = [for (final m in plan) for (final i in m.items) i.foodId];
      var fatSeen = false;
      for (final m in plan) {
        for (var k = 0; k < m.items.length; k++) {
          final it = m.items[k];
          // A loaded saved plan has no role: resolve through the Keto
          // templates (round 1 finding 4).
          final role = resolveSwapRole(
              foodId: it.foodId,
              category: it.category,
              role: null,
              slotKey: m.slotKey,
              strategy: DietStrategy.keto);
          expect(role, isNotNull, reason: '${m.name}: ${it.name}');
          if (it.role == DietRole.fat.name) {
            expect(role, DietRole.fat, reason: it.name);
            fatSeen = true;
          }
          final alts = swapAlternatives(
              foodId: it.foodId,
              category: it.category,
              calories: it.calories,
              role: null,
              slotKey: m.slotKey,
              dietPreference: 'non-veg',
              planFoodIds: ids,
              slotOtherNames: [
                for (var j = 0; j < m.items.length; j++)
                  if (j != k) m.items[j].name,
              ],
              repo: repo,
              strategy: DietStrategy.keto);
          for (final a in alts) {
            final e = entryOf[a.foodId]!;
            expect(
                (byId[a.foodId]!['carbs_std'] as num) * e.portions.reduce(min),
                lessThanOrEqualTo(kKetoItemCarbCap),
                reason: '${m.name}: ${it.name} -> ${a.name}');
          }
        }
      }
      expect(fatSeen, isTrue, reason: 'precondition: the plan has a fat item');
    });

    test('Balanced never resolves fat and never offers a Low carb only food',
        () {
      expect(
          resolveSwapRole(
              foodId: 'F0402', category: 'dairy', role: null, slotKey: 'lunch'),
          isNot(DietRole.fat));
      final alts = swapAlternatives(
          foodId: 'F0019',
          category: 'protein',
          calories: 165,
          role: DietRole.mainProtein.name,
          slotKey: 'lunch',
          dietPreference: 'non-veg',
          planFoodIds: const ['F0019'],
          slotOtherNames: const [],
          repo: repo,
          limit: 100);
      expect(alts.map((a) => a.foodId).toSet().intersection(_lowCarbIds),
          isEmpty);
    });
  });
}
