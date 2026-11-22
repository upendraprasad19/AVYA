// test/contracts/ci_lockfile_enforced_test.dart
//
// OI-520. A `pubspec.lock` that is not what the pinned Flutter writes was INVISIBLE to CI: every job ran
// a plain `flutter pub get`, which re-resolves such a lock and goes green (the three Dependabot lock
// commits of 2026-11-21 did not match what Flutter 3.41.4 writes, and every job passed on them).
// The guard is two adjacent steps of ONE job, the `analyze` job (check name `Analyze`, a job that
// scripts/safe_pr_merge.sh requires): `flutter pub get`, then `git ls-files --error-unmatch -- pubspec.lock &&
// git diff --exit-code -- pubspec.lock` (the first half catches a PR that DELETES the lock: `pub get`
// regenerates it untracked and `git diff` says nothing about an untracked file).
// `flutter pub get --enforce-lockfile` was tried first and rejected: measured, it exits 0 on a lock whose
// only drift is metadata (an `sdks` floor edited, a dependency added that the lock already holds
// transitively) and the next plain `pub get` still rewrites the file, which is OI-520's own symptom.
//
// A source grep proves PRESENCE only (feedback_source_grep_false_confidence), and this guard has silent
// failure modes a presence check misses, so the test pins the SHAPE of the guard and of the job around it:
//
//   - the verify step dropped, neutered (`|| true`, another path), conditional or non-blocking
//   - the verify step not directly after the one resolving step (moved after `flutter analyze`)
//   - a second resolving step, or any `run:` / unknown action step BEFORE the resolving step
//     (a step that re-resolved first would make the check compare a lock that was just rewritten)
//   - the job made conditional or non-blocking, given `env:` / `defaults:` / `container:` / `needs:`
//     (only name, runs-on and timeout-minutes are allowed), renamed, or its check name duplicated
//   - the job's `flutter-version` changed alone (the guard would then judge the lock against another SDK)
//   - `Analyze` no longer in `requiredSuccessJobs` (scripts/safe_pr_merge_lib.dart), which would turn a
//     red guard into advice
//
// The behavioural half is NOT in this file: that `pub get` rewrites a drifted lock and `git diff` then
// fails is the SDK's and git's behaviour. It is measured on the pinned SDK and on a real runner
// (docs/plans/2026-11-22-oi520-enforce-lockfile.md, F3 and F11). What this file adds is that the repo's
// own workflow keeps the guard in the one shape in which that behaviour matters.
//
// Each mutant names the guard behaviour it kills and the problem token it must produce, so a mutant that
// dies for an unrelated reason fails here (rule 21). Mutants are applied to the REAL files in memory and
// every case first asserts the mutation APPLIED, so a stale anchor cannot pass as "killed".

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _resolveCommand = 'flutter pub get';
const _verifyCommand = 'git ls-files --error-unmatch -- pubspec.lock && git diff --exit-code -- pubspec.lock';
const _jobId = 'analyze';
const _checkName = 'Analyze';
const _allowedJobKeys = {'name', 'runs-on', 'timeout-minutes'};
const _allowedActionsBeforeResolve = ['actions/checkout@', 'subosito/flutter-action@'];

/// Full-line YAML comments removed (a `#` inside a `run:` body or a value survives).
String _strip(String s) =>
    s.replaceAll('\r\n', '\n').split('\n').where((l) => !RegExp(r'^\s*#').hasMatch(l)).join('\n');

/// The line range [start, end) of a job block: from `  <id>:` to the next sibling job; null when absent.
(int, int)? _jobRange(List<String> lines, String id) {
  final start = lines.indexWhere((l) => RegExp('^  ${RegExp.escape(id)}:\\s*\$').hasMatch(l));
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^  [A-Za-z0-9_-]+:').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return (start, end);
}

