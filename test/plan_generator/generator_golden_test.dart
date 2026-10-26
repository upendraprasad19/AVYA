// Batch B1 Task 0 — golden of the REAL generator (flag-OFF identity proof).
//
// Each persona from test/helpers/generator_golden_personas.dart runs
// PlanGenerator.instance.generateV4 over the shipped library; the sha256 of
// jsonEncode(phase.toMap()) must equal the recorded fixture. First recorded on the
// pre-B1 tree (5696c4c8: lib/ and assets/ identical to main 08c077d1); re-recorded
// wholesale by Batch C1 on the 914-row library (the OFF generator changes on purpose
// when 629 rows join the pool, plan R6).
//
// Re-record only in a commit whose diagnose doc or plan names each changed key
// (B2, Batch C and OI-53 flips will):
//   RECORD_GENERATOR_GOLDEN=1 TZ=Asia/Kolkata flutter test test/plan_generator/generator_golden_test.dart
//
// Batch C1 (R6) adds three assertions inside the same persona loop, scoped to the NEW ids (G####, N##):
//   (i)   no picked new row is a calisthenics_skill, olympic, plyometric, high_impact or requires_coaching row;
//   (ii)  every picked new row carries its original-sibling floor, family-rule and twin tokens, and one with no tags is
//         a kV14SafePool name;
//   (iii) the picked new ids are non-empty (the new rows reach the generator at all).
// (i) and (ii) are collected into lists asserted BEFORE the hash diff, so a violation is visible on its own and not hidden
// behind "N golden keys differ"; both are skipped when recording. (iii) is the last test and computes any persona the group
// tests have not run (one run per persona however the tests are selected, the checkOnce pattern of core_list_pool_gate_test),
// so --plain-name on one group stays green.
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
import '../helpers/library_injury_floor.dart';

const _fixturePath = 'test/fixtures/generator_golden_hashes.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  final record = Platform.environment['RECORD_GENERATOR_GOLDEN'] == '1';
  final actual = <String, String>{};
  late List<Map<String, dynamic>> library;
  late Map<String, Map<String, dynamic>> byId;
  Map<String, dynamic>? oldFixture; // read before a record run overwrites it, for the change summary
  final changedByGroup = <String, int>{};

  setUpAll(() async {
    if (record && File(_fixturePath).existsSync()) {
      oldFixture = jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
    }
    tempDir = await Directory.systemTemp.createTemp('generator_golden');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    library = rows.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
    byId = {for (final r in library) r['id'] as String: r};
    for (final r in library) {
      await exBox.put((r['id'] ?? r['name']).toString(), r);
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    if (record) {
      final sorted = Map.fromEntries(
          actual.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
      File(_fixturePath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
                '_meta': {'recorded_on': 'library-batch-c C1 (914-row library)', 'personas': actual.length},
                ...sorted,
              })}\n');
    }
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final personas = generatorGoldenPersonas();
  final groups = <String>{for (final p in personas) p.group};

  // One run per persona however the tests are selected; only the hash and the built ids are kept, never the Phase.
  final ran = <String, ({String hash, List<String> ids})>{};
  ({String hash, List<String> ids}) runOnce(GoldenPersona p) => ran[p.key] ??= () {
        final phase = p.run();
        return (hash: sha256Hex(utf8.encode(jsonEncode(phase.toMap()))), ids: builtIds(phase).toList());
      }();

  for (final group in groups) {
    test('golden: $group', () {
      final fixture = record
          ? const <String, dynamic>{}
          : jsonDecode(File(_fixturePath).readAsStringSync())
              as Map<String, dynamic>;
      final diffs = <String>[];
      final violations = <String>[];
      for (final p in personas.where((p) => p.group == group)) {
        final r = runOnce(p);
        actual[p.key] = r.hash;
        if (!record && fixture[p.key] != r.hash) diffs.add(p.key);
        if (record && oldFixture != null && oldFixture![p.key] != r.hash) {
          changedByGroup.update(group, (v) => v + 1, ifAbsent: () => 1);
        }
        violations.addAll(newRowPickViolations(personaKey: p.key, builtIds: r.ids, byId: byId, library: library));
      }
      if (!record) {
        final one = violations.where((v) => v.contains(' (i) ')).toList();
        final two = violations.where((v) => v.contains(' (ii) ')).toList();
        expect(violations, isEmpty,
            reason: '${violations.length} new-row violations in $group (R6): (i) ${one.length}, (ii) ${two.length}; first 3 of each:\n'
                '${[...one.take(3), ...two.take(3)].join('\n')}');
      }
      expect(diffs, isEmpty,
          reason: '${diffs.length} golden keys differ; first 10: '
              '${diffs.take(10).join(', ')}');
    });
  }

  test('R6 (iii): the picked new ids are non-empty, and the derived summary', () {
    final picks = <String, int>{};
    var personasWithNew = 0;
    for (final p in personas) {
      final ids = runOnce(p).ids.where(isNewRowId).toSet();
      if (ids.isNotEmpty) personasWithNew++;
      for (final id in ids) {
        picks.update(id, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final top = picks.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final share = top.isEmpty ? 0.0 : top.first.value / personas.length;
    // ignore: avoid_print
    print('[golden summary] personas ${personas.length}; distinct new ids picked ${picks.length}; '
        'personas picking at least one new id $personasWithNew; top pick '
        '${top.isEmpty ? '-' : '${top.first.key} ${byId[top.first.key]!['name']} x${top.first.value} (${(share * 100).toStringAsFixed(1)}%)'}; '
        'top 10 ${top.take(10).map((e) => '${e.key}x${e.value}').join(', ')}');
    if (record) {
      // ignore: avoid_print
      print('[golden summary] changed personas by group: ${changedByGroup.isEmpty ? 'none or no prior fixture' : changedByGroup}; '
          'total ${changedByGroup.values.fold<int>(0, (a, b) => a + b)}');
      return;
    }
    expect(picks, isNotEmpty, reason: 'no golden persona picked any new row: the 629 rows never reach the generator');
  });

  test('golden: persona count matches the fixture', () {
    expect(personas.length, 998);
    if (!record) {
      final fixture = jsonDecode(File(_fixturePath).readAsStringSync())
          as Map<String, dynamic>;
      expect(fixture.keys.where((k) => k != '_meta').toSet(),
          {for (final p in personas) p.key});
    }
  });
}
