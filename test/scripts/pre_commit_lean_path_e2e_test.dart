// test/scripts/pre_commit_lean_path_e2e_test.dart
//
// END-TO-END: runs the REAL scripts/pre-commit.sh with a stub `flutter` on PATH
// and asserts that the DEFAULT (lean) path invokes no flutter command at all,
// while each escape hatch invokes exactly the right pair.
//
// WHY THIS EXISTS — it closes a hole the B-pass found in its source-grep
// sibling. `test/contracts/hook_gate_placement_test.dart` matches
// `flutter\s+(analyze|test|...)` over the script text. That catches the
// realistic regressions (restoring the call in place, adding one above the
// chain, double-spacing it) but it is still a SOURCE grep, and a source grep
// cannot see through indirection. Verified live: putting
//
//     _sub="ana""lyze"
//     flutter "$_sub" --no-fatal-infos
//
// in the else branch runs analyze on every commit and leaves that suite fully
// GREEN. No regex fixes that class — only observing the actual invocation does.
// (feedback_source_grep_false_confidence: a source-grep certifies the text, not
// the behaviour.) The two files are complements: the grep pins WHERE the calls
// are written, this pins WHAT actually runs.
//
// HOW IT STAYS FAST. Running the whole hook costs ~22s even with every gate
// stubbed, because the loop still spawns ~71 subprocesses. So the stub `dart`
// here exits 1, which aborts the script at its FIRST dart invocation — Gate 40
// / the index regens — all of which sit strictly BELOW the hatch chain. The
// chain has therefore already run when the script dies. 2s per scenario.
// **The non-zero exit is EXPECTED and asserted**, so a future reader does not
// "fix" it into a hidden pass.
//
// WHY AN EMPTY LOG IS EVIDENCE HERE AND NOT A VACUOUS PASS. On its own, an
// empty flutter log is ambiguous: it could equally mean the stub never got onto
// PATH, or the script died before reaching the chain. The two hatch scenarios
// in this same file run the SAME harness and DO produce log lines, which is
// what makes the default path's empty log meaningful. Do not delete them as
// redundant — they are the premise guard for the assertion that matters.
//
// PATH FORM: the injected entry must be POSIX (`/c/...`). Git Bash silently
// ignores a Windows-form (`C:/...`) PATH entry, the real flutter would run, and
// the test would sit there for minutes proving nothing. Same trap documented in
// pre_push_analyze_always_e2e_test.dart.
//
// ENV SCRUBBING: run inside `pre-commit`, a test spawning a git-touching child
// inherits GIT_DIR / GIT_WORK_TREE, which override both `workingDirectory:` and
// `-C <path>` (feedback_mistake_git_hook_env_leak). pre-commit.sh opens with
// `git rev-parse --show-toplevel` and cd's there, so a leak would point it at
// whatever repo the surrounding hook was driving. Filtered environment +
// includeParentEnvironment: false, matching the gate e2e family (enforced by
// test/contracts/gate_e2e_env_hermetic_test.dart).

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parent environment minus git-, CI-range- and hatch-related keys, so neither a
/// surrounding git hook nor an ambient hatch var can steer the child.
///
///   GIT_*       — load-bearing: pre-commit.sh resolves its own repo root via
///                 `git rev-parse --show-toplevel`, and GIT_DIR overrides both
///                 `workingDirectory:` and `-C <path>`.
///   GITHUB_*    — the family shares one hermetic contract so a future reader of
///                 CI env cannot silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  // Never inherit a real hatch: it would silently invert every expectation.
  env.remove('PRE_COMMIT_FULL');
  env.remove('PRE_COMMIT_LEGACY');
  return env;
}

/// `C:\a\b` / `C:/a/b` -> `/c/a/b`. Git Bash ignores Windows-form PATH entries.
String _toPosixPath(String p) {
  var s = p.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/').firstMatch(s);
  if (m != null) s = '/${m.group(1)!.toLowerCase()}/${s.substring(3)}';
  return s;
}

