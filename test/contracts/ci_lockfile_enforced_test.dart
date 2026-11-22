// test/contracts/ci_lockfile_enforced_test.dart
//
// OI-520. A `pubspec.lock` the pinned Flutter cannot honour used to be INVISIBLE to CI: every job ran a
// plain `flutter pub get`, which re-resolves such a lock and goes green (the three Dependabot lock
// commits of 2026-11-21 were written by a Dart newer than 3.11.1, and every job passed on them).
// The guard is ONE flag in ONE required job: the `analyze` job (check name `Analyze`) resolves its
// packages with `flutter pub get --enforce-lockfile`, which exits 65 on such a lock and never writes it.
//
// A source grep proves PRESENCE only (feedback_source_grep_false_confidence), and this guard has three
// silent failure modes that a presence check misses, so the test pins the SHAPE of the whole guard:
//
//   - the flag dropped, or neutered (`|| true`, `--offline`, another command)  -> the guard is gone
//   - another `run:` step BEFORE it that resolves packages (`flutter pub get`)  -> the enforcing step
//     then checks a lock that was just rewritten, so it passes on any lock
//   - `if:` / `continue-on-error:` on the step or on the job                    -> a guard that did
//     not run, or whose failure is green
//   - `Analyze` no longer in `requiredSuccessJobs` (scripts/safe_pr_merge_lib.dart) -> the red job no
//     longer stops `safe_pr_merge.sh`, so the guard becomes advice
//
// The behavioural half is NOT in this file: whether the flag fails on a bad lock is the SDK's behaviour
// and is measured on the pinned SDK (docs/plans/2026-11-22-oi520-enforce-lockfile.md, F3) and on a real
// runner by a throwaway pull request that carries the old lock (same plan, F11). What this file adds is
// that the repo's own workflow keeps the guard in the one shape in which that behaviour matters.
//
// Each case names the mutant it kills (rule 21). The mutants are applied to the REAL files in memory;
// every case first asserts that the mutation APPLIED, so a mutant that matches nothing cannot pass
// as "killed" (feedback_mistake_mutation_restore_discards_uncommitted_fixes, the vacuous-mutant trap).

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _guardCommand = 'flutter pub get --enforce-lockfile';
const _jobId = 'analyze';
const _checkName = 'Analyze';

/// Full-line YAML comments removed (a `#` inside a `run:` body or a value survives).
String _strip(String s) =>
    s.replaceAll('\r\n', '\n').split('\n').where((l) => !RegExp(r'^\s*#').hasMatch(l)).join('\n');

/// A job's block: from `  <id>:` to the next sibling job (two-space indent); null when absent.
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

/// The job's own keys (four-space indent, before `steps:`), as key -> value text.
Map<String, String> _jobKeys(String job) {
  final keys = <String, String>{};
  for (final l in job.split('\n').skip(1)) {
    if (RegExp(r'^    steps:\s*$').hasMatch(l)) break;
    final m = RegExp(r'^    ([A-Za-z0-9_-]+):\s*(.*)$').firstMatch(l);
    if (m != null) keys[m.group(1)!] = m.group(2)!.trim();
  }
  return keys;
}

/// The steps of a job: the keys directly under each `      - ` item (eight-space indent), each with
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

