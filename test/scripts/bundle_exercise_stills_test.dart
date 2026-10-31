// test/scripts/bundle_exercise_stills_test.dart
//
// Batch M2a (plan Task 2): scripts/bundle_exercise_stills.js. --check passes on the repo copy, and a copy with ONE flipped byte
// makes it exit non-zero and name the slug. The COPY mode is exercised against a small STAGED source folder built in a temp
// directory (a ledger, thumbnails, a table that names them): the founder's own folder is never needed. Those cases pin that every
// source is verified BEFORE anything is written (a bad source leaves the output folder untouched) and that a table naming no
// stills is refused.
//
// Run: flutter test test/scripts/bundle_exercise_stills_test.dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/spawn.dart';
import '../helpers/webp_fixture.dart';

const _tool = 'scripts/bundle_exercise_stills.js';

/// A staged "wardroom" source: a ledger, thumbnails under thumbnails-192/, and a table naming them. [out] does not exist yet.
class _Staged {
  _Staged(this.tmp, this.slugs);
  final Directory tmp;
  final List<String> slugs;
  String get src => '${tmp.path}/src';
  String get table => '${tmp.path}/table.json';
  String get out => '${tmp.path}/out';
  File thumb(int i) => File('$src/thumbnails-192/e${i}_192.webp');
}

