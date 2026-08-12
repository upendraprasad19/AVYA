// test/scripts/pre_push_analyze_always_e2e_test.dart
//
// END-TO-END: runs the REAL scripts/pre-push.sh with a stub `flutter` on PATH
// and asserts that `analyze` is the FIRST thing it invokes — before any tier
// check and before every early exit.
//
// WHY this exists alongside test/contracts/hook_gate_placement_test.dart: that
// file asserts SOURCE ORDER by character index. Source order is necessary but
// not sufficient — it cannot show that the line is actually reached (it could
// sit inside a branch that never runs, or after a `return` in a sourced
// helper). Only executing the script and observing which flutter subcommand
// lands first shows that. Same lesson as worktree_config_integrity_e2e_test's
// header: unit-testing a helper certifies the helper, not the gate.
//
// HOW THE STUB WORKS, and the platform trap it cost: pre-push.sh calls flutter
// through a wrapper that execs `env -u GIT_DIR ... flutter "$@"`, so PATH
// interception has to survive `env`. It does — but ONLY if the injected PATH
// entry is in POSIX form. A Windows-style `C:/...` entry is silently ignored by
// Git Bash's PATH lookup, the real flutter runs instead, and the test would sit
// there for 3.5 minutes running a real analyze and then assert nothing useful.
// Verified live before this test was written; `_toPosixPath` is that fix.
//
// WHAT THIS PROVES AND WHAT IT DOES NOT. It proves analyze executes, and
// executes first, on the two paths exercised below. It does NOT independently
// re-derive that the `feature`-tier skip sits after analyze in the file — that
// is the companion test's job, by index. Together they cover the mutation
// (moving analyze below the skip): under PRE_PUSH_FULL the log would start with
// `test`, and on the tiered path a feature-tier range would log nothing at all.
//
// ENV SCRUBBING: run inside `pre-commit`, a test that spawns a git-touching
// child inherits GIT_DIR / GIT_WORK_TREE, which override BOTH `workingDirectory:`
// and `-C <path>` (feedback_mistake_git_hook_env_leak). pre-push.sh opens with
// `git rev-parse --show-toplevel` and then `cd`s there, so a leak would point
// the script at whatever repo the surrounding hook was operating on. Filtered
// environment + includeParentEnvironment: false, matching the rest of the gate
// e2e family (enforced by test/contracts/gate_e2e_env_hermetic_test.dart).

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parent environment minus anything git- or CI-range-related, so a surrounding
/// git hook cannot redirect the child at the real repository.
///
/// Scrubs the same three key families as the rest of the gate-e2e family:
///   GIT_*       — load-bearing here: pre-push.sh resolves its own repo root via
///                 `git rev-parse --show-toplevel`, and GIT_DIR overrides both
///                 `workingDirectory:` and `-C <path>`.
///   GITHUB_*    — this script reads no GITHUB_* var today, but the family
///                 shares one hermetic contract so a future reader cannot
///                 silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  // Never inherit a real override of the very variable one scenario sets.
  env.remove('PRE_PUSH_FULL');
  return env;
}

/// `C:\a\b` / `C:/a/b` -> `/c/a/b`. Git Bash ignores Windows-form PATH entries
/// outright, which is the trap documented in this file's header.
String _toPosixPath(String p) {
  var s = p.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/').firstMatch(s);
  if (m != null) s = '/${m.group(1)!.toLowerCase()}/${s.substring(3)}';
  return s;
}

