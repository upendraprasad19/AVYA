// test/contracts/library_seed_v28_upgrade_behavioral_test.dart
//
// OI-523 (seed v28, docs/plans/2026-11-23-oi523-lunge-alias-v28.md): G3470 Forward Lunge loses its name_aliases entry
// "Reverse Lunge" (a forward lunge is not a reverse lunge). A device at v27 holds the alias in its Hive box; without the
// version bump it would keep it (the coach tool and the name lookups would answer a reverse lunge with forward-lunge data).
// Pattern: library_seed_v27_upgrade_behavioral_test.dart.
// A plain test(), not testWidgets: real file I/O inside testWidgets hangs (CLAUDE.md section 4.9).
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
import '../helpers/library_lunge_alias_v28.dart';

List<Map<String, dynamic>> _bundled() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

/// The v27 bundle, rebuilt: the current asset with G3470's alias put back.
List<Map<String, dynamic>> _v27Bundle() => [for (final r in _bundled()) withLungeAliasV27(r)];

Future<void> _markSeeded(HiveService hive, int exerciseVersion) async {
  await hive.configBox.put('seeded', true);
  await hive.configBox.put('seeded_exercises', true);
  await hive.configBox.put('seeded_foods', true);
  await hive.configBox.put('exercise_library_version', exerciseVersion);
  await hive.configBox.put('food_library_version', 9999);
}

Map<String, dynamic> _asJson(Object? row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Future<void> _putV27Box(HiveService hive) async {
  for (final r in _v27Bundle()) {
    await hive.exerciseBox.put(r['id'], r);
  }
}

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('precondition: the shipped library has no row aliased "Reverse Lunge", and the rebuilt v27 row differs from it', () {
    final rows = _bundled();
    for (final r in rows) {
      final aliases = ((r['name_aliases'] as List?) ?? const []).map((a) => '$a'.trim().toLowerCase());
      expect(aliases.contains('reverse lunge'), isFalse, reason: '${r['id']}');
    }
    final g = rows.firstWhere((r) => r['id'] == lungeAliasRowIdV28);
    expect(g.containsKey('name_aliases'), isFalse);
    expect(jsonEncode(withLungeAliasV27(g)), isNot(jsonEncode(g)));
    expect(withLungeAliasV27(g)['name_aliases'], [lungeAliasV28]);
    // the key goes back at its original position: before the three media keys, which stay last
    final keys = withLungeAliasV27(g).keys.toList();
    expect(keys.indexOf('name_aliases'), 41);
    expect(keys.indexOf('name_aliases'), lessThan(keys.indexOf('media_slug')));
  });

  // The rebuilt v27 bundle must be byte-for-byte the shipped v27 bundle: sha256 of Dart's jsonEncode of
  // assets/data/exercise_library.json at the branch base (main 70add5cf), computed independently with Python's compact
  // json.dumps (ensure_ascii off), the method of library_seed_v27_upgrade_behavioral_test.dart.
  test('the v28 bundle is the v27 bundle with G3470 alias removed, and nothing else', () {
    expect(sha256.convert(utf8.encode(jsonEncode(_v27Bundle()))).toString(),
        'ef1cea152b3824cfae6e9508cbf8d214e46a87a1225b0f91676c8fb8d7682f18');
  });

  test('a v27 box ends at v28: G3470 is written as bundled without the alias, every other row is unchanged', () async {
    final hive = HiveService.instance;
    await _putV27Box(hive);
    await _markSeeded(hive, 27);
    expect(_asJson(hive.exerciseBox.get(lungeAliasRowIdV28))['name_aliases'], [lungeAliasV28], reason: 'precondition');
    final others = {
      for (final id in hive.exerciseBox.keys.where((k) => k != lungeAliasRowIdV28))
        id as String: jsonEncode(_asJson(hive.exerciseBox.get(id)))
    };

    await SeedService.instance.seedIfNeeded();

    final byId = {for (final r in _bundled()) r['id']: r};
    expect(jsonEncode(_asJson(hive.exerciseBox.get(lungeAliasRowIdV28))), jsonEncode(byId[lungeAliasRowIdV28]));
    expect(_asJson(hive.exerciseBox.get(lungeAliasRowIdV28)).containsKey('name_aliases'), isFalse);
    for (final e in others.entries) {
      expect(jsonEncode(_asJson(hive.exerciseBox.get(e.key))), e.value, reason: '${e.key} must be unchanged');
    }
    expect(hive.exerciseBox.length, _bundled().length);
    expect(hive.configBox.get('exercise_library_version') as int, 28);
  });

  test('a custom row named "Reverse Lunge" survives the upgrade (the prune deletes ids, never a name)', () async {
    final hive = HiveService.instance;
    await _putV27Box(hive);
    await _markSeeded(hive, 27);
    const customId = 'custom_reverse_lunge_oi523';
    await hive.exerciseBox.put(customId, {'id': customId, 'name': 'Reverse Lunge', 'is_custom': true});

    await SeedService.instance.seedIfNeeded();

    expect(_asJson(hive.exerciseBox.get(customId))['name'], 'Reverse Lunge');
    expect(_asJson(hive.exerciseBox.get(lungeAliasRowIdV28)).containsKey('name_aliases'), isFalse);
  });

  test('MIRROR: a box already at the current version (v28) is not rewritten (the upgrade fires only when the stored version is older)', () async {
    final hive = HiveService.instance;
    await _putV27Box(hive);
    await _markSeeded(hive, 28);
    await SeedService.instance.seedIfNeeded();
    expect(_asJson(hive.exerciseBox.get(lungeAliasRowIdV28))['name_aliases'], [lungeAliasV28], reason: 'keeps its v27 form');
    expect(hive.configBox.get('exercise_library_version') as int, 28);
  });
}