String? _job(String src, String id) {
  final lines = src.split('\n');
  final r = _jobRange(lines, id);
  return r == null ? null : lines.sublist(r.$1, r.$2).join('\n');
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
    if (RegExp(r'^\S').hasMatch(l)) break;
    final m = RegExp(r'^  ([A-Za-z0-9_-]+):\s*$').firstMatch(l);
    if (m != null) ids.add(m.group(1)!);
  }
  return ids;
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
  final noComments =
      libSrc.replaceAll('\r\n', '\n').split('\n').map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n');
  final m = RegExp(r'const List<String> requiredSuccessJobs = <String>\[(.*?)\];', dotAll: true).firstMatch(noComments);
  if (m == null) return const [];
  return RegExp(r"'([^']*)'").allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
}

String? _flutterVersionOf(Map<String, String> step) =>
    RegExp(r'flutter-version:\s*(\S+)').firstMatch(step['with'] ?? '')?.group(1);

/// Everything wrong with the lockfile guard; empty means the guard is intact. Every message starts with
/// a stable `[token]` that the mutants below assert on.
List<String> lockfileGuardProblems(String workflow, String mergeLibSrc) {
  final problems = <String>[];
  final src = _strip(workflow);
  final job = _job(src, _jobId);
  if (job == null) return ['[job-missing] no job `$_jobId` in test.yml'];

  final keys = _jobKeys(job);
  if (keys['name'] != _checkName) {
    problems.add('[job-name] the job must be named `$_checkName` (the check name the merge wrapper requires), '
        'found `${keys['name']}`');
  }
  final extraKeys = keys.keys.toSet().difference(_allowedJobKeys);
  if (extraKeys.isNotEmpty) {
    problems.add('[job-keys] the job carries ${extraKeys.map((k) => '`$k:`').join(', ')}; only '
        '${_allowedJobKeys.join(', ')} are allowed (`if:` skips the guard, `continue-on-error:` makes it '
        'green, `env:` / `defaults:` / `container:` / `needs:` change what its steps mean)');
  }
  final sameName = [
    for (final id in _jobIds(src))
      if (_jobKeys(_job(src, id)!)['name'] == _checkName) id
  ];
  if (sameName.length != 1) {
    problems.add('[job-name-unique] exactly one job may carry the check name `$_checkName`, found '
        '${sameName.length} (${sameName.join(', ')}): the wrapper judges the newest check-run of a NAME');
  }

  final steps = _steps(job);
  final resolving = [
    for (var i = 0; i < steps.length; i++)
      if (RegExp(r'\bpub\s+(get|upgrade|downgrade|add|remove)\b').hasMatch(steps[i]['run'] ?? '')) i
  ];
  if (resolving.length != 1) {
    problems.add('[resolve-count] the job must resolve packages in exactly ONE step, found ${resolving.length}');
  } else {
    final i = resolving.single;
    final step = steps[i];
    if (step['run'] != _resolveCommand) {
      problems.add('[resolve-command] the resolving step must run exactly `$_resolveCommand`, found `${step['run']}`');
    }
    final extra = step.keys.toSet().difference({'name', 'run'});
    if (extra.isNotEmpty) {
      problems.add('[resolve-extra-keys] the resolving step carries ${extra.map((k) => '`$k:`').join(', ')}');
    }
    for (var j = 0; j < i; j++) {
      final uses = steps[j]['uses'];
      final ok = uses != null &&
          !steps[j].containsKey('run') &&
          _allowedActionsBeforeResolve.any((a) => uses.startsWith(a));
      if (!ok) {
        problems.add('[pre-step] step ${j + 1} runs before the resolving step and is not an allowed action '
            '(${_allowedActionsBeforeResolve.join(', ')}): it may already have re-resolved the lock, which '
            'makes the verify step compare a lock that was just rewritten');
      }
    }
    final verify = i + 1 < steps.length ? steps[i + 1] : null;
    if (verify == null ||
        verify['run'] != _verifyCommand ||
        verify.keys.toSet().difference({'name', 'run'}).isNotEmpty) {
      problems.add('[verify-step] the step DIRECTLY after the resolving step must be a plain `run: $_verifyCommand` '
          'with only `name:` and `run:` (`if:` skips it, `continue-on-error:` and `|| true` make its failure '
          'green, another path or a later position checks nothing); found `${verify ?? '(none)'}`');
    }
  }

  final versions = RegExp(r'^\s*flutter-version:\s*(\S+)', multiLine: true)
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
  final own = steps.map(_flutterVersionOf).whereType<String>().toList();
  if (own.length != 1 || versions.length != 1 || !versions.contains(own.single)) {
    problems.add('[flutter-version] the job must pin the SAME flutter-version as every other job of the '
        'workflow (job: ${own.join(', ')}; workflow: ${versions.join(', ')}); a different SDK would judge '
        'the lock against another Flutter');
  }

  if (!_requiredJobs(mergeLibSrc).contains(_checkName)) {
    problems.add('[required-job] `$_checkName` is not in requiredSuccessJobs (scripts/safe_pr_merge_lib.dart): '
        'a red guard would no longer stop safe_pr_merge.sh');
  }
  return problems;
}

