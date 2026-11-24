// test/contracts/library_v28_lunge_alias_contract_test.dart
//
// OI-523 (library v28, docs/plans/2026-11-23-oi523-lunge-alias-v28.md): "Reverse Lunge" is NOT an alias of G3470 Forward Lunge.
// A forward lunge is not a reverse lunge, and the coach tool getFormCues answers a name through `name_aliases`, so the alias
// would answer a reverse lunge with forward-lunge cues. Four things must agree, and this pins all four:
//   1. the removals generator (REPLACEMENT.E144.alias false) and the removals file (E144 has no alias_to, keeps replacement G3470),
//   2. the shipped asset (G3470 has no name_aliases; no row aliases the name),
//   3. the seed generator's kept-row record (before ["Reverse Lunge"], after null),
//   4. the reader: ExerciseRepository.getByExactName resolves "Forward Lunge" to G3470 and "Reverse Lunge" to nothing.
// The asset is written by the importer from the removals file (G3470 is a source row, rebuilt on every run), so a hand edit of
// the asset cannot stay green: `node scripts/add_library_batch_c_v15.js --check` is the proof of that half.
//
// MUTATION (rule 21), run by the author: E144 back to `alias: true` in the generator and the file regenerated -> tests 1, 2 and
// 4 red; the asset with the alias put back -> tests 2 and 4 red; the record's `after` changed -> test 3 red.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

String _norm(Object? s) => '$s'.trim().toLowerCase();

List<Map<String, dynamic>> _library() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the removals generator and file: E144 is retired with no alias target', () {
    test('REPLACEMENT.E144 says alias: false and keeps its replacement G3470', () {
      final gen = File('scripts/library_batch_c2_removals_gen.js').readAsStringSync();
      expect(gen, contains("E144: { to: 'G3470', alias: false,"));
      expect(gen, isNot(contains("E144: { to: 'G3470', alias: true")));
    });

    test('the removals file: E144 has no alias_to, keeps replacement G3470, and no entry aliases to G3470', () {
      final entries = (_json('scripts/data/library_batch_c2_removals.json')['entries'] as List).cast<Map<String, dynamic>>();
      final e144 = entries.singleWhere((e) => e['id'] == 'E144');
      expect(e144['decision'], 'remove');
      expect(e144['name'], 'Reverse Lunge');
      expect(e144['replacement'], 'G3470');
      expect(e144.containsKey('alias_to'), isFalse);
      expect(entries.where((e) => e['alias_to'] == 'G3470'), isEmpty);
    });
  });

  group('the shipped asset', () {
    test('G3470 has no name_aliases, and no row in the library aliases or is named "Reverse Lunge"', () {
      final rows = _library();
      final g = rows.singleWhere((r) => r['id'] == 'G3470');
      expect(g['name'], 'Forward Lunge');
      expect(g.containsKey('name_aliases'), isFalse);
      for (final r in rows) {
        final aliases = ((r['name_aliases'] as List?) ?? const []).map(_norm);
        expect(aliases.contains('reverse lunge'), isFalse, reason: '${r['id']} aliases it');
        expect(_norm(r['name']), isNot('reverse lunge'), reason: '${r['id']} is named it (E144 is retired)');
      }
    });
  });

  group('the seed generator record', () {
    test('G3470: before ["Reverse Lunge"], after null (the key is absent from the asset)', () {
      final rows = (_json('scripts/data/library_v28_lunge_alias.json')['rows'] as List).cast<Map<String, dynamic>>();
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'G3470');
      expect(rows.single['before'], ['Reverse Lunge']);
      expect(rows.single['after'], isNull);
      expect(_library().singleWhere((r) => r['id'] == 'G3470').containsKey('name_aliases'), isFalse);
    });
  });

  group('the reader: ExerciseRepository.getByExactName over the shipped library', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('lunge_alias_v28');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      final box = await Hive.openBox(HiveService.exerciseBoxName);
      await box.putAll({for (final r in _library()) r['id'] as String: r});
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('"Forward Lunge" resolves to G3470; "Reverse Lunge" resolves to nothing (no alias fallback to the wrong movement)', () {
      final repo = ExerciseRepository.instance;
      expect(repo.getByExactName('Forward Lunge')?['id'], 'G3470');
      expect(repo.getByExactName('Reverse Lunge'), isNull);
      expect(repo.getByExactName(' reverse lunge '), isNull);
    });

    test('control: another alias still resolves (the repository fallback itself is intact)', () {
      expect(ExerciseRepository.instance.getByExactName('Hip Abductor Machine')?['id'], 'E107');
    });
  });
}
