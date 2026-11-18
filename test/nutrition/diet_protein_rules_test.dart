// test/nutrition/diet_protein_rules_test.dart
//
// Diet protein rules (2026-11-18, docs/plans/diet-protein-rules.md): a Non-veg,
// eggetarian or pescatarian plan must contain its protein. Real asset, real
// generator, 100 seeds per profile and strategy (the measured baseline is in
// the plan §2, 300 seeds: 16 % (Maintain) to 28 % (Build) of Non-veg plans had
// a vegetarian lunch AND dinner; 30-34 % of eggetarian days had no egg; 2-48 %
// of pescatarian days no fish).
//
//   R1 slotNeedsFor, pure: exact sets, combination bands, draw order replay,
//      exact draw counts (Veg / Vegan / pescatarian draw nothing)
//   R2 generated plans: the rule holds in EVERY plan, per food type, over every
//      strategy (Balanced, Low carb, Keto), no legacy fallback, caps are
//      INDEPENDENT literals (dietFamilyCapFor is not its own oracle)
//   R3 swap: the food-type caps reach the swap, a saved Surmai item still counts
//   R4 catalog pins: the egg dishes hold the lunch / dinner role, the Keto egg
//      pool, Surmai's family survives for a saved plan
//
// Mutants (plan §6), each confirmed applied with grep -c: M1 no eggetarian cap
// override; M2 pescatarian need unrestricted; M3 single-slot Non-veg
// combination; M4 Veg draws an rng value; M5 swap ignores foodType; M6 F0362
// back in the catalog; M7a empty retired map; M7b swap without the retired
// fallback; M9 Non-veg L/D set loses fish; M10 mutton coin always true; M11
// nextInt(3); M8' eggetarian breakfast need admits dairy.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_slot_needs.dart';
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

class _Profile {
  final String label;
  final int kcal;
  final int protein;
  const _Profile(this.label, this.kcal, this.protein);
}

const _profiles = [
  _Profile('cut 2000/144', 2000, 144),
  _Profile('maintain 2400/128', 2400, 128),
  _Profile('build 2700/126', 2700, 126),
  _Profile('female 1500/110', 1500, 110),
];

const _strategies = [
  DietStrategy.balanced,
  DietStrategy.lowCarb,
  DietStrategy.keto,
];

const _seeds = 100;

/// Carb target for a profile (the same derivation the strategy tests use).
double? _carbTarget(_Profile p, DietStrategy s) => s == DietStrategy.balanced
    ? null
    : BmrCalculator.macroSplit(
        dailyCalories: p.kcal.toDouble(),
        proteinGrams: p.protein.toDouble(),
        balancedCarbs: (p.kcal - 4 * p.protein - 0.25 * p.kcal) / 4,
        strategy: s,
      ).carbGrams.toDouble();

const _meat = {DietFamily.chicken, DietFamily.fish, DietFamily.mutton};

/// The catalog families of one slot's items (the plan's own item ids).
List<DietFamily> _families(List<DietMealPlan> plan, String slotKey) => [
  for (final m in plan)
    if (m.slotKey == slotKey)
      for (final i in m.items)
        if (dietCatalogFamily(i.foodId) != null) dietCatalogFamily(i.foodId)!,
];

int _count(List<DietMealPlan> plan, DietFamily f) => [
  for (final m in plan)
    for (final i in m.items)
      if (dietCatalogFamily(i.foodId) == f) i,
].length;

