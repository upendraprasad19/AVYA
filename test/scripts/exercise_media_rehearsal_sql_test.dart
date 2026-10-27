// Batch M1 (plan Task 8.4, B-pass finding C): scripts/exercise_media_rehearsal_sql.js composes the SQL the rehearsal sends,
// so it is never assembled by hand. It reads two committed SQL files and the migration draft and prints text; it contacts
// nothing. This file pins, on the REAL files and on fixture trees:
//   - FILE 1 comes out with the migration body TWICE (idempotence leg) at the marker, comments stripped, dollar quotes
//     balanced; FILE 2 comes out once-built and balanced;
//   - the comment stripper keeps string literals (a `--` inside a quoted string is data) and strips real comments;
//   - every shape problem is a refusal with exit 2: the marker not exactly once, the migration source not exactly one,
//     an unbalanced dollar quote, a missing file, an unknown flag.
//
// Run: flutter test test/scripts/exercise_media_rehearsal_sql_test.dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _tool = 'scripts/exercise_media_rehearsal_sql.js';

// A hung node must not hold the isolate until the file timeout: every spawn here is asynchronous and has its own limit (plan R12).
// Future.timeout alone only stops WAITING and leaves the child running, so the child is started with startSpawn and KILLED at the limit.
const _spawnTimeout = Duration(seconds: 90);

Future<ProcessResult> _spawnNode(List<String> args, String why) async {
  final p = await startSpawn('node', args);
  final out = utf8.decodeStream(p.stdout);
  final err = utf8.decodeStream(p.stderr);
  final code = await p.exitCode.timeout(_spawnTimeout, onTimeout: () {
    p.kill();
    throw TimeoutException('$why did not finish in ${_spawnTimeout.inSeconds} s; the node child was killed');
  });
  final result = ProcessResult(p.pid, code, await out, await err);
  reportSpawn(result.exitCode, result.stdout, result.stderr, why);
  return result;
}

Future<ProcessResult> _run(List<String> args) =>
    _spawnNode([_tool, ...args], 'exercise_media_rehearsal_sql.js ${args.join(' ')}');

/// Runs the module's [compose] (or [stripComments]) in a node child and returns {ok, text|error}.
Future<Map<String, dynamic>> _node(String expr) async {
  final script = File(_tool).absolute.path;
  final r = await _spawnNode(
    [
      '-e',
      'const t=require(${jsonEncode(script)});'
          'try{console.log(JSON.stringify({ok:true,text:$expr}));}'
          'catch(e){console.log(JSON.stringify({ok:false,problem:e instanceof t.Problem,error:String(e.message)}));}',
    ],
    'node $_tool $expr',
  );
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return jsonDecode((r.stdout as String).trim()) as Map<String, dynamic>;
}

int _count(String text, String needle) => text.split(needle).length - 1;