void main() {
  late Directory tmp;
  late File log;
  late String stubDirPosix;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('precommit_lean_');
    final sep = Platform.pathSeparator;

    // Records the subcommand line, one per invocation.
    File('${tmp.path}${sep}flutter').writeAsStringSync(
      '#!/bin/sh\necho "\$*" >> "\$STUB_LOG"\nexit 0\n',
    );
    // Exits 1 so the hook aborts at its first gate — which is BELOW the hatch
    // chain. This is the whole speed trick; see the header.
    File('${tmp.path}${sep}dart').writeAsStringSync('#!/bin/sh\nexit 1\n');
    Process.runSync('chmod', ['+x', '${tmp.path}${sep}flutter']);
    Process.runSync('chmod', ['+x', '${tmp.path}${sep}dart']);

    log = File('${tmp.path}${sep}flutter_calls.log')..writeAsStringSync('');
    stubDirPosix = _toPosixPath(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs the real hook with the stubs first on PATH. PATH is assembled INSIDE
  /// sh so the POSIX form is what bash actually sees.
  ProcessResult runHook({Map<String, String> extra = const {}}) {
    final env = _cleanEnv()..['STUB_LOG'] = _toPosixPath(log.path);
    env.addAll(extra);
    return Process.runSync(
      'sh',
      [
        '-c',
        'PATH="$stubDirPosix:\$PATH"; export PATH; exec sh scripts/pre-commit.sh',
      ],
      workingDirectory: Directory.current.path,
      environment: env,
      includeParentEnvironment: false,
    );
  }

  List<String> callsMade() => log
      .readAsStringSync()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  test('PRE_COMMIT_LEGACY=1 really invokes analyze + the contracts subset', () {
    // Runs FIRST on purpose: it is the premise guard for the empty-log
    // assertion below. If the stub could not intercept, this fails loudly here
    // instead of silently making the default-path test vacuous.
    final r = runHook(extra: {'PRE_COMMIT_LEGACY': '1'});
    expect(callsMade(), [
      'analyze --no-fatal-infos',
      'test test/contracts/',
    ], reason: 'stub interception is the premise of every assertion in this '
        'file. exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}');
  });

  test('PRE_COMMIT_FULL=1 really invokes analyze + the FULL suite', () {
    runHook(extra: {'PRE_COMMIT_FULL': '1'});
    expect(callsMade(), ['analyze --no-fatal-infos', 'test'],
        reason: 'PRE_COMMIT_FULL must run the whole suite, not the subset');
  });

  test('both hatches set: FULL wins (asking for more never yields less)', () {
    runHook(extra: {'PRE_COMMIT_FULL': '1', 'PRE_COMMIT_LEGACY': '1'});
    expect(callsMade(), ['analyze --no-fatal-infos', 'test'],
        reason: 'the chain must test PRE_COMMIT_FULL first; the original order '
            'handed back the weaker contracts-subset run');
  });

  test('DEFAULT path invokes NO flutter command at all', () {
    // THE ASSERTION THIS FILE EXISTS FOR. Unlike the source-grep sibling this
    // observes actual execution, so it holds against ANY spelling — a helper
    // function, a variable-built subcommand, an alias, `eval`. That indirection
    // class is exactly what defeated the grep (see header).
    final r = runHook();

    // The stub `dart` fails the first gate by design, so a non-zero exit is
    // correct here and is asserted so nobody "repairs" it into a hidden pass.
    expect(r.exitCode, isNot(0),
        reason: 'the stub dart exits 1 to abort the run just past the hatch '
            'chain; a zero exit means the harness no longer works the way this '
            'test assumes and its empty-log assertion may be vacuous');

    expect(callsMade(), isEmpty,
        reason: 'the DEFAULT pre-commit path must invoke NO flutter command — '
            'that is the entire cost saving. Anything here means every commit '
            'is paying for analyze and/or the test suite again. Got: '
            '${callsMade()}');
  });
}
