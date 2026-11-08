// Library Batch S1a (seed v21, docs/plans/2026-11-08-library-batch-s1-core-data.md): an install at the v20 library holds
// the OLD core_levels on 34 rows. Its next launch puts the new levels in the box (the seed's putAll rewrites by id) and
// changes nothing else; a fresh install gets the new levels. Drives the REAL SeedService.seedIfNeeded.
//
// The old levels come from the committed fixture test/fixtures/library_core_levels_before_s1a.json (CI checks out shallow).
//
// Mutations (each reddens a test below): put the version constant back to 20; drop the core-levels stage's effect on one
// row of the library (restore its old levels).
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _beforeLevels() =>
    ((jsonDecode(File('test/fixtures/library_core_levels_before_s1a.json').readAsStringSync()) as Map)['core_levels'] as Map)
        .cast<String, dynamic>();

/// The ids whose bundled core_levels differ from the fixture (the S1a rows).
List<String> _changedIds() {
  final before = _beforeLevels();
  return [
    for (final r in _bundled())
      if (jsonEncode(r['core_levels']) != jsonEncode(before[r['id']])) r['id'] as String
  ];
}

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: 34 rows differ from the fixture (Table A)', () {
    expect(_changedIds().length, 34);
  });

  test('a v20 box with the old levels ends at v21 with the new levels, and every other row unchanged', () async {
    final hive = HiveService.instance;
    final bundled = _bundled();
    final before = _beforeLevels();
    final changed = _changedIds().toSet();
    for (final r in bundled) {
      await hive.exerciseBox.put(r['id'], changed.contains(r['id']) ? {...r, 'core_levels': before[r['id']]} : r);
    }
    await _markSeeded(hive, 20);
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !changed.contains(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };
    expect(jsonEncode(_asJson(hive.exerciseBox.get('E046'))['core_levels']), '[]', reason: 'precondition: old levels');

    await SeedService.instance.seedIfNeeded();

    for (final r in bundled.where((r) => changed.contains(r['id']))) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(r['id']))), jsonEncode(r), reason: '${r['id']} is the bundled row');
    }
    expect(_asJson(hive.exerciseBox.get('E046'))['core_levels'], ['advanced']);
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, bundled.length);
    expect(hive.configBox.get('exercise_library_version') as int, 21);
  });

  test('a fresh install gets the new levels', () async {
    final hive = HiveService.instance;
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get('E046'))['core_levels'], ['advanced']);
    expect(_asJson(hive.exerciseBox.get('E255'))['core_levels'], <String>[]);
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 21);
  });

  test('MIRROR: a box already at v21 is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    final before = _beforeLevels();
    for (final r in _bundled()) {
      await hive.exerciseBox.put(r['id'], r['id'] == 'E046' ? {...r, 'core_levels': before['E046']} : r);
    }
    await _markSeeded(hive, 21);
    await SeedService.instance.seedIfNeeded();
    expect(jsonEncode(_asJson(hive.exerciseBox.get('E046'))['core_levels']), '[]');
    expect(hive.configBox.get('exercise_library_version') as int, 21);
  });
}