void main() {
  group('on the real files', () {
    late String f1;
    late String f2;
    setUpAll(() async {
      final a = await _run(['--file1']);
      expect(a.exitCode, 0, reason: '${a.stderr}');
      f1 = a.stdout as String;
      final b = await _run(['--file2']);
      expect(b.exitCode, 0, reason: '${b.stderr}');
      f2 = b.stdout as String;
    });

    test('FILE 1 carries the migration body twice, once more than the committed file does', () {
      expect(_count(f1, "PERFORM set_config('lock_timeout', '5s', true);"), 2);
      expect(_count(f1, 'CREATE POLICY exercise_media_authenticated_read ON storage.objects'), 2);
      expect(_count(f1, 'DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;'), 2);
      expect(_count(f1, 'INSERT INTO storage.buckets'), 2);
      final committed = File('test/sql/exercise_media_bucket_live_verify.sql').readAsStringSync();
      expect(committed.contains('CREATE POLICY'), isFalse, reason: 'the committed FILE 1 has no DDL; only the composed text has');
    });

    test('FILE 1 keeps the probe and the catalog, starts with its DO block and balances its dollar quote', () {
      expect(f1, startsWith(r'DO $v$'));
      expect(_count(f1, r'$v$'), 2);
      for (final needle in ['SET LOCAL ROLE anon', 'UPDATE storage.buckets SET public = true;', "strpos(qual, 'is_anonymous') > 0", 'VERIFY_RESULTS']) {
        expect(f1, contains(needle));
      }
      expect(f1.trimRight(), endsWith(r'$v$;'));
    });

    test('FILE 2 is built once, balanced, and still holds its six variants', () {
      expect(_count(f2, r'$r$'), 2);
      expect(f2, startsWith(r'DO $r$'));
      expect(f2, contains('FOR v_i IN 1..6 LOOP'));
      expect(_count(f2, "PERFORM set_config('lock_timeout', '5s', true);"), 1);
    });

    test('neither output holds a comment', () {
      for (final out in [f1, f2]) {
        expect(out.contains('--'), isFalse, reason: 'a comment survived');
        expect(out.contains('/*'), isFalse);
        expect(out.trimRight().split('\n').every((l) => l.trim().isNotEmpty), isTrue, reason: 'a blank line survived');
      }
    });

    test('an unknown flag, no flag and two flags are refused with exit 2 and no output', () async {
      for (final args in [<String>['--file3'], <String>[], <String>['--file1', '--file2']]) {
        final r = await _run(args);
        expect(r.exitCode, 2, reason: args.join(' '));
        expect((r.stdout as String).trim(), isEmpty);
        expect(r.stderr as String, contains('usage'));
      }
    });
  });

  group('the comment stripper', () {
    Future<String> strip(String sql) async {
      final r = await _node('t.stripComments(${jsonEncode(sql)})');
      expect(r['ok'], isTrue, reason: '$r');
      return r['text'] as String;
    }

    test('removes line and block comments, keeps code, drops the blank lines they leave', () async {
      expect(await strip('SELECT 1; -- one\n-- a whole line\n/* block\nspans */ SELECT 2;\n'), 'SELECT 1;\n  SELECT 2;\n');
    });

    test('keeps a double dash inside a string literal, including a doubled quote and an E-string escape', () async {
      expect(await strip("SELECT 'a -- b';\n"), "SELECT 'a -- b';\n");
      expect(await strip("SELECT 'it''s -- still a string';\n"), "SELECT 'it''s -- still a string';\n");
      expect(await strip(r"SELECT E'x\' -- y';" '\n'), r"SELECT E'x\' -- y';" '\n');
      expect(await strip(r"SELECT E'\n' || 'z'; -- c" '\n'), r"SELECT E'\n' || 'z';" '\n');
    });

    test('keeps a double dash or a block-comment opener inside a double-quoted identifier, and an apostrophe inside one', () async {
      expect(await strip('SELECT "col--name", "a/*b" FROM t; -- c\n'), 'SELECT "col--name", "a/*b" FROM t;\n');
      expect(await strip('SELECT "it\'s" FROM t; /* c */\n'), 'SELECT "it\'s" FROM t;\n');
      expect(await strip("SELECT 'a \"-- b' FROM t;\n"), "SELECT 'a \"-- b' FROM t;\n", reason: 'a double quote inside a string literal is data');
    });

    test('an unterminated quoted identifier is a refusal, not a silent cut', () async {
      final r = await _node("t.stripComments('SELECT \"oops -- c\\\\n')");
      expect(r['ok'], isFalse);
      expect(r['problem'], isTrue);
    });

    test('an unterminated string literal is a refusal, not a silent cut', () async {
      final r = await _node("t.stripComments(\"SELECT 'oops; -- c\\n\")");
      expect(r['ok'], isFalse);
      expect(r['problem'], isTrue);
    });
  });

  group('shape problems on a fixture tree are refusals', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('rehearsal_sql_'));
    tearDown(() => root.deleteSync(recursive: true));

    const f1Good = r'''
DO $v$
BEGIN
  -- PRELUDE-INSERT-POINT (rehearsal only)
  SELECT 1;
END
$v$;
''';
    const migGood = r'''
-- header
DO $mig$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
END
$mig$;
''';

    void write(String rel, String text) {
      final f = File('${root.path}/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    Future<Map<String, dynamic>> compose(String which) => _node('t.compose(${jsonEncode(which)}, ${jsonEncode(root.path)})');

    void goodTree() {
      write('test/sql/exercise_media_bucket_live_verify.sql', f1Good);
      write('test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql', 'DO \$r\$\nBEGIN\n  SELECT 1;\nEND\n\$r\$;\n');
      write('docs/plans/library-batch-m/exercise_media_bucket.sql.draft', migGood);
    }

    test('a good tree composes (control: the refusals below are not a broken fixture)', () async {
      goodTree();
      final r = await compose('file1');
      expect(r['ok'], isTrue, reason: '$r');
      expect(_count(r['text'] as String, "PERFORM set_config('lock_timeout', '5s', true);"), 2);
      expect((await compose('file2'))['ok'], isTrue);
    });

    test('a marker that appears twice, or not at all, is refused', () async {
      goodTree();
      write('test/sql/exercise_media_bucket_live_verify.sql', f1Good.replaceFirst('SELECT 1;', '-- PRELUDE-INSERT-POINT\n  SELECT 1;'));
      final twice = await compose('file1');
      expect(twice['ok'], isFalse);
      expect(twice['problem'], isTrue);
      write('test/sql/exercise_media_bucket_live_verify.sql', f1Good.replaceFirst('PRELUDE-INSERT-POINT', 'NOTHING-HERE'));
      final none = await compose('file1');
      expect(none['ok'], isFalse);
      expect(none['problem'], isTrue);
    });

    test('a migration source that is absent, or present twice (draft and final), is refused', () async {
      goodTree();
      File('${root.path}/docs/plans/library-batch-m/exercise_media_bucket.sql.draft').deleteSync();
      final absent = await compose('file1');
      expect(absent['ok'], isFalse);
      expect(absent['problem'], isTrue);
      write('docs/plans/library-batch-m/exercise_media_bucket.sql.draft', migGood);
      write('supabase/migrations/170_exercise_media_bucket.sql', migGood);
      final both = await compose('file1');
      expect(both['ok'], isFalse);
      expect(both['problem'], isTrue);
    });

    test('a migration body without the lock budget statement is refused (it is not the migration body the rehearsal needs)', () async {
      goodTree();
      write('docs/plans/library-batch-m/exercise_media_bucket.sql.draft', migGood.replaceFirst("PERFORM set_config('lock_timeout', '5s', true);", 'PERFORM 1;'));
      final r = await compose('file1');
      expect(r['ok'], isFalse);
      expect(r['problem'], isTrue);
      expect(r['error'], contains('twice'));
    });

    test('a migration with no DO block is refused', () async {
      goodTree();
      write('docs/plans/library-batch-m/exercise_media_bucket.sql.draft', '-- nothing\nSELECT 1;\n');
      final r = await compose('file1');
      expect(r['ok'], isFalse);
      expect(r['problem'], isTrue);
      expect(r['error'], contains('no DO'), reason: 'the refusal must name the missing DO block, not a downstream symptom');
    });

    test('an unbalanced dollar quote in either file is refused', () async {
      goodTree();
      write('test/sql/exercise_media_bucket_live_verify.sql', f1Good.replaceFirst('SELECT 1;', "SELECT '\$v\$';"));
      final f1 = await compose('file1');
      expect(f1['ok'], isFalse);
      expect(f1['problem'], isTrue);
      goodTree();
      write('test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql', 'DO \$r\$\nBEGIN\n  SELECT 1;\nEND\n\$r\$;\n\$r\$\n');
      final f2 = await compose('file2');
      expect(f2['ok'], isFalse);
      expect(f2['problem'], isTrue);
    });

    test('a missing SQL file is refused naming the file', () async {
      goodTree();
      File('${root.path}/test/sql/exercise_media_bucket_live_verify.sql').deleteSync();
      final r = await compose('file1');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('exercise_media_bucket_live_verify.sql'));
    });
  });
}
