// Library Batch S1b-1 (seed v22, docs/plans/2026-11-09-library-batch-s1b1-gym-hip-goblet.md, founder 2026-11-09): an
// install at the v21 library holds E038 Goblet Squat at [beginner, intermediate, advanced], E107 Hip Abduction Machine at
// [advanced], E109 Glute Kickback (Cable) at [intermediate, advanced] and G0168 Cable Hip Adduction at []. The v22
// targets: E038 [beginner, intermediate]; E107, E109 and G0168 at every level. Its next launch puts the v22 levels in the box (the seed's putAll rewrites by id) and changes nothing else.
// Drives the REAL SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 21; put E038's advanced level back in the
// library.
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

/// The two rows' core_levels as v21 shipped them (restated, never read from git: CI checks out shallow).
const _v21Levels = <String, List<String>>{
  'E038': ['beginner', 'intermediate', 'advanced'],
  'E107': ['advanced'],
  'E109': ['intermediate', 'advanced'],
  'G0168': [],
};

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _putV21Box(HiveService hive) async {
  for (final r in _bundled()) {
    final old = _v21Levels[r['id']];
    await hive.exerciseBox.put(r['id'], old == null ? r : {...r, 'core_levels': old});
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: the bundled library ships the v22 levels', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    expect(byId['E038']!['core_levels'], ['beginner', 'intermediate']);
    expect(byId['E107']!['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(byId['G0168']!['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(byId['E109']!['core_levels'], ['beginner', 'intermediate', 'advanced']);
  });

  test('a v21 box ends at the current version (v23) with the v22 levels, and every other row unchanged', () async {
    final hive = HiveService.instance;
    await _putV21Box(hive);
    await _markSeeded(hive, 21);
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !_v21Levels.containsKey(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    expect(_asJson(hive.exerciseBox.get('E038'))['core_levels'], ['beginner', 'intermediate']);
    expect(_asJson(hive.exerciseBox.get('E107'))['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(_asJson(hive.exerciseBox.get('G0168'))['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(_asJson(hive.exerciseBox.get('E109'))['core_levels'], ['beginner', 'intermediate', 'advanced']);
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 23);
  });

  test('MIRROR: a box already at the current version (v23, Library Batch S1b-2) is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV21Box(hive);
    await _markSeeded(hive, 23);
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get('E038'))['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(hive.configBox.get('exercise_library_version') as int, 23);
  });
}
