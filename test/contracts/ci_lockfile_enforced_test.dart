// test/contracts/ci_lockfile_enforced_test.dart
//
// OI-520. A `pubspec.lock` that the pinned Flutter's `pub get` would change was INVISIBLE to CI: every job ran
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
//     (a step that re-resolved first would make the check compare a lock that was just rewritten); the two
//     allowed actions may appear once each and carry only their known `with:` keys (a `ref:` would make
//     the job judge another ref's lock)
//   - the job made conditional or non-blocking, given `env:` / `defaults:` / `container:` / `needs:`
//     (only name, runs-on, timeout-minutes and steps are allowed, wherever they are written), renamed,
//     or its check name carried by a second job (explicit `name:` OR, when a job has none, its id) in this
//     file or in any other file of .github/workflows/ (the wrapper judges the newest check-run of a NAME)
//   - the job's `flutter-version` changed alone (the guard would then judge the lock against another SDK)
//   - `Analyze` no longer in `requiredSuccessJobs` (scripts/safe_pr_merge_lib.dart, read by IMPORT, not by
//     regex), which would turn a red guard into advice
//
// The reader is hand-written (`yaml` is only a transitive package, and declaring it would change the very
// lock this guard protects), so it FAILS CLOSED: a line of the jobs section or of the guarded job that it
// cannot interpret (a flow-style step, a step spelled `-  name:`, an anchor, a merge key, an odd indent) is
// itself a problem (`[unparsed]`, `[unparsed-jobs]`), never text silently merged into its neighbour.
// Every tolerance it grants (comments, quotes, `key :` spacing) has a mutant or a control below that goes
// red when the tolerance is removed (round 3 and the B-pass measured eleven that did not).
//
// The behavioural half is NOT in this file: that `pub get` rewrites a drifted lock and `git diff` then
// fails is the SDK's and git's behaviour. It is measured on the pinned SDK and on a real runner
// (docs/plans/2026-11-22-oi520-enforce-lockfile.md, F3, F11 and F15). What this file adds is that the repo's
// own workflow keeps the guard in the one shape in which that behaviour matters.
//
// Each mutant names the guard behaviour it kills and the problem token it must produce, so a mutant that
// dies for an unrelated reason fails here (rule 21). Mutants are applied to the REAL files in memory and
// every case first asserts the mutation APPLIED, so a stale anchor cannot pass as "killed". The pin
// (`flutter-version`) and the checkout line are read from the real workflow, so a legitimate Flutter bump
// does not turn the mutants vacuous.

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/safe_pr_merge_lib.dart' show requiredSuccessJobs;

const _resolveCommand = 'flutter pub get';
const _verifyCommand = 'git ls-files --error-unmatch -- pubspec.lock && git diff --exit-code -- pubspec.lock';
const _jobId = 'analyze';
const _checkName = 'Analyze';
const _allowedJobKeys = {'name', 'runs-on', 'timeout-minutes', 'steps'};
const _allowedActionsBeforeResolve = ['actions/checkout@', 'subosito/flutter-action@'];
const _allowedWithKeys = <String, Set<String>>{
  'actions/checkout@': <String>{},
  'subosito/flutter-action@': {'flutter-version', 'channel', 'cache'},
};
const _allowedPreStepKeys = {'name', 'uses', 'with'};

final _jobIdLine = RegExp(r'''^  ["']?([A-Za-z0-9_-]+)["']?\s*:\s*(#.*)?$''');
final _jobKeyLine = RegExp(r'''^    ["']?([A-Za-z0-9_-]+)["']?\s*:\s*(.*)$''');
final _stepItemLine = RegExp(r'''^      - ["']?([A-Za-z0-9_-]+)["']?\s*:\s*(.*)$''');
final _stepKeyLine = RegExp(r'''^        ["']?([A-Za-z0-9_-]+)["']?\s*:\s*(.*)$''');

/// Full-line YAML comments removed (a `#` inside a `run:` body or a value survives).
String _strip(String s) =>
    s.replaceAll('\r\n', '\n').split('\n').where((l) => !RegExp(r'^\s*#').hasMatch(l)).join('\n');