void main() {
  final workflow = File('.github/workflows/test.yml').readAsStringSync().replaceAll('\r\n', '\n');
  final mergeLib = File('scripts/safe_pr_merge_lib.dart').readAsStringSync().replaceAll('\r\n', '\n');

  const installBlock = '      - name: Install dependencies\n        run: $_resolveCommand\n';
  const verifyBlock =
      '      - name: Verify pubspec.lock is what the pinned Flutter writes (OI-520)\n        run: $_verifyCommand\n';
  const analyzeBlock = '      - name: Flutter analyze (zero warnings allowed)\n        run: flutter analyze --no-fatal-infos\n';

  /// Applies [change] to the `analyze` job's lines only, asserting the anchor [from] is inside it.
  String inJob(String src, String from, String to) {
    final lines = src.split('\n');
    final r = _jobRange(lines, _jobId)!;
    final block = lines.sublist(r.$1, r.$2).join('\n');
    expect(block, contains(from), reason: 'the anchor is not in the analyze job: the mutant would be vacuous');
    return [...lines.sublist(0, r.$1), block.replaceFirst(from, to), ...lines.sublist(r.$2)].join('\n');
  }

  test('the real workflow keeps the guard intact', () {
    expect(lockfileGuardProblems(workflow, mergeLib), isEmpty);
  });

  test('the real files contain the anchors the mutants below rely on', () {
    final job = _job(workflow, _jobId)!;
    expect(job, contains('$installBlock\n$verifyBlock\n$analyzeBlock'),
        reason: 'install, verify and analyze must be consecutive steps, each a name + run pair');
    expect(job, contains('    name: Analyze\n    runs-on: ubuntu-latest\n'));
    expect(job, contains('      - uses: actions/checkout@'));
    expect(job, contains("          flutter-version: '"));
    expect(mergeLib, contains("  'Analyze',\n"));
  });

  // name -> (token the guard must report, how the workflow is mutated, how the merge library is mutated)
  final mutants = <String, ({String token, String Function(String)? wf, String Function(String)? lib})>{
    'verify step removed': (token: 'verify-step', wf: (String s) => inJob(s, '$verifyBlock\n', ''), lib: null),
    'verify failure swallowed with || true': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: $_verifyCommand || true'),
      lib: null,
    ),
    'verify checks another file': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: git diff --exit-code -- pubspec.yaml'),
      lib: null,
    ),
    // The mirror of "the lock differs": a PR that DELETES pubspec.lock. `pub get` regenerates it untracked and
    // `git diff` says nothing about an untracked file (measured: exit 0), so the diff alone passes it.
    'verify is the bare diff, so a deleted lock passes': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: git diff --exit-code -- pubspec.lock'),
      lib: null,
    ),
    'tracked check joined with ; so only the last command decides': (
      token: 'verify-step',
      wf: (String s) => inJob(
        s,
        'run: $_verifyCommand',
        'run: git ls-files --error-unmatch -- pubspec.lock; git diff --exit-code -- pubspec.lock',
      ),
      lib: null,
    ),
    'verify step made conditional with if:': (
      token: 'verify-step',
      wf: (String s) => inJob(s, verifyBlock, "$verifyBlock        if: github.event_name == 'push'\n"),
      lib: null,
    ),
    'verify failure made green with continue-on-error': (
      token: 'verify-step',
      wf: (String s) => inJob(s, verifyBlock, '$verifyBlock        continue-on-error: true\n'),
      lib: null,
    ),
    'verify step moved after the analyze step': (
      token: 'verify-step',
      wf: (String s) => inJob(s, '$verifyBlock\n$analyzeBlock', '$analyzeBlock\n$verifyBlock'),
      lib: null,
    ),
    'resolving command changed (--offline)': (
      token: 'resolve-command',
      wf: (String s) => inJob(s, 'run: $_resolveCommand\n', 'run: $_resolveCommand --offline\n'),
      lib: null,
    ),
    'a second resolving step added': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - name: Again\n        run: flutter pub get\n'),
      lib: null,
    ),
    'a run step before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '      - name: Prepare\n        run: echo prepare\n\n$installBlock'),
      lib: null,
    ),
    'an unknown action before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '      - uses: some-org/resolve-action@v1\n\n$installBlock'),
      lib: null,
    ),
    'job made non-blocking with continue-on-error': (
      token: 'job-keys',
      wf: (String s) => inJob(s, '    runs-on: ubuntu-latest\n', '    continue-on-error: true\n    runs-on: ubuntu-latest\n'),
      lib: null,
    ),
    'job made conditional with if:': (
      token: 'job-keys',
      wf: (String s) =>
          inJob(s, '    runs-on: ubuntu-latest\n', "    if: github.event_name == 'push'\n    runs-on: ubuntu-latest\n"),
      lib: null,
    ),
    'job given env:': (
      token: 'job-keys',
      wf: (String s) => inJob(
          s, '    runs-on: ubuntu-latest\n', '    runs-on: ubuntu-latest\n    env:\n      PUB_HOSTED_URL: https://pub.example.invalid\n'),
      lib: null,
    ),
    'job given defaults:': (
      token: 'job-keys',
      wf: (String s) => inJob(s, '    runs-on: ubuntu-latest\n',
          '    runs-on: ubuntu-latest\n    defaults:\n      run:\n        working-directory: ./scripts\n'),
      lib: null,
    ),
    'job renamed, so the required check name no longer exists': (
      token: 'job-name',
      wf: (String s) => inJob(s, '    name: Analyze\n', '    name: Static analysis\n'),
      lib: null,
    ),
    'a second job carries the check name Analyze': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  analyze-twin:\n    name: Analyze\n    runs-on: ubuntu-latest\n',
      lib: null,
    ),
    "this job's flutter-version changed alone": (
      token: 'flutter-version',
      wf: (String s) => inJob(s, "flutter-version: '3.41.4'", "flutter-version: '3.99.0'"),
      lib: null,
    ),
    "this job's flutter-version removed": (
      token: 'flutter-version',
      wf: (String s) => inJob(s, "          flutter-version: '3.41.4'\n", ''),
      lib: null,
    ),
    'Analyze dropped from requiredSuccessJobs': (
      token: 'required-job',
      wf: null,
      lib: (String s) => s.replaceFirst("  'Analyze',\n", ''),
    ),
  };

  for (final entry in mutants.entries) {
    test('kills the mutant: ${entry.key}', () {
      final wf = entry.value.wf?.call(workflow) ?? workflow;
      final lib = entry.value.lib?.call(mergeLib) ?? mergeLib;
      expect(wf != workflow || lib != mergeLib, isTrue, reason: 'the mutation did not apply: the anchor is stale');
      final problems = lockfileGuardProblems(wf, lib);
      expect(problems.any((p) => p.startsWith('[${entry.value.token}]')), isTrue,
          reason: 'the guard must report [${entry.value.token}] for "${entry.key}", got: $problems');
    });
  }

  test('a comment that quotes the command does not count as the step', () {
    // The explanatory comment in test.yml quotes the commands; only real steps may be judged.
    final withoutSteps = inJob(workflow, '$installBlock\n$verifyBlock\n', '');
    expect(withoutSteps, isNot(equals(workflow)));
    expect(lockfileGuardProblems(withoutSteps, mergeLib).any((p) => p.startsWith('[resolve-count]')), isTrue,
        reason: 'a workflow with both steps removed but the comment kept must fail');
  });
}
