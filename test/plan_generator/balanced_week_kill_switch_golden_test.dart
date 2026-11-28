// Unit 2C-a (docs/plans/2026-11-14-generator-step2c-balanced-week.md S5, OI-475): with
// `configBox['disable_balanced_week'] = true` the generator reproduces today's splits and credit verbatim. Each of the
// 1,010 golden personas runs the REAL PlanGenerator.instance.generateV4 with the switch set; the sha256 of
// jsonEncode(phase.toMap()) must equal test/fixtures/generator_golden_hashes_balanced_week_off.json, recorded on the
// base tree 421cd2d2 with `disable_balanced_week` set and the 3A / 3C keys unset (generator-killswitch-3a3c, plan §1). The fixture and this test are deleted in the commit that
// deletes the switch (tracked on the OI board).
//
// Mutation: ignore the flag in `SplitResolver.balancedWeekApplies` and every 60+-minute build_muscle 3 / 4 / 5-day
// persona goes red here.
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

const _fixturePath = 'test/fixtures/generator_golden_hashes_balanced_week_off.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('balanced_week_golden');
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
    await HiveService.instance.configBox.put('disable_balanced_week', true);
  });

  tearDownAll(() async {
    await HiveService.instance.configBox.delete('disable_balanced_week');
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // Since library v30 (OI-443) these values are recorded from the current tree with the switch set;
  // equality with the older tree they name was last proven at seed 29,
  // and now rests on the plan-engine code being unchanged.
  test('the switch set: every golden persona equals the recorded switch-off world', () {
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