_Staged _stage({int n = 2}) {
  final tmp = Directory.systemTemp.createTempSync('stills_copy_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  Directory('${tmp.path}/src/thumbnails-192').createSync(recursive: true);
  final slugs = <String>[for (var i = 0; i < n; i++) 'slug-${String.fromCharCode(97 + i)}'];
  final entries = <Map<String, dynamic>>[];
  final files = <String, dynamic>{};
  for (var i = 0; i < n; i++) {
    final bytes = webpBytes(60 + i, i + 1);
    File('${tmp.path}/src/thumbnails-192/e${i}_192.webp').writeAsBytesSync(bytes);
    entries.add(<String, dynamic>{
      'id': 'e$i',
      'outputs': <String, dynamic>{'thumbnail': 'thumbnails-192/e${i}_192.webp'},
    });
    files[slugs[i]] = <String, dynamic>{'ledger_id': 'e$i', 'thumb_bytes': bytes.length, 'thumb_sha256': sha256Hex(bytes)};
  }
  File('${tmp.path}/src/generation-ledger.json').writeAsStringSync(jsonEncode(<String, dynamic>{'entries': entries}));
  File('${tmp.path}/table.json').writeAsStringSync(jsonEncode(<String, dynamic>{'files': files}));
  return _Staged(tmp, slugs);
}

/// THE one spawn of the tool in this file.
Future<ProcessResult> _run(List<String> args) {
  return runSpawnAsync(
    'node',
    [_tool, ...args],
    why: 'bundle_exercise_stills.js ${args.join(' ')}',
    report: (_) {},
  ).timeout(const Duration(seconds: 90), onTimeout: () => throw TimeoutException('tool run timed out'));
}

void main() {
  test('--check passes on the repo copy and needs no --src', () async {
    final r = await _run(['--check']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('--check on a copy with ONE flipped byte exits non-zero and names the slug', () async {
    final table = jsonDecode(File('scripts/data/library_media_v16.json').readAsStringSync()) as Map<String, dynamic>;
    final slug = (table['files'] as Map<String, dynamic>).keys.toList()..sort();
    final victim = slug.first;
    final tmp = Directory.systemTemp.createTempSync('stills_check_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final f in Directory('assets/exercise_stills').listSync().whereType<File>()) {
      f.copySync('${tmp.path}/${f.uri.pathSegments.last}');
    }
    final target = File('${tmp.path}/$victim.webp');
    final bytes = target.readAsBytesSync();
    bytes[bytes.length - 1] ^= 0xFF;
    target.writeAsBytesSync(bytes);

    final r = await _run(['--check', '--dir', tmp.path]);
    expect(r.exitCode, isNot(0), reason: 'a flipped byte must fail the hash check\n${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains(victim));
  });

  test('--check on a folder missing a still names the slug', () async {
    final tmp = Directory.systemTemp.createTempSync('stills_missing_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final files = Directory('assets/exercise_stills').listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.skip(1)) {
      f.copySync('${tmp.path}/${f.uri.pathSegments.last}');
    }
    final missing = files.first.uri.pathSegments.last.replaceAll('.webp', '');
    final r = await _run(['--check', '--dir', tmp.path]);
    expect(r.exitCode, isNot(0), reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains(missing));
  });

  group('copy mode against a staged source', () {
    test('copies every still, then verifies the result', () async {
      final st = _stage();
      final r = await _run(['--src', st.src, '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}', contains('copied 2 stills'));
      for (var i = 0; i < st.slugs.length; i++) {
        expect(File('${st.out}/${st.slugs[i]}.webp').readAsBytesSync(), st.thumb(i).readAsBytesSync());
      }
    });

    test('a source whose bytes differ from the table is refused BEFORE anything is written (exit 1, names the slug, output untouched)', () async {
      final st = _stage();
      final b = st.thumb(1).readAsBytesSync();
      b[b.length - 1] ^= 0xFF;
      st.thumb(1).writeAsBytesSync(b);
      final r = await _run(['--src', st.src, '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains(st.slugs[1]));
      expect(Directory(st.out).existsSync(), isFalse, reason: 'the FIRST still was good, and still nothing was written');
    });

    test('a missing source thumbnail is refused before anything is written', () async {
      final st = _stage();
      st.thumb(1).deleteSync();
      final r = await _run(['--src', st.src, '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains(st.slugs[1]));
      expect(Directory(st.out).existsSync(), isFalse);
    });

    test('a table row whose ledger id is not in the ledger is refused', () async {
      final st = _stage();
      final table = jsonDecode(File(st.table).readAsStringSync()) as Map<String, dynamic>;
      ((table['files'] as Map<String, dynamic>)[st.slugs[0]] as Map<String, dynamic>)['ledger_id'] = 'no-such-entry';
      File(st.table).writeAsStringSync(jsonEncode(table));
      final r = await _run(['--src', st.src, '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains(st.slugs[0]));
      expect(Directory(st.out).existsSync(), isFalse);
    });

    test('a ledger thumbnail path that climbs out of thumbnails-192 is refused', () async {
      final st = _stage();
      final ledgerFile = File('${st.src}/generation-ledger.json');
      final ledger = jsonDecode(ledgerFile.readAsStringSync()) as Map<String, dynamic>;
      ((ledger['entries'] as List<dynamic>)[0] as Map<String, dynamic>)['outputs'] = <String, dynamic>{'thumbnail': 'thumbnails-192/../../evil.webp'};
      ledgerFile.writeAsStringSync(jsonEncode(ledger));
      final r = await _run(['--src', st.src, '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('thumbnails-192/<file>.webp'));
      expect(Directory(st.out).existsSync(), isFalse);
    });
  });

  group('the table itself', () {
    test('a table that names NO stills is refused (a zero-file result is not a pass), in check mode too', () async {
      final tmp = Directory.systemTemp.createTempSync('stills_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/table.json').writeAsStringSync(jsonEncode(<String, dynamic>{'files': <String, dynamic>{}}));
      Directory('${tmp.path}/empty').createSync(); // an EMPTY stills folder: nothing else may be the reason for the refusal
      final r = await _run(['--check', '--table', '${tmp.path}/table.json', '--dir', '${tmp.path}/empty']);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('names no stills'));
    });

    test('a table slug that is not a valid media slug (a path) is refused', () async {
      final st = _stage(n: 1);
      final table = jsonDecode(File(st.table).readAsStringSync()) as Map<String, dynamic>;
      final files = table['files'] as Map<String, dynamic>;
      files['../escape'] = files.values.first;
      File(st.table).writeAsStringSync(jsonEncode(table));
      final r = await _run(['--check', '--table', st.table, '--dir', st.out]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('not a valid media slug'));
    });
  });

  test('copy mode without --src is refused with a usage message (exit 2)', () async {
    final tmp = Directory.systemTemp.createTempSync('stills_nosrc_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final r = await _run(['--dir', tmp.path]);
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('--src'));
  });
}
