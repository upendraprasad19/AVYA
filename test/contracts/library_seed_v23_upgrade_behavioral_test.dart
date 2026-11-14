// Library Batch S1b-2 (seed v23, docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md): an install at the v22
// library has no N14 to N22 and holds E010 Pike Push Up at [Beginner, Intermediate] and E045 Romanian Deadlift at
// [Intermediate, Advanced]. Its next launch writes the nine loaded versions (with `same_movement_as`) and the two
// widened suitable_for values (the seed's putAll writes by id) and changes nothing else. Drives the REAL
// SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 22; drop a loaded version from the library;
// edit any other row of the bundle (the v22 digest pin).
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

/// The v23 bundle, rebuilt from the current one: Library Batch S1b-3 (seed v24) removed E053 (re-inserted at its v23
/// index from the restated v23 row) and gave G1373 `name_aliases` and `merged_ids` (stripped). Keeps the v22 -> v23 digest
/// chain below byte-proven.
List<Map<String, dynamic>> _v23Bundle() {
  final fx = jsonDecode(File('test/fixtures/library_e053_row_v23.json').readAsStringSync()) as Map<String, dynamic>;
  // Unit 1B-F (seed v25) tagged 14 rows `hip`; their v24 (= v23) tags are restated in library_hip_tags_v24.json.
  final hip = ((jsonDecode(File('test/fixtures/library_hip_tags_v24.json').readAsStringSync()) as Map<String, dynamic>)['rows']
      as Map<String, dynamic>);
  final rows = [
    for (final r0 in _bundled())
      () {
        final r = hip.containsKey(r0['id']) ? (Map<String, dynamic>.from(r0)..['injury_contraindications'] = hip[r0['id']]) : r0;
        // Unit 1B-R (seed v26) gave G0355 `beginner`; the v23 bundle keeps its v25 levels.
        // Unit 1B-F2 (seed v27) copied the overlays; the v23 bundle keeps them.
        final g = withOverlaysV26(withG0355V25(r));
        return g['id'] == 'G1373' ? (Map<String, dynamic>.from(g)..remove('name_aliases')..remove('merged_ids')) : g;
      }(),
  ];
  rows.insert((fx['_meta'] as Map<String, dynamic>)['v23_index'] as int, fx['row'] as Map<String, dynamic>);
  return rows;
}

/// The nine rows v23 adds (restated from the plan, never read from the library).
const _newIds = ['N14', 'N15', 'N16', 'N17', 'N18', 'N19', 'N20', 'N21', 'N22'];

/// suitable_for as v22 shipped it (restated, never read from git: CI checks out shallow).
const _v22Suitable = <String, List<String>>{
  'E010': ['Beginner', 'Intermediate'],
  'E045': ['Intermediate', 'Advanced'],
};

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

/// A v22 box: every bundled row except the nine new ones, with the two rows at their v22 suitable_for.
Future<void> _putV22Box(HiveService hive) async {
  for (final r in _bundled()) {
    if (_newIds.contains(r['id'])) continue;
    final old = _v22Suitable[r['id']];
    await hive.exerciseBox.put(r['id'], old == null ? r : {...r, 'suitable_for': old});
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: the bundled library ships the nine rows and the two widened rows', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in _newIds) {
      expect(byId[id], isNotNull, reason: id);
      expect(byId[id]!['same_movement_as'], isA<String>(), reason: id);
    }
    expect(byId['E010']!['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
    expect(byId['E045']!['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
  });

  // B-pass seat B (2026-11-09): _putV22Box builds the "v22" box FROM the v23 bundle, so "every other row unchanged"
  // below compares v23 rows with v23 rows and cannot see a v23 edit to some other row. This pin closes that: the v23
  // bundle minus the nine rows, with E010 / E045 back at their v22 suitable_for, must be byte-for-byte the v22 bundle
  // (sha256 of Dart's jsonEncode of the shipped v22 assets/data/exercise_library.json at 5d64d1a9, recorded 2026-11-09).
  test('the v23 bundle is the v22 bundle plus the nine rows and the two widenings, and nothing else', () {
    final rebuilt = [
      for (final r in _v23Bundle())
        if (!_newIds.contains(r['id'])) (_v22Suitable[r['id']] == null ? r : {...r, 'suitable_for': _v22Suitable[r['id']]}),
    ];
    expect(sha256.convert(utf8.encode(jsonEncode(rebuilt))).toString(),
        '7a37c26c8fdc14e075c90558e4cf6adea71ab91f7614982e910d23e4962065d8');
  });

  test('a v22 box ends at the current version (v27) with the nine rows and the widened suitable_for, and every other row unchanged', () async {
    final hive = HiveService.instance;
    await _putV22Box(hive);
    await _markSeeded(hive, 22);
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !_v22Suitable.containsKey(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in _newIds) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(id))), jsonEncode(byId[id]), reason: '$id written as bundled');
    }
    expect(_asJson(hive.exerciseBox.get('E010'))['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
    expect(_asJson(hive.exerciseBox.get('E045'))['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });

  test('MIRROR: a box already at the current version (v27, Unit 1B-F2) is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV22Box(hive);
    await _markSeeded(hive, 27);
    await SeedService.instance.seedIfNeeded();
    expect(hive.exerciseBox.get('N14'), isNull);
    expect(_asJson(hive.exerciseBox.get('E045'))['suitable_for'], ['Intermediate', 'Advanced']);
    expect(hive.configBox.get('exercise_library_version') as int, 27);
  });
}
