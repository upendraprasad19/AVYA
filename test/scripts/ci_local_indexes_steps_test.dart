// test/scripts/ci_local_indexes_steps_test.dart
//
// Pins and EXECUTES the strict "Build the local indexes" steps of .github/workflows/test.yml
// (landing A2 of the merge-conflict-treadmill plan). docs/audit/OPEN_INDEX.md and
// docs/diagnoses/INDEX.md are gitignored LOCAL BUILD PRODUCTS, so a CI checkout has NEITHER.
// Every failure mode here is silent or far from its cause:
//
//   - a job that reads an index without building it fails with "No such file" inside a shard,
//     or - worse - a gate that fails OPEN on a missing file passes vacuously;
//   - a step that builds LENIENT (`--lenient`), or ends in `|| true`, turns a board with an
//     unknown status or a diagnose doc with no date into a green build, and the problem surfaces
//     on a developer's machine instead of on the PR that caused it;
//   - a step behind `if:` / `continue-on-error:` is a build that silently did not run;
//   - a step placed AFTER the shard run or the gate loop builds the files too late.
//
// Source assertions are comment-stripped (feedback_source_grep_strip_comments_first): the
// explanatory comments in test.yml quote `--lenient` and `if:`. A source grep proves PRESENCE
// only, so the step's own `run:` string is also EXECUTED (with the `dart` it calls replaced by a
// shell function pointing at the test's dart), in a throwaway tree with the REAL builders:
// against a board whose entry has an unknown status it must FAIL, against a good tree it must
// pass and leave both files - the behavioural half (feedback_source_grep_false_confidence).
//
// Each case names the mutant it kills (rule 21):
//   the jobs that run the suite / gate loop    -> a third such job added without the build step
//   (derived from test.yml, then pinned)
//   one build step per job, the exact command   -> step dropped from either job; `--lenient`;
//                                                  extra arguments; `|| true`; another script
//   only `name:` and `run:` on the step         -> `if:`, `continue-on-error:`, `env:`, `shell:`,
//                                                  `working-directory:` added
//   ordered after pub get, before its consumer  -> the step moved below the shard run / gate loop
//   `--lenient` appears nowhere in the file     -> a lenient build wired in any other step
//   EXECUTED: unknown status fails, good passes -> the run string made lenient, `|| true`-ed or
//                                                  pointed at a script that exits 0

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';

const _command = 'dart run scripts/build_local_indexes.dart';
const _jobs = ['unit-test', 'audit-gates'];

/// Full-line YAML comments removed (a `#` inside a `run:` body or a value survives).
String _strip(String s) => s.split('\n').where((l) => !RegExp(r'^\s*#').hasMatch(l)).join('\n');

