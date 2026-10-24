// Injury re-check (seed v14) — an install that already holds the v13 library
// must receive the new injury tags on its next launch.
//
// Review Focus 3 of docs/plans/2026-10-23-library-injury-recheck.md. Presence of
// the number 14 in seed_service.dart proves nothing about a box: this drives the
// REAL SeedService.seedIfNeeded against a box holding a v13-shaped Push Up row.
// Mutation: put `_exerciseLibraryVersion` back to 13 and the row stays
// wrist-only, which reddens the first expectation.
//
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs
// (CLAUDE.md section 4.9).
//
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('a v13 box gets the v14 injury tags and the new version on seedIfNeeded', () async {
    final bundled = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();
    final shipped = bundled.firstWhere((r) => r['id'] == 'E005');
    expect(shipped['name'], 'Push Up');
    expect(shipped['injury_contraindications'], ['shoulder', 'wrist'],
        reason: 'the bundled row carries the founder call: wrist AND shoulder');

    // What a v13 install holds: the same row, wrist-only.
    final stale = Map<String, dynamic>.from(shipped)
      ..['injury_contraindications'] = ['wrist'];
    final hive = HiveService.instance;
    await hive.exerciseBox.put('E005', stale);
    await hive.configBox.put('seeded', true);
    await hive.configBox.put('seeded_exercises', true);
    await hive.configBox.put('seeded_foods', true);
    await hive.configBox.put('exercise_library_version', 13);
    // A version far above the food constant, so this never seeds foods into a
    // box the test did not open.
    await hive.configBox.put('food_library_version', 9999);

    await SeedService.instance.seedIfNeeded();

    final after = Map<String, dynamic>.from(hive.exerciseBox.get('E005') as Map);
    expect(after['injury_contraindications'], ['shoulder', 'wrist']);
    expect(hive.configBox.get('exercise_library_version') as int,
        greaterThanOrEqualTo(14));
  });
}
