// test/contracts/library_seed_v29_upgrade_behavioral_test.dart
//
// Seed v29 (docs/plans/2026-11-26-media-three-adds.md): E051, E109 and E264 gain their three media keys. A device at v28
// holds the rows without them in its Hive box; without the version bump it would never show the three animations.
// Pattern: library_seed_v28_upgrade_behavioral_test.dart. A plain test(), not testWidgets (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/library_media_three_v29.dart';

const _slugs = {
  'E051': '0108-barbell-standing-leg-calf-raise',
  'E109': '0228-cable-standing-kickback',
  'E264': '9001-table-row-clean',
};

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _v28Bundle() => [for (final r in _bundled()) withoutMediaV29(r)];

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _seedV28(HiveService hive, {required int markedVersion}) async {
  for (final r in _v28Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', markedVersion);
  await hive.configBox.put('food_library_version', 9999);
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  // sha256 of the shipped v28 asset (HEAD 7ba0745a), computed from git with Python's compact json.dumps (ensure_ascii off).
  test('the v29 bundle is the v28 bundle plus the media keys of three rows, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v28Bundle()))).toString(),
        '62825408779e63bcbc883fe85e16e0e44de4473d5c217e77c237585d1666311c');
    final byId = {for (final r in _bundled()) r['id'] as String: r};
    for (final e in _slugs.entries) {
      expect(byId[e.key]!['media_slug'], e.value, reason: e.key);
      expect(byId[e.key]!['media_version'], 1);
      expect(byId[e.key]!['media_source'], 'wardroom');
    }
  });

  test('a v28 box ends at v29: the three rows get their animation, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _seedV28(hive, markedVersion: 28);
    for (final id in _slugs.keys) {
      expect(_asJson(hive.exerciseBox.get(id)).containsKey('media_slug'), isFalse, reason: 'precondition $id');
    }
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !_slugs.containsKey(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    for (final e in _slugs.entries) {
      expect(_asJson(hive.exerciseBox.get(e.key))['media_slug'], e.value, reason: e.key);
    }
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.configBox.get('exercise_library_version') as int, 29);
  });

  test('MIRROR: a box already at the current version (v29) is not rewritten', () async {
    final hive = HiveService.instance;
    await _seedV28(hive, markedVersion: 29);
    await SeedService.instance.seedIfNeeded();
    for (final id in _slugs.keys) {
      expect(_asJson(hive.exerciseBox.get(id)).containsKey('media_slug'), isFalse, reason: id);
    }
  });
}
