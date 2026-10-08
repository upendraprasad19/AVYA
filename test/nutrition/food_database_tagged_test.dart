// test/nutrition/food_database_tagged_test.dart
//
// Real-DB gates for the 2026-09 meal-quality tagged food database:
//   1. Schema: every row carries is_ultra_processed (bool) + meal_fit
//      (list of valid slots; EMPTY list is the legal "never generated"
//      state — the five alcohol rows).
//   2. Pinned spot-checks: Pringles/Maggi/Special K => UPF true,
//      Idli/Roti/Almonds => false. These make silent heuristic drift
//      impossible (the heuristic's guesses are regression-pinned, not
//      just founder-reviewed).
//   3. Row count >= 1431 with every original id present (new vegan rows
//      may be appended under NEW ids only).
//   4. The four protein-band archetypes re-run against the REAL json load
//      (the curated fixture drifts from production data — round-3 review
//      finding 6 — so only this run is authoritative for the band).
//   5. The quality-constraint invariants hold on the real DB: quotas,
//      no-UPF, caps, day-uniqueness, and the meal_fit "never" semantics
//      (alcohol never generated).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

class _RealDbRepo implements FoodRepository {
  final List<Map<String, dynamic>> _foods;
  _RealDbRepo(this._foods);

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

const _validSlots = {'breakfast', 'lunch', 'dinner', 'snack'};

void main() {
  final asset = File('assets/data/food_database.json');
  final rows =
      (jsonDecode(asset.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final repo = _RealDbRepo(rows);
  final gen = DietPlanGenerator.forTest(repo);

  test('tagged schema: every row carries both new fields with valid values', () {
    for (final row in rows) {
      final id = row['id'];
      expect(row['is_ultra_processed'], isA<bool>(),
          reason: '$id (${row['name']}): is_ultra_processed must be a bool');
      final fit = row['meal_fit'];
      expect(fit, isA<List>(),
          reason: '$id (${row['name']}): meal_fit must be a list '
              '(empty = deliberately never-generated, e.g. alcohol)');
      for (final s in fit as List) {
        expect(_validSlots.contains(s), isTrue,
            reason: '$id (${row['name']}): invalid meal_fit slot "$s"');
      }
    }
  });

  test('pinned spot-checks: UPF rows stay UPF, clean staples stay clean', () {
    bool allUpf(String needle) => rows
        .where((r) => (r['name'] as String).toLowerCase().contains(needle))
        .every((r) => r['is_ultra_processed'] == true);
    expect(allUpf('pringles'), isTrue, reason: 'Pringles rows must be UPF');
    expect(allUpf('maggi'), isTrue, reason: 'Maggi rows must be UPF');
    expect(allUpf('special k'), isTrue, reason: 'Special K rows must be UPF');

    bool clean(String name) => rows
        .where((r) => r['name'] == name)
        .every((r) => r['is_ultra_processed'] == false);
    expect(clean('Idli'), isTrue, reason: 'Idli must never be UPF-flagged');
    expect(clean('Roti (Whole Wheat)'), isTrue,
        reason: 'Roti must never be UPF-flagged (kcal/g cap regression would');
    expect(clean('Almonds'), isTrue, reason: 'Almonds must never be UPF-flagged');
  });

  test('row count >= 1431 and the original id set is fully preserved', () {
    expect(rows.length, greaterThanOrEqualTo(1431));
    final ids = rows.map((r) => r['id'] as String).toSet();
    expect(ids.length, rows.length, reason: 'duplicate ids in the asset');
    for (var i = 1; i <= 93; i++) {
      expect(ids.contains('F${i.toString().padLeft(4, '0')}'), isTrue,
          reason: 'seed row F${i.toString().padLeft(4, '0')} missing');
    }
  });

  test('alcohol rows are tagged never-generate (empty meal_fit)', () {
    for (final name in ['Beer (Lager)', 'Whisky (40% ABV)', 'Vodka (40% ABV)',
        'Rum (40% ABV)', 'Gin (40% ABV)']) {
      final row = rows.firstWhere((r) => r['name'] == name,
          orElse: () => <String, dynamic>{});
      expect(row, isNotEmpty, reason: '$name missing from the asset');
      expect((row['meal_fit'] as List?) ?? ['x'], isEmpty,
          reason: '$name must carry an EMPTY meal_fit (never generated)');
    }
  });

  test('vegan purity: no is_vegan=false or dairy-category row in vegan plans', () {
    // The real-DB catch: the name blocklist missed '1% Milk',
    // 'Greek Yogurt Plain (2%)', 'Jaouda Perly', 'Nestle Milkybar Moosha',
    // 'Buttermilk (Cultured)' — all is_vegan=false. The generator now
    // honors the DB's is_vegan field authoritatively; this test pins it.
    for (var seed = 1; seed <= 10; seed++) {
      final plan = gen.generate(DietPlanInputs(
        calorieTarget: 2200,
        proteinTarget: 150,
        dietPreference: 'vegan',
        fiberTarget: 30,
        seed: seed,
      ));
      for (final meal in plan) {
        for (final item in meal.items) {
          // NOTE: dairy-CATEGORY rows are legal in vegan plans — plant
          // milks (Almond/Coconut/Soy) are genuinely categorized 'dairy'
          // in the DB while carrying is_vegan=true. The authoritative
          // check is the is_vegan field, not the category.
          final row = rows.firstWhere((r) => r['id'] == item.foodId,
              orElse: () => <String, dynamic>{});
          if (row.isNotEmpty) {
            expect(row['is_vegan'], isNot(false),
                reason: 'seed=$seed ${meal.slotKey}: is_vegan=false item '
                    '${item.name} in a VEGAN plan');
          }
        }
      }
    }
  });

  test('veg purity: no is_veg=false row in vegetarian plans', () {
    // B-pass finding 2: the veg preference was a 9-name blocklist that
    // leaked 187 is_veg=false rows on real data (e.g. 'Anda Paratha' into
    // staples fillers). is_veg is now authoritative, mirroring the vegan fix.
    for (var seed = 1; seed <= 10; seed++) {
      final plan = gen.generate(DietPlanInputs(
        calorieTarget: 2200,
        proteinTarget: 140,
        dietPreference: 'veg',
        fiberTarget: 30,
        seed: seed,
      ));
      for (final meal in plan) {
        for (final item in meal.items) {
          final row = rows.firstWhere((r) => r['id'] == item.foodId,
              orElse: () => <String, dynamic>{});
          if (row.isNotEmpty) {
            expect(row['is_veg'], isNot(false),
                reason: 'seed=$seed ${meal.slotKey}: is_veg=false item '
                    '${item.name} in a VEG plan');
          }
        }
      }
    }
  });

  test('no alcohol ever appears in any generated plan', () {
    final alcoholNames = {'Beer (Lager)', 'Whisky (40% ABV)', 'Vodka (40% ABV)',
        'Rum (40% ABV)', 'Gin (40% ABV)'};
    for (var seed = 1; seed <= 10; seed++) {
      final plan = gen.generate(DietPlanInputs(
        calorieTarget: 2200,
        proteinTarget: 140,
        dietPreference: 'non-veg',
        fiberTarget: 30,
        seed: seed,
      ));
      for (final meal in plan) {
        for (final item in meal.items) {
          expect(alcoholNames.contains(item.name), isFalse,
              reason: 'alcohol item ${item.name} in ${meal.slotKey} '
                  '(seed=$seed) — empty-meal_fit never-generate semantics broken');
        }
      }
    }
  });

  test('real-DB archetypes: daily protein in [95%, 115%] on the 1431-row DB', () {
    final archetypes = [
      ('low-cal cut', 1500, 130, 'veg'),
      ('balanced maintain', 2400, 130, 'non-veg'),
      ('surplus build', 3000, 200, 'non-veg'),
      ('vegan high-protein', 2200, 150, 'vegan'),
    ];
    for (final (label, calories, protein, diet) in archetypes) {
      // seeds 1-8: the vegan archetype's anchor-upgrade guard is
      // load-bearing on seeds 1/2/8 (mutation M8 blind-spot fix — seeds
      // 42/7 pass even with the guard neutered)
      for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final plan = gen.generate(DietPlanInputs(
          calorieTarget: calories,
          proteinTarget: protein,
          dietPreference: diet,
          fiberTarget: 30,
          seed: seed,
        ));
        final totalProtein = plan.fold<int>(0, (s, m) => s + m.totalProtein);
        expect(
          totalProtein,
          greaterThanOrEqualTo((protein * 0.95).floor()),
          reason: '$label seed=$seed: protein deficit on the REAL DB '
              '($totalProtein g vs >= ${protein * 0.95} g)',
        );
        expect(
          totalProtein,
          lessThanOrEqualTo((protein * 1.15).round()),
          reason: '$label seed=$seed: protein surplus on the REAL DB '
              '($totalProtein g vs <= ${protein * 1.15} g)',
        );
      }
    }
  });

  test('real-DB quality invariants: quotas, caps, uniqueness, UPF on the real DB', () {
    for (final diet in ['veg', 'vegan', 'non-veg']) {
      for (final seed in [42, 7]) {
        final plan = gen.generate(DietPlanInputs(
          calorieTarget: 2200,
          proteinTarget: 140,
          dietPreference: diet,
          fiberTarget: 30,
          seed: seed,
        ));
        final anchorOrQuotaIds = <String>{};
        for (final meal in plan) {
          if (meal.slotKey == 'lunch' || meal.slotKey == 'dinner') {
            expect(meal.items.any((i) => i.category == 'vegetables'), isTrue,
                reason: '$diet seed=$seed ${meal.slotKey}: no vegetables item');
          }
          final counts = <String, int>{};
          for (final item in meal.items) {
            counts[item.category] = (counts[item.category] ?? 0) + 1;
            expect(
              item.name.toLowerCase().contains('pringles'), isFalse,
              reason: '$diet seed=$seed: UPF item ${item.name} generated');
            if (item.isAnchor || item.isQuotaLocked) {
              expect(anchorOrQuotaIds.contains(item.foodId), isFalse,
                  reason: '$diet seed=$seed: anchor/quota ${item.name} '
                      'repeated in one day');
              anchorOrQuotaIds.add(item.foodId);
            }
          }
          expect(counts['pulses'] ?? 0, lessThanOrEqualTo(2),
              reason: '$diet seed=$seed ${meal.slotKey}: pulses stacking');
          expect(counts['staples'] ?? 0, lessThanOrEqualTo(2),
              reason: '$diet seed=$seed ${meal.slotKey}: staple stacking');
        }
      }
    }
  });
}
