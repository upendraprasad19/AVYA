// Batch M1 (seed v16, docs/plans/2026-10-27-library-batch-m1-media-data.md, Task 2.4) - an install that already holds the
// v15 library must receive the media fields (`media_slug`, `media_version`, `media_source`) on exactly the rows the media
// table maps on its next launch, and must keep every other field and every row it already has.
//
// Presence of the number 16 in seed_service.dart proves nothing about a box: this drives the REAL
// SeedService.seedIfNeeded against a box holding the 914 v15 library rows without the media keys, a custom exercise and a
// community exercise, both UUID-keyed.
// Mutation: put `_exerciseLibraryVersion` back to 15 and nothing is re-seeded, which reddens the first expectation.
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

const _customId = '7b1f6c1e-6f43-4d52-9d0c-0c0a3f1f0a01';
const _communityId = '0d0e0f10-1112-4314-9516-171819202122';
const _mediaKeys = ['media_slug', 'media_version', 'media_source'];

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _withoutMedia(Map<String, dynamic> row) =>
    {for (final e in row.entries) if (!_mediaKeys.contains(e.key)) e.key: e.value};

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  Future<void> markSeeded(int version) async {
    final hive = HiveService.instance;
    await hive.configBox.put('seeded', true);
    await hive.configBox.put('seeded_exercises', true);
    await hive.configBox.put('seeded_foods', true);
    await hive.configBox.put('exercise_library_version', version);
    // A version far above the food constant, so this never seeds foods into a box the test did not open.
    await hive.configBox.put('food_library_version', 9999);
    await hive.exerciseBox.put(_customId, {'id': _customId, 'name': 'My Own Curl', 'is_custom': true, 'equipment_needed': ['dumbbells']});
    await hive.exerciseBox.put(_communityId, {'id': _communityId, 'name': 'Shared Row', 'source': 'community', 'equipment_needed': ['cables']});
  }

  void expectSeededLikeBundled(List<Map<String, dynamic>> bundled) {
    final hive = HiveService.instance;
    final mapped = bundled.where((r) => r.containsKey('media_slug')).toList();
    expect(mapped, hasLength(617), reason: 'the bundled library carries the media fields on the 617 mapped rows');
    for (final r in bundled) {
      final stored = Map<String, dynamic>.from(hive.exerciseBox.get(r['id']) as Map);
      expect(stored.containsKey('media_slug'), r.containsKey('media_slug'), reason: '${r['id']} media keys');
      expect(stored, equals(r), reason: '${r['id']} must equal the bundled row after the upgrade');
    }
    expect(Map<String, dynamic>.from(hive.exerciseBox.get(_customId) as Map)['name'], 'My Own Curl');
    expect(Map<String, dynamic>.from(hive.exerciseBox.get(_communityId) as Map)['name'], 'Shared Row');
    expect(hive.exerciseBox.length, bundled.length + 2);
    expect(hive.configBox.get('exercise_library_version') as int, 16);
  }

  test('a v15 box gets the media fields on exactly the mapped ids and version 16; every other field and row stays', () async {
    final bundled = _bundled();
    final hive = HiveService.instance;
    for (final r in bundled) {
      await hive.exerciseBox.put(r['id'], _withoutMedia(r)); // what a v15 install holds
    }
    await markSeeded(15);
    expect(hive.exerciseBox.values.where((v) => (v as Map).containsKey('media_slug')), isEmpty, reason: 'the precondition: no media keys yet');

    await SeedService.instance.seedIfNeeded();

    expectSeededLikeBundled(bundled);
    // E274 keeps the v15 relabel; the upgrade changed nothing but the three keys.
    expect(Map<String, dynamic>.from(hive.exerciseBox.get('E274') as Map)['target_focus'], ['Mid Back']);
  });

  test('an install that skipped v15 (stored 13) also reaches 16 with the new rows and the media fields', () async {
    final bundled = _bundled();
    final hive = HiveService.instance;
    for (final r in bundled.where((r) => RegExp(r'^E\d').hasMatch(r['id'] as String))) {
      await hive.exerciseBox.put(r['id'], _withoutMedia(r));
    }
    await markSeeded(13);

    await SeedService.instance.seedIfNeeded();

    expectSeededLikeBundled(bundled);
  });

  test('a v16 box is left alone (the fast path): a row edited in the box is not overwritten', () async {
    final bundled = _bundled();
    final hive = HiveService.instance;
    for (final r in bundled) {
      await hive.exerciseBox.put(r['id'], r);
    }
    await markSeeded(16);
    final edited = Map<String, dynamic>.from(hive.exerciseBox.get('E001') as Map)..['name'] = 'Edited On Device';
    await hive.exerciseBox.put('E001', edited);

    await SeedService.instance.seedIfNeeded();

    expect((hive.exerciseBox.get('E001') as Map)['name'], 'Edited On Device');
    expect(hive.configBox.get('exercise_library_version') as int, 16);
  });
}
