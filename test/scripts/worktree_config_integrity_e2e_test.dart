// test/scripts/worktree_config_integrity_e2e_test.dart
//
// END-TO-END gate test: builds a throwaway repo WITH A REAL LINKED WORKTREE,
// injects the exact corruption from the 2026-08-09 incident, and runs
// `check_worktree_config_integrity.dart` against it, asserting exit codes.
//
// WHY this exists in addition to worktree_config_integrity_lib_test.dart:
// the pure tests certify the parser and the verdict function. They cannot
// prove the GATE reads the right thing — that it invokes git with the right
// arguments, that git's real output matches the fixtures, or that the exit
// code maps the way the lib assumes. Only executing the real binary against a
// real corrupted repo shows that. (Same lesson recorded in
// plan_review_record_gate_e2e_test.dart's header: unit-testing a helper
// certifies the helper, not the gate.)
//
// ENV SCRUBBING IS LOAD-BEARING — MORE SO HERE THAN ANYWHERE ELSE IN THE REPO.
// Run inside `pre-commit`, a test that spawns its own git repo inherits
// GIT_DIR / GIT_WORK_TREE, which override BOTH `workingDirectory:` and
// `-C <path>` (feedback_mistake_git_hook_env_leak). This gate's ENTIRE SUBJECT
// is git working-tree resolution, so a leak would not merely weaken the test —
// it would make the gate read the REAL repo and report on it, passing
// standalone and asserting nothing inside the hook. We pass a filtered
// environment with includeParentEnvironment: false, and ABORT LOUDLY if the
// isolation did not take rather than running assertions against the real repo.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parent environment minus anything git-related, so a surrounding git hook
/// cannot redirect the child git at the real repository.
///
/// Scrubs the same three keys as the rest of the gate-e2e family
/// (test/contracts/gate_e2e_env_hermetic_test.dart enforces this uniformly):
///   GIT_*      — load-bearing HERE specifically: GIT_DIR / GIT_WORK_TREE
///                override both `workingDirectory:` and `-C <path>`, and this
///                gate's entire subject IS working-tree resolution, so a leak
///                would make it report on the REAL repo while passing.
///   GITHUB_*   — this gate reads no GITHUB_* var today (unlike the keystone
///                gate, diagnose c3f8e1). Scrubbed anyway so the family shares
///                one hermetic contract and a future reader of CI env cannot
///                silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) {
  return Process.runSync(
    exe,
    args,
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    runInShell: true,
  );
}

