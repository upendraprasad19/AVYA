// Batch C2a (seed v18, OI-460, docs/plans/2026-11-04-library-batch-c2a-removals.md): an install that holds the v17 library
// (the BASE rows, removed ones included) loses exactly the removed ids on its next launch and keeps every other row, the
// UUID-keyed custom and community rows included. Drives the REAL SeedService.seedIfNeeded.
//
// The pre-state is the committed base fixture (test/fixtures/library_c2_base_depth.json), never git history.
// Mutations (each reddens a test below): delete the second pruneRetired( call in SeedService._seedExercises; put the
// version constant back to 17; add a shipped id to kRetiredLibraryIdsNoTwin.
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/library_retired_ids.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';

const _customId = '7b1f6c1e-6f43-4d52-9d0c-0c0a3f1f0a01';
const _communityId = '0d0e0f10-1112-4314-9516-171819202122';

Set<String> _removeIds() => {
      for (final e in ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync()) as Map<String, dynamic>)['entries'] as List))
        if ((e as Map)['decision'] == 'remove') e['id'] as String,
    };

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('the retired set equals the removals file and never intersects the bundled ids', () {
    final shipped = {for (final r in _bundled()) r['id'] as String};
    expect(kRetiredLibraryIdsNoTwin, _removeIds());
    expect(kRetiredLibraryIdsNoTwin.intersection(shipped), isEmpty, reason: 'a shipped id in the retired set');
    expect(kRetiredLibraryIdsNoTwin, isNotEmpty);
  });

  test('a v17 box holding the removed rows loses exactly them; every other row, custom and community rows stay', () async {
    final hive = HiveService.instance;
    final bundled = _bundled();
    final removed = _removeIds();
    final base = (jsonDecode(File('test/fixtures/library_c2_base_depth.json').readAsStringSync()) as Map<String, dynamic>)['rows'] as List;
    for (final r in bundled) {
      await hive.exerciseBox.put(r['id'], r);
    }
    for (final id in removed) {
      final b = base.cast<Map>().firstWhere((r) => r['id'] == id);
      await hive.exerciseBox.put(id, {'id': id, 'name': b['name']}); // what the v17 install still holds
    }
    await hive.configBox.put('seeded', true);
    await hive.configBox.put('seeded_exercises', true);
    await hive.configBox.put('seeded_foods', true);
    await hive.configBox.put('exercise_library_version', 17);
    await hive.configBox.put('food_library_version', 9999);
    await hive.exerciseBox.put(_customId, {'id': _customId, 'name': 'Reverse Lunge', 'is_custom': true});
    await hive.exerciseBox.put(_communityId, {'id': _communityId, 'name': 'Shared Row', 'source': 'community'});
    expect(removed.every(hive.exerciseBox.containsKey), isTrue, reason: 'precondition: the removed rows are in the box');

    await SeedService.instance.seedIfNeeded();

    for (final id in removed) {
      expect(hive.exerciseBox.containsKey(id), isFalse, reason: '$id must be pruned');
    }
    expect(hive.exerciseBox.length, bundled.length + 2);
    for (final r in bundled) {
      expect(hive.exerciseBox.containsKey(r['id']), isTrue, reason: '${r['id']} stays');
    }
    // A custom row named like a removed row is untouched by the id prune.
    expect((hive.exerciseBox.get(_customId) as Map)['name'], 'Reverse Lunge');
    expect((hive.exerciseBox.get(_communityId) as Map)['name'], 'Shared Row');
    expect(hive.configBox.get('exercise_library_version') as int, 25);
  });
}
