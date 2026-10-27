// Batch M1 (plan R4, R13): the media stage of scripts/add_library_batch_c_v15.js. It appends
// `media_slug`, `media_version` and `media_source` (last, in that order) to the library rows the
// provenance table maps, and removes them from any row it does not map.
//
// Every test runs the REAL scripts on COPIES of the real committed files in a temp tree (plan
// R12), text-mutated where a case needs it; nothing here touches the committed library.
//
// Run: flutter test test/scripts/library_media_importer_test.dart
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_media_table_checks.dart';
import '../helpers/spawn.dart';

const _importer = 'scripts/add_library_batch_c_v15.js';
const _builder = 'scripts/build_library_media_v16.js';
const _libRel = 'assets/data/exercise_library.json';
const _srcRel = 'scripts/data/library_batch_c_source.json';
const _injRel = 'scripts/data/library_injury_additions_v15.json';
const _mediaRel = 'scripts/data/library_media_v16.json';
const _mapRel = 'scripts/data/library_batch_c_media_map.json';
const _mediaKeys = ['media_slug', 'media_version', 'media_source'];

Json _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Json;

/// A mirror of the repo layout in a temp directory: a COPY of the importer under scripts/, its
/// data files under scripts/data/ and the library under assets/data/. The script resolves its
/// defaults from its own directory, so a run with no --library or no --media can only ever touch
/// this tree, never the committed library.
class _Tree {
  _Tree() : dir = Directory.systemTemp.createTempSync('lmi_') {
    Directory('${dir.path}/scripts/data').createSync(recursive: true);
    Directory('${dir.path}/assets/data').createSync(recursive: true);
    File(script).writeAsStringSync(File(_importer).readAsStringSync());
    for (final e in {src: _srcRel, inj: _injRel, media: _mediaRel, lib: _libRel}.entries) {
      File(e.key).writeAsStringSync(File(e.value).readAsStringSync());
    }
  }

  final Directory dir;
  String get script => '${dir.path}/scripts/add_library_batch_c_v15.js';
  String get lib => '${dir.path}/assets/data/exercise_library.json';
  String get src => '${dir.path}/scripts/data/library_batch_c_source.json';
  String get inj => '${dir.path}/scripts/data/library_injury_additions_v15.json';
  String get media => '${dir.path}/scripts/data/library_media_v16.json';

  List<String> get base => ['--library', lib, '--source', src, '--table', inj];

  Future<ProcessResult> run(List<String> args, {String? script, String? why}) => runSpawnAsync(
        'node',
        [script ?? this.script, ...args],
        why: why ?? 'importer ${args.join(' ')}',
        report: (_) {},
      ).timeout(const Duration(seconds: 90), onTimeout: () => throw TimeoutException('script run timed out'));

  /// The importer with every path explicit (the tree's own files).
  Future<ProcessResult> importer({List<String> extra = const []}) => run([...base, '--media', media, ...extra]);

  /// The REAL builder in --prune-only mode on the tree's table and library.
  Future<ProcessResult> prune({List<String> extra = const []}) =>
      run(['--prune-only', '--write', '--table', media, '--library', lib, ...extra], script: _builder);

  String readLibText() => File(lib).readAsStringSync();
  List<Json> readLib() => (jsonDecode(readLibText()) as List).cast<Json>();
  Json readMedia() => _readJson(media);
  void writeMedia(Json m) => File(media).writeAsStringSync(jsonEncode(m));
  Json readSrc() => _readJson(src);
  void writeSrc(Json s) => File(src).writeAsStringSync(jsonEncode(s));
  void writeLibText(String t) => File(lib).writeAsStringSync(t);

  void dispose() => dir.deleteSync(recursive: true);
}

String _out(ProcessResult r) => '${r.stdout}\n${r.stderr}';

String _err(ProcessResult r) => '${r.stderr}';

/// The library rows keyed by id.
Map<String, Json> _byId(List<Json> lib) => {for (final r in lib) r['id'] as String: r};

bool _hasMediaKey(Json row) => _mediaKeys.any(row.containsKey);

/// Inserts the three media keys (a wrong slug, in the wrong place) right after the row's id line.
String _withStrayKeys(String text, String id) {
  final re = RegExp('^    "id": "$id",\n', multiLine: true);
  expect(re.hasMatch(text), isTrue, reason: 'row $id must be in the library text');
  return text.replaceFirst(
    re,
    '    "id": "$id",\n    "media_slug": "0000-stray",\n    "media_version": 9,\n    "media_source": "stray",\n',
  );
}

