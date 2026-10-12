// test/contracts/ci_unit_test_matrix_shape_test.dart
//
// Pins the shape of the CI unit-test MATRIX in .github/workflows/test.yml (OI-275
// batch B3) and EXECUTES its two shell snippets, because the failure modes here are
// silent:
//
//   - a shard that runs an EMPTY argument list runs the ENTIRE test/ directory (so
//     every shard repeats everything and the batch saves nothing), or - if the list
//     silently shrinks - a test runs nowhere while every job is green;
//   - a gate job that passes when a shard did not, or is SKIPPED when a shard failed,
//     lets a red suite through scripts/safe_pr_merge.sh (main has no required checks);
//   - a second job named `Unit Tests`, or a renamed gate, breaks the one check name
//     that safe_pr_merge_lib.dart requires green (/build-apk Gate 3.5 and
//     reconcile_ci.dart read the run-level conclusion of the workflow, not a name);
//   - a red `flutter test` that does not fail its step: the step's status is that of
//     its LAST command under GitHub's default `bash -e {0}` (no pipefail), so a pipe, a
//     `|| true`, a step `if:` or `continue-on-error` on the shard turns a red suite into a
//     green shard, a green gate and a mergeable PR;
//   - a gate fed by anything other than `needs.unit-test.result` (`job.status` is
//     always `success` at step time), or a matrix with a second dimension (the shard
//     list stays [1..4] while `strategy.job-total` grows, and half the files run nowhere).
//
// Source assertions are comment-stripped (feedback_source_grep_strip_comments_first):
// the explanatory comments in test.yml quote `flutter test test/` and `needs:`.
// A source grep proves PRESENCE only, so the two `run:` scripts are also RUN, with
// the `dart` and `flutter` they call replaced by shell functions that record their
// arguments and return a chosen status - the behavioural half
// (feedback_source_grep_false_confidence). The wiring that the scripts cannot see
// (which expression feeds the gate, which keys the jobs carry) is pinned by name.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _matrixJobId = 'unit-test';
const _gateJobId = 'unit-tests-gate';
const _shardNameTemplate = r'Unit Tests shard ${{ matrix.shard }}/${{ strategy.job-total }}';

/// Full-line YAML comments removed (a `#` inside a `run:` body or a value survives).
String _strip(String s) => s.split('\n').where((l) => !RegExp(r'^\s*#').hasMatch(l)).join('\n');

/// A job's block: from `  <id>:` to the next sibling job (two-space indent).
String? _job(String src, String id) {
  final lines = src.split('\n');
  final start = lines.indexWhere((l) => RegExp('^  ${RegExp.escape(id)}:\\s*\$').hasMatch(l));
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^  [A-Za-z0-9_-]+:').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// The `name:` of every job (4-space indent), in file order.
List<String> _jobNames(String src) => [
      for (final l in src.split('\n'))
        if (RegExp(r'^    name: (.+?)\s*$').firstMatch(l) case final m?) m.group(1)!,
    ];

/// The dedented body of the first `run: |` block in [job] (the first one containing
/// [contains], when given); throws when there is none.
String _runBlock(String job, {Pattern? contains}) {
  final lines = job.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^(\s*)run: \|\s*$').firstMatch(lines[i]);
    if (m == null) continue;
    final baseIndent = m.group(1)!.length;
    final body = <String>[];
    var bodyIndent = -1;
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j];
      if (l.trim().isEmpty) {
        body.add('');
        continue;
      }
      final ind = l.length - l.trimLeft().length;
      if (ind <= baseIndent) break;
      bodyIndent = bodyIndent < 0 ? ind : (ind < bodyIndent ? ind : bodyIndent);
      body.add(l);
    }
    final text = body.map((l) => l.isEmpty ? '' : l.substring(bodyIndent)).join('\n').trimRight();
    if (contains == null || text.contains(contains)) return '$text\n';
  }
  throw StateError('no matching `run: |` block in job:\n$job');
}

/// The shard list `strategy.matrix.shard: [1, 2, 3, 4]` as integers.
List<int> _matrixShards(String job) {
  final m = RegExp(r'shard:\s*\[([^\]]*)\]').firstMatch(job);
  if (m == null) throw StateError('no `shard: [...]` matrix in job:\n$job');
  return [for (final p in m.group(1)!.split(',')) int.parse(p.trim())];
}

