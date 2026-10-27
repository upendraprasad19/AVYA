// Batch C1 (seed v15, docs/plans/2026-10-25-library-batch-c-new-rows.md, Task 4.4) - an install that already holds the
// v14 library must receive the new rows and the E274 relabel on its next launch, and must keep every row it already has.
//
// Presence of the number 15 in seed_service.dart proves nothing about a box: this drives the REAL
// SeedService.seedIfNeeded against a box holding the 285 v14 library rows (E274 still labelled Upper Back), a custom
// exercise and a community exercise, both UUID-keyed.
// Mutation: put `_exerciseLibraryVersion` back to 14 and nothing is seeded, which reddens the first expectation.
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

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('a v14 box gets the new rows, the E274 relabel and version 15; the 285 and the UUID-keyed rows stay', () async {
    final bundled = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final original = bundled.where((r) => RegExp(r'^E\d').hasMatch(r['id'] as String)).toList();
    final added = bundled.where((r) => RegExp(r'^[GN]\d').hasMatch(r['id'] as String)).toList();
    expect(original, hasLength(285), reason: 'the v14 library is the 285 E-id rows');
    expect(added, isNotEmpty, reason: 'run: node scripts/add_library_batch_c_v15.js');
    expect(bundled.firstWhere((r) => r['id'] == 'E274')['target_focus'], ['Mid Back']);

    final hive = HiveService.instance;
    for (final r in original) {
      final row = Map<String, dynamic>.from(r);
      if (row['id'] == 'E274') row['target_focus'] = ['Upper Back']; // what a v14 install holds
      await hive.exerciseBox.put(row['id'], row);
    }
    final custom = {'id': _customId, 'name': 'My Own Curl', 'is_custom': true, 'equipment_needed': ['dumbbells']};
    final community = {'id': _communityId, 'name': 'Shared Row', 'source': 'community', 'equipment_needed': ['cables']};
    await hive.exerciseBox.put(_customId, custom);
    await hive.exerciseBox.put(_communityId, community);
    await hive.configBox.put('seeded', true);
    await hive.configBox.put('seeded_exercises', true);
    await hive.configBox.put('seeded_foods', true);
    await hive.configBox.put('exercise_library_version', 14);
    // A version far above the food constant, so this never seeds foods into a box the test did not open.
    await hive.configBox.put('food_library_version', 9999);

    await SeedService.instance.seedIfNeeded();

    for (final r in added) {
      expect(hive.exerciseBox.containsKey(r['id']), isTrue, reason: '${r['id']} ${r['name']} was not seeded');
    }
    for (final r in original) {
      expect(hive.exerciseBox.containsKey(r['id']), isTrue, reason: '${r['id']} was lost');
    }
    final e274 = Map<String, dynamic>.from(hive.exerciseBox.get('E274') as Map);
    expect(e274['target_focus'], ['Mid Back']);
    expect(Map<String, dynamic>.from(hive.exerciseBox.get(_customId) as Map)['name'], 'My Own Curl');
    expect(Map<String, dynamic>.from(hive.exerciseBox.get(_communityId) as Map)['name'], 'Shared Row');
    expect(hive.exerciseBox.length, original.length + added.length + 2);
    expect(hive.configBox.get('exercise_library_version') as int, 15);
  });
}