void main() {
  late Directory tmp;
  late String repo;
  late String linkedWt;

  final srcRoot = Directory.current.path;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('wt_config_gate_e2e_');
    repo = '${tmp.path}/main';
    linkedWt = '${tmp.path}/linked';
    Directory(repo).createSync(recursive: true);

    _run('git', ['init', '-q', '-b', 'main', '.'], repo);
    _run('git', ['config', 'user.email', 'test@example.invalid'], repo);
    _run('git', ['config', 'user.name', 'Test'], repo);

    // Prove the isolation actually took, rather than assuming it. If a GIT_DIR
    // leaked, this resolves to the REAL repo and we must not continue.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    final resolved = (top.stdout as String).trim();
    if (!resolved.toLowerCase().contains('wt_config_gate_e2e_')) {
      throw StateError(
          'ENV LEAK: throwaway git resolved to "$resolved", not the temp repo. '
          'GIT_DIR/GIT_WORK_TREE scrubbing failed — aborting rather than '
          'running assertions against the real repository.');
    }

    // The gate + its lib.
    Directory('$repo/scripts').createSync(recursive: true);
    for (final f in const [
      'check_worktree_config_integrity.dart',
      'worktree_config_integrity_lib.dart',
    ]) {
      File('$srcRoot/scripts/$f').copySync('$repo/scripts/$f');
    }

    File('$repo/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-q', '-m', 'seed'], repo);

    // A REAL linked worktree — the configuration the gate exists to protect.
    final wt = _run('git', ['worktree', 'add', '-q', linkedWt, '-b', 'feature'], repo);

    // ASSERT the setup actually worked. Without this, a failed `worktree add`
    // leaves the tests named "...with a normal linked worktree" and "a normal
    // `git worktree add` does NOT set core.worktree" passing while testing
    // nothing at all — they would be unfalsifiable. (B-pass P2-5.)
    if (wt.exitCode != 0 || !Directory(linkedWt).existsSync()) {
      throw StateError('SETUP FAILED: git worktree add exited ${wt.exitCode} '
          '(${(wt.stderr as String).trim()}); linked worktree exists='
          '${Directory(linkedWt).existsSync()}. Refusing to run assertions '
          'that would vacuously pass.');
    }
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows can hold locks on freshly-written files; a leaked temp dir is
      // not worth failing a green suite over.
    }
  });

  ProcessResult runGate(String cwd) =>
      _run('dart', ['run', 'scripts/check_worktree_config_integrity.dart'],
          cwd);

  /// The gate lives in the main checkout; run it there, but the CONFIG state
  /// under test is shared, so corruption injected anywhere is visible.
  test('PASS on a clean repo with a normal linked worktree', () {
    final r = runGate(repo);
    expect(r.exitCode, 0,
        reason: 'clean repo must pass. stdout=${r.stdout} stderr=${r.stderr}');
    expect(r.stdout as String, contains('PASS'));
  });

  test('a normal `git worktree add` does NOT itself set core.worktree', () {
    // Guards the gate against being a false-positive machine: if git set this
    // key during `worktree add`, the gate would fire on every healthy repo.
    final r = _run(
        'git', ['config', '--show-origin', '--get-all', 'core.worktree'], repo);
    expect(r.exitCode, 1,
        reason: 'expected NO core.worktree after a plain worktree add; '
            'got: ${r.stdout}');
  });

  test('FAIL when core.worktree is injected into the shared config — '
      'the exact 2026-08-09 corruption', () {
    _run('git', ['config', 'core.worktree', linkedWt], repo);

    final r = runGate(repo);

    expect(r.exitCode, 1, reason: 'gate must FAIL on the injected corruption');
    final err = r.stderr as String;
    expect(err, contains('FAIL'));
    // The message must name the offending value, or the operator cannot act.
    expect(err, contains('linked'),
        reason: 'failure output must echo the configured path');
    expect(err, contains('--unset-all'),
        reason: 'failure output must carry the repair command');
  });

  test('the corruption is observable as wrong toplevel resolution '
      '(proves the gate targets a real hazard, not a cosmetic key)', () {
    // core.worktree is still set from the previous test.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    final resolved = (top.stdout as String).trim().replaceAll('\\', '/');
    expect(resolved.toLowerCase(), contains('linked'),
        reason: 'with core.worktree set, the main checkout must resolve to the '
            'OTHER worktree — this is the mixing hazard §4.13 exists to stop');
  });

  test('--warn-only exits 0 while corrupt BUT still reports the violation', () {
    final r = _run(
        'dart',
        ['run', 'scripts/check_worktree_config_integrity.dart', '--warn-only'],
        repo);
    expect(r.exitCode, 0);
    // Asserting only exitCode == 0 would be satisfied by a gate that silently
    // no-ops on the flag — the flag must soften the exit, not the detection.
    // (B-pass P2-6.)
    expect(r.stderr as String, contains('FAIL'),
        reason: '--warn-only must still DETECT and report; it only downgrades '
            'the exit code');
  });

  test('PASS again after the documented repair (unset restores health)', () {
    _run('git', ['config', '--unset-all', 'core.worktree'], repo);

    final r = runGate(repo);
    expect(r.exitCode, 0,
        reason: 'gate must go green once repaired. stderr=${r.stderr}');

    // And resolution is restored — the actual point of the repair.
    final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
    expect((top.stdout as String).trim().replaceAll('\\', '/').toLowerCase(),
        contains('/main'));
  });
}