void main() {
  late _Tree t;
  setUp(() => t = _Tree());
  tearDown(() => t.dispose());

  final table0 = _readJson(_mediaRel);
  final tableRows = (table0['rows'] as Json).cast<String, String>();
  final tableFiles = table0['files'] as Json;

  group('the media stage (R4)', () {
    test('mapped rows get the three keys last and in order; unmapped rows get none', () async {
      final r = await t.importer();
      expect(r.exitCode, 0, reason: _out(r));
      final lib = t.readLib();
      var mapped = 0;
      for (final row in lib) {
        final slug = tableRows[row['id']];
        if (slug == null) {
          expect(_hasMediaKey(row), isFalse, reason: '${row['id']} is unmapped but carries a media key');
          continue;
        }
        mapped++;
        final keys = row.keys.toList();
        expect(keys.sublist(keys.length - 3), _mediaKeys, reason: '${row['id']}: media keys last and in order');
        final versions = (tableFiles[slug] as Json)['versions'] as List;
        expect(row['media_slug'], slug);
        expect(row['media_version'], (versions.last as Json)['media_version']);
        expect(row['media_source'], 'wardroom');
      }
      expect(mapped, tableRows.length);
    });

    test('a second run is byte-identical and --check is byte equality (a one-character edit fails it)', () async {
      expect((await t.importer()).exitCode, 0);
      final first = t.readLibText();
      final again = await t.importer();
      expect(again.exitCode, 0, reason: _out(again));
      expect(t.readLibText(), first);
      final ok = await t.importer(extra: ['--check']);
      expect(ok.exitCode, 0, reason: _out(ok));
      expect(first, contains('"media_slug": "'));
      t.writeLibText(first.replaceFirst('"media_slug": "0', '"media_slug": "9'));
      final bad = await t.importer(extra: ['--check']);
      expect(bad.exitCode, isNot(0), reason: _out(bad));
    });

    test('a library whose one media_version differs from the table fails --check', () async {
      expect((await t.importer()).exitCode, 0);
      final text = t.readLibText();
      expect(text, contains('"media_version": 1'));
      t.writeLibText(text.replaceFirst('"media_version": 1', '"media_version": 2'));
      final r = await t.importer(extra: ['--check']);
      expect(r.exitCode, isNot(0), reason: _out(r));
    });

    test('a run with no --media dies naming the missing media table (no silent skip)', () async {
      File(t.media).deleteSync();
      final before = t.readLibText();
      final r = await t.run(t.base, why: 'the importer with no --media and no default table');
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(_err(r), contains('library_media_v16.json'));
      expect(t.readLibText(), before, reason: 'a refused run must not write');
    });

    test('--media none with --library runs and leaves no media key on any new row', () async {
      expect((await t.importer()).exitCode, 0);
      expect(t.readLib().where(_hasMediaKey), isNotEmpty);
      final r = await t.run([...t.base, '--media', 'none']);
      expect(r.exitCode, 0, reason: _out(r));
      final fresh = t.readLib().where((row) => row['source'] == 'exercise-gif-set');
      expect(fresh, isNotEmpty);
      expect(fresh.where(_hasMediaKey), isEmpty);
    });

    test('--media none without --library is refused and touches nothing (the default library of the tree)', () async {
      expect((await t.importer()).exitCode, 0);
      final before = File(t.lib).readAsBytesSync();
      final r = await t.run(['--media', 'none', '--source', t.src, '--table', t.inj]);
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(_err(r), contains('--library'));
      expect(File(t.lib).readAsBytesSync(), before, reason: 'the keys on the default library must survive a refused run');
    });

    test('a table row whose id is not in the new library (a newly held mapped row) is refused, naming the id', () async {
      final s = t.readSrc();
      final srcRows = (s['rows'] as List).cast<Json>();
      final victim = srcRows.firstWhere((r) => r['hold'] == null && tableRows.containsKey(r['id']));
      victim['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      t.writeSrc(s);
      final before = t.readLibText();
      final r = await t.importer();
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(_err(r), contains(victim['id'] as String));
      expect(t.readLibText(), before, reason: 'a refused run must not write');
    });

    test('a rows slug with no files entry stops the run, naming the slug', () async {
      final m = t.readMedia();
      final id = tableRows.keys.first;
      (m['rows'] as Json)[id] = '0001-no-such-file';
      t.writeMedia(m);
      final r = await t.importer();
      expect(r.exitCode, isNot(0), reason: _out(r));
      expect(_err(r), contains('0001-no-such-file'));
    });

    for (final c in <String, Object?>{'an empty versions list': <Object>[], 'no versions key': null}.entries) {
      test('a files entry with ${c.key} stops the run, naming the slug (no partial triple)', () async {
        final m = t.readMedia();
        final id = tableRows.keys.first;
        final slug = (m['rows'] as Json)[id] as String;
        final f = (m['files'] as Json)[slug] as Json;
        if (c.value == null) {
          f.remove('versions');
        } else {
          f['versions'] = c.value;
        }
        t.writeMedia(m);
        final before = t.readLibText();
        final r = await t.importer();
        expect(r.exitCode, isNot(0), reason: _out(r));
        expect(_err(r), contains(slug));
        expect(t.readLibText(), before);
      });
    }

    test('an old row that still carries media keys and that the table does not map loses them', () async {
      t.writeLibText(_withStrayKeys(t.readLibText(), 'E003'));
      expect(_hasMediaKey(_byId(t.readLib())['E003']!), isTrue);
      final r = await t.importer();
      expect(r.exitCode, 0, reason: _out(r));
      expect(_hasMediaKey(_byId(t.readLib())['E003']!), isFalse);
    });

    test('an old row the table maps gets the keys last and in order (delete-then-set, not assignment)', () async {
      t.writeLibText(_withStrayKeys(t.readLibText(), 'E004'));
      final m = t.readMedia();
      final slug = tableRows['G0103']!;
      (m['rows'] as Json)['E004'] = slug;
      t.writeMedia(m);
      final r = await t.importer();
      expect(r.exitCode, 0, reason: _out(r));
      final row = _byId(t.readLib())['E004']!;
      final keys = row.keys.toList();
      expect(keys.sublist(keys.length - 3), _mediaKeys);
      expect(row['media_slug'], slug);
      expect(row['media_version'], 1);
      expect(row['media_source'], 'wardroom');
    });

    test('an old-row entry mapping E001 does not trip the 40-key sentinel, on the first run or the second', () async {
      final m = t.readMedia();
      (m['rows'] as Json)['E001'] = tableRows['G0103']!;
      t.writeMedia(m);
      final first = await t.importer();
      expect(first.exitCode, 0, reason: _out(first));
      expect(_byId(t.readLib())['E001']!['media_slug'], tableRows['G0103']);
      // The sentinel only sees E001's media keys on the SECOND run.
      final second = await t.importer();
      expect(second.exitCode, 0, reason: _out(second));
      expect(_byId(t.readLib())['E001']!.keys.where(_mediaKeys.contains).length, 3);
    });
  });

  group('table maintenance chains on the real files (R13)', () {
    test('hold chain: importer --media none, --prune-only, importer; the table-side legs are red in between and green at the end', () async {
      final map = _readJson(_mapRel);
      final s = t.readSrc();
      final srcRows = (s['rows'] as List).cast<Json>();
      final slugUse = <String, int>{};
      for (final slug in tableRows.values) {
        slugUse[slug] = (slugUse[slug] ?? 0) + 1;
      }
      final victim = srcRows.firstWhere((r) =>
          r['hold'] == null && tableRows.containsKey(r['id']) && slugUse[tableRows[r['id']]] == 1);
      final id = victim['id'] as String;
      final slug = tableRows[id]!;
      victim['hold'] = {'class': 'picture', 'reason': 'test', 'owner': 'founder'};
      t.writeSrc(s);

      final s1 = await t.run([...t.base, '--media', 'none']);
      expect(s1.exitCode, 0, reason: _out(s1));
      expect(t.readLib().where((r) => r['id'] == id), isEmpty, reason: 'the held row leaves the library');
      expect(tableViolations(t.readMedia(), map, t.readLib()).where((v) => v.startsWith('(c)')), isNotEmpty,
          reason: 'between steps 2 and 3 the table still maps a row the library lost');

      final s2 = await t.prune();
      expect(s2.exitCode, 0, reason: _out(s2));
      final pruned = t.readMedia();
      expect((pruned['rows'] as Json).containsKey(id), isFalse);
      expect(((pruned['files'] as Json)[slug] as Json)['status'], 'unmapped');

      final s3 = await t.importer();
      expect(s3.exitCode, 0, reason: _out(s3));
      expect(tableViolations(t.readMedia(), map, t.readLib()), isEmpty);
      expect(t.readLib().where(_hasMediaKey).length, tableRows.length - 1);
    });

    test('takedown chain up to the importer: the file is taken_down, its rows keep no keys, the legs stay green', () async {
      final map = _readJson(_mapRel);
      final slug = tableRows['G3643']!;
      expect(tableRows['N06'], slug, reason: 'a slug shared by two rows is the interesting case');
      final m = t.readMedia();
      (m['_meta'] as Json)['taken_down'] = [slug];
      t.writeMedia(m);

      final p = await t.prune();
      expect(p.exitCode, 0, reason: _out(p));
      final after = t.readMedia();
      expect(((after['files'] as Json)[slug] as Json)['status'], 'taken_down');
      expect((after['rows'] as Json).values.contains(slug), isFalse);

      final imp = await t.importer();
      expect(imp.exitCode, 0, reason: _out(imp));
      final lib = _byId(t.readLib());
      for (final id in ['G3643', 'N06']) {
        expect(lib.containsKey(id), isTrue, reason: '$id stays in the library');
        expect(_hasMediaKey(lib[id]!), isFalse, reason: '$id loses its keys');
      }
      expect(_hasMediaKey(lib['G0103']!), isTrue, reason: 'a row on another slug keeps its keys (the stage ran)');
      expect(lib.values.where(_hasMediaKey).length, tableRows.length - 2);
      expect(tableViolations(t.readMedia(), map, t.readLib()), isEmpty);
    });
  });
}