/// A scalar as the YAML reader would see it: a trailing ` # comment` and one pair of surrounding quotes removed.
String _clean(String v) {
  var s = v.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
  if (s.length >= 2 && (s.startsWith('"') && s.endsWith('"') || s.startsWith("'") && s.endsWith("'"))) {
    s = s.substring(1, s.length - 1);
  }
  return s;
}

/// The line range [start, end) of a job block: from `  <id>:` to the next sibling job; null when absent.
/// A trailing comment, a quoted id and whitespace before the colon are all still the same job line.
(int, int)? _jobRange(List<String> lines, String id) {
  final start =
      lines.indexWhere((l) => RegExp('^  ["\']?${RegExp.escape(id)}["\']?\\s*:\\s*(#.*)?\$').hasMatch(l));
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'''^  ["']?[A-Za-z0-9_-]+["']?\s*:''').hasMatch(lines[i])) {
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
    final m = _jobIdLine.firstMatch(l);
    if (m != null) ids.add(m.group(1)!);
  }
  return ids;
}

/// FAIL CLOSED, jobs section: every line of the `jobs:` section at one or two spaces of indent must be a
/// canonical job id line; anything else (a flow-style job `x: {...}`, an odd indent) is a job this reader would
/// not see. A `jobs:` section with no two-space id at all (a four-space file) is also unreadable.
List<String> _unparsedJobsSection(String src) {
  final lines = src.split('\n');
  final at = lines.indexWhere((l) => RegExp(r'^jobs:\s*$').hasMatch(l));
  if (at < 0) return ['no `jobs:` section at column 0'];
  final bad = <String>[];
  var ids = 0;
  for (var i = at + 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    if (RegExp(r'^\S').hasMatch(l)) break;
    if (!RegExp(r'^ {1,2}\S').hasMatch(l)) continue;
    if (_jobIdLine.hasMatch(l)) {
      ids++;
    } else {
      bad.add('line ${i + 1}: `${l.trim()}`');
    }
  }
  if (ids == 0 && bad.isEmpty) bad.add('no job id at two-space indent under `jobs:`');
  return bad;
}

/// FAIL CLOSED, guarded job: every line of the job must be a shape the reader understands at its indent:
/// four spaces a job key, six a `- key:` step item, eight a step key, ten or more content (a `with:` value,
/// a block scalar). A flow-style step, `-  name:`, a bare `-`, an anchor, `<<:`, a tab or an odd indent
/// would otherwise be merged silently into the previous step or key.
List<String> _unparsedJobBody(String job) {
  final bad = <String>[];
  final lines = job.split('\n');
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    final indent = l.length - l.trimLeft().length;
    final ok = switch (indent) {
      4 => _jobKeyLine.hasMatch(l),
      6 => _stepItemLine.hasMatch(l),
      8 => _stepKeyLine.hasMatch(l),
      >= 10 => true,
      _ => false,
    };
    if (!ok) bad.add('line ${i + 1} of the job: `${l.trim()}`');
  }
  return bad;
}

