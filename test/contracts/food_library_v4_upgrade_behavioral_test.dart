// Diet plan Unit 1 (2026-11-14, docs/plans/diet-food-quality.md §4): food
// library v4. An install holding the v3 food rows (no is_everyday, Thums Up
// non-UPF, no F1442-F1448) re-seeds on its next launch: the new rows land,
// the tags are rewritten. Drives the REAL SeedService.seedIfNeeded (the
// bundled asset through rootBundle), like library_seed_v27_upgrade_behavioral
// _test.dart does for exercises (those tests pin food_library_version to 9999,
// so they are untouched by this bump).
//
// Mutations: put _foodLibraryVersion back to 3 or 4 (the upgrade tests
// redden); drop the version source pin.
//
// Diet plan Unit 3b (2026-11-14, docs/plans/diet-strategy-3b.md §3.7): v5
// flips is_everyday to true for the 14 Low carb / Keto catalog foods, so a
// v4 box re-seeds too (the v3 -> v5 path keeps Unit 1's assertions).
//
// Diet plan observations batch (2026-11-15): v6 flips is_everyday to true for
// the 5 vegan-friendly Low carb foods (tempeh, edamame, avocado, almond
// butter, chia seeds), so a v5 box re-seeds too; a v4 and a v3 box end at v6.
//
// Diet chart v3 (2026-11-17): v7 flips is_everyday to true for the 10 SWAP-ONLY
// catalog foods, so a v6 box re-seeds too; every older box ends at v7.
//
// Diet protein rules (2026-11-18, docs/plans/diet-protein-rules.md §A3): v8
// flips is_everyday to false for F0362 (Surmai leaves the catalog), so a v7 box
// re-seeds too and every older box ends at v8. The simulated old boxes carry
// F0362 as everyday (it was), so the true -> false flip is VISIBLE: before this
// batch they were derived from the new asset and no test could see it.
//
// Diet Portions / Grams view (2026-11-18, OI-517): v9 adds `weight_unit: "ml"` to
// the 145 audited liquid rows, so a v8 box re-seeds too and every older box ends
// at v9. The old boxes are built from the asset, so the v8 test strips the field
// first (otherwise the gain would be invisible).
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs
// (CLAUDE.md section 4.9).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';

import '../helpers/hive_test_setup.dart';

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/food_database.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();

/// The v3 rows, derived from the v4 asset (no git at test time).
List<Map<String, dynamic>> _v3Rows() {
  const newIds = {'F1442', 'F1443', 'F1444', 'F1445', 'F1446', 'F1447', 'F1448'};
  return [
    for (final r in _bundled())
      if (!newIds.contains(r['id']))
        {
          for (final e in r.entries)
            if (e.key != 'is_everyday') e.key: e.value,
          if (r['id'] == 'F0522') 'is_ultra_processed': false,
        },
  ];
}

/// The Unit 3b Low carb / Keto ids (false in v4, true in v5).
const _v5Everyday = {
  'F0402', 'F0403', 'F0483', 'F0383', 'F0371', 'F0790', 'F0023', 'F0398',
  'F0394', 'F0348', 'F1022', 'F1024', 'F0040', 'F0264',
};

/// The v6 ids (2026-11-15): Low carb plans only, vegan friendly.
const _v6Everyday = {'F1017', 'F1018', 'F0455', 'F0480', 'F0082'};

/// The v7 ids (2026-11-17): the swap-only catalog entries.
const _v7Everyday = {
  'F1433', 'F0477', 'F0471', 'F1015', 'F1019', 'F1061', 'F0269', 'F0295',
  'F0043', 'F1028',
};

/// The v8 retirement (2026-11-18): Surmai left the catalog, so its asset flag
/// went true -> false. Every older box still holds it as everyday.
const _v8Retired = {'F0362'};

/// The v7 rows: the v8 asset with F0362 still `is_everyday: true`.
List<Map<String, dynamic>> _v7Rows() => [
      for (final r in _bundled())
        {
          ...r,
          if (_v8Retired.contains(r['id'])) 'is_everyday': true,
        },
    ];

