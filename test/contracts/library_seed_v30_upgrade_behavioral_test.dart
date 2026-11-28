// test/contracts/library_seed_v30_upgrade_behavioral_test.dart
//
// Seed v30 (docs/plans/2026-11-28-media-two-new-two-retag.md): G0592 and G0979 are new; E027 and E120 are retagged and
// gain their media keys. A device at v29 holds the old rows in its Hive box; without the version bump it would never see
// any of it. Pattern: library_seed_v29_upgrade_behavioral_test.dart. A plain test(), not testWidgets (CLAUDE.md 4.9).
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
import '../helpers/library_v30_rows.dart';

const _touched = {'E027', 'E120', 'G0592', 'G0979', 'G0574'};

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _seedV29(HiveService hive, {required int markedVersion}) async {
  for (final r in beforeV30(_bundled())) {
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

  // sha256 of the shipped v29 asset (d2d92832), computed from git with Python's compact json.dumps (ensure_ascii off).
  test('the v30 bundle is the v29 bundle plus two rows, the two retags and the G0574 rotation change', () {
    expect(sha256.convert(utf8.encode(jsonEncode(beforeV30(_bundled())))).toString(),
        '93a39007e24f1ebe9e81ab621e65add2c95b76c5a85fbc6ba50a5cd4a5907c54');
    expect(_bundled().length, beforeV30(_bundled()).length + newRowIdsV30.length);
  });

  test('a v29 box ends at v30: the five rows are written as bundled, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _seedV29(hive, markedVersion: 29);
    for (final id in newRowIdsV30) {
      expect(hive.exerciseBox.get(id), isNull, reason: 'precondition $id');
    }
    expect(_asJson(hive.exerciseBox.get('E027'))['equipment_needed'], ['barbell'], reason: 'precondition');
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => !_touched.contains(k)))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final byId = {for (final r in _bundled()) r['id'] as String: r};
    for (final id in _touched) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(id))), jsonEncode(byId[id]), reason: id);
    }
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.configBox.get('exercise_library_version') as int, 30);
  });

  test('MIRROR: a box already at the current version (v30) is not rewritten', () async {
    final hive = HiveService.instance;
    await _seedV29(hive, markedVersion: 30);
    await SeedService.instance.seedIfNeeded();
    for (final id in newRowIdsV30) {
      expect(hive.exerciseBox.get(id), isNull, reason: id);
    }
    expect(_asJson(hive.exerciseBox.get('E120'))['equipment_needed'], ['barbell']);
  });
}
