// Batch C2b (seed v19, OI-462, docs/plans/2026-11-05-library-batch-c2b-twins.md): an install at the v18 library holds the six
// rows C2a kept as twin_pending (E084 E111 E162 E169 E179 E211) and lacks the four twins (G1368 G1489 G2567 G0474). Its next
// launch prunes exactly the six, gains the four, and the retired NAMES still resolve (a plan or log written before the
// removal holds a name, not an id). A fresh install gets the four and none of the six. Drives the REAL
// SeedService.seedIfNeeded and the REAL ExerciseRepository.getByExactName.
//
// History keyed by a retired ID is not remapped to the twin (accepted, plan "Accepted behaviour changes"): only the name
// resolves, by exact name or by alias.
//
// Mutations (each reddens a test below): put the version constant back to 18; delete one of the six ids from
// kRetiredLibraryIdsNoTwin; drop the alias of G2567 or G1368 from the library.
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import '../helpers/hive_test_setup.dart';

/// The six rows and the twin each one folds into (the removals file pins the same pairs).
const _sixToTwin = {
  'E084': 'G1368',
  'E211': 'G1368',
  'E111': 'G1489',
  'E162': 'G2567',
  'E169': 'G2567',
  'E179': 'G0474',
};
const _twins = {'G1368', 'G1489', 'G2567', 'G0474'};

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, String> _baseNames() => {
      for (final r in (jsonDecode(File('test/fixtures/library_c2_base_depth.json').readAsStringSync()) as Map<String, dynamic>)['rows'] as List)
        (r as Map)['id'] as String: r['name'] as String,
    };

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('a v18 box holding the six rows and no twins prunes exactly the six and gains the four', () async {
    final hive = HiveService.instance;
    final bundled = _bundled();
    final names = _baseNames();
    for (final r in bundled) {
      if (_twins.contains(r['id'])) continue; // the v18 install has no twin
      await hive.exerciseBox.put(r['id'], r);
    }
    for (final id in _sixToTwin.keys) {
      await hive.exerciseBox.put(id, {'id': id, 'name': names[id]}); // what the v18 install still holds
    }
    await _markSeeded(hive, 18);
    expect(_sixToTwin.keys.every(hive.exerciseBox.containsKey), isTrue, reason: 'precondition: the six are in the box');
    expect(_twins.any(hive.exerciseBox.containsKey), isFalse, reason: 'precondition: no twin yet');

    await SeedService.instance.seedIfNeeded();

    for (final id in _sixToTwin.keys) {
      expect(hive.exerciseBox.containsKey(id), isFalse, reason: '$id must be pruned');
    }
    for (final id in _twins) {
      expect(hive.exerciseBox.containsKey(id), isTrue, reason: '$id must arrive');
    }
    expect(hive.exerciseBox.length, bundled.length);
    expect(hive.configBox.get('exercise_library_version') as int, 20);
  });

  test('every retired name still resolves to its twin: exact name for four, alias for two', () async {
    final hive = HiveService.instance;
    await _markSeeded(hive, 18);
    await SeedService.instance.seedIfNeeded();
    final repo = ExerciseRepository.instance;

    // The four rows that carried the twin's own name now resolve by EXACT name.
    expect(repo.getByExactName('Ankle Circles')?['id'], 'G1368');
    expect(repo.getByExactName('Sissy Squat')?['id'], 'G1489');
    expect(repo.getByExactName('Seated Piriformis Stretch')?['id'], 'G2567');
    expect(repo.getByExactName('Toes to Bar')?['id'], 'G0474');
    // The two differently named rows resolve by ALIAS.
    expect(repo.getByExactName('Ankle Rotations')?['id'], 'G1368');
    expect(repo.getByExactName('Piriformis Stretch')?['id'], 'G2567');
  });

  test('a fresh install gets the four twins and none of the six', () async {
    final hive = HiveService.instance;
    await SeedService.instance.seedIfNeeded();
    for (final id in _twins) {
      expect(hive.exerciseBox.containsKey(id), isTrue, reason: '$id ships');
    }
    for (final id in _sixToTwin.keys) {
      expect(hive.exerciseBox.containsKey(id), isFalse, reason: '$id must not ship');
    }
    expect(hive.exerciseBox.length, _bundled().length);
  });
}
