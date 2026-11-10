// Library Batch S1b-3 (seed v24, OI-147, docs/plans/2026-11-10-library-batch-s1b3-retire-donkey-calf-raise.md): an install
// at the v23 library holds E053 Donkey Calf Raise and a G1373 without `name_aliases` / `merged_ids`. Its next launch
// deletes E053 (G1373 lists it in `merged_ids`, so SeedService's prune removes it), rewrites G1373 by id, and changes
// nothing else. A community row that happens to share E053's name (a UUID key) is never touched: the prune deletes ids.
// Drives the REAL SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 23; drop `merged_ids` from G1373 (E053
// survives); edit any other row of the bundle (the v23 digest pin).
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

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/library_e053_row_v23.json').readAsStringSync()) as Map<String, dynamic>;

/// The v23 bundle, rebuilt: E053 back at its v23 index (the restated v23 row) and G1373 without the two keys.
List<Map<String, dynamic>> _v23Bundle() {
  final fx = _fixture();
  final rows = [
    for (final r in _bundled()) r['id'] == 'G1373' ? (Map<String, dynamic>.from(r)..remove('name_aliases')..remove('merged_ids')) : r,
  ];
  rows.insert((fx['_meta'] as Map<String, dynamic>)['v23_index'] as int, fx['row'] as Map<String, dynamic>);
  return rows;
}

const _communityId = '3f2a1b0c-5d6e-4f70-8a91-b2c3d4e5f607';

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _putV23Box(HiveService hive) async {
  for (final r in _v23Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
  await hive.exerciseBox.put(_communityId, {'id': _communityId, 'name': 'Donkey Calf Raise', 'source': 'community'});
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: the bundle ships no E053, and G1373 carries merged_ids [E053] and the alias', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    expect(byId.containsKey('E053'), isFalse);
    expect(byId['G1373']!['merged_ids'], ['E053']);
    expect(byId['G1373']!['name_aliases'], ['Donkey Calf Raise']);
    expect((_fixture()['row'] as Map)['id'], 'E053');
  });

  // The rebuilt v23 bundle must be byte-for-byte the shipped v23 bundle: sha256 of Dart's jsonEncode of
  // assets/data/exercise_library.json at 01ed781c (PR #237), computed independently from git with Python's compact
  // json.dumps (the same method reproduces the v22 pin 7a37c26c of library_seed_v23_upgrade_behavioral_test.dart).
  test('the v24 bundle is the v23 bundle minus E053, plus the two G1373 keys, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v23Bundle()))).toString(),
        'd858d26b59e0a7574f779c59f3910647200eb206a4805126122bbc936f8daeff');
  });

  test('a v23 box ends at v24: E053 is gone, G1373 is written as bundled, the community row and every other row are unchanged', () async {
    final hive = HiveService.instance;
    await _putV23Box(hive);
    await _markSeeded(hive, 23);
    expect(hive.exerciseBox.containsKey('E053'), isTrue, reason: 'precondition: the v23 box holds E053');
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => k != 'E053' && k != 'G1373'))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    expect(hive.exerciseBox.containsKey('E053'), isFalse, reason: 'E053 is pruned (G1373 lists it in merged_ids)');
    final g = _bundled().singleWhere((r) => r['id'] == 'G1373');
    expect(jsonEncode(_asJson(hive.exerciseBox.get('G1373'))), jsonEncode(g), reason: 'G1373 written as bundled');
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(_asJson(hive.exerciseBox.get(_communityId))['name'], 'Donkey Calf Raise', reason: 'the prune deletes ids, never a name');
    expect(hive.exerciseBox.length, _bundled().length + 1);
    expect(hive.configBox.get('exercise_library_version') as int, 24);
  });

  test('MIRROR: a box already at v24 is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV23Box(hive);
    await _markSeeded(hive, 24);
    await SeedService.instance.seedIfNeeded();
    expect(hive.exerciseBox.containsKey('E053'), isTrue);
    expect(_asJson(hive.exerciseBox.get('G1373')).containsKey('merged_ids'), isFalse);
    expect(hive.configBox.get('exercise_library_version') as int, 24);
  });
}
