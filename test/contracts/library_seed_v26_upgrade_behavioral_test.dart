// Unit 1B-R, Ruling 1 (seed v26, founder d24, docs/plans/2026-11-12-generator-1br-loaded-wins.md): G0355 Dumbbell
// Single Arm Lateral Raise gains `beginner` in core_levels, so a beginner day with two Lateral Delts slots gets a second
// loaded raise instead of Towel Lateral Raise (OI-387). An install at the v25 library holds G0355 at
// [intermediate, advanced]; its next launch rewrites the row by id and changes nothing else. A bundle-only bump:
// core_levels has no cloud column (verified live 2026-11-12). Drives the REAL SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 25; drop `beginner` from G0355 in the asset
// (the precondition); edit any other row of the bundle (the v25 digest pin).
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/library_g0355_v25.dart';
import '../helpers/library_overlay_v26.dart';

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

/// The v25 bundle, rebuilt: the current asset with G0355's v25 levels restored.
// Unit 1B-F2 (seed v27) copied the overlays; the v25 bundle keeps them.
List<Map<String, dynamic>> _v25Bundle() => [for (final r in _bundled()) withOverlaysV26(withG0355V25(r))];

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _putV25Box(HiveService hive) async {
  for (final r in _v25Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: G0355 is core at every level in the bundle and Beginner-suitable', () {
    final g = _bundled().singleWhere((r) => r['id'] == g0355Id);
    expect(g['name'], 'Dumbbell Single Arm Lateral Raise');
    expect(g['core_levels'], ['beginner', 'intermediate', 'advanced']);
    expect(g['suitable_for'], contains('Beginner'));
  });

  // The rebuilt v25 bundle must be byte-for-byte the shipped v25 bundle: sha256 of Dart's jsonEncode of
  // assets/data/exercise_library.json at the branch base (main 4e0637ae), computed independently with Python's compact
  // json.dumps (ensure_ascii off), the method of library_seed_v25_upgrade_behavioral_test.dart.
  test('the v26 bundle is the v25 bundle plus beginner on G0355, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v25Bundle()))).toString(),
        'ea479a1ee98b1c906cec680cda1da167e4fba5704dc88a65e13212eaf5ff874e');
  });

  test('a v25 box ends at the current version (v27): G0355 is written as bundled, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _putV25Box(hive);
    await _markSeeded(hive, 25);
    expect(_asJson(hive.exerciseBox.get(g0355Id))['core_levels'], g0355CoreLevelsV25, reason: 'precondition');
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => k != g0355Id && !overlayRowIdsV27.contains(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final bundled = _bundled().singleWhere((r) => r['id'] == g0355Id);
    expect(jsonEncode(_asJson(hive.exerciseBox.get(g0355Id))), jsonEncode(bundled), reason: 'G0355 written as bundled');
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });

  test('MIRROR: a box already at the current version (v27) is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV25Box(hive);
    await _markSeeded(hive, 27);
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get(g0355Id))['core_levels'], g0355CoreLevelsV25);
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });
}