/// What the pure function SHOULD return for [foodType] and [seed], replayed by
/// hand from `Random(seed)` (the draw order documented in the source).
Map<String, Set<DietFamily>> _replay(FoodType foodType, int seed) {
  final r = Random(seed);
  switch (foodType) {
    case FoodType.nonVeg:
      final c = r.nextInt(4); // 0 B+L, 1 B+D, 2 L+D, 3 B+L+D
      final out = <String, Set<DietFamily>>{};
      if (c != 2) out['breakfast'] = {DietFamily.egg};
      if (c != 1) {
        final mutton = r.nextBool();
        out['lunch'] = {
          DietFamily.chicken,
          DietFamily.fish,
          DietFamily.egg,
          if (mutton) DietFamily.mutton,
        };
      }
      if (c != 0) {
        final mutton = r.nextBool();
        out['dinner'] = {
          DietFamily.chicken,
          DietFamily.fish,
          DietFamily.egg,
          if (mutton) DietFamily.mutton,
        };
      }
      return out;
    case FoodType.eggetarian:
      final lunch = r.nextBool();
      return {
        'breakfast': {DietFamily.egg},
        lunch ? 'lunch' : 'dinner': {DietFamily.egg},
      };
    case FoodType.pescatarian:
      return {
        'lunch': {DietFamily.fish},
        'dinner': {DietFamily.fish},
      };
    case FoodType.veg:
    case FoodType.vegan:
      return {};
  }
}

