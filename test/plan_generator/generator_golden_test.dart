// Batch B1 Task 0 — golden of the REAL generator (OFF identity proof).
//
// Each persona from test/helpers/generator_golden_personas.dart runs
// PlanGenerator.instance.generateV4 over the shipped library; the sha256 of
// jsonEncode(phase.toMap()) must equal the recorded fixture. Recorded on the
// pre-B1 tree (5696c4c8: lib/ and assets/ identical to main 08c077d1).
//
// Re-record only in a commit whose diagnose doc or plan names each changed key
// (B2, Batch C and OI-53 flips will):
//   RECORD_GENERATOR_GOLDEN=1 TZ=Asia/Kolkata flutter test test/plan_generator/generator_golden_test.dart
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

const _fixturePath = 'test/fixtures/generator_golden_hashes.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  final record = Platform.environment['RECORD_GENERATOR_GOLDEN'] == '1';
  final actual = <String, String>{};

  setUpAll(() async {
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
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(),
          Map<String, dynamic>.from(r));
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
                '_meta': {'recorded_on': '5696c4c8', 'personas': actual.length},
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

  for (final group in groups) {
    test('golden: $group', () {
      final fixture = record
          ? const <String, dynamic>{}
          : jsonDecode(File(_fixturePath).readAsStringSync())
              as Map<String, dynamic>;
      final diffs = <String>[];
      for (final p in personas.where((p) => p.group == group)) {
        final hash = sha256Hex(utf8.encode(jsonEncode(p.run().toMap())));
        actual[p.key] = hash;
        if (!record && fixture[p.key] != hash) diffs.add(p.key);
      }
      expect(diffs, isEmpty,
          reason: '${diffs.length} golden keys differ; first 10: '
              '${diffs.take(10).join(', ')}');
    });
  }

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