/// The v6 rows: the v8 asset with the 10 v7 ids still `is_everyday: false` and
/// F0362 still true.
List<Map<String, dynamic>> _v6Rows() => [
      for (final r in _bundled())
        {
          ...r,
          if (_v7Everyday.contains(r['id'])) 'is_everyday': false,
          if (_v8Retired.contains(r['id'])) 'is_everyday': true,
        },
    ];

/// The v5 rows: the v8 asset with the v6 and v7 ids still `is_everyday: false`
/// and F0362 still true.
List<Map<String, dynamic>> _v5Rows() => [
      for (final r in _bundled())
        {
          ...r,
          if (_v6Everyday.contains(r['id']) || _v7Everyday.contains(r['id']))
            'is_everyday': false,
          if (_v8Retired.contains(r['id'])) 'is_everyday': true,
        },
    ];

/// The v4 rows: the v8 asset with the 14 + 5 + 10 ids still `is_everyday: false`
/// and F0362 still true.
List<Map<String, dynamic>> _v4Rows() => [
      for (final r in _bundled())
        {
          ...r,
          if (_v5Everyday.contains(r['id']) ||
              _v6Everyday.contains(r['id']) ||
              _v7Everyday.contains(r['id']))
            'is_everyday': false,
          if (_v8Retired.contains(r['id'])) 'is_everyday': true,
        },
    ];

Future<void> _markSeeded(HiveService hive, int foodVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', 9999);
  await hive.configBox.put('food_library_version', foodVersion);
}

