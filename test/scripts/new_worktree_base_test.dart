// End-to-end tests for scripts/new-worktree.sh's BASE selection.
//
// The bug: it preferred `origin/main` unconditionally whenever `git fetch`
// succeeded, calling that "the freshest main". It is only freshest when nothing
// is merged-but-unpushed — and §4.13's workflow is merge-locally-then-push, so
// the stale window is structural. It bit on 2026-08-10: a worktree created after
// a merge to local main but before the push was based on the PRE-merge commit.
//
// Each case builds a real scratch repo with a real `origin` remote, so the
// ancestor logic is exercised against git rather than a mock.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subprocess environment with git/CI leakage removed.
///
///   GIT_*      — git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into
///                every hook, and they override BOTH `workingDirectory:` and
///                `git -C <path>`. This test shells out to git constantly, so a
///                leak would drive the REAL repo — and this script CREATES
///                WORKTREES, so that is destructive, not merely meaningless
///                (feedback_mistake_git_hook_env_leak).
///   GITHUB_*   — the family shares one hermetic contract so a future reader of
///                CI env cannot silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

late final String _script;

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe,
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

void _git(String cwd, List<String> args) {
  final r = _run('git', args, cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed in $cwd:\n${r.stdout}${r.stderr}');
  }
}

/// A scratch repo with a real `origin` remote, both at one shared commit.
({Directory root, Directory origin}) _repo() {
  final tmp = Directory.systemTemp.createTempSync('nwt_base_');
  final originDir = Directory('${tmp.path}/origin')..createSync();
  final workDir = Directory('${tmp.path}/work')..createSync();

  _git(originDir.path, ['init', '--bare', '--initial-branch=main']);
  _git(workDir.path, ['init', '--initial-branch=main']);
  _git(workDir.path, ['config', 'user.email', 't@example.com']);
  _git(workDir.path, ['config', 'user.name', 'T']);
  File('${workDir.path}/seed.txt').writeAsStringSync('seed\n');
  _git(workDir.path, ['add', '-A']);
  _git(workDir.path, ['commit', '-m', 'seed']);
  _git(workDir.path, ['remote', 'add', 'origin', originDir.path]);
  _git(workDir.path, ['push', '-u', 'origin', 'main']);
  return (root: workDir, origin: originDir);
}

void _commit(String cwd, String name) {
  File('$cwd/$name').writeAsStringSync('$name\n');
  _git(cwd, ['add', '-A']);
  _git(cwd, ['commit', '-m', name]);
}

/// Runs the real script and returns the sha the new worktree was based on.
({int exitCode, String out, String? baseSha}) _newWorktree(String cwd, String slug) {
  final r = _run('sh', [_script, slug], cwd);
  final out = '${r.stdout}${r.stderr}';
  String? sha;
  final wt = Directory('$cwd/.claude/worktrees/$slug');
  if (wt.existsSync()) {
    final rev = _run('git', ['rev-parse', 'HEAD'], wt.path);
    if (rev.exitCode == 0) sha = (rev.stdout as String).trim();
  }
  return (exitCode: r.exitCode, out: out, baseSha: sha);
}