void main() {
  final rows =
      (jsonDecode(File('assets/data/food_database.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final repo = _Repo(rows);
  final byId = {for (final r in rows) r['id'] as String: r};

  group('R1 slotNeedsFor (pure)', () {
    test('Non-veg: exact sets, the four combinations in 25 % +/- 4 %, mutton '
        'in 40-60 % of L/D needs', () {
      const n = 2000;
      final combos = <String, int>{};
      var needsLd = 0, needsWithMutton = 0;
      for (var seed = 1; seed <= n; seed++) {
        final needs = slotNeedsFor(FoodType.nonVeg, Random(seed));
        final key = (needs.keys.toList()..sort()).join('+');
        combos[key] = (combos[key] ?? 0) + 1;
        if (needs.containsKey('breakfast')) {
          expect(needs['breakfast'], {DietFamily.egg});
        }
        for (final slot in ['lunch', 'dinner']) {
          final set = needs[slot];
          if (set == null) continue;
          needsLd++;
          expect(
            set.containsAll({
              DietFamily.chicken,
              DietFamily.fish,
              DietFamily.egg,
            }),
            isTrue,
            reason: '$slot $set',
          );
          expect(
            set.difference({
              DietFamily.chicken,
              DietFamily.fish,
              DietFamily.egg,
              DietFamily.mutton,
            }),
            isEmpty,
          );
          if (set.contains(DietFamily.mutton)) needsWithMutton++;
        }
      }
      // The four combinations, each 25 % +/- 4 % (about 4 sd at n = 2000).
      expect(combos.keys.toSet(), {
        'breakfast+lunch',
        'breakfast+dinner',
        'dinner+lunch',
        'breakfast+dinner+lunch',
      });
      combos.forEach((k, v) {
        expect(v / n, inInclusiveRange(0.21, 0.29), reason: '$k $v/$n');
      });
      expect(needsWithMutton / needsLd, inInclusiveRange(0.40, 0.60));
    });

    test('eggetarian: egg at breakfast and at ONE of lunch / dinner (40-60 % '
        'each)', () {
      const n = 2000;
      var lunch = 0;
      for (var seed = 1; seed <= n; seed++) {
        final needs = slotNeedsFor(FoodType.eggetarian, Random(seed));
        expect(needs['breakfast'], {DietFamily.egg});
        final second = needs.keys.where((k) => k != 'breakfast').toList();
        expect(second.length, 1);
        expect(needs[second.single], {DietFamily.egg});
        expect(second.single, anyOf('lunch', 'dinner'));
        if (second.single == 'lunch') lunch++;
      }
      expect(lunch / n, inInclusiveRange(0.40, 0.60));
    });

    test('pescatarian: fish at lunch and dinner, nothing at breakfast', () {
      final needs = slotNeedsFor(FoodType.pescatarian, Random(1));
      expect(needs, {
        'lunch': {DietFamily.fish},
        'dinner': {DietFamily.fish},
      });
    });

    test('Veg and Vegan: the empty map', () {
      expect(slotNeedsFor(FoodType.veg, Random(1)), isEmpty);
      expect(slotNeedsFor(FoodType.vegan, Random(1)), isEmpty);
    });

    test(
      'ORACLE REPLAY: the draw order (mapping 0..3, mutton coin lunch '
      'before dinner, true = lunch) equals a by-hand replay of Random(seed)',
      () {
        for (final t in [
          FoodType.nonVeg,
          FoodType.eggetarian,
          FoodType.pescatarian,
          FoodType.veg,
          FoodType.vegan,
        ]) {
          for (var seed = 1; seed <= 300; seed++) {
            final actual = slotNeedsFor(t, Random(seed));
            final expected = _replay(t, seed);
            expect(
              actual.keys.toSet(),
              expected.keys.toSet(),
              reason: '$t seed $seed',
            );
            expected.forEach((slot, set) {
              expect(actual[slot], set, reason: '$t seed $seed $slot');
            });
          }
        }
      },
    );

    test('exact draw counts: Veg, Vegan and pescatarian consume NO rng value; '
        'Non-veg 2 or 3; eggetarian 1', () {
      for (var seed = 1; seed <= 200; seed++) {
        for (final t in [FoodType.veg, FoodType.vegan, FoodType.pescatarian]) {
          final a = Random(seed);
          slotNeedsFor(t, a);
          expect(
            a.nextInt(1 << 30),
            Random(seed).nextInt(1 << 30),
            reason: '$t seed $seed must not draw',
          );
        }
        final egg = Random(seed);
        slotNeedsFor(FoodType.eggetarian, egg);
        final eggRef = Random(seed)..nextBool();
        expect(egg.nextInt(1 << 30), eggRef.nextInt(1 << 30));

        final nv = Random(seed);
        final needs = slotNeedsFor(FoodType.nonVeg, nv);
        final ref = Random(seed)..nextInt(4);
        final ld = needs.keys.where((k) => k != 'breakfast').length;
        for (var i = 0; i < ld; i++) {
          ref.nextBool();
        }
        expect(
          nv.nextInt(1 << 30),
          ref.nextInt(1 << 30),
          reason: 'Non-veg seed $seed draws 1 + $ld values',
        );
      }
    });
  });

  group('R2 generated plans meet their rule', () {
    for (final entry in <FoodType, String>{
      FoodType.nonVeg: 'non_veg',
      FoodType.eggetarian: 'eggetarian',
      FoodType.pescatarian: 'pescatarian',
    }.entries) {
      test('${entry.value}: every plan, every profile, every strategy', () {
        final gen = CuratedDietPlanGenerator.forTest(repo);
        var checked = 0;
        for (final p in _profiles) {
          for (final st in _strategies) {
            for (var seed = 1; seed <= _seeds; seed++) {
              final plan = gen
                  .generatePlan(
                    DietPlanInputs(
                      calorieTarget: p.kcal,
                      proteinTarget: p.protein,
                      dietPreference: entry.value,
                      seed: seed,
                      strategy: st,
                      carbTarget: _carbTarget(p, st),
                    ),
                  )
                  .meals;
              final why = '${entry.value} ${p.label} ${st.name} seed $seed';
              final ids = [
                for (final m in plan)
                  for (final i in m.items) i.foodId,
              ];
              expect(
                ids.toSet().length,
                ids.length,
                reason: '$why repeats $ids',
              );
              expect(
                ids.contains('F0362'),
                isFalse,
                reason: '$why holds Surmai',
              );
              final b = _families(plan, 'breakfast');
              final l = _families(plan, 'lunch');
              final d = _families(plan, 'dinner');
              // chicken / fish / mutton only have the lunch / dinner role.
              expect(
                b.where(_meat.contains),
                isEmpty,
                reason: '$why breakfast',
              );

              switch (entry.key) {
                case FoodType.nonVeg:
                  final meals = [b, l, d]
                      .where(
                        (fs) => fs.any(
                          (f) => _meat.contains(f) || f == DietFamily.egg,
                        ),
                      )
                      .length;
                  expect(
                    meals,
                    greaterThanOrEqualTo(2),
                    reason: '$why: $b $l $d',
                  );
                  // independent literal caps
                  expect(
                    _count(plan, DietFamily.egg),
                    lessThanOrEqualTo(1),
                    reason: why,
                  );
                  expect(
                    _count(plan, DietFamily.fish),
                    lessThanOrEqualTo(1),
                    reason: why,
                  );
                  expect(
                    _count(plan, DietFamily.chicken),
                    lessThanOrEqualTo(1),
                    reason: why,
                  );
                  expect(
                    _count(plan, DietFamily.mutton),
                    lessThanOrEqualTo(1),
                    reason: why,
                  );
                case FoodType.eggetarian:
                  expect(
                    b.contains(DietFamily.egg),
                    isTrue,
                    reason: '$why breakfast',
                  );
                  expect(
                    l.contains(DietFamily.egg) || d.contains(DietFamily.egg),
                    isTrue,
                    reason: '$why lunch/dinner',
                  );
                  expect(
                    _count(plan, DietFamily.egg),
                    lessThanOrEqualTo(2),
                    reason: why,
                  );
                  expect(_count(plan, DietFamily.fish), 0, reason: why);
                case FoodType.pescatarian:
                  expect(
                    l.contains(DietFamily.fish),
                    isTrue,
                    reason: '$why lunch',
                  );
                  expect(
                    d.contains(DietFamily.fish),
                    isTrue,
                    reason: '$why dinner',
                  );
                  expect(
                    _count(plan, DietFamily.fish),
                    lessThanOrEqualTo(2),
                    reason: why,
                  );
                  expect(
                    _count(plan, DietFamily.egg),
                    lessThanOrEqualTo(1),
                    reason: why,
                  );
                  expect(
                    _count(plan, DietFamily.chicken) +
                        _count(plan, DietFamily.mutton),
                    0,
                    reason: why,
                  );
                case FoodType.veg:
                case FoodType.vegan:
                  break;
              }
              checked++;
            }
          }
        }
        expect(checked, _profiles.length * _strategies.length * _seeds);
        expect(
          gen.lastFallbackCount,
          0,
          reason: 'a need could not be met: the legacy generator ran',
        );
      });
    }
  });

  group('R3 swap', () {
    // A dinner main protein (a dal) to replace; the plan around it is
    // hand-built so the cap, not the random plan, is what is tested.
    const dal = 'F0011';
    List<String> alts(String pref, List<String> planIds) {
      final row = byId[dal]!;
      return [
        for (final i in swapAlternatives(
          foodId: dal,
          category: row['category'] as String,
          calories: (row['calories_std'] as num).round(),
          role: 'mainProtein',
          slotKey: 'dinner',
          dietPreference: pref,
          planFoodIds: [...planIds, dal],
          slotOtherNames: const [],
          repo: repo,
          limit: 60,
        ))
          i.foodId,
      ];
    }

    bool hasFamily(List<String> ids, DietFamily f) =>
        ids.any((id) => dietCatalogFamily(id) == f);

    test('eggetarian sees egg cap 2, Non-veg cap 1, for the same plan', () {
      final plan = ['F0021']; // one egg at breakfast
      expect(hasFamily(alts('eggetarian', plan), DietFamily.egg), isTrue);
      expect(hasFamily(alts('non-veg', plan), DietFamily.egg), isFalse);
      // a second egg item fills the eggetarian cap too
      expect(
        hasFamily(alts('eggetarian', ['F0021', 'F0370']), DietFamily.egg),
        isFalse,
      );
    });

    test('pescatarian sees fish cap 2, Non-veg cap 1; never a third fish', () {
      expect(
        hasFamily(alts('pescatarian', ['F0358']), DietFamily.fish),
        isTrue,
      );
      expect(hasFamily(alts('non-veg', ['F0358']), DietFamily.fish), isFalse);
      expect(
        hasFamily(alts('pescatarian', ['F0358', 'F0357']), DietFamily.fish),
        isFalse,
      );
    });

    test('a saved Surmai item (out of the catalog) still counts toward the '
        'fish cap', () {
      expect(
        hasFamily(alts('pescatarian', ['F0362', 'F0358']), DietFamily.fish),
        isFalse,
        reason: 'Surmai + Rohu = 2 fish: no third',
      );
      expect(
        hasFamily(alts('pescatarian', ['F0362']), DietFamily.fish),
        isTrue,
      );
    });

    test('the swap never offers Surmai', () {
      for (final pref in ['pescatarian', 'non-veg']) {
        expect(alts(pref, ['F0358']).contains('F0362'), isFalse);
      }
    });
  });

  group('R4 catalog pins', () {
    test('the three egg dishes hold the lunch / dinner role; the boiled egg '
        'keeps breakfast and snack', () {
      final byFood = {for (final e in kDietPlanCatalog) e.foodId: e};
      for (final id in ['F0341', 'F0344', 'F0021']) {
        expect(byFood[id]!.roles, contains(DietRole.mainProtein), reason: id);
        expect(
          byFood[id]!.roles,
          contains(DietRole.breakfastProtein),
          reason: id,
        );
      }
      expect(byFood['F0021']!.roles, contains(DietRole.snack));
    });

    test(
      'Keto: the egg main-protein pool is F0021, F0341, F0344 plus the two '
      'Low carb / Keto only egg dishes F0371 and F0790 (Anda Masala is over '
      'the carb cap), and those two are never offered to a Balanced plan',
      () {
        final byFood = {for (final e in kDietPlanCatalog) e.foodId: e};
        for (final id in ['F0371', 'F0790']) {
          expect(byFood[id]!.lowCarbOnly, isTrue, reason: id);
          expect(
            byFood[id]!.roles,
            containsAll([DietRole.breakfastProtein, DietRole.mainProtein]),
            reason: id,
          );
        }
        final inKeto = <String>{};
        for (var i = 0; i < kDietPlanCatalog.length; i++) {
          final e = kDietPlanCatalog[i];
          if (e.family != DietFamily.egg ||
              !e.roles.contains(DietRole.mainProtein) ||
              e.lowCarbPlansOnly ||
              e.swapOnly) {
            continue;
          }
          final c = CuratedCandidate(e, byId[e.foodId]!, i);
          if (c.carbs * e.portions.reduce(min) <= kKetoItemCarbCap) {
            inKeto.add(e.foodId);
          }
        }
        expect(inKeto, {'F0021', 'F0341', 'F0344', 'F0371', 'F0790'});
      },
    );

    test(
      'a pescatarian can still load a plan saved BEFORE Unit 2a that holds '
      'Surmai (no food_type stamp): the family survives in the retired map',
      () {
        final plan = {
          'meals': [
            {
              'items': [
                {'food_id': 'F0362'},
              ],
            },
          ],
        };
        expect(
          savedPlanMatchesFoodType(
            plan,
            FoodType.pescatarian,
            rowOf: (id) => byId[id],
          ),
          isTrue,
        );
        // and it still does not load for a vegetarian
        expect(
          savedPlanMatchesFoodType(plan, FoodType.veg, rowOf: (id) => byId[id]),
          isFalse,
        );
      },
    );

    test('the pescatarian fish pool is the 5 remaining dishes', () {
      final fish = {
        for (final e in kDietPlanCatalog)
          if (e.family == DietFamily.fish &&
              e.roles.contains(DietRole.mainProtein) &&
              !e.lowCarbOnly &&
              !e.swapOnly)
            e.foodId,
      };
      expect(fish, {'F0024', 'F0358', 'F0357', 'F0367', 'F0327'});
    });
  });
}
