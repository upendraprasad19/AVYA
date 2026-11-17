// Unit 1B-R, Ruling 4 (docs/plans/2026-11-12-generator-1br-loaded-wins.md): with `configBox['disable_loaded_wins']
// = true` the generator reproduces the pre-1B-R ranking verbatim. Each of the 1,010 golden personas runs the REAL
// PlanGenerator.instance.generateV4 with the switch set; the sha256 of jsonEncode(phase.toMap()) must equal
// test/fixtures/generator_golden_hashes_loaded_wins_off.json, recorded by generator_golden_test.dart on run r0's tree
// (main 4e0637ae's picker code with this unit's seed v26 data). The fixture and this test are deleted in the commit
// that deletes the switch (tracked on the OI board).
//
// Mutation: ignore the flag (`final loadedWins = true;` in `_pickCoreList`) and the personas whose plan 1B-R changes
// go red here.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/generator_golden_personas.dart';

const _fixturePath = 'test/fixtures/generator_golden_hashes_loaded_wins_off.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('loaded_wins_golden');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.configBox.put('disable_loaded_wins', true);
    // Unit 2C-a: the fixture predates the balanced week, so its switch is set too.
    await HiveService.instance.configBox.put('disable_balanced_week', true);
  });

  tearDownAll(() async {
    await HiveService.instance.configBox.delete('disable_loaded_wins');
    await HiveService.instance.configBox.delete('disable_balanced_week');
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('the switch set: every golden persona equals the pre-1B-R world (run r0)', () {
    final fixture = jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
    final personas = generatorGoldenPersonas();
    expect(fixture.keys.where((k) => k != '_meta').toSet(), {for (final p in personas) p.key});
    final diffs = <String>[];
    for (final p in personas) {
      if (fixture[p.key] != sha256Hex(utf8.encode(jsonEncode(p.run().toMap())))) diffs.add(p.key);
    }
    expect(diffs, isEmpty, reason: '${diffs.length} keys differ with the switch set; first 10: ${diffs.take(10).join(', ')}');
  });
}