void main() {
  late Directory tmp;
  late String stubDirPosix;
  late String logPosix;
  late File logFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prepush_analyze_');
    final stub = File('${tmp.path}${Platform.pathSeparator}flutter');
    // Records only the subcommand, one per line: `analyze` or `test`.
    stub.writeAsStringSync(
      '#!/bin/sh\n'
      'echo "\$1" >> "\$FLUTTER_STUB_LOG"\n'
      'exit 0\n',
    );
    Process.runSync('chmod', ['+x', stub.path]);

    logFile = File('${tmp.path}${Platform.pathSeparator}flutter_calls.log');
    logFile.writeAsStringSync('');

    stubDirPosix = _toPosixPath(tmp.path);
    logPosix = _toPosixPath(logFile.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs the real hook with the stub first on PATH. PATH is assembled INSIDE
  /// sh (not via the env map) so the POSIX form is the one bash actually sees.
  ProcessResult runHook({bool prePushFull = false}) {
    final env = _cleanEnv();
    env['FLUTTER_STUB_LOG'] = logPosix;
    if (prePushFull) env['PRE_PUSH_FULL'] = '1';

    return Process.runSync(
      'sh',
      [
        '-c',
        'PATH="$stubDirPosix:\$PATH"; export PATH; '
            'exec sh scripts/pre-push.sh < /dev/null',
      ],
      workingDirectory: Directory.current.path,
      environment: env,
      includeParentEnvironment: false,
    );
  }

  List<String> callsMade() => logFile
      .readAsStringSync()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  test('stub really intercepts (guards the premise of every assertion below)',
      () {
    final r = runHook(prePushFull: true);
    expect(callsMade(), isNotEmpty,
        reason: 'the stub recorded nothing, so either the real flutter ran or '
            'the hook never called it. Every assertion in this file would be '
            'vacuous — fix the interception before trusting a green run. '
            'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}');
  });

  test('PRE_PUSH_FULL=1: analyze runs BEFORE the forced full suite', () {
    final r = runHook(prePushFull: true);
    final calls = callsMade();

    expect(r.exitCode, 0, reason: 'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');
    expect(calls.first, 'analyze',
        reason: 'PRE_PUSH_FULL=1 returns early via run_full_suite. If analyze '
            'sat below that check it would never run at all and the first '
            'recorded call would be `test`. Got: $calls');
    expect(calls, contains('test'),
        reason: 'the forced full suite must still run');
  });

  test('FEATURE-tier push: the suite is skipped and analyze still runs', () {
    // THE DISCRIMINATING CASE, and the one the first version of this file
    // failed to cover. That version ran the hook against the REAL worktree and
    // asserted "analyze is first, whatever the tier". Round-1 review showed
    // that is nearly vacuous here: this branch classifies `platform`, so
    // control reaches the bottom run_full_suite and analyze logged first even
    // WITH the mutation applied. In CI it is worse — `origin/main..HEAD` is
    // typically empty after checkout, so the empty-range fail-safe fires and
    // the feature path is never exercised at all.
    //
    // So build a scratch repo whose pushed range is deterministically
    // feature-tier, exactly as the other test/scripts/*_e2e_test.dart do:
    // a committed `docs/` file vs a synthetic origin/main ref, with `dart`
    // stubbed to return the tier. Now the skip path IS taken, and analyze is
    // the ONLY call that may appear. Mutation → empty log → red.
    final repo = Directory.systemTemp.createTempSync('prepush_feature_');
    try {
      String git(List<String> args) {
        final r = Process.runSync('git', args,
            workingDirectory: repo.path,
            environment: _cleanEnv(),
            includeParentEnvironment: false);
        expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
        return (r.stdout as String).trim();
      }

      git(['init', '--quiet']);
      git(['config', 'user.email', 'test@example.com']);
      git(['config', 'user.name', 'test']);

      File('${repo.path}/seed.txt').writeAsStringSync('seed\n');
      git(['add', '-A']);
      git(['commit', '--quiet', '--no-verify', '-m', 'seed']);
      // Synthetic origin/main: the hook only needs the ref to resolve.
      git(['update-ref', 'refs/remotes/origin/main', 'HEAD']);

      // A docs-only second commit → the range the hook will classify.
      Directory('${repo.path}/docs').createSync();
      File('${repo.path}/docs/note.md').writeAsStringSync('note\n');
      git(['add', '-A']);
      git(['commit', '--quiet', '--no-verify', '-m', 'docs: note']);

      // The hook under test, copied verbatim.
      Directory('${repo.path}/scripts').createSync();
      File('scripts/pre-push.sh')
          .copySync('${repo.path}/scripts/pre-push.sh');

      // Stub `dart` so the tier is FORCED, not inherited from the real repo.
      // Mimics the real helper's output shape, including the `dart run`
      // build-hooks preamble the hook's grep is written to tolerate.
      final stub2 = Directory('${repo.path}/stub')..createSync();
      File('${stub2.path}/flutter').writeAsStringSync(
        '#!/bin/sh\necho "\$1" >> "\$FLUTTER_STUB_LOG"\nexit 0\n',
      );
      File('${stub2.path}/dart').writeAsStringSync(
        '#!/bin/sh\ncat > /dev/null\n'
        'printf "Running build hooks...Blast-radius: feature\\n"\nexit 0\n',
      );
      Process.runSync('chmod', ['+x', '${stub2.path}/flutter']);
      Process.runSync('chmod', ['+x', '${stub2.path}/dart']);

      final log2 = File('${repo.path}/calls.log')..writeAsStringSync('');
      final env = _cleanEnv();
      env['FLUTTER_STUB_LOG'] = _toPosixPath(log2.path);

      final r = Process.runSync(
        'sh',
        [
          '-c',
          'PATH="${_toPosixPath(stub2.path)}:\$PATH"; export PATH; '
              'exec sh scripts/pre-push.sh < /dev/null',
        ],
        workingDirectory: repo.path,
        environment: env,
        includeParentEnvironment: false,
      );

      final calls = log2
          .readAsStringSync()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      expect(r.exitCode, 0,
          reason: 'stdout:\n${r.stdout}\nstderr:\n${r.stderr}');
      expect(r.stdout.toString(), contains('blast-radius=feature'),
          reason: 'the scenario must actually reach the feature-tier skip, '
              'otherwise this test is not exercising the case it claims. '
              'stdout:\n${r.stdout}');
      expect(calls, ['analyze'],
          reason: 'on a feature-tier push the suite is skipped, so analyze must '
              'be the ONLY flutter call — and it must still happen. An empty '
              'list means analyze sits below the skip and never runs, which is '
              'the precise regression this file exists to catch. Got: $calls');
    } finally {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    }
  });
}
