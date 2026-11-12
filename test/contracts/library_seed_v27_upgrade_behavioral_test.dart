// Generator Unit 1B-F2 (seed v27, OI-495, docs/plans/2026-11-12-generator-1bf2-overlay-copy.md): the core-list overlays
// are copied into the rows' own fields (slot_pattern -> movement_pattern on 13 rows, slot_focus -> target_focus on 19;
// 27 rows) and both overlay keys are removed, so the picker, queryV4 (the thin-day top-up) and the muscle label read one
// set of labels. An install at the v26 library holds the overlays; its next launch rewrites the 27 rows by id and changes
// nothing else. Drives the REAL SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 26; skip the importer's overlay-copy stage
// (the precondition); edit any other row of the bundle (the v26 digest pin).
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
import '../helpers/library_overlay_v26.dart';

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

/// The v26 bundle, rebuilt: the current asset with the 27 rows' overlays restored.
List<Map<String, dynamic>> _v26Bundle() => [for (final r in _bundled()) withOverlaysV26(r)];

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _putV26Box(HiveService hive) async {
  for (final r in _v26Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: no bundled row carries an overlay key, and the 27 rows differ from their v26 form', () {
    final rows = _bundled();
    expect(rows.where((r) => r.containsKey('slot_pattern') || r.containsKey('slot_focus')).map((r) => r['id']), isEmpty);
    expect(overlayRowIdsV27, hasLength(27));
    for (final r in rows.where((r) => overlayRowIdsV27.contains(r['id']))) {
      expect(jsonEncode(withOverlaysV26(r)), isNot(jsonEncode(r)), reason: '${r['id']}');
    }
  });

  // The rebuilt v26 bundle must be byte-for-byte the shipped v26 bundle: sha256 of Dart's jsonEncode of
  // assets/data/exercise_library.json at the branch base (main 67b536e4), computed independently with Python's compact
  // json.dumps (ensure_ascii off), the method of library_seed_v26_upgrade_behavioral_test.dart.
  test('the v27 bundle is the v26 bundle with the 27 overlays copied, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v26Bundle()))).toString(),
        '2fb9cc7377e39cd72e9e15dc5c3a6440b93d883b644b1ea06e8ce713f6858cef');
  });

  test('a v26 box ends at v27: the 27 rows are written as bundled, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _putV26Box(hive);
    await _markSeeded(hive, 26);
    expect(_asJson(hive.exerciseBox.get('E048'))['slot_pattern'], ['hip_dominant'], reason: 'precondition');
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !overlayRowIdsV27.contains(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in overlayRowIdsV27) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(id))), jsonEncode(byId[id]), reason: '$id written as bundled');
    }
    expect(_asJson(hive.exerciseBox.get('E048'))['movement_pattern'], ['hip_dominant']);
    expect(_asJson(hive.exerciseBox.get('E048')).containsKey('slot_pattern'), isFalse);
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });

  test('MIRROR: a box already at v27 is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV26Box(hive);
    await _markSeeded(hive, 27);
    await SeedService.instance.seedIfNeeded();
    for (final id in overlayRowIdsV27) {
      final r = _asJson(hive.exerciseBox.get(id));
      expect(r.containsKey('slot_pattern') || r.containsKey('slot_focus'), isTrue, reason: '$id keeps its v26 form');
    }
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });
}
