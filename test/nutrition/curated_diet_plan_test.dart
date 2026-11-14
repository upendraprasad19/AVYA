// test/nutrition/curated_diet_plan_test.dart
//
// Diet plan Unit 1 (2026-11-14, docs/plans/diet-food-quality.md §4): the
// curated catalog + template generator + catalog-only swap, run against the
// REAL bundled food database (the curated fixture of the legacy tests cannot
// see real-data leaks — d3c7a9 lesson).
//
//   T1 catalog integrity          T6 determinism
//   T2 template shape (+ v3 box)  T7 serving descriptions
//   T3 variety / family caps      T8 processed foods
//   T4 diet purity                T9 swap alternatives
//   T5 macro / fiber bands (the floors are the CONTRACT: an implementation
//      change may raise them, never lower them — fix K/weights/catalog instead)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

List<Map<String, dynamic>> _loadAsset() =>
    (jsonDecode(File('assets/data/food_database.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();

/// The asset as a device whose v4 re-seed failed would hold it (round 2
/// finding 8): no new rows, no is_everyday, the v3 UPF tags.
List<Map<String, dynamic>> _v3Rows(List<Map<String, dynamic>> v4) {
  const newIds = {'F1442', 'F1443', 'F1444', 'F1445', 'F1446', 'F1447', 'F1448'};
  return [
    for (final r in v4)
      if (!newIds.contains(r['id']))
        {
          for (final e in r.entries)
            if (e.key != 'is_everyday') e.key: e.value,
          if (r['id'] == 'F0522') 'is_ultra_processed': false,
          if (r['id'] == 'F0708' || r['id'] == 'F0710')
            'is_ultra_processed': true,
        },
  ];
}

class _Archetype {
  final String label;
  final int kcal;
  final int protein;
  final String pref;
  final double proteinMinFloor;
  final double proteinMeanFloor;
  const _Archetype(this.label, this.kcal, this.protein, this.pref,
      this.proteinMinFloor, this.proteinMeanFloor);
}

// Plan §4 T5 table. Realistic BmrCalculator outputs (cut 2.0 g/kg of goal
// weight, maintain 1.6, build 1.8).
const _archetypes = [
  _Archetype('cut male non-veg', 2000, 144, 'non-veg', 0.82, 0.90),
  _Archetype('cut male veg', 2000, 144, 'veg', 0.70, 0.78),
  _Archetype('cut female veg', 1500, 110, 'veg', 0.66, 0.75),
  _Archetype('cut female non-veg', 1500, 110, 'non-veg', 0.78, 0.88),
  _Archetype('cut vegan', 1800, 130, 'vegan', 0.68, 0.77),
  _Archetype('recomp non-veg', 2200, 160, 'non-veg', 0.84, 0.88),
  _Archetype('maintain veg', 2400, 128, 'veg', 0.90, 0.93),
  _Archetype('maintain vegan', 2200, 110, 'vegan', 0.90, 0.93),
  _Archetype('build non-veg', 2700, 126, 'non-veg', 0.90, 0.93),
  _Archetype('build veg', 3000, 150, 'veg', 0.90, 0.93),
  _Archetype('1200 floor veg', 1200, 100, 'veg', 0.50, 0.62),
  _Archetype('1200 floor non-veg', 1200, 100, 'non-veg', 0.58, 0.78),
];

const _seeds = 50;

void main() {
  final rows = _loadAsset();
  final byId = {for (final r in rows) r['id'] as String: r};
  final repo = _Repo(rows);
  final catalogIds = {for (final e in kDietPlanCatalog) e.foodId};

  // Generate the whole matrix once; most tests read it.
  final gen = CuratedDietPlanGenerator.forTest(repo);
  final plans = <_Archetype, List<List<DietMealPlan>>>{
    for (final a in _archetypes)
      a: [
        for (var s = 1; s <= _seeds; s++)
          gen.generate(DietPlanInputs(
            calorieTarget: a.kcal,
            proteinTarget: a.protein,
            dietPreference: a.pref,
            seed: s,
          )),
      ],
  };
  final fallbacksAfterMatrix = gen.lastFallbackCount;

  group('T1 catalog integrity', () {
    test('every id exists, non-UPF, everyday; >= 150 unique; tag mirrors catalog', () {
      expect(catalogIds.length, greaterThanOrEqualTo(150));
      for (final id in catalogIds) {
        final r = byId[id];
        expect(r, isNotNull, reason: '$id missing from the asset');
        expect(r!['is_ultra_processed'], isFalse, reason: '$id ${r['name']} is UPF');
        expect(r['is_everyday'], isTrue, reason: '$id ${r['name']} not everyday');
        expect(r['source'], isNot('openfoodfacts_india_v2'), reason: id);
      }
      final everyday = rows.where((r) => r['is_everyday'] == true).length;
      expect(everyday, catalogIds.length,
          reason: 'is_everyday must mirror the catalog exactly (re-run '
              'scripts/patch_food_database_v4.dart after a catalog edit)');
    });

    test('categories: everyday food groups, plus four named exceptions', () {
      const allowed = {
        'staples', 'pulses', 'protein', 'dairy', 'vegetables', 'fruits',
        'nuts_seeds',
      };
      const exceptions = {'F0708', 'F0710', 'F0303', 'F0327'};
      for (final id in catalogIds) {
        final cat = byId[id]!['category'] as String;
        expect(allowed.contains(cat) || exceptions.contains(id), isTrue,
            reason: '$id ${byId[id]!['name']} has category $cat');
      }
    });

    test('no fats, herbs, sambar/rasam sides, packaged bread', () {
      const banned = {
        'F0402', 'F0403', 'F0404', 'F0405', // ghee / butter
        'F0284', 'F0285', 'F0291', 'F0292', 'F0293', // garlic, ginger, herbs
        'F0187', 'F0188', // sambar, rasam (were sides)
        'F0255', // drumstick sambar (dal + sambar meals)
        'F0921', 'F1300', 'F1420', // packaged bread
      };
      expect(catalogIds.intersection(banned), isEmpty);
    });

    test('no two entries share identical std macros within a category', () {
      final seen = <String, String>{};
      for (final id in catalogIds) {
        final r = byId[id]!;
        final key = '${r['category']}|${r['calories_std']}|${r['protein_std']}|'
            '${r['carbs_std']}|${r['fat_std']}';
        expect(seen.containsKey(key), isFalse,
            reason: '$id ${r['name']} duplicates ${seen[key]}');
        seen[key] = '$id ${r['name']}';
      }
    });

    test('every entry has a role and a portion; ids are unique', () {
      final ids = <String>{};
      for (final e in kDietPlanCatalog) {
        expect(ids.add(e.foodId), isTrue, reason: 'duplicate ${e.foodId}');
        expect(e.roles, isNotEmpty);
        expect(e.portions, isNotEmpty);
        expect(e.portions.every((m) => m > 0), isTrue);
      }
    });

    test('the catalog file imports nothing (the asset script imports it)', () {
      final src = File('lib/features/nutrition/services/diet_plan_catalog.dart')
          .readAsStringSync();
      expect(RegExp(r'^\s*import ', multiLine: true).hasMatch(src), isFalse);
    });
  });

  group('T2 template shape', () {
    test('every slot holds its required roles plus at most its optional ones', () {
      final templates = {for (final t in kCuratedSlotTemplates) t.slotKey: t};
      for (final entry in plans.entries) {
        for (final plan in entry.value) {
          expect(plan.map((m) => m.slotKey).toList(),
              ['breakfast', 'mid_morning', 'lunch', 'evening', 'dinner']);
          for (final meal in plan) {
            final t = templates[meal.slotKey]!;
            final roles = meal.items.map((i) => i.role).toList();
            for (final r in t.required) {
              expect(roles.where((x) => x == r.name).length, 1,
                  reason: '${entry.key.label} ${meal.name}: $roles');
            }
            expect(meal.items.length,
                lessThanOrEqualTo(t.required.length + t.optional.length));
            for (final i in meal.items) {
              expect(t.roles.map((r) => r.name), contains(i.role));
              expect(catalogIds, contains(i.foodId));
              expect(i.category, isNot('beverages'));
              expect(
                  i.isAnchor,
                  i.role == DietRole.mainProtein.name ||
                      i.role == DietRole.breakfastProtein.name,
                  reason: 'isAnchor mapping for ${i.name}');
            }
            final grains =
                meal.items.where((i) => i.role == DietRole.grain.name).length;
            expect(grains,
                (meal.slotKey == 'lunch' || meal.slotKey == 'dinner') ? 1 : 0,
                reason: '${meal.name}: exactly one grain at lunch/dinner');
          }
        }
      }
      expect(fallbacksAfterMatrix, 0, reason: 'no archetype may hit the legacy fallback');
    });

    test('meal coherence: no shared key-ingredient word inside a meal', () {
      for (final entry in plans.entries) {
        for (final plan in entry.value) {
          for (final meal in plan) {
            final seen = <String>{};
            for (final i in meal.items) {
              final t = coherenceTokensOf(i.name);
              expect(t.intersection(seen), isEmpty,
                  reason: '${entry.key.label} ${meal.name}: '
                      '${meal.items.map((x) => x.name).toList()}');
              seen.addAll(t);
            }
          }
        }
      }
    });

    test('T2-v3: a device whose v4 re-seed failed still generates', () {
      final v3 = CuratedDietPlanGenerator.forTest(_Repo(_v3Rows(rows)));
      for (final a in _archetypes) {
        for (var s = 1; s <= 10; s++) {
          final plan = v3.generate(DietPlanInputs(
              calorieTarget: a.kcal,
              proteinTarget: a.protein,
              dietPreference: a.pref,
              seed: s));
          for (final m in plan) {
            for (final i in m.items) {
              expect(catalogIds, contains(i.foodId));
            }
          }
        }
      }
      expect(v3.lastFallbackCount, 0);
    });
  });

  group('T3 variety', () {
    test('no id twice a day; family caps hold', () {
      final familyOf = {for (final e in kDietPlanCatalog) e.foodId: e.family};
      for (final entry in plans.entries) {
        for (final plan in entry.value) {
          final ids = [for (final m in plan) for (final i in m.items) i.foodId];
          expect(ids.toSet().length, ids.length,
              reason: '${entry.key.label}: repeated id in $ids');
          final counts = <DietFamily, int>{};
          for (final id in ids) {
            counts[familyOf[id]!] = (counts[familyOf[id]!] ?? 0) + 1;
          }
          counts.forEach((f, n) {
            final cap = dietFamilyDailyCap[f];
            if (cap != null) {
              expect(n, lessThanOrEqualTo(cap),
                  reason: '${entry.key.label}: $f x$n');
            }
          });
        }
      }
    });

    test('lunch proteins vary across seeds', () {
      for (final a in _archetypes) {
        final lunchProteins = {
          for (final plan in plans[a]!)
            plan[2].items.firstWhere((i) => i.role == 'mainProtein').foodId,
        };
        expect(lunchProteins.length, greaterThanOrEqualTo(8),
            reason: '${a.label}: $lunchProteins');
      }
    });

    test('fixture: the soy cap alone prevents a double-soy day', () {
      // Two soy proteins + one dal: without the cap, lunch AND dinner would
      // often both be soy; with it, never.
      final fixture = <CatalogEntry>[
        for (final e in kDietPlanCatalog)
          if (e.roles.contains(DietRole.mainProtein))
            if (e.foodId == 'F0373' || e.foodId == 'F0018' || e.foodId == 'F0011')
              e
            else
              ...[]
          else
            e,
      ];
      final g = CuratedDietPlanGenerator.forTest(repo, catalog: fixture);
      const soy = {'F0373', 'F0018', 'F1014'};
      for (var s = 1; s <= 60; s++) {
        final plan = g.generate(DietPlanInputs(
            calorieTarget: 2200, proteinTarget: 140,
            dietPreference: 'veg', seed: s));
        final n = [for (final m in plan) for (final i in m.items) i.foodId]
            .where(soy.contains)
            .length;
        expect(n, lessThanOrEqualTo(1), reason: 'seed $s: $n soy items');
      }
    });
  });

  group('T4 diet purity', () {
    test('veg plans are all is_veg; vegan plans all is_vegan', () {
      for (final entry in plans.entries) {
        for (final plan in entry.value) {
          for (final m in plan) {
            for (final i in m.items) {
              final r = byId[i.foodId]!;
              if (entry.key.pref == 'veg') {
                expect(r['is_veg'], isTrue, reason: i.name);
              }
              if (entry.key.pref == 'vegan') {
                expect(r['is_vegan'], isTrue, reason: i.name);
              }
            }
          }
        }
      }
    });
  });

  group('T5 macro bands', () {
    test('calories, protein (min + mean) and fiber per archetype', () {
      final report = StringBuffer('\n');
      for (final a in _archetypes) {
        final kcalR = <double>[];
        final protR = <double>[];
        final fiber = <int>[];
        for (final plan in plans[a]!) {
          final k = plan.fold<int>(0, (s, m) => s + m.totalCalories);
          final p = plan.fold<int>(0, (s, m) => s + m.totalProtein);
          kcalR.add(k / a.kcal);
          protR.add(p / a.protein);
          fiber.add(plan.fold<int>(0, (s, m) => s + m.totalFiber));
        }
        double minOf(List<double> l) => l.reduce((x, y) => x < y ? x : y);
        double maxOf(List<double> l) => l.reduce((x, y) => x > y ? x : y);
        final mean = protR.reduce((x, y) => x + y) / protR.length;
        final fiberMin = fiber.reduce((x, y) => x < y ? x : y);
        report.writeln('${a.label.padRight(20)} kcal '
            '${minOf(kcalR).toStringAsFixed(2)}-${maxOf(kcalR).toStringAsFixed(2)}'
            '  protein ${minOf(protR).toStringAsFixed(2)}-'
            '${maxOf(protR).toStringAsFixed(2)} mean ${mean.toStringAsFixed(2)}'
            '  fiber min ${fiberMin}g');
        // ignore: avoid_print
        print(report.toString().trimRight().split('\n').last);
        final kcalHi = a.kcal <= 1200 ? 1.18 : 1.10;
        expect(minOf(kcalR), greaterThanOrEqualTo(0.92), reason: a.label);
        expect(maxOf(kcalR), lessThanOrEqualTo(kcalHi), reason: a.label);
        expect(minOf(protR), greaterThanOrEqualTo(a.proteinMinFloor),
            reason: a.label);
        expect(mean, greaterThanOrEqualTo(a.proteinMeanFloor), reason: a.label);
        if (a.kcal >= 1500) {
          expect(fiberMin, greaterThanOrEqualTo(21), reason: a.label);
        }
      }
    });
  });

  group('T6 determinism', () {
    test('same seed, same plan; seeds differ', () {
      List<String> sig(List<DietMealPlan> p) => [
            for (final m in p)
              for (final i in m.items) '${i.foodId}@${i.servingG}',
          ];
      final g2 = CuratedDietPlanGenerator.forTest(repo);
      const inputs = DietPlanInputs(
          calorieTarget: 2000, proteinTarget: 144,
          dietPreference: 'veg', seed: 7);
      expect(sig(g2.generate(inputs)), sig(g2.generate(inputs)));
      final distinct = {
        for (final plan in plans[_archetypes[1]]!.take(20)) sig(plan).join(','),
      };
      expect(distinct.length, greaterThanOrEqualTo(10));
    });

    test('dietPlanSeed: stable within a day, moves per regenerate', () {
      final morning = DateTime(2026, 11, 14, 8);
      final night = DateTime(2026, 11, 14, 22);
      expect(dietPlanSeed(morning, 0), dietPlanSeed(night, 0));
      expect(dietPlanSeed(morning, 1), isNot(dietPlanSeed(morning, 0)));
      expect(dietPlanSeed(morning, 2), isNot(dietPlanSeed(morning, 1)));
    });
  });

  group('T7 serving descriptions', () {
    test('fixed examples', () {
      const cases = <(String, double, String)>[
        ('1 roti', 3, '3 rotis'),
        ('1/2 cup', 1.5, '3/4 cup'),
        ('1 cup (2 eggs)', 2, '2 cups (4 eggs)'),
        ('1 omelette (2 eggs)', 2, '2 omelettes (4 eggs)'),
        ('100g', 1.5, '150g'),
        ('100 g', 0.5, '50 g'),
        ('2 idli', 1.5, '3 idli'),
        ('3 egg whites', 2, '6 egg whites'),
        ('1 masala dosa', 2, '2 masala dosas'),
        ('2 set dosas', 1.5, '3 set dosas'),
        ('1 bowl', 0.5, '1/2 bowl'),
        ('1 cup', 1.5, '1 1/2 cups'),
        ('1 leg piece', 2, '2 leg pieces'),
        ('1 medium', 2, '2 medium'),
        ('1 egg', 3, '3 eggs'),
        ('1 phulka', 4, '4 phulkas'),
        ('1 cup', 1, '1 cup'),
      ];
      for (final (desc, m, want) in cases) {
        expect(scaleServingDesc(desc, m), want, reason: '$desc x$m');
      }
    });

    test('every catalog entry x every portion: parses, whole counts, no fallback', () {
      for (final e in kDietPlanCatalog) {
        final r = byId[e.foodId]!;
        final desc = r['standard_serving_desc'] as String;
        expect(servingDescParses(desc), isTrue, reason: '${e.foodId} "$desc"');
        final qty = RegExp(r'^(\d+/\d+|\d+(?:\.\d+)?)').firstMatch(desc)!.group(1)!;
        final q = qty.contains('/')
            ? double.parse(qty.split('/')[0]) / double.parse(qty.split('/')[1])
            : double.parse(qty);
        final unitWords = desc
            .replaceFirst(RegExp(r'^[\d./]+ ?'), '')
            .split(' (')
            .first
            .split(' ');
        final countable = unitWords.any(kCountableServingUnits.contains);
        for (final m in e.portions) {
          final out = scaleServingDesc(desc, m);
          expect(out, isNot(contains('×')), reason: '$desc x$m');
          expect(out, isNot(contains('NaN')));
          expect(out, isNot(contains('Infinity')));
          if (countable) {
            final v = q * m;
            expect((v - v.round()).abs() < 1e-9, isTrue,
                reason: '${e.foodId} "$desc" x$m = $v is not whole');
          }
        }
      }
    });
  });

  group('T8 processed foods', () {
    test('every soda / cola / jam / instant-noodle name is UPF', () {
      final re = RegExp(
          r'\b(thums|thumbs|cola|pepsi|sprite|limca|maaza|frooti|frroti|sting|red bull|gatorade|glucon|mountain dew|campa|noodles?|noodels|wafer)\b|jam\b',
          caseSensitive: false);
      // Restaurant / street-food noodle DISHES are cooked meals, not
      // packaged UPF; they are outside the catalog either way.
      const cookedDishes = {'F0076', 'F0581', 'F0582', 'F0583', 'F0920'};
      for (final r in rows) {
        if (cookedDishes.contains(r['id'])) continue;
        if (re.hasMatch(r['name'] as String)) {
          expect(r['is_ultra_processed'], isTrue,
              reason: '${r['id']} ${r['name']}');
        }
      }
    });

    test('non-UPF Open Food Facts beverages are only coconut / plain water', () {
      final left = rows
          .where((r) =>
              r['source'] == 'openfoodfacts_india_v2' &&
              r['category'] == 'beverages' &&
              r['is_ultra_processed'] != true)
          .map((r) => r['id'])
          .toSet();
      expect(left, {'F1246', 'F1280', 'F1411'});
    });

    test('no curated plan contains a UPF row (the founder\'s Thums Up)', () {
      for (final entry in plans.entries) {
        for (final plan in entry.value) {
          for (final m in plan) {
            for (final i in m.items) {
              expect(byId[i.foodId]!['is_ultra_processed'], isFalse);
              expect(i.foodId, isNot('F0522'));
            }
          }
        }
      }
    });
  });

  group('T9 swap alternatives', () {
    final plan = plans[_archetypes[0]]!.first; // cut male non-veg, seed 1
    final planIds = [for (final m in plan) for (final i in m.items) i.foodId];
    List<DietPlanFoodItem> altsFor(DietMealPlan meal, int idx,
        {String? role, String pref = 'non-veg', List<String>? ids,
         FoodRepository? r}) {
      final item = meal.items[idx];
      return swapAlternatives(
        foodId: item.foodId,
        category: item.category,
        calories: item.calories,
        role: role,
        slotKey: meal.slotKey,
        dietPreference: pref,
        planFoodIds: ids ?? planIds,
        slotOtherNames: [
          for (var j = 0; j < meal.items.length; j++)
            if (j != idx) meal.items[j].name,
        ],
        repo: r ?? repo,
      );
    }

    test('(a) same-role catalog entries only, (h) never UPF, (g) role kept', () {
      for (final meal in plan) {
        for (var idx = 0; idx < meal.items.length; idx++) {
          final item = meal.items[idx];
          final alts = altsFor(meal, idx, role: item.role);
          for (final a in alts) {
            expect(catalogIds, contains(a.foodId));
            expect(a.role, item.role);
            expect(a.category, byId[a.foodId]!['category']);
            expect(byId[a.foodId]!['is_ultra_processed'], isFalse);
            final entry =
                kDietPlanCatalog.firstWhere((e) => e.foodId == a.foodId);
            expect(entry.roles.map((r) => r.name), contains(item.role));
          }
        }
      }
    });

    test('(b) a saved plan (no role) gets the same alternatives', () {
      for (final meal in plan) {
        for (var idx = 0; idx < meal.items.length; idx++) {
          final fresh = altsFor(meal, idx, role: meal.items[idx].role)
              .map((a) => a.foodId)
              .toList();
          final loaded = altsFor(meal, idx).map((a) => a.foodId).toList();
          expect(loaded, fresh, reason: '${meal.name} ${meal.items[idx].name}');
        }
      }
    });

    test('(c) a legacy non-catalog item gets catalog alternatives only', () {
      for (final legacy in [byId['F1115']!, byId['F1063']!]) {
        final alts = swapAlternatives(
          foodId: legacy['id'] as String,
          category: legacy['category'] as String,
          calories: (legacy['calories_std'] as num).round(),
          role: null,
          slotKey: 'dinner',
          dietPreference: 'non-veg',
          planFoodIds: [legacy['id'] as String],
          slotOtherNames: const [],
          repo: repo,
        );
        for (final a in alts) {
          expect(catalogIds, contains(a.foodId), reason: legacy['name'] as String);
        }
      }
    });

    test('(d) never in plan, never over a family cap, never a coherence clash, never off-diet', () {
      final familyOf = {for (final e in kDietPlanCatalog) e.foodId: e.family};
      for (final a in _archetypes) {
        for (final p in plans[a]!.take(10)) {
          final ids = [for (final m in p) for (final i in m.items) i.foodId];
          for (final meal in p) {
            for (var idx = 0; idx < meal.items.length; idx++) {
              final alts = altsFor(meal, idx,
                  role: meal.items[idx].role, pref: a.pref, ids: ids);
              final others = [
                for (var j = 0; j < meal.items.length; j++)
                  if (j != idx) meal.items[j],
              ];
              final otherTokens = {
                for (final o in others) ...coherenceTokensOf(o.name),
              };
              for (final alt in alts) {
                expect(ids, isNot(contains(alt.foodId)));
                expect(coherenceTokensOf(alt.name).intersection(otherTokens),
                    isEmpty);
                expect(DietPlanGenerator.passesDiet(byId[alt.foodId]!, a.pref),
                    isTrue);
                final f = familyOf[alt.foodId]!;
                final cap = dietFamilyDailyCap[f];
                if (cap != null) {
                  final rest = [...ids]..remove(meal.items[idx].foodId);
                  final n = rest.where((id) => familyOf[id] == f).length;
                  expect(n + 1, lessThanOrEqualTo(cap),
                      reason: '${alt.name} breaks the $f cap');
                }
              }
            }
          }
        }
      }
    });

    test('(e) is_everyday false retires a catalog food; an absent tag does not', () {
      final lunch = plan[2];
      final idx = lunch.items.indexWhere((i) => i.role == 'sabzi');
      final before = altsFor(lunch, idx, role: 'sabzi').map((a) => a.foodId).toList();
      expect(before, isNotEmpty);
      final retired = before.first;
      final patched = [
        for (final r in rows)
          if (r['id'] == retired) {...r, 'is_everyday': false} else r,
      ];
      final afterRetire = altsFor(lunch, idx, role: 'sabzi', r: _Repo(patched))
          .map((a) => a.foodId);
      expect(afterRetire, isNot(contains(retired)));
      final absent = [
        for (final r in rows)
          if (r['id'] == retired)
            {for (final e in r.entries) if (e.key != 'is_everyday') e.key: e.value}
          else
            r,
      ];
      final afterAbsent = altsFor(lunch, idx, role: 'sabzi', r: _Repo(absent))
          .map((a) => a.foodId);
      expect(afterAbsent, contains(retired));
    });

    test('(f) never offers a food the founder rejected', () {
      const never = {
        'F0690', 'F0375', 'F0376', 'F0696', 'F0692', 'F0126', 'F0286',
        'F0921', 'F0522', 'F1115', 'F1063',
      };
      for (final a in _archetypes) {
        for (final p in plans[a]!.take(10)) {
          final ids = [for (final m in p) for (final i in m.items) i.foodId];
          for (final meal in p) {
            for (var idx = 0; idx < meal.items.length; idx++) {
              for (final alt in altsFor(meal, idx, pref: a.pref, ids: ids)) {
                expect(never, isNot(contains(alt.foodId)));
              }
            }
          }
        }
      }
    });

    test('resolveSwapRole: enum order for multi-role foods; snack slot dairy has no role', () {
      // Curd is breakfastProtein, side and snack.
      expect(
          resolveSwapRole(foodId: 'F0029', category: 'dairy', role: null, slotKey: 'breakfast'),
          DietRole.breakfastProtein);
      expect(
          resolveSwapRole(foodId: 'F0029', category: 'dairy', role: null, slotKey: 'lunch'),
          DietRole.side);
      expect(
          resolveSwapRole(foodId: 'F0029', category: 'dairy', role: null, slotKey: 'evening'),
          DietRole.snack);
      // A legacy non-catalog dairy row in a snack slot: no role (snackbar).
      expect(
          resolveSwapRole(foodId: 'F1115', category: 'dairy', role: null, slotKey: 'evening'),
          isNull);
      expect(kDietMealNameToSlotKey['Mid-Morning Snack'], 'mid_morning');
    });
  });
}
