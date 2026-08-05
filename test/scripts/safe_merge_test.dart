// test/scripts/safe_merge_test.dart
//
// END-TO-END coverage for scripts/safe_merge.sh (Unit 3c, discipline-tooling
// hardening batch, 2026-08-03). Builds a real bare "remote" + a real
// "primary" clone in throwaway directories and runs the actual script
// against them, asserting exit codes and HEAD movement -- not a mocked git.
//
// WHY THIS EXISTS: before this unit, the merge-into-main step had no wrapper
// at all -- just a raw `git merge --no-ff <branch>`, exempted by
// git_safety_hook.dart as an integration op. That is exactly the moment
// "is local main caught up with origin/main" matters most. This test proves
// the new wrapper actually refuses onto a stale base rather than merging
// silently, mirroring the seeded-stale-origin scenario the plan called for.
//
// ENV SCRUBBING IS LOAD-BEARING -- see plan_review_record_gate_e2e_test.dart's
// header for why (feedback_mistake_git_hook_env_leak): a surrounding git hook
// exports GIT_DIR/GIT_WORK_TREE, which override BOTH `workingDirectory:` and
// `-C <path>`, so an unscrubbed child git would operate on the REAL repo.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String>? extra}) {
  final env = _cleanEnv();
  if (extra != null) env.addAll(extra);
  return Process.runSync(exe, args,
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: false,
      runInShell: true);
}

String _fileUri(String path) => 'file:///${path.replaceAll('\\', '/')}';