Map<String, dynamic> _asJson(Object? row) =>
    jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('the version constant is 9', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    expect(RegExp(r'static const int _foodLibraryVersion = 9;').hasMatch(src),
        isTrue);
  });

  test('the v5 + v6 ids are exactly the catalog\'s Low carb / Keto only entries '
      '(B-pass seat C finding 6)', () {
    expect({..._v5Everyday, ..._v6Everyday},
        {for (final e in kDietPlanCatalog) if (e.lowCarbOnly) e.foodId});
  });

  test('the v7 ids are exactly the catalog\'s swap-only entries', () {
    expect(_v7Everyday,
        {for (final e in kDietPlanCatalog) if (e.swapOnly) e.foodId});
  });

  test('precondition: the 14 + 5 + 10 ids are everyday in the asset', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in {..._v5Everyday, ..._v6Everyday, ..._v7Everyday}) {
      expect(byId[id]?['is_everyday'], isTrue, reason: id);
    }
  });

  test('a v6 food box ends at v9 with the 10 swap-only ids everyday', () async {
    final hive = HiveService.instance;
    for (final r in _v6Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 6);
    expect(_asJson(hive.foodBox.get('F1433'))['is_everyday'], isFalse,
        reason: 'precondition');

    await SeedService.instance.seedIfNeeded();

    for (final id in _v7Everyday) {
      expect(_asJson(hive.foodBox.get(id))['is_everyday'], isTrue, reason: id);
    }
    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isFalse,
        reason: 'Surmai left the catalog in v8');
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('a v5 food box ends at v9 with the 5 vegan Low carb ids everyday',
      () async {
    final hive = HiveService.instance;
    for (final r in _v5Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 5);
    expect(_asJson(hive.foodBox.get('F1017'))['is_everyday'], isFalse,
        reason: 'precondition');

    await SeedService.instance.seedIfNeeded();

    for (final id in {..._v6Everyday, ..._v7Everyday}) {
      expect(_asJson(hive.foodBox.get(id))['is_everyday'], isTrue, reason: id);
    }
    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isFalse,
        reason: 'Surmai left the catalog in v8');
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('a v4 food box ends at v9 with the 14 + 5 + 10 ids everyday', () async {
    final hive = HiveService.instance;
    for (final r in _v4Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 4);
    expect(_asJson(hive.foodBox.get('F0402'))['is_everyday'], isFalse,
        reason: 'precondition');

    await SeedService.instance.seedIfNeeded();

    for (final id in {..._v5Everyday, ..._v6Everyday, ..._v7Everyday}) {
      expect(_asJson(hive.foodBox.get(id))['is_everyday'], isTrue, reason: id);
    }
    expect(_asJson(hive.foodBox.get('F0007'))['is_everyday'], isFalse);
    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isFalse,
        reason: 'Surmai left the catalog in v8');
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('a v3 food box ends at v9 with the new rows and tags', () async {
    final hive = HiveService.instance;
    for (final r in _v3Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 3);
    expect(hive.foodBox.get('F1442'), isNull, reason: 'precondition');

    await SeedService.instance.seedIfNeeded();

    expect(_asJson(hive.foodBox.get('F1442'))['name'], 'Kanda Poha');
    expect(_asJson(hive.foodBox.get('F0522'))['is_ultra_processed'], isTrue);
    expect(_asJson(hive.foodBox.get('F0001'))['is_everyday'], isTrue);
    expect(_asJson(hive.foodBox.get('F0007'))['is_everyday'], isFalse);
    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isFalse,
        reason: 'Surmai left the catalog in v8');
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('a v7 food box ends at v9 with F0362 (Surmai) no longer everyday',
      () async {
    final hive = HiveService.instance;
    for (final r in _v7Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 7);
    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isTrue,
        reason: 'precondition: a v7 box holds Surmai as everyday');
    final stillEveryday = kDietPlanCatalog.first.foodId;

    await SeedService.instance.seedIfNeeded();

    expect(_asJson(hive.foodBox.get('F0362'))['is_everyday'], isFalse);
    expect(_asJson(hive.foodBox.get(stillEveryday))['is_everyday'], isTrue,
        reason: 'a catalog food keeps its flag');
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('a v8 food box gains weight_unit ml on the audited liquids at v9 '
      '(the old rows are built from the asset, so strip the field first)',
      () async {
    final hive = HiveService.instance;
    final stripped = [
      for (final r in _bundled())
        {...r}..remove('weight_unit'),
    ];
    for (final r in stripped) {
      await hive.foodBox.put(r['id'], r);
    }
    expect(_asJson(hive.foodBox.get('F0031')).containsKey('weight_unit'),
        isFalse);
    await _markSeeded(hive, 8);

    await SeedService.instance.seedIfNeeded();

    // Milk (Toned), Lassi (Sweet), Falooda, a 200ml cola row.
    for (final id in ['F0031', 'F0034', 'F0622', 'F1235']) {
      expect(_asJson(hive.foodBox.get(id))['weight_unit'], 'ml', reason: id);
    }
    // A solid stays without the field (absent = grams).
    expect(_asJson(hive.foodBox.get('F0001')).containsKey('weight_unit'),
        isFalse);
    expect(hive.configBox.get('food_library_version') as int, 9);
  });

  test('Surmai is out of the catalog, kept in the asset, retired in the asset '
      'flag, and its family survives in the retired map', () {
    final catalogIds = {for (final e in kDietPlanCatalog) e.foodId};
    expect(catalogIds.contains('F0362'), isFalse);
    expect(kRetiredCatalogFamilies.keys.toSet().intersection(catalogIds),
        isEmpty, reason: 'a retired id must not also be a catalog id');
    final row = {for (final r in _bundled()) r['id']: r}['F0362'];
    expect(row, isNotNull, reason: 'the food row stays (Search any food)');
    expect(row!['is_everyday'], isFalse);
    expect(dietCatalogFamily('F0362'), DietFamily.fish);
  });

  test('MIRROR: a box already at v9 is not re-seeded', () async {
    final hive = HiveService.instance;
    for (final r in _v3Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 9);
    await SeedService.instance.seedIfNeeded();
    expect(hive.foodBox.get('F1442'), isNull);
  });
}
