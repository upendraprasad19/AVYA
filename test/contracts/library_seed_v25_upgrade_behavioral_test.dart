// Unit 1B-F, Ruling 12 (seed v25, founder d19, docs/plans/2026-11-10-generator-1bf-flip.md): the 14 lower-body jump rows
// (E063 Jump Rope, E065 Burpee, E066 Box Jump, E193 Jump Squat, E202 Jumping Jacks and the nine G rows of the jump,
// burpee and cardio_run families) gain `hip` in injury_contraindications, so a hip-injured user is never handed a row that
// lands from flight. An install at the v24 library holds them without `hip`; its next launch rewrites the 14 by id and
// changes nothing else. A bundle-only bump: injury_contraindications has no cloud column. Drives the REAL
// SeedService.seedIfNeeded.
//
// Mutations (each reddens a test below): put the version constant back to 24; drop `hip` from one of the 14 rows of the
// asset (the precondition); edit any other row of the bundle (the v24 digest pin).
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

const _hipIds = [
  'E063', 'E065', 'E066', 'E193', 'E202', 'G1473', 'G1472', 'G0053', 'G0371', 'G3219', 'G3361', 'G3222', 'G1201', 'G3656',
];
const _upperPlyoIds = ['G1750', 'G0492', 'G1273', 'G1353'];

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, List<String>> _v24Tags() => {
      for (final e in ((jsonDecode(File('test/fixtures/library_hip_tags_v24.json').readAsStringSync())
              as Map<String, dynamic>)['rows'] as Map<String, dynamic>)
          .entries)
        e.key: [for (final t in e.value as List) '$t'],
    };

/// The v24 bundle, rebuilt: the current asset with the 14 rows' tags restored from the restated fixture.
List<Map<String, dynamic>> _v24Bundle() {
  final tags = _v24Tags();
  return [
    for (final r in _bundled())
      tags.containsKey(r['id']) ? (Map<String, dynamic>.from(r)..['injury_contraindications'] = tags[r['id']]) : r,
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

Future<void> _putV24Box(HiveService hive) async {
  for (final r in _v24Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: the 14 rows carry hip in the bundle and not in the fixture; the 4 upper-body plyometric rows do not', () {
    final byId = {for (final r in _bundled()) r['id']: r};
    final tags = _v24Tags();
    expect(tags.keys.toSet(), _hipIds.toSet());
    for (final id in _hipIds) {
      expect(byId[id]!['injury_contraindications'], contains('hip'), reason: id);
      expect(tags[id], isNot(contains('hip')), reason: '$id in the v24 fixture');
      final now = [for (final t in byId[id]!['injury_contraindications'] as List) '$t'];
      expect(now, ([...tags[id]!, 'hip']..sort()), reason: '$id gains hip and nothing else');
    }
    for (final id in _upperPlyoIds) {
      expect(byId[id]!['injury_contraindications'], isNot(contains('hip')), reason: id);
    }
  });

  // The rebuilt v24 bundle must be byte-for-byte the shipped v24 bundle: sha256 of Dart's jsonEncode of
  // assets/data/exercise_library.json at the branch base, computed independently with Python's compact json.dumps
  // (ensure_ascii off; the same method reproduces the v23 pin d858d26b of library_seed_v24_upgrade_behavioral_test.dart).
  test('the v25 bundle is the v24 bundle plus hip on the 14 rows, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v24Bundle()))).toString(),
        '5470450a61073fbd6e2683dd323b1f38f6319b43123144d1c306eecda2b2ab13');
  });

  test('a v24 box ends at v25: the 14 rows are written as bundled, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _putV24Box(hive);
    await _markSeeded(hive, 24);
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !_hipIds.contains(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final byId = {for (final r in _bundled()) r['id']: r};
    for (final id in _hipIds) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(id))), jsonEncode(byId[id]), reason: '$id written as bundled');
    }
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 25);
  });

  test('MIRROR: a box already at v25 is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV24Box(hive);
    await _markSeeded(hive, 25);
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get('E193'))['injury_contraindications'], isNot(contains('hip')));
    expect(hive.configBox.get('exercise_library_version') as int, 25);
  });
}