void main() {
  final srcRoot = Directory.current.path;
  late Directory tmp;
  late String remote; // bare "origin"
  late String primary; // clone acting as the primary worktree

  void copyScripts(String repoPath) {
    Directory('$repoPath/scripts').createSync(recursive: true);
    for (final f in const ['safe_merge.sh', '_git_lock.sh']) {
      File('$srcRoot/scripts/$f').copySync('$repoPath/scripts/$f');
    }
  }

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('safe_merge_e2e_');
    remote = '${tmp.path}/remote.git';
    primary = '${tmp.path}/primary';

    Directory(remote).createSync(recursive: true);
    expect(_run('git', ['init', '-q', '--bare', '-b', 'main', '.'], remote)
        .exitCode, 0);

    Directory(primary).createSync(recursive: true);
    expect(
        _run('git', ['clone', '-q', _fileUri(remote), '.'], primary).exitCode,
        0,
        reason: 'setup: cloning the empty bare remote must succeed');
    _run('git', ['config', 'user.email', 'test@example.invalid'], primary);
    _run('git', ['config', 'user.name', 'Test'], primary);

    // Verify isolation actually took before trusting any assertion below.
    final top = _run('git', ['rev-parse', '--show-toplevel'], primary);
    final resolved = (top.stdout as String).trim();
    if (!resolved.toLowerCase().contains('safe_merge_e2e_')) {
      throw StateError(
          'ENV LEAK: throwaway primary resolved to "$resolved", not the temp '
          'dir. GIT_* scrubbing failed -- aborting rather than running '
          'assertions against the real repository.');
    }

    copyScripts(primary);
    File('$primary/seed.txt').writeAsStringSync('seed\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'seed'], primary);
    expect(_run('git', ['push', '-q', '-u', 'origin', 'main'], primary)
        .exitCode, 0,
        reason: 'setup: seeding the bare remote must succeed');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* best effort on Windows file locks */}
  });

  /// Creates a feature branch in [repo] off its current `main`, with one
  /// commit, then returns to `main`. Returns the branch name.
  String makeFeatureBranch(String repo, String name) {
    _run('git', ['checkout', '-q', '-B', name, 'main'], repo);
    File('$repo/$name.txt').writeAsStringSync('$name\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'work on $name'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);
    return name;
  }

  test('refuses to merge when local main is BEHIND origin/main', () {
    // Simulate someone else pushing directly to the shared remote: a THIRD
    // clone, independent of `primary`, commits and pushes -- advancing the
    // bare repo without primary's local main or its cached
    // refs/remotes/origin/main moving at all.
    final otherDir = '${tmp.path}/other_pusher';
    Directory(otherDir).createSync(recursive: true);
    expect(_run('git', ['clone', '-q', _fileUri(remote), '.'], otherDir)
        .exitCode, 0);
    _run('git', ['config', 'user.email', 'other@example.invalid'], otherDir);
    _run('git', ['config', 'user.name', 'Other'], otherDir);
    File('$otherDir/other.txt').writeAsStringSync('other push\n');
    _run('git', ['add', '-A'], otherDir);
    _run('git', ['commit', '-qm', 'a push primary has not seen'], otherDir);
    expect(_run('git', ['push', '-q', 'origin', 'main'], otherDir).exitCode,
        0,
        reason: 'setup: the "other pusher" must land on the shared remote');

    final branch = makeFeatureBranch(primary, 'stale-base-feature');
    final beforeHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 1,
        reason: 'local main is behind origin/main -- this must refuse, not '
            'merge onto a stale base.\n${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('behind origin/main'));

    final afterHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();
    expect(afterHead, beforeHead,
        reason: 'a refused merge must not move HEAD at all');
  });

  test('merges cleanly once local main is caught up with origin/main', () {
    // Catch primary up for real (the previous test's failure left it
    // deliberately behind).
    expect(_run('git', ['fetch', '-q', 'origin', 'main'], primary).exitCode,
        0);
    expect(
        _run('git', ['merge', '-q', '--ff-only', 'origin/main'], primary)
            .exitCode,
        0,
        reason: 'setup: primary must genuinely catch up before this test');

    final branch = makeFeatureBranch(primary, 'caught-up-feature');
    final beforeHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);

    expect(r.exitCode, 0,
        reason: 'local main matches origin/main -- this must succeed.\n'
            '${r.stdout}${r.stderr}');
    final afterHead = (_run('git', ['rev-parse', 'HEAD'], primary).stdout
            as String)
        .trim();
    expect(afterHead, isNot(beforeHead),
        reason: 'a successful merge must advance HEAD');

    final log = _run('git', ['log', '-1', '--format=%P'], primary).stdout
        as String;
    expect(log.trim().split(RegExp(r'\s+')).length, 2,
        reason: 'must be a real merge commit (two parents), i.e. --no-ff');
  });

  test(
      'passes a multi-word -m message through as ONE argument, not '
      'word-split (round-2 review blocking #2)', () {
    // Re-sync defensively rather than assume prior test ordering left
    // primary caught up.
    expect(
        _run('git', ['fetch', '-q', 'origin', 'main'], primary).exitCode, 0);
    _run('git', ['merge', '-q', '--ff-only', 'origin/main'], primary);

    final branch = makeFeatureBranch(primary, 'extra-args-feature');
    // ASCII-only deliberately: Dart's Process API on Windows does not
    // reliably preserve a non-ASCII argument (e.g. an em-dash, this repo's
    // actual merge-message convention) through to the child process's
    // command line -- confirmed separately by invoking safe_merge.sh
    // directly from a real shell, where the SAME em-dash round-trips as
    // correct UTF-8 bytes. That is a Dart/Windows test-harness limitation
    // unconnected to safe_merge.sh itself (which is only ever invoked from
    // a real shell in actual use, never via Dart's Process API), so it is
    // avoided here rather than "fixed" -- this test's job is to pin the
    // word-splitting bug (round-2 blocking #2), not Windows Unicode
    // argv handling.
    final subject = "Merge branch 'extra-args-feature' "
        '- regression test for the round-2 word-splitting bug';

    final r =
        _run('sh', ['scripts/safe_merge.sh', branch, '-m', subject], primary);

    expect(r.exitCode, 0,
        reason: 'a multi-word -m message must be accepted, not shredded '
            'into unresolvable extra merge-target arguments. The FIRST '
            'shipped version of this passthrough failed here with '
            '"branch - not something we can merge".\n${r.stdout}${r.stderr}');

    final actualSubject =
        (_run('git', ['log', '-1', '--format=%s'], primary).stdout as String)
            .trim();
    expect(actualSubject, subject,
        reason: 'the commit subject must be the EXACT string passed to -m, '
            'proving it survived as one argument rather than being '
            'word-split and partially consumed by git as separate '
            'extra merge-target arguments.');
  });

  test('refuses when the current branch is not main', () {
    final branch = makeFeatureBranch(primary, 'off-main-feature');
    _run('git', ['checkout', '-q', branch], primary);
    addTearDown(() => _run('git', ['checkout', '-q', 'main'], primary));

    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('not \'main\''));
  });

  test('refuses when run from a LINKED worktree, not primary', () {
    final worktreeDir = '${tmp.path}/linked_wt';
    final wtBranch = 'linked-wt-probe';
    _run('git', ['branch', wtBranch, 'main'], primary);
    final add = _run(
        'git', ['worktree', 'add', '-q', worktreeDir, wtBranch], primary);
    expect(add.exitCode, 0, reason: 'setup: worktree add must succeed');
    copyScripts(worktreeDir);
    addTearDown(() {
      _run('git', ['worktree', 'remove', '--force', worktreeDir], primary);
    });

    final r = _run('sh', ['scripts/safe_merge.sh', 'main'], worktreeDir);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('LINKED worktree'));
  });
}
