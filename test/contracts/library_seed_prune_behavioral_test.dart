// Batch A Task 2 — the seed prune removes retired library rows from an install
// that already holds them.
//
// `_seedExercises` writes with `putAll`, which never deletes, so before v12 a
// retired row would have lived on in every existing install's exerciseBox and
// kept being offered by the generator and the pickers. The prune deletes
// exactly the ids listed in the bundled rows' `merged_ids` and nothing else:
// community rows share the box under UUID keys and must survive.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/seed_service.dart';

void main() {
  late Directory tempDir;
  final bundled = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('seed_prune');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('retiredLibraryIds is exactly the union of merged_ids', () {
    expect(SeedService.retiredLibraryIds(bundled),
        {'E241', 'E240', 'E225', 'E249', 'E165', 'E167', 'E168'});
    expect(SeedService.retiredLibraryIds(const []), isEmpty);
  });

  test('an upgraded box loses only the retired ids', () async {
    final box = await Hive.openBox('prune_upgrade');
    const community = '0c5e9f2a-1111-4b2c-9d3e-123456789abc';
    await box.putAll({
      'E241': {'id': 'E241', 'name': 'Close-Grip Bench Press'},
      'E016': {'id': 'E016', 'name': 'Close Grip Bench Press'},
      community: {'id': community, 'name': 'Community Row'},
    });
    await SeedService.pruneRetired(box, SeedService.retiredLibraryIds(bundled));
    expect(box.containsKey('E241'), isFalse);
    expect(box.containsKey('E016'), isTrue);
    expect(box.containsKey(community), isTrue);
    // A second run (every later re-seed) must not throw.
    await SeedService.pruneRetired(box, SeedService.retiredLibraryIds(bundled));
    expect(box.length, 2);
    await box.close();
  });

  test('a fresh box is left untouched', () async {
    final box = await Hive.openBox('prune_fresh');
    await SeedService.pruneRetired(box, SeedService.retiredLibraryIds(bundled));
    expect(box.isEmpty, isTrue);
    await box.close();
  });
}
