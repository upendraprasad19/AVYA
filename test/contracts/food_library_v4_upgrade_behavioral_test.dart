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
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs
// (CLAUDE.md section 4.9).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

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

/// The v4 rows: the v5 asset with the 14 ids still `is_everyday: false`.
List<Map<String, dynamic>> _v4Rows() => [
      for (final r in _bundled())
        {
          ...r,
          if (_v5Everyday.contains(r['id'])) 'is_everyday': false,
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

  test('the version constant is 5', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    expect(RegExp(r'static const int _foodLibraryVersion = 5;').hasMatch(src),
        isTrue);
  });

  test('precondition: the 14 ids are everyday in the asset', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in _v5Everyday) {
      expect(byId[id]?['is_everyday'], isTrue, reason: id);
    }
  });

  test('a v4 food box ends at v5 with the 14 ids everyday', () async {
    final hive = HiveService.instance;
    for (final r in _v4Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 4);
    expect(_asJson(hive.foodBox.get('F0402'))['is_everyday'], isFalse,
        reason: 'precondition');

    await SeedService.instance.seedIfNeeded();

    for (final id in _v5Everyday) {
      expect(_asJson(hive.foodBox.get(id))['is_everyday'], isTrue, reason: id);
    }
    expect(_asJson(hive.foodBox.get('F0007'))['is_everyday'], isFalse);
    expect(hive.configBox.get('food_library_version') as int, 5);
  });

  test('a v3 food box ends at v5 with the new rows and tags', () async {
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
    expect(hive.configBox.get('food_library_version') as int, 5);
  });

  test('MIRROR: a box already at v5 is not re-seeded', () async {
    final hive = HiveService.instance;
    for (final r in _v3Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 5);
    await SeedService.instance.seedIfNeeded();
    expect(hive.foodBox.get('F1442'), isNull);
  });
}