void main() {
  setUpAll(() {
    _script = File('scripts/new-worktree.sh').absolute.path;
    expect(File(_script).existsSync(), isTrue, reason: 'run from the repo root');
    expect(_cleanEnv().keys.where((k) => k.toUpperCase().startsWith('GIT_')),
        isEmpty,
        reason: 'env scrub failed — this test creates worktrees, so a GIT_DIR '
            'leak would act on the REAL repo');
  });

  test('LOCAL AHEAD (merged-but-unpushed) bases on local main — the 2026-08-10 bug',
      () {
    final r = _repo();
    addTearDown(() => r.root.parent.deleteSync(recursive: true));

    _commit(r.root.path, 'merged-locally.txt');
    final localSha = (_run('git', ['rev-parse', 'main'], r.root.path).stdout as String).trim();
    final remoteSha =
        (_run('git', ['rev-parse', 'origin/main'], r.root.path).stdout as String).trim();
    expect(localSha, isNot(remoteSha), reason: 'fixture must be ahead of origin');

    final w = _newWorktree(r.root.path, 'slice');
    expect(w.exitCode, 0, reason: w.out);
    expect(w.baseSha, localSha,
        reason: 'basing on origin/main here drops the merged work and '
            'guarantees a conflict — the exact failure this fixes');
  });

  test('LOCAL BEHIND bases on origin/main', () {
    final r = _repo();
    addTearDown(() => r.root.parent.deleteSync(recursive: true));

    // Advance origin via a second clone, leaving the fixture behind.
    final other = Directory('${r.root.parent.path}/other')..createSync();
    _git(other.path, ['clone', r.origin.path, '.']);
    _git(other.path, ['config', 'user.email', 't@example.com']);
    _git(other.path, ['config', 'user.name', 'T']);
    _commit(other.path, 'remote-ahead.txt');
    _git(other.path, ['push', 'origin', 'main']);

    final w = _newWorktree(r.root.path, 'slice');
    expect(w.exitCode, 0, reason: w.out);
    final remoteSha =
        (_run('git', ['rev-parse', 'origin/main'], r.root.path).stdout as String).trim();
    expect(w.baseSha, remoteSha);
  });

  test('IDENTICAL refs succeed (both --is-ancestor tests pass)', () {
    // git merge-base --is-ancestor A B returns 0 when A == B, so this case
    // satisfies BOTH branches. It is handled first and explicitly.
    final r = _repo();
    addTearDown(() => r.root.parent.deleteSync(recursive: true));

    final sha = (_run('git', ['rev-parse', 'main'], r.root.path).stdout as String).trim();
    final w = _newWorktree(r.root.path, 'slice');
    expect(w.exitCode, 0, reason: w.out);
    expect(w.baseSha, sha);
  });

  test('DIVERGED warns and continues on local main — never a ship-stop', () {
    final r = _repo();
    addTearDown(() => r.root.parent.deleteSync(recursive: true));

    final other = Directory('${r.root.parent.path}/other')..createSync();
    _git(other.path, ['clone', r.origin.path, '.']);
    _git(other.path, ['config', 'user.email', 't@example.com']);
    _git(other.path, ['config', 'user.name', 'T']);
    _commit(other.path, 'remote-side.txt');
    _git(other.path, ['push', 'origin', 'main']);
    _commit(r.root.path, 'local-side.txt'); // now genuinely diverged

    final localSha = (_run('git', ['rev-parse', 'main'], r.root.path).stdout as String).trim();
    final w = _newWorktree(r.root.path, 'slice');

    expect(w.exitCode, 0,
        reason: 'new-worktree.sh is the entry point for ALL new work (§4.13 '
            'point 1) — hard-failing here is a ship-stop for a hygiene problem, '
            'the error class §4.13 point 6 names. ${w.out}');
    expect(w.out, contains('DIVERGED'), reason: 'must warn LOUDLY');
    expect(w.baseSha, localSha);
  });

  test('NO REMOTE falls back to local main without erroring', () {
    // --is-ancestor errors under `set -e` if origin/main does not exist, so the
    // existence guard must come first.
    final tmp = Directory.systemTemp.createTempSync('nwt_noremote_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    _git(tmp.path, ['init', '--initial-branch=main']);
    _git(tmp.path, ['config', 'user.email', 't@example.com']);
    _git(tmp.path, ['config', 'user.name', 'T']);
    _commit(tmp.path, 'seed.txt');

    final sha = (_run('git', ['rev-parse', 'main'], tmp.path).stdout as String).trim();
    final w = _newWorktree(tmp.path, 'slice');
    expect(w.exitCode, 0, reason: w.out);
    expect(w.baseSha, sha);
  });
}
