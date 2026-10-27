// Batch M1 (plan R1, R3, R5, R13): scripts/build_library_media_v16.js builds the provenance
// table `scripts/data/library_media_v16.json` from the media map, the Wardroom ledger, the
// files on disk and the shipped library. These tests run the REAL script against a fixture
// Wardroom tree (test/helpers/webp_fixture.dart); no test reads the founder's folder.
//
// Run: flutter test test/scripts/library_media_builder_test.dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/spawn.dart';
import '../helpers/webp_fixture.dart';

const _builder = 'scripts/build_library_media_v16.js';
const _slugRegex = r'^\d{4}-[a-z0-9]+(-[a-z0-9]+)*$';

List<FixtureEntry> _defaultEntries() => [
      FixtureEntry(number: '0103', name: 'Barbell Standing Ab Rollout', seed: 1),
      FixtureEntry(number: '3643', name: "Farmer's Walk", seed: 2),
      FixtureEntry(number: '0007', name: 'Alternate Lateral Pulldown', seed: 3),
      FixtureEntry(
        number: '6000',
        name: 'Alias One',
        duplicateOf: '0103_Barbell_Standing_Ab_Rollout',
        sameBytesAs: '0103_Barbell_Standing_Ab_Rollout',
      ),
      FixtureEntry(id: 'table-row-clean', name: 'Table Row Clean', seed: 9),
    ];

const _defaultMap = <String, Object>{
  'G0103': {'_gif': '0103', '_folder': 'Barbell Standing Ab Rollout'},
  'G3643': {'_gif': '3643', '_folder': "Farmer's Walk"},
  'N06': {'_gif': '3643'},
  'N01': <String, Object>{},
  'G0007': {'_gif': '0007', '_folder': 'Alternate Lateral Pulldown'},
  'G6000': {'_gif': '6000'},
};

/// The library the builder sees: G0007 (the held row) is absent on purpose.
List<Map<String, Object>> _defaultLib() => [
      for (final id in ['G0103', 'G3643', 'N06', 'N01', 'G6000']) {'id': id, 'source': 'exercise-gif-set'},
      {'id': 'E050', 'source': 'other'},
      {'id': 'E060', 'source': 'other'},
    ];

class _Env {
  _Env({List<FixtureEntry>? entries}) : dir = Directory.systemTemp.createTempSync('lmb_') {
    ward = writeFixtureWardroom(Directory('${dir.path}/ward')..createSync(), entries ?? _defaultEntries());
    writeMap(_defaultMap);
    writeLib(_defaultLib());
  }

  final Directory dir;
  late FixtureWardroom ward;

  String get table => '${dir.path}/table.json';
  String get map => '${dir.path}/map.json';
  String get lib => '${dir.path}/lib.json';
  String get oldRows => '${dir.path}/old_rows.json';

  void writeMap(Map<String, Object> m) => File(map).writeAsStringSync(jsonEncode(m));
  void writeLib(List<Map<String, Object>> rows) => File(lib).writeAsStringSync(jsonEncode(rows));
  void writeOldRows(Object o) => File(oldRows).writeAsStringSync(jsonEncode(o));
  Map<String, dynamic> readTable() => jsonDecode(File(table).readAsStringSync()) as Map<String, dynamic>;
  void writeTable(Map<String, dynamic> t) => File(table).writeAsStringSync(jsonEncode(t));

  /// Runs the builder. [mode] is `--write`, `--check` or empty; [wardroom] false omits the folder.
  Future<ProcessResult> run(
    List<String> mode, {
    bool wardroom = true,
    List<String> extra = const [],
  }) =>
      runSpawnAsync(
        'node',
        [
          _builder,
          ...mode,
          '--table', table,
          '--map', map,
          '--library', lib,
          if (wardroom) ...['--wardroom-dir', ward.dir.path],
          ...extra,
        ],
        why: 'build_library_media_v16.js ${mode.join(' ')} on a fixture tree',
        report: (_) {},
      ).timeout(const Duration(seconds: 60), onTimeout: () => throw TimeoutException('builder run timed out'));

  Future<ProcessResult> build({List<String> extra = const []}) => run(['--write'], extra: extra);

  void dispose() => dir.deleteSync(recursive: true);
}

String _out(ProcessResult r) => '${r.stdout}\n${r.stderr}';