/// The check names listed in `requiredSuccessJobs` of the merge wrapper's library (comments removed).
List<String> _requiredJobs(String libSrc) {
  final m = RegExp(r'const List<String> requiredSuccessJobs = <String>\[(.*?)\];', dotAll: true)
      .firstMatch(libSrc.replaceAll('\r\n', '\n').split('\n').map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n'));
  if (m == null) return const [];
  return RegExp(r"'([^']*)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
}

/// Everything wrong with the lockfile guard; empty means the guard is intact.
List<String> lockfileGuardProblems(String workflow, String mergeLibSrc) {
  final problems = <String>[];
  final job = _job(_strip(workflow), _jobId);
  if (job == null) return ['no job `$_jobId` in test.yml'];

  final keys = _jobKeys(job);
  if (keys['name'] != _checkName) {
    problems.add('the job must be named `$_checkName` (the check name the merge wrapper requires), '
        'found `${keys['name']}`');
  }
  for (final bad in ['if', 'continue-on-error']) {
    if (keys.containsKey(bad)) {
      problems.add('the job carries `$bad:` (a skipped job, or a red one that is green)');
    }
  }

  final steps = _steps(job);
  final firstRun = steps.indexWhere((s) => s.containsKey('run'));
  final pubGetSteps = [
    for (var i = 0; i < steps.length; i++)
      if (RegExp(r'\bpub\s+get\b|\bpub\s+upgrade\b').hasMatch(steps[i]['run'] ?? '')) i
  ];
  if (pubGetSteps.length != 1) {
    problems.add('the job must resolve packages in exactly ONE step, found ${pubGetSteps.length}');
  } else {
    final i = pubGetSteps.single;
    final step = steps[i];
    if (step['run'] != _guardCommand) {
      problems.add('the resolving step must run exactly `$_guardCommand`, found `${step['run']}`');
    }
    if (i != firstRun) {
      problems.add('the resolving step must be the FIRST `run:` step of the job: an earlier step '
          'may already have re-resolved the lock, which makes the enforcing step pass on any lock');
    }
    final extra = step.keys.toSet().difference({'name', 'run'});
    if (extra.isNotEmpty) {
      problems.add('the resolving step carries ${extra.map((k) => '`$k:`').join(', ')} '
          '(`if:` skips the guard, `continue-on-error:` makes its failure green, `env:` / `shell:` / '
          '`working-directory:` change what the command means)');
    }
  }

  if (!_requiredJobs(mergeLibSrc).contains(_checkName)) {
    problems.add('`$_checkName` is not in requiredSuccessJobs (scripts/safe_pr_merge_lib.dart): '
        'a red guard would no longer stop safe_pr_merge.sh');
  }
  return problems;
}

void main() {
  final workflow = File('.github/workflows/test.yml').readAsStringSync().replaceAll('\r\n', '\n');
  final mergeLib = File('scripts/safe_pr_merge_lib.dart').readAsStringSync().replaceAll('\r\n', '\n');

  const installBlock = '      - name: Install dependencies\n        run: $_guardCommand\n';
  const analyzeStep = '      - name: Flutter analyze (zero warnings allowed)\n        run: flutter analyze --no-fatal-infos\n';

  test('the real workflow keeps the guard intact', () {
    expect(lockfileGuardProblems(workflow, mergeLib), isEmpty);
  });

  test('the real files contain the anchors the mutants below rely on', () {
    // Without these the mutants would match nothing and every "killed" below would be vacuous.
    expect(workflow, contains(installBlock));
    expect(workflow, contains('$installBlock\n$analyzeStep'));
    expect(workflow, contains('    name: Analyze\n    runs-on: ubuntu-latest\n'));
    expect(mergeLib, contains("  'Analyze',\n"));
  });

  // Each entry: the mutant's name, what it does to the workflow and to the merge library, and the
  // guard behaviour it kills. Both transforms default to identity.
  final mutants = <String, ({String Function(String)? wf, String Function(String)? lib})>{
    'flag dropped': (wf: (String s) => s.replaceFirst('run: $_guardCommand', 'run: flutter pub get'), lib: null),
    'failure swallowed with || true': (wf: (String s) => s.replaceFirst('run: $_guardCommand', 'run: $_guardCommand || true'), lib: null),
    'extra argument that changes the meaning': (
      wf: (String s) => s.replaceFirst('run: $_guardCommand', 'run: $_guardCommand --offline'),
      lib: null,
    ),
    'step made conditional with if:': (
      wf: (String s) => s.replaceFirst(installBlock, "$installBlock        if: github.event_name == 'push'\n"),
      lib: null,
    ),
    'step failure made green with continue-on-error': (
      wf: (String s) => s.replaceFirst(installBlock, '$installBlock        continue-on-error: true\n'),
      lib: null,
    ),
    'a plain pub get step BEFORE the enforcing step': (
      wf: (String s) => s.replaceFirst(installBlock, '      - name: Resolve\n        run: flutter pub get\n\n$installBlock'),
      lib: null,
    ),
    'enforcing step moved after the analyze step': (
      wf: (String s) => s.replaceFirst('$installBlock\n$analyzeStep', '$analyzeStep\n$installBlock'),
      lib: null,
    ),
    'job made non-blocking with continue-on-error': (
      wf: (String s) => s.replaceFirst('    name: Analyze\n    runs-on: ubuntu-latest\n',
          '    name: Analyze\n    continue-on-error: true\n    runs-on: ubuntu-latest\n'),
      lib: null,
    ),
    'job made conditional with if:': (
      wf: (String s) => s.replaceFirst('    name: Analyze\n    runs-on: ubuntu-latest\n',
          "    name: Analyze\n    if: github.event_name == 'push'\n    runs-on: ubuntu-latest\n"),
      lib: null,
    ),
    'job renamed, so the required check name no longer exists': (
      wf: (String s) => s.replaceFirst('    name: Analyze\n    runs-on: ubuntu-latest\n', '    name: Static analysis\n    runs-on: ubuntu-latest\n'),
      lib: null,
    ),
    'Analyze dropped from requiredSuccessJobs': (wf: null, lib: (String s) => s.replaceFirst("  'Analyze',\n", '')),
  };

  for (final entry in mutants.entries) {
    test('kills the mutant: ${entry.key}', () {
      final wf = entry.value.wf?.call(workflow) ?? workflow;
      final lib = entry.value.lib?.call(mergeLib) ?? mergeLib;
      expect(wf != workflow || lib != mergeLib, isTrue, reason: 'the mutation did not apply: the anchor is stale');
      expect(lockfileGuardProblems(wf, lib), isNotEmpty,
          reason: 'the guard must notice: ${entry.key}');
    });
  }

  test('a comment that quotes the command does not count as the step', () {
    // The explanatory comment in test.yml quotes `flutter pub get`; only real steps may be judged.
    final withoutStep = workflow.replaceFirst(installBlock, '');
    expect(withoutStep, isNot(equals(workflow)));
    expect(lockfileGuardProblems(withoutStep, mergeLib), isNotEmpty,
        reason: 'a workflow with the step removed but the comment kept must fail');
  });
}