/// A job's block: from `  <id>:` to the next sibling job (two-space indent).
String _job(String src, String id) {
  final lines = src.split('\n');
  final start = lines.indexWhere((l) => RegExp('^  ${RegExp.escape(id)}:\\s*\$').hasMatch(l));
  if (start < 0) throw StateError('no job `$id` in test.yml');
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^  [A-Za-z0-9_-]+:').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// Every job id of the workflow, in file order (two-space-indented keys under `jobs:`).
List<String> _jobIds(String src) {
  final ids = <String>[];
  var inJobs = false;
  for (final l in src.split('\n')) {
    if (RegExp(r'^jobs:\s*$').hasMatch(l)) {
      inJobs = true;
      continue;
    }
    if (!inJobs) continue;
    if (RegExp(r'^\S').hasMatch(l)) break; // the next top-level key ends `jobs:`
    final m = RegExp(r'^  ([A-Za-z0-9_-]+):\s*$').firstMatch(l);
    if (m != null) ids.add(m.group(1)!);
  }
  return ids;
}

/// The jobs that run the WHOLE test suite or the WHOLE gate loop, derived from the workflow itself
/// so a third such job cannot appear without the build step: the shard run
/// (`ci_test_partition.dart`), the gate loop (`scripts/check_*.dart`) and a `flutter test` with no
/// path argument. A narrow run (`flutter test test/supabase/ ...`) and a job that runs ONE named
/// gate are not readers of the generated indexes in this sense.
List<String> _suiteOrGateLoopJobs(String src) {
  final out = <String>[];
  for (final id in _jobIds(src)) {
    final runs = _steps(_job(src, id)).map((s) => s['run'] ?? '').join('\n');
    // Logical commands: a trailing backslash continues the command on the next line.
    final commands = runs.replaceAll(RegExp(r'\\\s*\n'), ' ').split('\n');
    final wholeSuite = commands.any((c) =>
        RegExp(r'\bflutter test\b').hasMatch(c) && !RegExp(r'\bflutter test\b[^\n]*\btest/').hasMatch(c));
    if (runs.contains('ci_test_partition.dart') || runs.contains('scripts/check_*.dart') || wholeSuite) {
      out.add(id);
    }
  }
  return out;
}

/// The steps of a job: the keys directly under each `      - ` item (8-space indent), each with
/// its value text (a block scalar is the indicator plus its trimmed lines).
List<Map<String, String>> _steps(String job) {
  final steps = <Map<String, String>>[];
  Map<String, String>? cur;
  String? key;
  final buf = <String>[];
  void flush() {
    if (cur != null && key != null) cur[key!] = buf.join('\n').trim();
    buf.clear();
    key = null;
  }

  for (final l in job.split('\n')) {
    final dash = RegExp(r'^      - ([A-Za-z0-9_-]+):\s*(.*)$').firstMatch(l);
    final next = RegExp(r'^        ([A-Za-z0-9_-]+):\s*(.*)$').firstMatch(l);
    if (dash != null) {
      flush();
      cur = <String, String>{};
      steps.add(cur);
      key = dash.group(1);
      buf.add(dash.group(2)!);
    } else if (next != null && cur != null) {
      flush();
      key = next.group(1);
      buf.add(next.group(2)!);
    } else if (cur != null && key != null) {
      buf.add(l.trim());
    }
  }
  flush();
  return steps;
}

/// The index of the first step whose `run:` contains [needle]; -1 when none.
int _indexOfRun(List<Map<String, String>> steps, Pattern needle) =>
    steps.indexWhere((s) => (s['run'] ?? '').contains(needle));

List<int> _buildStepIndexes(List<Map<String, String>> steps) => [
      for (var i = 0; i < steps.length; i++)
        if ((steps[i]['run'] ?? '').contains('build_local_indexes.dart')) i,
    ];

/// The `run:` string of [id]'s build step, as the workflow carries it.
String _buildCommand(String src, String id) {
  final steps = _steps(_job(src, id));
  return steps[_buildStepIndexes(steps).single]['run']!;
}

String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

String _board(List<String> sections) => '# Open issues\n\n${sections.join()}';

String _oi(int id, {String status = 'OPEN'}) =>
    '## OI-$id — issue $id\n\n- **Status**: $status\n- **Blocked on**: nothing\n- **Verified**: never\n\n';

void main() {
  late String src;
  late String repoRoot;
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    final f = File('.github/workflows/test.yml');
    expect(f.existsSync(), isTrue);
    src = _strip(f.readAsStringSync());
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('ci_local_indexes_');
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('each job that reads an index builds it, strict, once', () {
    test('the jobs that run the whole suite or the whole gate loop are exactly the ones pinned below', () {
      // Derived from test.yml, not from the list: a new job that runs `flutter test` (whole), the
      // shard partition or the gate loop would otherwise be invisible to every case in this group.
      expect(_suiteOrGateLoopJobs(src), unorderedEquals(_jobs),
          reason: 'a job that runs the suite or the gate loop must build the local indexes first '
              '(a checkout has neither) and be added to `_jobs` here');
    });

    test('the derivation itself: whole suite / shard / gate loop count, a narrow run or ONE named gate does not', () {
      String wf(String run) => 'jobs:\n  j:\n    steps:\n      - name: x\n        run: $run\n';
      expect(_suiteOrGateLoopJobs(wf('flutter test')), ['j']);
      expect(_suiteOrGateLoopJobs(wf('flutter test --coverage')), ['j']);
      expect(_suiteOrGateLoopJobs(wf('dart run scripts/ci_test_partition.dart')), ['j']);
      expect(_suiteOrGateLoopJobs(wf('for g in scripts/check_*.dart; do dart run \$g; done')), ['j']);
      expect(_suiteOrGateLoopJobs(wf('flutter test test/supabase/')), isEmpty);
      expect(_suiteOrGateLoopJobs(wf('dart run scripts/check_plan_review_record_exists.dart')), isEmpty);
      expect(_suiteOrGateLoopJobs('jobs:\n  a:\n    steps:\n      - name: x\n        run: |\n          flutter test \\\n            test/edge_functions/\n'),
          isEmpty,
          reason: 'a line continuation joins the path to the command');
    });

    for (final id in _jobs) {
      test('$id: exactly one build step, the exact command', () {
        final steps = _steps(_job(src, id));
        final at = _buildStepIndexes(steps);
        expect(at, hasLength(1),
            reason: '`$id` must carry ONE step that builds the local indexes (a checkout has '
                'neither file); found ${at.length}');
        expect(steps[at.single]['run'], _command,
            reason: 'the exact command: `--lenient`, extra arguments, `|| true` or a different '
                'script each turn a bad board / diagnose doc into a green build');
      });

      test('$id: the step has ONLY `name` and `run` (no condition, no continue-on-error)', () {
        final steps = _steps(_job(src, id));
        final step = steps[_buildStepIndexes(steps).single];
        expect(step.keys.toSet(), {'name', 'run'},
            reason: 'an `if:` makes it a build that silently did not run; `continue-on-error:` '
                'makes a failed build green; `env:` / `shell:` / `working-directory:` change '
                'what the command means');
      });
    }

    test('the shard job builds BEFORE the shard run, after pub get', () {
      final steps = _steps(_job(src, 'unit-test'));
      final build = _buildStepIndexes(steps).single;
      final pubGet = _indexOfRun(steps, 'flutter pub get');
      final shardRun = _indexOfRun(steps, 'ci_test_partition.dart');
      expect(pubGet, greaterThanOrEqualTo(0));
      expect(shardRun, greaterThanOrEqualTo(0), reason: 'the shard run step must still be findable');
      expect(build, greaterThan(pubGet), reason: '`dart run` needs the packages resolved first');
      expect(build, lessThan(shardRun),
          reason: 'tests that read an index run inside the shard: built after it is built too late');
    });

    test('the audit job builds BEFORE the gate loop, after pub get', () {
      final steps = _steps(_job(src, 'audit-gates'));
      final build = _buildStepIndexes(steps).single;
      final pubGet = _indexOfRun(steps, 'flutter pub get');
      final loop = _indexOfRun(steps, 'scripts/check_*.dart');
      expect(pubGet, greaterThanOrEqualTo(0));
      expect(loop, greaterThanOrEqualTo(0), reason: 'the gate loop step must still be findable');
      expect(build, greaterThan(pubGet));
      expect(build, lessThan(loop),
          reason: 'gates that read an index (check_context_artifact_budget, '
              'check_no_deferral_euphemism) run in that loop');
    });

    test('`--lenient` appears nowhere in the workflow (CI is STRICT)', () {
      expect(src, isNot(contains('--lenient')),
          reason: 'lenient is the developer-machine mode that tolerates what strict refuses; a '
              'CI step that used it would let the very problem it exists to catch through');
    });
  });

  group('the step\'s own command, EXECUTED', () {
    /// A tree with the real builders (closure of the orchestrator) and [board] as the OI board.
    String tree(String board) {
      final root = '${tmp.path}/t${n++}';
      Directory(root).createSync(recursive: true);
      copyScriptClosure(repoRoot, root, const ['scripts/build_local_indexes.dart']);
      Directory('$root/docs/audit').createSync(recursive: true);
      Directory('$root/docs/diagnoses').createSync(recursive: true);
      File('$root/docs/audit/open_issues.md').writeAsStringSync(board);
      File('$root/docs/diagnoses/2026-10-01-seed-aaaaaa.md').writeAsStringSync(
          '---\nbug_id: aaaaaa\ndate: 2026-10-01\nsymptom: it broke\n---\n# seed\n');
      return root;
    }

    /// Runs [command] the way a CI step does (`sh`, cwd = the tree), with `dart` resolved to the
    /// test's own dart through a shell function (the runner has dart on PATH; this harness may not).
    ProcessResult step(String command, String root) => runSpawn(
          'sh',
          ['-c', 'dart() { ${_shQuote(dartBin())} "\$@"; }\n$command\n'],
          why: 'ci_local_indexes_steps_test: $command in $root',
          workingDirectory: root,
          stdoutEncoding: systemEncoding,
          stderrEncoding: systemEncoding,
        );

    String diag(ProcessResult r) => 'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}';

    test('both jobs run the SAME command string (one execution covers both)', () {
      expect({for (final id in _jobs) _buildCommand(src, id)}, {_command});
    });

    test('a board with an UNKNOWN status FAILS the step (strict), naming the entry', () {
      final root = tree(_board([_oi(1), _oi(2, status: 'WIBBLE')]));
      final r = step(_buildCommand(src, 'unit-test'), root);
      expect(r.exitCode, isNot(0), reason: 'a lenient or `|| true` step would pass here\n${diag(r)}');
      expect('${r.stdout}${r.stderr}', contains('OI-2'), reason: diag(r));
    });

    test('a good tree passes the step and leaves BOTH generated files', () {
      final root = tree(_board([_oi(1), _oi(2)]));
      final r = step(_buildCommand(src, 'audit-gates'), root);
      expect(r.exitCode, 0, reason: diag(r));
      expect(File('$root/docs/audit/OPEN_INDEX.md').existsSync(), isTrue, reason: diag(r));
      expect(File('$root/docs/diagnoses/INDEX.md').existsSync(), isTrue, reason: diag(r));
    });

    test('a diagnose doc with no date FAILS the step too (the other half of strict)', () {
      final root = tree(_board([_oi(1)]));
      File('$root/docs/diagnoses/2026-10-02-dateless-bbbbbb.md')
          .writeAsStringSync('---\nbug_id: bbbbbb\nsymptom: it broke\n---\n# dateless\n');
      final r = step(_buildCommand(src, 'unit-test'), root);
      expect(r.exitCode, isNot(0), reason: diag(r));
      expect('${r.stdout}${r.stderr}', contains('dateless-bbbbbb'), reason: diag(r));
    });
  });
}