void main() {
  late _Env env;
  setUp(() => env = _Env());
  tearDown(() => env.dispose());

  group('the table is built from the ledger, the disk and the library', () {
    test('rows, files, hashes, sizes and the carried ledger fields', () async {
      final r = await env.build();
      expect(r.exitCode, 0, reason: _out(r));
      final t = env.readTable();
      final rows = (t['rows'] as Map).cast<String, String>();
      final files = (t['files'] as Map).cast<String, Map<String, dynamic>>();
      expect(rows, {
        'G0103': '0103-barbell-standing-ab-rollout',
        'G3643': '3643-farmer-s-walk',
        'N06': '3643-farmer-s-walk',
        'G6000': '6000-alias-one',
      });
      expect(files.keys.toSet(), {'0103-barbell-standing-ab-rollout', '3643-farmer-s-walk', '6000-alias-one'});
      for (final e in files.entries) {
        expect(RegExp(_slugRegex).hasMatch(e.key), isTrue, reason: e.key);
        expect(e.value['status'], 'active');
        expect(e.value['gif'], e.key.substring(0, 4));
      }
      final f = files['0103-barbell-standing-ab-rollout']!;
      final entryId = '0103_Barbell_Standing_Ab_Rollout';
      final animBytes = env.ward.animFile(entryId).readAsBytesSync();
      final thumbBytes = env.ward.thumbFile(entryId).readAsBytesSync();
      expect(f['webp_sha256'], sha256Hex(animBytes));
      expect(f['webp_bytes'], animBytes.length);
      expect(f['thumb_sha256'], sha256Hex(thumbBytes));
      expect(f['thumb_bytes'], thumbBytes.length);
      expect(f['ledger_id'], entryId);
      expect(f['frames'], 12);
      expect(f['source_gif_sha256'], env.ward.entry(entryId)['sourceSHA256']);
      expect(f['versions'], [
        {
          'media_version': 1,
          'webp_sha256': sha256Hex(animBytes),
          'webp_bytes': animBytes.length,
          'file': (env.ward.entry(entryId)['outputs'] as Map)['animation'],
        }
      ]);
      final meta = t['_meta'] as Map<String, dynamic>;
      expect(meta['bucket'], 'exercise-media');
      expect(meta['webp_bytes_max'], 1500000);
      expect(meta['ledger_completed_at'], '2026-10-08T13:11:00.000Z');
      expect(meta['old_rows'], isNull);
      expect(meta['taken_down'], isEmpty);
    });

    test('two rows with one gif number share one slug and one files entry', () async {
      await env.build();
      final t = env.readTable();
      expect((t['rows'] as Map)['G3643'], (t['rows'] as Map)['N06']);
      expect((t['files'] as Map).keys.where((k) => (k as String).startsWith('3643')).length, 1);
    });

    test('a library row the map maps but the library does not hold (held) is excluded; a row with no gif stays out', () async {
      await env.build();
      final t = env.readTable();
      expect((t['rows'] as Map).containsKey('G0007'), isFalse);
      expect((t['rows'] as Map).containsKey('N01'), isFalse);
      expect((t['files'] as Map).keys.any((k) => (k as String).startsWith('0007')), isFalse);
    });

    test('an alias number is an ordinary number with its own slug and file', () async {
      await env.build();
      final files = (env.readTable()['files'] as Map).cast<String, Map<String, dynamic>>();
      expect(files['6000-alias-one']!['webp_sha256'], files['0103-barbell-standing-ab-rollout']!['webp_sha256']);
      expect(files['6000-alias-one']!['ledger_id'], '6000_Alias_One');
    });

    test('--write is byte-stable; --check is byte equality (a one-byte edit fails it)', () async {
      await env.build();
      final first = File(env.table).readAsStringSync();
      expect(first.endsWith('\n'), isTrue);
      await env.build();
      expect(File(env.table).readAsStringSync(), first);
      final ok = await env.run(['--check']);
      expect(ok.exitCode, 0, reason: _out(ok));
      File(env.table).writeAsStringSync(first.replaceFirst('"exercise-media"', '"exercise-medix"'));
      final bad = await env.run(['--check']);
      expect(bad.exitCode, isNot(0), reason: _out(bad));
    });

    test('no mode flag is a usage error and writes nothing', () async {
      final r = await env.run([]);
      expect(r.exitCode, 2, reason: _out(r));
      expect(File(env.table).existsSync(), isFalse);
    });

    test('--out writes elsewhere and leaves --table alone', () async {
      final r = await env.build(extra: ['--out', '${env.dir.path}/elsewhere.json']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(File('${env.dir.path}/elsewhere.json').existsSync(), isTrue);
      expect(File(env.table).existsSync(), isFalse);
    });
  });

  group('the builder stops instead of guessing', () {
    test('a mapped id whose gif has no ledger entry stops the run naming the id', () async {
      final m = Map<String, Object>.from(_defaultMap)..['G0103'] = {'_gif': '4444'};
      env.writeMap(m);
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('G0103'));
      expect(File(env.table).existsSync(), isFalse);
    });

    test('a map entry naming a non-numeric id (table-row-clean) is refused', () async {
      final m = Map<String, Object>.from(_defaultMap)..['G0007'] = {'_gif': 'table-row-clean'};
      env.writeMap(m);
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('G0007'));
    });

    test('a file missing on disk stops the run naming the slug', () async {
      env.ward.animFile('3643_Farmer_s_Walk').deleteSync();
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('3643-farmer-s-walk'));
    });

    test('an animation whose sha256 differs from the ledger validation sha stops the run', () async {
      final f = env.ward.animFile('3643_Farmer_s_Walk');
      final b = f.readAsBytesSync()..[100] ^= 0xff;
      f.writeAsBytesSync(b);
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('3643-farmer-s-walk'));
    });

    test('a thumbnail whose sha256 differs from the ledger validation sha stops the run', () async {
      final f = env.ward.thumbFile('3643_Farmer_s_Walk');
      final b = f.readAsBytesSync()..[50] ^= 0xff;
      f.writeAsBytesSync(b);
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('3643-farmer-s-walk'));
    });

    test('a file that differs from the table\'s recorded sha for the same slug stops the run (objects are immutable)', () async {
      expect((await env.build()).exitCode, 0);
      // A new file whose ledger entry agrees with it, under the same slug: the ledger check passes,
      // the recorded-sha check must not.
      final id = '3643_Farmer_s_Walk';
      final nb = webpBytes(2100, 77);
      env.ward.animFile(id).writeAsBytesSync(nb);
      (env.ward.entry(id)['animationValidation'] as Map)['SHA256'] = sha256Hex(nb);
      (env.ward.entry(id)['animationValidation'] as Map)['bytes'] = nb.length;
      env.ward.saveLedger();
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('3643-farmer-s-walk'));
      expect(r.stderr, contains('recorded'));
    });

    test('a THUMBNAIL that differs from the table\'s recorded sha for the same slug stops the run (the other half of immutability)', () async {
      expect((await env.build()).exitCode, 0);
      final id = '3643_Farmer_s_Walk';
      final nb = webpBytes(700, 78);
      env.ward.thumbFile(id).writeAsBytesSync(nb);
      (env.ward.entry(id)['thumbnailValidation'] as Map)['SHA256'] = sha256Hex(nb);
      (env.ward.entry(id)['thumbnailValidation'] as Map)['bytes'] = nb.length;
      env.ward.saveLedger();
      final r = await env.build();
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(r.stderr, contains('3643-farmer-s-walk'));
      expect(r.stderr, contains('recorded'));
    });

    test('an animation whose byte count differs from the ledger\'s stops the run, naming the slug and both numbers', () async {
      final id = '3643_Farmer_s_Walk';
      final real = env.ward.animFile(id).lengthSync();
      (env.ward.entry(id)['animationValidation'] as Map)['bytes'] = real + 1;
      env.ward.saveLedger();
      final r = await env.build();
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(r.stderr, contains('3643-farmer-s-walk'));
      expect(r.stderr, contains('$real bytes'));
      expect(r.stderr, contains('${real + 1}'));
    });

    for (final bad in <String, Object?>{'a string': '12', 'a fraction': 12.5, 'absent': null}.entries) {
      test('a ledger frame count that is ${bad.key} (not an integer) stops the run, naming the slug', () async {
        final id = '3643_Farmer_s_Walk';
        final validation = env.ward.entry(id)['animationValidation'] as Map;
        if (bad.value == null) {
          validation.remove('frames');
        } else {
          validation['frames'] = bad.value;
        }
        env.ward.saveLedger();
        final r = await env.build();
        expect(r.exitCode, isNot(0), reason: _out(r));
        expect(r.stderr, contains('3643-farmer-s-walk'));
        expect(r.stderr, contains('frame count'));
      });
    }

    test('a file over webp_bytes_max stops the run', () async {
      final e = _Env(entries: [..._defaultEntries(), FixtureEntry(number: '0555', name: 'Huge One', animSize: 1500001, seed: 5)]);
      addTearDown(e.dispose);
      e.writeMap(Map<String, Object>.from(_defaultMap)..['G0555'] = {'_gif': '0555'});
      e.writeLib([..._defaultLib(), {'id': 'G0555', 'source': 'exercise-gif-set'}]);
      final r = await e.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('0555-huge-one'));
    });

    test('an animation path outside webp-720/ in the ledger is refused', () async {
      (env.ward.entry('3643_Farmer_s_Walk')['outputs'] as Map)['animation'] = '../outside/3643.webp';
      env.ward.saveLedger();
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('3643-farmer-s-walk'));
    });

    test('the id-derived and the name-derived slug must agree', () async {
      env.ward.entry('0103_Barbell_Standing_Ab_Rollout')['name'] = 'Barbell Rollout';
      env.ward.saveLedger();
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('0103'));
    });
  });

  group('kebab (R1): permanent because object names are immutable', () {
    Future<String?> slugFor(String name) async {
      final e = _Env(entries: [FixtureEntry(number: '0042', name: name, seed: 4)]);
      addTearDown(e.dispose);
      e.writeMap({'G0042': {'_gif': '0042'}});
      e.writeLib([{'id': 'G0042', 'source': 'exercise-gif-set'}]);
      final r = await e.build();
      if (r.exitCode != 0) return null;
      return (e.readTable()['rows'] as Map)['G0042'] as String;
    }

    test('apostrophe, ampersand, digits, leading and trailing punctuation', () async {
      expect(await slugFor("Farmer's Walk"), '0042-farmer-s-walk');
      expect(await slugFor('Curl & Press'), '0042-curl-press');
      expect(await slugFor('90/90 Hip Switch'), '0042-90-90-hip-switch');
      expect(await slugFor('(Smith) Squat!'), '0042-smith-squat');
      expect(await slugFor('Run  --  Fast'), '0042-run-fast');
    });

    test('a name that kebabs to nothing is refused, naming the id', () async {
      final e = _Env(entries: [FixtureEntry(number: '0042', name: '!!!', seed: 4)]);
      addTearDown(e.dispose);
      e.writeMap({'G0042': {'_gif': '0042'}});
      e.writeLib([{'id': 'G0042', 'source': 'exercise-gif-set'}]);
      final r = await e.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('G0042'));
      expect(File(e.table).existsSync(), isFalse);
    });
  });

  group('old rows (R5): the founder\'s export, only through the builder', () {
    test('an entry builds an E-id row; _meta.old_rows records sha256, entries and omitted', () async {
      env.writeOldRows({
        'entries': [
          {'id': 'E050', 'gif': '0103', 'equipment_checked': true},
          {'id': 'E060', 'gif': '3643', 'equipment_checked': true},
        ]
      });
      final r = await env.build(extra: ['--old-rows', env.oldRows]);
      expect(r.exitCode, 0, reason: _out(r));
      final t = env.readTable();
      expect((t['rows'] as Map)['E050'], '0103-barbell-standing-ab-rollout');
      expect((t['rows'] as Map)['E060'], '3643-farmer-s-walk');
      expect((t['_meta'] as Map)['old_rows'], {
        'sha256': sha256Hex(File(env.oldRows).readAsBytesSync()),
        'entries': 2,
        'omitted': 0,
      });
    });

    test('an entry on a taken-down slug is omitted and counted', () async {
      env.writeOldRows({
        'entries': [
          {'id': 'E050', 'gif': '0103', 'equipment_checked': true},
          {'id': 'E060', 'gif': '3643', 'equipment_checked': true},
        ]
      });
      expect((await env.build(extra: ['--old-rows', env.oldRows])).exitCode, 0);
      final t = env.readTable();
      (t['_meta'] as Map)['taken_down'] = ['3643-farmer-s-walk'];
      env.writeTable(t);
      final r = await env.build(extra: ['--old-rows', env.oldRows]);
      expect(r.exitCode, 0, reason: _out(r));
      final t2 = env.readTable();
      expect((t2['rows'] as Map).containsKey('E060'), isFalse);
      expect((t2['_meta'] as Map)['old_rows'], containsPair('entries', 1));
      expect((t2['_meta'] as Map)['old_rows'], containsPair('omitted', 1));
    });

    test('without the flag the existing E rows are carried verbatim', () async {
      env.writeOldRows({
        'entries': [
          {'id': 'E050', 'gif': '0103', 'equipment_checked': true}
        ]
      });
      expect((await env.build(extra: ['--old-rows', env.oldRows])).exitCode, 0);
      final before = File(env.table).readAsStringSync();
      expect((await env.build()).exitCode, 0);
      expect(File(env.table).readAsStringSync(), before);
    });

    for (final c in <String, Map<String, Object>>{
      'without equipment_checked': {'id': 'E050', 'gif': '0103'},
      'with equipment_checked false': {'id': 'E050', 'gif': '0103', 'equipment_checked': false},
      'with a gif that has no ledger entry': {'id': 'E050', 'gif': '4444', 'equipment_checked': true},
      'naming the non-numeric table-row-clean': {'id': 'E050', 'gif': 'table-row-clean', 'equipment_checked': true},
      'for an id the library does not hold': {'id': 'E999', 'gif': '0103', 'equipment_checked': true},
    }.entries) {
      test('an entry ${c.key} is refused and nothing is written', () async {
        env.writeOldRows({'entries': [c.value]});
        final r = await env.build(extra: ['--old-rows', env.oldRows]);
        expect(r.exitCode, isNot(0), reason: _out(r));
        expect(r.stderr, contains((c.value['id'] ?? '') as String), reason: 'the refusal must name the entry');
        expect(File(env.table).existsSync(), isFalse);
      });
    }
  });

  group('table maintenance (R13): hold, release, takedown', () {
    test('a rebuild never drops a files entry: a row that leaves the library makes its file unmapped', () async {
      await env.build();
      env.writeLib(_defaultLib().where((r) => r['id'] != 'G6000').toList());
      final r = await env.build();
      expect(r.exitCode, 0, reason: _out(r));
      final t = env.readTable();
      expect((t['rows'] as Map).containsKey('G6000'), isFalse);
      expect(((t['files'] as Map)['6000-alias-one'] as Map)['status'], 'unmapped');
    });

    test('release: the row comes back, a rebuild turns the file active again', () async {
      await env.build();
      final lib = _defaultLib();
      env.writeLib(lib.where((r) => r['id'] != 'G6000').toList());
      await env.build();
      env.writeLib(lib);
      final r = await env.build();
      expect(r.exitCode, 0, reason: _out(r));
      final t = env.readTable();
      expect((t['rows'] as Map)['G6000'], '6000-alias-one');
      expect(((t['files'] as Map)['6000-alias-one'] as Map)['status'], 'active');
    });

    test('a slug in _meta.taken_down gets status taken_down and none of its rows', () async {
      await env.build();
      final t = env.readTable();
      (t['_meta'] as Map)['taken_down'] = ['3643-farmer-s-walk'];
      env.writeTable(t);
      final r = await env.build();
      expect(r.exitCode, 0, reason: _out(r));
      final t2 = env.readTable();
      expect(((t2['files'] as Map)['3643-farmer-s-walk'] as Map)['status'], 'taken_down');
      expect((t2['rows'] as Map).containsKey('G3643'), isFalse);
      expect((t2['rows'] as Map).containsKey('N06'), isFalse);
      expect((t2['rows'] as Map)['G0103'], isNotNull);
    });

    test('a taken_down slug with no files entry is refused', () async {
      await env.build();
      final t = env.readTable();
      (t['_meta'] as Map)['taken_down'] = ['9999-not-there'];
      env.writeTable(t);
      final r = await env.build();
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('9999-not-there'));
    });

    test('--prune-only needs no Wardroom folder: removes rows absent from --library, flips unused files to unmapped, byte-identical on a second run', () async {
      await env.build();
      env.writeLib(_defaultLib().where((r) => r['id'] != 'G6000').toList());
      final r = await env.run(['--write', '--prune-only'], wardroom: false);
      expect(r.exitCode, 0, reason: _out(r));
      final t = env.readTable();
      expect((t['rows'] as Map).containsKey('G6000'), isFalse);
      expect(((t['files'] as Map)['6000-alias-one'] as Map)['status'], 'unmapped');
      expect(((t['files'] as Map)['0103-barbell-standing-ab-rollout'] as Map)['status'], 'active');
      final first = File(env.table).readAsStringSync();
      expect((await env.run(['--write', '--prune-only'], wardroom: false)).exitCode, 0);
      expect(File(env.table).readAsStringSync(), first);
    });
  });
}