/// The keys directly under `matrix:` (its dimensions, plus `include`/`exclude` if any),
/// in file order. Throws when `matrix:` is not a block (an inline `{...}` or a
/// `fromJson(...)` expression cannot be checked here, so it must not pass silently).
List<String> _matrixKeys(String job) {
  final lines = job.split('\n');
  final start = lines.indexWhere((l) => RegExp(r'^\s*matrix:\s*$').hasMatch(l));
  if (start < 0) throw StateError('no block-style `matrix:` in job:\n$job');
  int indentOf(String l) => l.length - l.trimLeft().length;
  final matrixIndent = indentOf(lines[start]);
  final keys = <String>[];
  int? keyIndent;
  for (var i = start + 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    if (indentOf(l) <= matrixIndent) break;
    keyIndent ??= indentOf(l);
    if (indentOf(l) == keyIndent) {
      final m = RegExp(r'^\s*([A-Za-z0-9_-]+):').firstMatch(l);
      if (m != null) keys.add(m.group(1)!);
    }
  }
  return keys;
}

/// Every `${{ ... }}` expression in [text], trimmed. A set: the question is WHICH
/// contexts reach the job, not how often.
Set<String> _expressions(String text) =>
    {for (final m in RegExp(r'\$\{\{\s*(.*?)\s*\}\}').allMatches(text)) m.group(1)!};

/// The lines of [job] that set [key] - as a job key or a step key (`- key:` too).
List<String> _keyLines(String job, String key) => [
      for (final l in job.split('\n'))
        if (RegExp('^\\s*(?:-\\s+)?${RegExp.escape(key)}:').hasMatch(l)) l.trim(),
    ];

