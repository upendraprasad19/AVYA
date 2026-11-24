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

import '../../scripts/land_pr_lib.dart' show sweepTestStepName;
import '../helpers/spawn.dart';

const _matrixJobId = 'unit-test';
const _sweepJobId = 'sweep-test';
const _gateJobId = 'unit-tests-gate';
const _shardNameTemplate = r'Unit Tests shard ${{ matrix.shard }}/${{ strategy.job-total }}';
const _sweepNameTemplate = r'Unit Tests sweep shard ${{ matrix.shard }}/${{ strategy.job-total }}';

/// The two matrices (docs/plans/2026-11-24-ci-sweep-split.md): the CORE set and the
/// SWEEP set. Every shape rule below holds for BOTH; a rule pinned for one only would
/// leave the other free to run nothing under a green gate.
const _matrices = <(String id, String set, String nameTemplate)>[
  (_matrixJobId, 'core', _shardNameTemplate),
  (_sweepJobId, 'sweep', _sweepNameTemplate),
];

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
  late String sweepJob;
  late String gateJob;
  String jobOf(String id) => id == _matrixJobId ? matrixJob : sweepJob;

  setUpAll(() {
    final f = File('.github/workflows/test.yml');
    expect(f.existsSync(), isTrue);
    src = _strip(f.readAsStringSync());
    matrixJob = _job(src, _matrixJobId)!;
    sweepJob = _job(src, _sweepJobId)!;
    gateJob = _job(src, _gateJobId)!;
  });

  for (final (jobId, set, nameTemplate) in _matrices) {
  group('the $set shard matrix ($jobId)', () {
    late String matrixJob;
    setUpAll(() => matrixJob = jobOf(jobId));

    test('exists under its job id, named by its template', () {
      expect(_job(src, jobId), isNotNull);
      expect(matrixJob, contains('name: $nameTemplate\n'),
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
      expect(_expressions(matrixJob), {'matrix.shard', 'strategy.job-total', if (set == 'sweep') 'github.event_name'},
          reason: 'nothing else (github.event.*, a branch name, a secret) may reach the shell script; the '
              'sweep job alone also reads the event NAME, through env, for its scope step');
    });

    test('the shard count is the matrix length (strategy.job-total), never a second literal', () {
      final invocation =
          RegExp(r'ci_test_partition\.dart[^\n]*').firstMatch(matrixJob)?.group(0) ?? '';
      expect(invocation, contains(r'${{ matrix.shard }}'));
      expect(invocation, contains(r'${{ strategy.job-total }}'),
          reason: 'a hard-coded "4" next to a matrix of 3 or 5 silently drops or duplicates files');
      expect(invocation, isNot(matches(RegExp(r'"\d+"\s*\)'))),
          reason: 'no numeric literal as the total argument');
      expect(invocation, contains('--set $set)'),
          reason: 'the $jobId matrix must ask for the $set set and nothing else: the wrong set runs '
              'one half of the suite twice and the other half nowhere, under a green gate');
      expect(RegExp(r'ci_test_partition\.dart').allMatches(matrixJob), hasLength(1));
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

    test('keeps the Flutter pin, the 30-minute headroom (OI-461) and the workflow-level TZ', () {
      expect(matrixJob, contains("flutter-version: '3.41.4'"));
      expect(matrixJob, matches(RegExp(r'timeout-minutes:\s*30\b')));
      expect(src, matches(RegExp(r'^env:\s*\n\s+TZ: Asia/Kolkata', multiLine: true)),
          reason: 'IST is pinned at workflow level (several date-boundary contracts read it)');
    });
  });
  }

  group('the gate job is THE `Unit Tests` check', () {
    test('named exactly `Unit Tests`, needs BOTH matrices, and runs even when a shard failed', () {
      expect(gateJob, contains('name: Unit Tests\n'));
      expect(gateJob, matches(RegExp(r'needs:\s*\[unit-test, sweep-test\]\s*\n')),
          reason: 'a gate that does not need the sweep matrix passes while a sweep leg is red');
      expect(gateJob, contains(r'if: ${{ !cancelled() }}'),
          reason: 'without it a failed shard SKIPS the gate, and a skipped gate is not a failure '
              'the merge wrapper can see as one');
    });

    test('the gate reads the shard result from `needs`, through env, and from nothing else', () {
      expect(gateJob.split('\n').map((l) => l.trim()), contains(r'SHARDS_RESULT: ${{ needs.unit-test.result }}'),
          reason: 'the behaviour test below injects SHARDS_RESULT itself, so the YAML that feeds it '
              'must be pinned here: `job.status` is always `success` while the gate step runs, so a '
              'gate fed by it can never fail');
      expect(gateJob.split('\n').map((l) => l.trim()), contains(r'SWEEPS_RESULT: ${{ needs.sweep-test.result }}'));
      expect(RegExp(r'^\s*SHARDS_RESULT:', multiLine: true).allMatches(gateJob), hasLength(1),
          reason: 'a second assignment could shadow the pinned one');
      expect(RegExp(r'^\s*SWEEPS_RESULT:', multiLine: true).allMatches(gateJob), hasLength(1));
      expect(_expressions(gateJob), {'!cancelled()', 'needs.unit-test.result', 'needs.sweep-test.result'},
          reason: 'the gate has exactly three inputs: the job-level condition and the two matrix results');
    });

    test('nothing can turn a red shard green: no continue-on-error, no `if:` on the shard job or '
        'its steps, no `if:` on the gate step', () {
      // A job with `continue-on-error: true` reports `success` in needs.*.result when it
      // fails, a step with `if: false` is skipped (a green step), and a gate step with
      // `if: false` is skipped inside a green job: each leaves every check green with
      // zero tests run. They live in the YAML, where no script test can see them.
      for (final (name, job) in [('unit-test', matrixJob), ('sweep-test', sweepJob), ('unit-tests-gate', gateJob)]) {
        expect(_keyLines(job, 'continue-on-error'), isEmpty, reason: '$name must not set continue-on-error');
      }
      expect(_keyLines(matrixJob, 'if'), isEmpty,
          reason: 'a shard job or step with a condition can be skipped, and a skipped test step is a green one');
      expect(_keyLines(sweepJob, 'if'), ["if: steps.scope.outputs.run != 'false'"],
          reason: 'the sweep job has exactly ONE condition, on its test step, written so that a MISSING '
              'output runs the tests (compared against false, never against true)');
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

    test('BEHAVIOUR: the gate script passes ONLY when every shard of BOTH matrices succeeded', () {
      final script = _runBlock(gateJob);
      ProcessResult run(String core, String sweep) => runSpawn('sh', ['-e', '-c', script],
          why: 'unit-tests-gate script with SHARDS_RESULT=$core SWEEPS_RESULT=$sweep',
          extraEnv: {'SHARDS_RESULT': core, 'SWEEPS_RESULT': sweep});

      expect(run('success', 'success').exitCode, 0);
      for (final bad in ['failure', 'cancelled', 'skipped', '']) {
        // Each matrix alone: a gate that reads only one of them passes the other's mirror.
        for (final (core, sweep) in [(bad, 'success'), ('success', bad), (bad, bad)]) {
          final r = run(core, sweep);
          expect(r.exitCode, isNot(0),
              reason: 'core "$core" + sweep "$sweep" must fail the Unit Tests check');
          expect(r.stdout as String, contains('::error::'));
        }
      }
    });
  });

  group('the sweep scope step (option A): the only way to skip is an explicit run=false on a pull request', () {
    late List<String> stepNames;
    late String scope;

    setUpAll(() {
      stepNames = [
        for (final l in sweepJob.split('\n'))
          if (RegExp(r'^      - (?:name|uses): (.+?)\s*$').firstMatch(l) case final m?) m.group(1)!,
      ];
      scope = _runBlock(sweepJob, contains: 'ci_sweep_scope.dart');
    });

    test('order: pub get, index build, scope, tests; the condition sits on the test step and nowhere else', () {
      expect(stepNames, [
        'actions/checkout@v7',
        'subosito/flutter-action@v2',
        'Install dependencies',
        'Build the local indexes (strict)',
        'Decide whether this pull request can change the sweeps',
        sweepTestStepName,
      ], reason: 'land_pr_lib.sweepTestStepName must be the test step\'s exact name: land_pr reads that step\'s conclusion');
      final lines = sweepJob.split('\n');
      final ifLine = lines.indexWhere((l) => l.trim().startsWith('if:'));
      expect(lines[ifLine - 1].trim(), '- name: $sweepTestStepName',
          reason: 'the one `if:` belongs to the test step; on pub get or the index build it would break '
              'ci_local_indexes_steps_test, on the scope step it would leave the output unset');
      expect(sweepJob, contains('        id: scope\n'));
      expect(sweepJob, contains(r'EVENT_NAME: ${{ github.event_name }}'));
      expect(scope, isNot(contains(r'${{')), reason: 'the event name reaches the script through env only');
    });

    test('the checkout fetches the merge commit\'s parents (fetch-depth: 2)', () {
      expect(sweepJob, matches(RegExp(r'uses: actions/checkout@v7\n\s+with:\n\s+fetch-depth: 2\n')));
    });

    test('the output is written ONCE, as the last line, and the default is RUN', () {
      expect(RegExp(r'GITHUB_OUTPUT').allMatches(scope), hasLength(1));
      expect(scope.trimRight().split('\n').last, r'echo "run=$RUN" >> "$GITHUB_OUTPUT"');
      expect(scope.split('\n').first, 'RUN=true');
    });

    // GitHub runs the step under `bash -e`; dash (`sh` here) is the stricter reading of
    // POSIX errexit. The step relies on -e NOT applying inside an `if` condition and in
    // the non-final commands of an && list, so both shells are run.
    for (final shell in ['sh', 'bash'])
    group('BEHAVIOUR under $shell -e', () {
      late Directory tmp;
      setUp(() => tmp = Directory.systemTemp.createTempSync('ci_sweep_scope_step_'));
      tearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {/* best effort */}
      });

      /// Runs the step under `sh -e` with `git` and `dart` replaced by shell functions.
      /// [parents] is what `git rev-list --parents -n 1 HEAD` prints; [answer] what the
      /// scope script prints. Returns the content of $GITHUB_OUTPUT and the step status.
      ({int code, String output, String out, String calls}) runStep({
        String event = 'pull_request',
        String parents = 'aaa bbb ccc',
        int revListRc = 0,
        int diffRc = 0,
        String answer = 'run=false',
        int dartRc = 0,
      }) {
        File('${tmp.path}/answer').writeAsStringSync(answer);
        for (final stale in ['out', 'calls.log', 'summary', 'stdin.log']) {
          final f = File('${tmp.path}/$stale');
          if (f.existsSync()) f.deleteSync(); // runStep may be called twice in one test
        }
        final prelude = [
          'git() {',
          r'  echo "git $*" >> calls.log',
          r'  case "$1" in',
          "    rev-list) printf '%s\\n' '$parents'; return $revListRc;;",
          "    diff) printf '%s\\n' 'docs/x.md'; return $diffRc;;",
          '  esac',
          '}',
          r'dart() { echo "dart $*" >> calls.log; cat > stdin.log; cat answer; return ' '$dartRc; }',
          '',
        ].join('\n');
        final r = runSpawn(shell, ['-e', '-c', '$prelude$scope'],
            why: '$shell: sweep scope step (event=$event parents="$parents" answer="$answer" dartRc=$dartRc)',
            workingDirectory: tmp.path,
            extraEnv: {
              'EVENT_NAME': event,
              'GITHUB_OUTPUT': '${tmp.path}/out',
              'GITHUB_STEP_SUMMARY': '${tmp.path}/summary',
            },
            // The step under test writes these two files; they are the scenario, not a leak.
            allowControl: const {'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY'});
        final out = File('${tmp.path}/out');
        final calls = File('${tmp.path}/calls.log');
        return (
          code: r.exitCode,
          output: out.existsSync() ? out.readAsStringSync() : '',
          out: '${r.stdout}${r.stderr}',
          calls: calls.existsSync() ? calls.readAsStringSync() : '',
        );
      }

      test('SKIP: a pull request, a two-parent merge commit, and the script says exactly run=false', () {
        final r = runStep(answer: 'run=false\n');
        expect(r.code, 0, reason: r.out);
        expect(r.output, 'run=false\n');
        expect(r.out, contains('::notice::sweeps skipped'));
        expect(r.calls, contains('git diff --no-renames --name-only HEAD^1 HEAD'),
            reason: '--no-renames makes a rename print its OLD path too (the deleted-path fail-safe)');
        expect(r.calls, contains('dart scripts/ci_sweep_scope.dart'));
        expect(File('${tmp.path}/stdin.log').readAsStringSync(), 'docs/x.md\n',
            reason: 'the change list must reach the script on stdin');
        expect(File('${tmp.path}/summary').readAsStringSync(), contains('sweeps skipped'));
      });

      test('RUN: the script says run=true', () {
        final r = runStep(answer: 'run=true\n');
        expect(r.code, 0);
        expect(r.output, 'run=true\n');
        expect(r.out, isNot(contains('sweeps skipped')));
      });

      for (final event in ['push', 'workflow_dispatch', 'schedule', 'merge_group', '']) {
        test('RUN: event "$event" never asks the script (a push to main ALWAYS runs the sweeps)', () {
          final r = runStep(event: event);
          expect(r.code, 0);
          expect(r.output, 'run=true\n');
          expect(r.calls, isNot(contains('dart ')));
        });
      }

      for (final (why, parents) in [('one parent', 'aaa bbb'), ('no parent', 'aaa'), ('octopus', 'a b c d'), ('nothing', '')]) {
        test('RUN: HEAD is not a two-parent merge commit ($why)', () {
          final r = runStep(parents: parents);
          expect(r.code, 0);
          expect(r.output, 'run=true\n');
          expect(r.calls, isNot(contains('git diff')));
        });
      }

      test('RUN, and the step still SUCCEEDS: a failing `git rev-list`, a failing `git diff`, a failing `dart`', () {
        for (final r in [
          runStep(revListRc: 128, parents: ''),
          runStep(diffRc: 128),
          runStep(dartRc: 254),
          runStep(dartRc: 1),
        ]) {
          expect(r.code, 0, reason: 'a broken decision must run the sweeps, not turn the leg red: ${r.out}');
          expect(r.output, 'run=true\n');
        }
      });

      for (final stray in ['', 'run=False\n', 'run=false \n', 'Running build hooks...\nrun=false\n', 'run=false\nrun=true\n', 'false\n']) {
        test('RUN: anything on stdout other than exactly `run=false` (${stray.replaceAll('\n', r'\n')})', () {
          final r = runStep(answer: stray);
          expect(r.code, 0);
          expect(r.output, 'run=true\n');
        });
      }
    });
  });

  for (final (jobId, set, _) in _matrices) {
  group('BEHAVIOUR: the $set shard step cannot run the wrong files', () {
    late String script;
    late Directory tmp;

    setUpAll(() {
      script = _runBlock(jobOf(jobId), contains: 'ci_test_partition.dart')
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
      expect(r.calls, contains('dart scripts/ci_test_partition.dart 2 4 --set $set\n'),
          reason: 'shard, total and the set must reach the partition script');
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
  });  }
}
