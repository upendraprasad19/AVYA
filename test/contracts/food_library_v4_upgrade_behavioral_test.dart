// Diet plan Unit 1 (2026-11-14, docs/plans/diet-food-quality.md §4): food
// library v4. An install holding the v3 food rows (no is_everyday, Thums Up
// non-UPF, no F1442-F1448) re-seeds on its next launch: the new rows land,
// the tags are rewritten. Drives the REAL SeedService.seedIfNeeded (the
// bundled asset through rootBundle), like library_seed_v27_upgrade_behavioral
// _test.dart does for exercises (those tests pin food_library_version to 9999,
// so they are untouched by this bump).
//
// Mutations: put _foodLibraryVersion back to 3 (the upgrade test reddens);
// drop the version source pin.
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

  test('the version constant is 4', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    expect(RegExp(r'static const int _foodLibraryVersion = 4;').hasMatch(src),
        isTrue);
  });

  test('a v3 food box ends at v4 with the new rows and tags', () async {
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
    expect(hive.configBox.get('food_library_version') as int, 4);
  });

  test('MIRROR: a box already at v4 is not re-seeded', () async {
    final hive = HiveService.instance;
    for (final r in _v3Rows()) {
      await hive.foodBox.put(r['id'], r);
    }
    await _markSeeded(hive, 4);
    await SeedService.instance.seedIfNeeded();
    expect(hive.foodBox.get('F1442'), isNull);
  });
}