void main() {
  late String src;
  late String matrixJob;
  late String gateJob;

  setUpAll(() {
    final f = File('.github/workflows/test.yml');
    expect(f.existsSync(), isTrue);
    src = _strip(f.readAsStringSync());
    matrixJob = _job(src, _matrixJobId)!;
    gateJob = _job(src, _gateJobId)!;
  });

  group('the shard matrix', () {
    test('exists under the job id `unit-test`, named by the template', () {
      expect(_job(src, _matrixJobId), isNotNull);
      expect(matrixJob, contains('name: $_shardNameTemplate'),
          reason: 'safe_pr_merge_lib.matrixJobNameTemplates names this exact template');
    });

    test('shards are 1..N consecutive, N >= 2, and fail-fast is off', () {
      final shards = _matrixShards(matrixJob);
      expect(shards.length, greaterThanOrEqualTo(2), reason: 'one shard is just the old single job');
      expect(shards, [for (var i = 1; i <= shards.length; i++) i],
          reason: 'scripts/ci_test_partition.dart takes a 1-based shard <= total; a gap or a 0 '
              'leaves files in no shard');
      expect(matrixJob, matches(RegExp(r'fail-fast:\s*false')),
          reason: 'one red shard must not cancel the others and hide their failures');
    });

    test('the matrix has ONE dimension, `shard`: job-total can never outgrow the shard list', () {
      expect(_matrixKeys(matrixJob), ['shard'],
          reason: 'a second dimension (or include:/exclude:) multiplies strategy.job-total while '
              'the shard list stays 1..4, so shards 1-4 of 8 cover half the files and the other '
              'half runs nowhere under a green gate (528 of 1057 files, measured by the B-pass)');
    });

    test('the only expressions in the shard job are matrix.shard and strategy.job-total', () {
      expect(_expressions(matrixJob), {'matrix.shard', 'strategy.job-total'},
          reason: 'nothing else (github.event.*, a branch name, a secret) may reach the shell script');
    });

    test('the shard count is the matrix length (strategy.job-total), never a second literal', () {
      final invocation =
          RegExp(r'ci_test_partition\.dart[^\n]*').firstMatch(matrixJob)?.group(0) ?? '';
      expect(invocation, contains(r'${{ matrix.shard }}'));
      expect(invocation, contains(r'${{ strategy.job-total }}'),
          reason: 'a hard-coded "4" next to a matrix of 3 or 5 silently drops or duplicates files');
      expect(invocation, isNot(matches(RegExp(r'"\d+"\s*\)'))),
          reason: 'no numeric literal as the total argument');
    });

    test('runs ONLY its own files; the whole-directory invocation is gone', () {
      final lastLine = _runBlock(matrixJob, contains: 'ci_test_partition.dart').trimRight().split('\n').last;
      expect(lastLine, r'flutter test $FILES --exclude-tags golden --reporter expanded',
          reason: 'flutter test must be the LAST command of the step and exactly this line: a pipe '
              '(`| tee`), `|| true` or anything appended changes the status the step reports, and '
              'GitHub\'s default `bash -e {0}` has no pipefail');
      expect(matrixJob, isNot(matches(RegExp(r'flutter test test/\s'))),
          reason: 'a shard that still runs `flutter test test/` repeats the whole suite');
      expect(matrixJob, contains(r'test -n "$FILES"'),
          reason: 'an empty list would make flutter test run the ENTIRE test/ directory');
    });

    test('keeps the Flutter pin, the 20-minute headroom and the workflow-level TZ', () {
      expect(matrixJob, contains("flutter-version: '3.41.4'"));
      expect(matrixJob, matches(RegExp(r'timeout-minutes:\s*20')));
      expect(src, matches(RegExp(r'^env:\s*\n\s+TZ: Asia/Kolkata', multiLine: true)),
          reason: 'IST is pinned at workflow level (several date-boundary contracts read it)');
    });
  });

  group('the gate job is THE `Unit Tests` check', () {
    test('named exactly `Unit Tests`, needs the matrix, and runs even when a shard failed', () {
      expect(gateJob, contains('name: Unit Tests\n'));
      expect(gateJob, matches(RegExp(r'needs:\s*unit-test\s*\n')));
      expect(gateJob, contains(r'if: ${{ !cancelled() }}'),
          reason: 'without it a failed shard SKIPS the gate, and a skipped gate is not a failure '
              'the merge wrapper can see as one');
    });

    test('the gate reads the shard result from `needs`, through env, and from nothing else', () {
      expect(gateJob.split('\n').map((l) => l.trim()), contains(r'SHARDS_RESULT: ${{ needs.unit-test.result }}'),
          reason: 'the behaviour test below injects SHARDS_RESULT itself, so the YAML that feeds it '
              'must be pinned here: `job.status` is always `success` while the gate step runs, so a '
              'gate fed by it can never fail');
      expect(RegExp(r'^\s*SHARDS_RESULT:', multiLine: true).allMatches(gateJob), hasLength(1),
          reason: 'a second assignment could shadow the pinned one');
      expect(_expressions(gateJob), {'!cancelled()', 'needs.unit-test.result'},
          reason: 'the gate has exactly two inputs: the job-level condition and the shard result');
    });

    test('nothing can turn a red shard green: no continue-on-error, no `if:` on the shard job or '
        'its steps, no `if:` on the gate step', () {
      // A job with `continue-on-error: true` reports `success` in needs.*.result when it
      // fails, a step with `if: false` is skipped (a green step), and a gate step with
      // `if: false` is skipped inside a green job: each leaves every check green with
      // zero tests run. They live in the YAML, where no script test can see them.
      for (final (name, job) in [('unit-test', matrixJob), ('unit-tests-gate', gateJob)]) {
        expect(_keyLines(job, 'continue-on-error'), isEmpty, reason: '$name must not set continue-on-error');
      }
      expect(_keyLines(matrixJob, 'if'), isEmpty,
          reason: 'a shard job or step with a condition can be skipped, and a skipped test step is a green one');
      expect(_keyLines(gateJob, 'if'), [r'if: ${{ !cancelled() }}'],
          reason: 'the gate has ONE condition; a second `if:` is on its step');
      expect(gateJob, contains('\n    if: \${{ !cancelled() }}\n'),
          reason: 'and that one is the JOB-level condition (4 spaces), not a step condition');
    });

    test('exactly ONE job in the workflow is named `Unit Tests`; names are unique', () {
      final names = _jobNames(src);
      expect(names.where((n) => n == 'Unit Tests'), hasLength(1),
          reason: 'two checks with one name make "latest run per name" judge only one of them');
      expect(names.toSet().length, names.length, reason: 'duplicate job names: $names');
    });

    test('BEHAVIOUR: the gate script passes ONLY when every shard succeeded', () {
      final script = _runBlock(gateJob);
      ProcessResult run(String result) => runSpawn('sh', ['-e', '-c', script],
          why: 'unit-tests-gate script with SHARDS_RESULT=$result',
          extraEnv: {'SHARDS_RESULT': result});

      expect(run('success').exitCode, 0);
      for (final bad in ['failure', 'cancelled', 'skipped', '']) {
        final r = run(bad);
        expect(r.exitCode, isNot(0),
            reason: 'shards that finished as "$bad" must fail the Unit Tests check');
        expect(r.stdout as String, contains('::error::'));
      }
    });
  });

  group('BEHAVIOUR: the shard step cannot run the wrong files', () {
    late String script;
    late Directory tmp;

    setUpAll(() {
      script = _runBlock(matrixJob, contains: 'ci_test_partition.dart')
          .replaceAll(r'${{ matrix.shard }}', '2')
          .replaceAll(r'${{ strategy.job-total }}', '4');
      expect(script, isNot(contains(r'${{')), reason: 'every expression must be substituted');
    });
    setUp(() => tmp = Directory.systemTemp.createTempSync('ci_matrix_step_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    });

    /// Runs the step with `dart` and `flutter` replaced by shell FUNCTIONS (a function
    /// beats a PATH lookup in sh, and a PATH stub cannot work on Windows).
    /// -e WITHOUT pipefail mirrors GitHub's default `bash -e {0}`: that is exactly the
    /// shell in which a `| tee` after `flutter test` would swallow a red suite.
    ({int code, String calls, String out}) runStep(
        {required String dartStdout, required int dartRc, int flutterRc = 0}) {
      final prelude = '''
dart() { echo "dart \$*" >> calls.log; printf '%s' '$dartStdout'; return $dartRc; }
flutter() { echo "flutter \$*" >> calls.log; return $flutterRc; }
''';
      final r = runSpawn('sh', ['-e', '-c', '$prelude$script'],
          why: 'shard step (dart rc=$dartRc, flutter rc=$flutterRc, stdout="$dartStdout")',
          workingDirectory: tmp.path);
      final log = File('${tmp.path}/calls.log');
      return (
        code: r.exitCode,
        calls: log.existsSync() ? log.readAsStringSync() : '',
        out: '${r.stdout}${r.stderr}',
      );
    }

    test('hands flutter exactly the partition output, plus the golden exclusion', () {
      final r = runStep(dartStdout: 'test/a_test.dart\ntest/b_test.dart\n', dartRc: 0);
      expect(r.code, 0, reason: r.out);
      expect(r.calls, contains('dart scripts/ci_test_partition.dart 2 4'),
          reason: 'shard and total must reach the partition script');
      final flutterCall = r.calls.split('\n').firstWhere((l) => l.startsWith('flutter '), orElse: () => '');
      expect(flutterCall, 'flutter test test/a_test.dart test/b_test.dart --exclude-tags golden --reporter expanded');
    });

    test('an EMPTY list FAILS and flutter is never called', () {
      final r = runStep(dartStdout: '', dartRc: 0);
      expect(r.code, isNot(0), reason: 'an empty list would run the entire test/ directory');
      expect(r.calls, isNot(contains('flutter ')), reason: 'flutter must not run with no file arguments');
      expect(r.out, contains('::error::'));
    });

    test('a FAILING partition script fails the step and flutter is never called', () {
      final r = runStep(dartStdout: 'test/a_test.dart\n', dartRc: 3);
      expect(r.code, isNot(0));
      expect(r.calls, isNot(contains('flutter ')),
          reason: 'a partition error must not be papered over by whatever it printed first');
    });

    test('a RED `flutter test` fails the step: the shard must report the suite\'s status', () {
      // The mirror of the tests above: they prove the step hands flutter the right files;
      // this proves a red result comes back out. Without it `flutter test ... | tee log`,
      // `... || true` or a trailing command leaves every test green (the B-pass mutant).
      final r = runStep(dartStdout: 'test/a_test.dart\ntest/b_test.dart\n', dartRc: 0, flutterRc: 7);
      expect(r.calls, contains('flutter test test/a_test.dart test/b_test.dart'),
          reason: 'setup: flutter did run, with the shard\'s files');
      expect(r.code, isNot(0),
          reason: 'a failing `flutter test` must fail the step (no pipefail under GitHub\'s default shell)');
    });

    test('a STRAY line in the partition output fails the step before flutter sees it', () {
      // Anything on the CLI's stdout becomes a `flutter test` file argument. The CLI prints
      // paths only, but a banner or a hook line from a future toolchain would not be one.
      for (final stray in [
        'Running build hooks...',
        'Welcome to Dart!',
        'lib/a_test.dart',
        'test/helper.dart',
        '-rf/a_test.dart',
        'test/has space_test.dart',
      ]) {
        final r = runStep(dartStdout: 'test/a_test.dart\n$stray\ntest/b_test.dart\n', dartRc: 0);
        expect(r.code, isNot(0), reason: 'stray line "$stray" must fail the step');
        expect(r.calls, isNot(contains('flutter ')), reason: 'flutter must not run with "$stray" in its arguments');
        expect(r.out, contains('::error::'));
      }
    });

    test('a list of well-formed paths is NOT mistaken for stray output', () {
      final r = runStep(
          dartStdout: 'test/a_test.dart\ntest/b/c-d_test.dart\ntest/e+f/g.h_test.dart\n', dartRc: 0);
      expect(r.code, 0, reason: r.out);
      expect(r.calls, contains('flutter test test/a_test.dart test/b/c-d_test.dart test/e+f/g.h_test.dart'));
    });
  });
}