/// EVERY key of the job itself (exactly four-space indent), wherever it is written, including after `steps:`
/// (a step's own keys sit at six or more spaces, so a four-space line is always a job key), as key -> value.
/// `key : value` and a quoted key are still that key.
Map<String, String> _jobKeys(String job) {
  final keys = <String, String>{};
  for (final l in job.split('\n').skip(1)) {
    final m = _jobKeyLine.firstMatch(l);
    if (m != null) keys[m.group(1)!] = _clean(m.group(2)!);
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
    final dash = _stepItemLine.firstMatch(l);
    final next = _stepKeyLine.firstMatch(l);
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

String? _flutterVersionOf(Map<String, String> step) =>
    RegExp(r'flutter-version:\s*(\S+)').firstMatch(step['with'] ?? '')?.group(1);

/// The keys named in a step's `with:` text (one `key: value` per line, indentation already trimmed).
Set<String> _withKeys(Map<String, String> step) => {
      for (final l in (step['with'] ?? '').split('\n'))
        if (RegExp(r'''^["']?([A-Za-z0-9_-]+)["']?\s*:''').firstMatch(l) case final m?) m.group(1)!
    };

/// A name value this reader cannot read as text (a block or folded scalar, an anchor, an alias, a flow
/// collection, an empty value) is assumed to MIGHT be the check name: fail closed, never open.
bool _unreadableName(String v) => v.isEmpty || RegExp(r'^[>|&*{\[!?@%`]').hasMatch(v);

/// Does the job with this id and these keys produce a check-run named [_checkName]? Its `name:` when it has
/// one, else its id (GitHub's default; compared case-insensitively to stay on the safe side).
bool _carriesCheckName(String id, Map<String, String> keys) {
  if (!keys.containsKey('name')) return id.toLowerCase() == _checkName.toLowerCase();
  return keys['name'] == _checkName || _unreadableName(keys['name']!);
}

/// What is wrong with the OTHER files of `.github/workflows/` (name -> text): a job that carries the check
/// name, or job lines this reader cannot interpret. The merge wrapper judges the newest check-run of a NAME
/// across the whole PR, so a twin in another file could mask or replace the guard.
List<String> _otherWorkflowProblems(Map<String, String> others) {
  final out = <String>[];
  for (final e in others.entries) {
    final src = _strip(e.value);
    final unparsed = _unparsedJobsSection(src);
    if (unparsed.isNotEmpty) {
      out.add('${e.key} has job lines this reader cannot interpret (${unparsed.join('; ')})');
      continue;
    }
    final twins = [
      for (final id in _jobIds(src))
        if (_carriesCheckName(id, _jobKeys(_job(src, id)!))) id
    ];
    if (twins.isNotEmpty) out.add('${e.key} defines ${twins.join(', ')} with the check name `$_checkName`');
  }
  return out;
}

/// Everything wrong with the lockfile guard; empty means the guard is intact. Every message starts with
/// a stable `[token]` that the mutants below assert on. [requiredJobs] is `requiredSuccessJobs` of the merge
/// wrapper; [otherWorkflows] holds every OTHER file of `.github/workflows/` (name -> text).
List<String> lockfileGuardProblems(String workflow, List<String> requiredJobs,
    {Map<String, String> otherWorkflows = const {}}) {
  final problems = <String>[];
  final others = _otherWorkflowProblems(otherWorkflows);
  if (others.isNotEmpty) {
    problems.add('[other-workflow] ${others.join('; ')}: the wrapper judges the newest check-run of a NAME, '
        'so a second job of that name could mask the guard');
  }
  final src = _strip(workflow);
  final unparsedJobs = _unparsedJobsSection(src);
  if (unparsedJobs.isNotEmpty) {
    problems.add('[unparsed-jobs] test.yml has job lines this reader cannot interpret, so a job could hide '
        'from it: ${unparsedJobs.join('; ')}');
  }
  final job = _job(src, _jobId);
  if (job == null) {
    problems.add('[job-missing] no job `$_jobId` in test.yml');
    return problems;
  }
  final unparsedBody = _unparsedJobBody(job);
  if (unparsedBody.isNotEmpty) {
    problems.add('[unparsed] the `$_jobId` job has lines this reader cannot interpret, so a step or key could '
        'hide from it (write each step as `      - key: value` and each key as `key: value`): '
        '${unparsedBody.join('; ')}');
  }

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
      if (_carriesCheckName(id, _jobKeys(_job(src, id)!))) id
  ];
  if (sameName.length != 1) {
    problems.add('[job-name-unique] exactly one job may carry the check name `$_checkName` (by `name:`, or by its '
        'id when it has no `name:`), found ${sameName.length} (${sameName.join(', ')}): the wrapper judges the '
        'newest check-run of a NAME');
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
    final seenActions = <String>{};
    for (var j = 0; j < i; j++) {
      final uses = steps[j]['uses'];
      final action = uses == null
          ? null
          : _allowedActionsBeforeResolve.where((a) => uses.startsWith(a)).cast<String?>().firstOrNull;
      if (uses == null || steps[j].containsKey('run') || action == null) {
        problems.add('[pre-step] step ${j + 1} runs before the resolving step and is not an allowed action '
            '(${_allowedActionsBeforeResolve.join(', ')}): it may already have re-resolved the lock, which '
            'makes the verify step compare a lock that was just rewritten');
        continue;
      }
      if (!seenActions.add(action)) {
        problems.add('[pre-step] step ${j + 1} repeats `$action`: a second checkout or setup could change the '
            'ref or the SDK the lock is judged against');
      }
      final extraStepKeys = steps[j].keys.toSet().difference(_allowedPreStepKeys);
      if (extraStepKeys.isNotEmpty) {
        problems.add('[pre-step] step ${j + 1} (`$uses`) carries ${extraStepKeys.map((k) => '`$k:`').join(', ')}');
      }
      final extraWith = _withKeys(steps[j]).difference(_allowedWithKeys[action]!);
      if (extraWith.isNotEmpty) {
        problems.add('[pre-step] step ${j + 1} (`$uses`) carries with: ${extraWith.join(', ')}; only '
            '${_allowedWithKeys[action]!.isEmpty ? 'no keys' : _allowedWithKeys[action]!.join(', ')} are allowed '
            '(a `ref:` would make the job judge another ref\'s lock)');
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

  if (!requiredJobs.contains(_checkName)) {
    problems.add('[required-job] `$_checkName` is not in requiredSuccessJobs (scripts/safe_pr_merge_lib.dart): '
        'a red guard would no longer stop safe_pr_merge.sh');
  }
  return problems;
}

void main() {
  final workflow = File('.github/workflows/test.yml').readAsStringSync().replaceAll('\r\n', '\n');
  // Every OTHER workflow file (the merge wrapper judges a check NAME across the whole PR).
  final otherWorkflows = <String, String>{
    for (final f in Directory('.github/workflows').listSync().whereType<File>())
      if (RegExp(r'\.ya?ml$').hasMatch(f.path) && f.path.replaceAll('\\', '/').split('/').last != 'test.yml')
        f.path.replaceAll('\\', '/').split('/').last: f.readAsStringSync().replaceAll('\r\n', '\n'),
  };

  // Read from the real workflow so a legitimate all-jobs Flutter bump or a checkout version bump does not
  // turn the mutants below vacuous (the B-pass measured the hard-coded pin doing exactly that).
  final realJob = _job(workflow, _jobId)!;
  final pin = RegExp(r"flutter-version:\s*'([^']+)'").firstMatch(realJob)!.group(1)!;
  final checkoutLine = RegExp(r'      - uses: actions/checkout@\S+\n').firstMatch(realJob)!.group(0)!;

  const installBlock = '      - name: Install dependencies\n        run: $_resolveCommand\n';
  const verifyBlock =
      '      - name: Verify pubspec.lock is unchanged after pub get (OI-520)\n        run: $_verifyCommand\n';
  const analyzeBlock = '      - name: Flutter analyze (zero warnings allowed)\n        run: flutter analyze --no-fatal-infos\n';

  /// Applies [change] to the `analyze` job's lines only, asserting the anchor [from] is inside it.
  String inJob(String src, String from, String to) {
    final lines = src.split('\n');
    final r = _jobRange(lines, _jobId)!;
    final block = lines.sublist(r.$1, r.$2).join('\n');
    expect(block, contains(from), reason: 'the anchor is not in the analyze job: the mutant would be vacuous');
    return [...lines.sublist(0, r.$1), block.replaceFirst(from, to), ...lines.sublist(r.$2)].join('\n');
  }

  /// Inserts [block] as lines directly after the analyze job (before its next sibling job).
  String afterJob(String src, String block) {
    final lines = src.split('\n');
    final r = _jobRange(lines, _jobId)!;
    return [...lines.sublist(0, r.$2), ...block.split('\n'), ...lines.sublist(r.$2)].join('\n');
  }

  test('the real workflow keeps the guard intact', () {
    expect(lockfileGuardProblems(workflow, requiredSuccessJobs, otherWorkflows: otherWorkflows), isEmpty);
  });

  test('the real files contain the anchors the mutants below rely on', () {
    final job = _job(workflow, _jobId)!;
    expect(job, contains('$installBlock\n$verifyBlock\n$analyzeBlock'),
        reason: 'install, verify and analyze must be consecutive steps, each a name + run pair');
    expect(job, contains('    name: Analyze\n    runs-on: ubuntu-latest\n'));
    expect(job, contains(checkoutLine));
    expect(job, contains("          flutter-version: '$pin'\n"));
    expect(job, contains('          cache: true\n'));
    expect(requiredSuccessJobs, contains('Analyze'));
  });

  // name -> (token the guard must report, how the workflow is mutated, how requiredSuccessJobs is mutated)
  final mutants = <String, ({String token, String Function(String)? wf, List<String> Function(List<String>)? req})>{
    'verify step removed': (token: 'verify-step', wf: (String s) => inJob(s, '$verifyBlock\n', ''), req: null),
    'verify failure swallowed with || true': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: $_verifyCommand || true'),
      req: null,
    ),
    'verify checks another file': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: git diff --exit-code -- pubspec.yaml'),
      req: null,
    ),
    // The mirror of "the lock differs": a PR that DELETES pubspec.lock. `pub get` regenerates it untracked and
    // `git diff` says nothing about an untracked file (measured: exit 0), so the diff alone passes it.
    'verify is the bare diff, so a deleted lock passes': (
      token: 'verify-step',
      wf: (String s) => inJob(s, 'run: $_verifyCommand', 'run: git diff --exit-code -- pubspec.lock'),
      req: null,
    ),
    'tracked check joined with ; so only the last command decides': (
      token: 'verify-step',
      wf: (String s) => inJob(
        s,
        'run: $_verifyCommand',
        'run: git ls-files --error-unmatch -- pubspec.lock; git diff --exit-code -- pubspec.lock',
      ),
      req: null,
    ),
    'verify step made conditional with if:': (
      token: 'verify-step',
      wf: (String s) => inJob(s, verifyBlock, "$verifyBlock        if: github.event_name == 'push'\n"),
      req: null,
    ),
    'verify failure made green with continue-on-error': (
      token: 'verify-step',
      wf: (String s) => inJob(s, verifyBlock, '$verifyBlock        continue-on-error: true\n'),
      req: null,
    ),
    'verify step moved after the analyze step': (
      token: 'verify-step',
      wf: (String s) => inJob(s, '$verifyBlock\n$analyzeBlock', '$analyzeBlock\n$verifyBlock'),
      req: null,
    ),
    'resolving command changed (--offline)': (
      token: 'resolve-command',
      wf: (String s) => inJob(s, 'run: $_resolveCommand\n', 'run: $_resolveCommand --offline\n'),
      req: null,
    ),
    'a second resolving step added': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - name: Again\n        run: flutter pub get\n'),
      req: null,
    ),
    // Tolerances of the step reader, each pinned by a second resolving step that is only visible WITH it.
    'a second resolving step whose run key is quoted after the dash': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - "run": flutter pub get\n'),
      req: null,
    ),
    'a second resolving step with a space before the colon after the dash': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - run : flutter pub get\n'),
      req: null,
    ),
    'a second resolving step whose run key is quoted below the dash': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - name: Again\n        "run": flutter pub get\n'),
      req: null,
    ),
    'a second resolving step with a space before the colon below the dash': (
      token: 'resolve-count',
      wf: (String s) => inJob(s, installBlock, '$installBlock\n      - name: Again\n        run : flutter pub get\n'),
      req: null,
    ),
    'env: on the resolving step': (
      token: 'resolve-extra-keys',
      wf: (String s) => inJob(
          s,
          installBlock,
          '      - name: Install dependencies\n        env:\n          PUB_HOSTED_URL: https://pub.example.invalid\n'
              '        run: $_resolveCommand\n'),
      req: null,
    ),
    'a run step before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '      - name: Prepare\n        run: echo prepare\n\n$installBlock'),
      req: null,
    ),
    'an unknown action before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '      - uses: some-org/resolve-action@v1\n\n$installBlock'),
      req: null,
    ),
    // R3-2: the allowed actions are pinned too (a `ref:` makes the job judge another ref's lock).
    'checkout given a with: ref': (
      token: 'pre-step',
      wf: (String s) => inJob(s, checkoutLine, '$checkoutLine        with:\n          ref: main\n'),
      req: null,
    ),
    'a second checkout of another ref before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '$checkoutLine        with:\n          ref: main\n\n$installBlock'),
      req: null,
    ),
    'env: on the checkout step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, checkoutLine, '$checkoutLine        env:\n          GIT_CONFIG_COUNT: "1"\n'),
      req: null,
    ),
    'an extra with: key on the flutter setup action': (
      token: 'pre-step',
      wf: (String s) => inJob(s, '          cache: true\n', '          cache: true\n          flutter-root: /tmp/other-sdk\n'),
      req: null,
    ),
    // Round 3 and the B-pass (P2): spellings the reader could not see used to be merged into the previous
    // step. It now fails closed.
    'a flow-style step before the resolving step': (
      token: 'unparsed',
      wf: (String s) => inJob(
          s, installBlock, "      - {name: Neuter, run: 'git update-index --assume-unchanged pubspec.lock'}\n\n$installBlock"),
      req: null,
    ),
    'a step written with two spaces after the dash': (
      token: 'unparsed',
      wf: (String s) => inJob(
          s,
          installBlock,
          '      -  name: Neuter\n        run: git update-index --assume-unchanged pubspec.lock\n\n$installBlock'),
      req: null,
    ),
    'a step introduced by an anchor': (
      token: 'unparsed',
      wf: (String s) => inJob(s, installBlock, '      - &neuter\n        name: Neuter\n        run: echo x\n\n$installBlock'),
      req: null,
    ),
    'a bare dash followed by the step keys': (
      token: 'unparsed',
      wf: (String s) => inJob(s, installBlock, '      -\n        name: Neuter\n        run: echo x\n\n$installBlock'),
      req: null,
    ),
    'a merge key inside a step': (
      token: 'unparsed',
      wf: (String s) => inJob(s, installBlock,
          '      - name: Install dependencies\n        <<: *step-defaults\n        run: $_resolveCommand\n'),
      req: null,
    ),
    'a step indented by an odd number of spaces': (
      token: 'unparsed',
      wf: (String s) => inJob(s, installBlock, '     - name: Odd\n       run: echo x\n\n$installBlock'),
      req: null,
    ),
    'a tab-indented step': (
      token: 'unparsed',
      wf: (String s) => inJob(s, installBlock, '\t- name: Tabbed\n\t  run: echo x\n\n$installBlock'),
      req: null,
    ),
    // A PLAIN repeat (no with: key, no env:), so only the "each allowed action once" rule can flag it.
    'a plain second checkout before the resolving step': (
      token: 'pre-step',
      wf: (String s) => inJob(s, installBlock, '$checkoutLine\n$installBlock'),
      req: null,
    ),
    'a merge key at job level': (
      token: 'unparsed',
      wf: (String s) => inJob(s, '    runs-on: ubuntu-latest\n', '    runs-on: ubuntu-latest\n    <<: *defaults\n'),
      req: null,
    ),
    'a flow-style job mapping in the same file': (
      token: 'unparsed-jobs',
      wf: (String s) => '$s\n  flowy: {name: Analyze, runs-on: ubuntu-latest}\n',
      req: null,
    ),
    'job made non-blocking with continue-on-error': (
      token: 'job-keys',
      wf: (String s) => inJob(s, '    runs-on: ubuntu-latest\n', '    continue-on-error: true\n    runs-on: ubuntu-latest\n'),
      req: null,
    ),
    'job made conditional with if:': (
      token: 'job-keys',
      wf: (String s) =>
          inJob(s, '    runs-on: ubuntu-latest\n', "    if: github.event_name == 'push'\n    runs-on: ubuntu-latest\n"),
      req: null,
    ),
    'job given env:': (
      token: 'job-keys',
      wf: (String s) => inJob(
          s, '    runs-on: ubuntu-latest\n', '    runs-on: ubuntu-latest\n    env:\n      PUB_HOSTED_URL: https://pub.example.invalid\n'),
      req: null,
    ),
    'job given defaults:': (
      token: 'job-keys',
      wf: (String s) => inJob(s, '    runs-on: ubuntu-latest\n',
          '    runs-on: ubuntu-latest\n    defaults:\n      run:\n        working-directory: ./scripts\n'),
      req: null,
    ),
    // Round 2 (R2-1): job keys may be written ANYWHERE in the job block, not only before `steps:`.
    'job-level continue-on-error written AFTER steps:': (
      token: 'job-keys',
      wf: (String s) => inJob(s, analyzeBlock, '$analyzeBlock    continue-on-error: true\n'),
      req: null,
    ),
    'job-level if: written AFTER steps:': (
      token: 'job-keys',
      wf: (String s) => inJob(s, analyzeBlock, "$analyzeBlock    if: github.event_name == 'push'\n"),
      req: null,
    ),
    'job-level env: written AFTER steps:': (
      token: 'job-keys',
      wf: (String s) =>
          inJob(s, analyzeBlock, '$analyzeBlock    env:\n      PUB_HOSTED_URL: https://pub.example.invalid\n'),
      req: null,
    ),
    'job key written with a space before the colon': (
      token: 'job-keys',
      wf: (String s) =>
          inJob(s, '    runs-on: ubuntu-latest\n', '    continue-on-error : true\n    runs-on: ubuntu-latest\n'),
      req: null,
    ),
    'job key written in quotes': (
      token: 'job-keys',
      wf: (String s) =>
          inJob(s, '    runs-on: ubuntu-latest\n', '    "continue-on-error": true\n    runs-on: ubuntu-latest\n'),
      req: null,
    ),
    'the job id renamed, so the guarded job vanishes': (
      token: 'job-missing',
      wf: (String s) => s.replaceFirst('\n  $_jobId:\n', '\n  analyse:\n'),
      req: null,
    ),
    'job renamed, so the required check name no longer exists': (
      token: 'job-name',
      wf: (String s) => inJob(s, '    name: Analyze\n', '    name: Static analysis\n'),
      req: null,
    ),
    'a second job carries the check name Analyze': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  analyze-twin:\n    name: Analyze\n    runs-on: ubuntu-latest\n',
      req: null,
    ),
    'a second job carries the check name in quotes': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  analyze-twin:\n    name: "Analyze"\n    runs-on: ubuntu-latest\n',
      req: null,
    ),
    'a second job whose id line and name line carry comments': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  analyze-twin:  # sneaky\n    name: Analyze  # twin\n    runs-on: ubuntu-latest\n',
      req: null,
    ),
    'a second job whose id is quoted': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  "analyze-twin":\n    name: Analyze\n    runs-on: ubuntu-latest\n',
      req: null,
    ),
    'a second job whose id has a space before the colon': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  analyze-twin :\n    name: Analyze\n    runs-on: ubuntu-latest\n',
      req: null,
    ),
    'a second job named only by its id, Analyze (no name: key)': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  Analyze:\n    runs-on: ubuntu-latest\n    steps: []\n',
      req: null,
    ),
    'a second job named only by its id, ANALYZE (no name: key)': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  ANALYZE:\n    runs-on: ubuntu-latest\n    steps: []\n',
      req: null,
    ),
    'a second job whose name is a folded scalar': (
      token: 'job-name-unique',
      wf: (String s) => '$s\n  twin:\n    name: >-\n      Analyze\n    runs-on: ubuntu-latest\n    steps: []\n',
      req: null,
    ),
    "this job's flutter-version changed alone": (
      token: 'flutter-version',
      wf: (String s) => inJob(s, "flutter-version: '$pin'", "flutter-version: '99.99.99'"),
      req: null,
    ),
    "this job's flutter-version removed": (
      token: 'flutter-version',
      wf: (String s) => inJob(s, "          flutter-version: '$pin'\n", ''),
      req: null,
    ),
    'Analyze dropped from requiredSuccessJobs': (
      token: 'required-job',
      wf: null,
      req: (List<String> l) => l.where((x) => x != 'Analyze').toList(),
    ),
  };

  for (final entry in mutants.entries) {
    test('kills the mutant: ${entry.key}', () {
      final wf = entry.value.wf?.call(workflow) ?? workflow;
      final req = entry.value.req?.call(requiredSuccessJobs) ?? requiredSuccessJobs;
      expect(wf != workflow || req.length != requiredSuccessJobs.length, isTrue,
          reason: 'the mutation did not apply: the anchor is stale');
      final problems = lockfileGuardProblems(wf, req);
      expect(problems.any((p) => p.startsWith('[${entry.value.token}]')), isTrue,
          reason: 'the guard must report [${entry.value.token}] for "${entry.key}", got: $problems');
    });
  }

  // A job of the same check NAME in ANOTHER workflow file (the wrapper judges the newest check-run of a name).
  final otherMutants = <String, String>{
    'another workflow file defines a job named Analyze':
        'name: Evil\njobs:\n  x:\n    name: Analyze\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file quotes the check name and comments the line':
        'jobs:\n  x:\n    name: "Analyze"  # twin\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file names its job Analyze only by the id':
        'jobs:\n  Analyze:\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file uses a flow-style job mapping':
        'jobs:\n  x: {name: Analyze, runs-on: ubuntu-latest, steps: []}\n',
    'another workflow file uses a folded scalar for the name':
        'jobs:\n  x:\n    name: >-\n      Analyze\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file quotes the name key': 'jobs:\n  x:\n    "name": Analyze\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file puts a space before the name colon':
        'jobs:\n  x:\n    name : Analyze\n    runs-on: ubuntu-latest\n    steps: []\n',
    'another workflow file indents its job ids by four spaces':
        'jobs:\n    x:\n        name: Analyze\n        runs-on: ubuntu-latest\n',
  };
  for (final entry in otherMutants.entries) {
    test('kills the mutant: ${entry.key}', () {
      final problems = lockfileGuardProblems(workflow, requiredSuccessJobs,
          otherWorkflows: {...otherWorkflows, 'evil.yml': entry.value});
      expect(problems.any((p) => p.startsWith('[other-workflow]')), isTrue,
          reason: 'the guard must report [other-workflow] for "${entry.key}", got: $problems');
    });
  }

  // Controls: shapes that are LEGITIMATE must stay green. Each pins a tolerance of the reader that no mutant
  // above can reach (removing the tolerance makes the control red), and guards against over-matching.
  final controls = <String, String Function(String)>{
    'a quoted-id sibling job right after the guarded job is not part of it': (String s) => afterJob(
        s, '  "lint-sibling":\n    name: Lint\n    if: github.event_name == \'push\'\n    runs-on: ubuntu-latest\n    steps: []\n'),
    'a sibling job with a space before the colon right after the guarded job is not part of it': (String s) =>
        afterJob(s, '  lint-sibling :\n    name: Lint\n    if: github.event_name == \'push\'\n    runs-on: ubuntu-latest\n    steps: []\n'),
    'a top-level mapping after jobs: is not part of jobs': (String s) =>
        '$s\nextra:\n  analyze-like:\n    name: Analyze\n    runs-on: ubuntu-latest\n',
    // Ordinary (non-job-looking) keys: only the column-0 stop of `_unparsedJobsSection` keeps them out of the jobs section.
    'a top-level mapping with ordinary keys after jobs: is not part of jobs': (String s) => '$s\nextra:\n  key: value\n',
    'a comment inside with: that quotes another flutter-version is ignored': (String s) =>
        inJob(s, "          flutter-version: '$pin'\n", "          # flutter-version: 9\n          flutter-version: '$pin'\n"),
    'a job with a different id and a different explicit name is not a twin': (String s) =>
        '$s\n  lint-extra:\n    name: Analyze data\n    runs-on: ubuntu-latest\n    steps: []\n',
  };
  for (final entry in controls.entries) {
    test('stays green: ${entry.key}', () {
      final wf = entry.value(workflow);
      expect(wf, isNot(equals(workflow)), reason: 'the control did not change the workflow');
      expect(lockfileGuardProblems(wf, requiredSuccessJobs, otherWorkflows: otherWorkflows), isEmpty);
    });
  }

  test('another workflow file with a merely similar job name is not a false positive', () {
    final problems = lockfileGuardProblems(workflow, requiredSuccessJobs, otherWorkflows: {
      ...otherWorkflows,
      'ok.yml': 'jobs:\n  x:\n    name: Analyze data\n    runs-on: ubuntu-latest\n    steps: []\n',
    });
    expect(problems, isEmpty);
  });

  test('a comment that quotes the command does not count as the step', () {
    // The explanatory comment in test.yml quotes the commands; only real steps may be judged.
    final withoutSteps = inJob(workflow, '$installBlock\n$verifyBlock\n', '');
    expect(withoutSteps, isNot(equals(workflow)));
    expect(lockfileGuardProblems(withoutSteps, requiredSuccessJobs).any((p) => p.startsWith('[resolve-count]')), isTrue,
        reason: 'a workflow with both steps removed but the comment kept must fail');
  });
}
