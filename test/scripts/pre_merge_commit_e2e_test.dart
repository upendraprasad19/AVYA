// test/scripts/pre_merge_commit_e2e_test.dart
//
// Executes the REAL scripts/pre-merge-commit.sh as a REAL git hook, in a real
// throwaway repo, against a real clean merge that lands an OI-number collision.
//
// WHY THIS FILE EXISTS.
// The hook shipped on 2026-08-17 with no e2e coverage at all, and review round
// 1 showed the consequence: deleting the collision-gate invocation from the
// hook reddened NOTHING in the entire suite. A hook with no executing test is
// indistinguishable from a hook that does not work, which is the Gate-44 lesson
// (CLAUDE.md rule 24) restated for hooks rather than gates.
//
// Two contracts, and the second is the one that bites:
//
//   1. A CLEAN auto-merge carrying a collision must be BLOCKED. Clean is
//      load-bearing: a merge that conflicts textually was never the danger,
//      because git stops and the operator looks. Every real incident took the
//      clean path -- the two boards' additions sat in different regions, git
//      combined them without complaint, and before this hook existed NO hook
//      ran at all for an auto-created merge commit.
//
//   2. The hook must leave the INDEX and the WORKING TREE exactly as it found
//      them. Its first version regenerated OPEN_INDEX.md and `git add`-ed it,
//      believing that put the index in the merge commit. It does not: git
//      computes the merge tree BEFORE running the hook, so the add reached
//      nothing and merely left a file staged -- which the next unrelated commit
//      would sweep in. That is the cross-session index-mixing shape §4.13
//      exists to prevent, and it would happen on the PRIMARY worktree, the one
//      shared by every session.

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// This file deliberately spawns NO dart process of its own, so it carries no
// `_dartBin()` helper — its sibling test/scripts/oi_numbering_lib_test.dart
// does, and explains the flutter_tester trap there. Everything here goes
// through `git`, and git invokes the hook, which resolves its own Dart via
// scripts/_dart_bin.sh. That exercises the REAL resolution path rather than a
// test-chosen one, which is better coverage anyway.
//
// The first draft left an unused `_dartBin()` here and it FAILED THE PUSH:
// `unused_element` is a WARNING, and pre-push runs `flutter analyze
// --no-fatal-infos`, so infos pass and warnings do not. It was the only
// warning in the entire repo. Worth knowing before leaving a helper "for
// later" in a test — analyze is the one gate that runs on every push,
// including the feature-tier ones that skip the suite.

/// The parent environment with git's location variables REMOVED.
///
/// A test that spawns its own git repo inherits GIT_DIR / GIT_WORK_TREE when it
/// runs inside a git hook -- and the pre-commit gate loop runs exactly this
/// suite that way. Those variables OVERRIDE `workingDirectory`, so without this
/// the test silently operates on the REAL repo (feedback_mistake_git_hook_env_leak).
///
/// They must be UNSET, not set to ''. Dart merges `environment` over the parent
/// rather than replacing it, so `{'GIT_DIR': ''}` leaves GIT_DIR defined-but-
/// empty and git reports `fatal: not in a git directory` -- which is how the
/// first version of this file failed.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  for (final k in const [
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_COMMON_DIR',
  ]) {
    env.remove(k);
  }
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) {
  return Process.runSync(
    exe,
    args,
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
  );
}

void _git(String cwd, List<String> args) {
  final r = _run('git', args, cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed in $cwd:\n'
        '${r.stdout}\n${r.stderr}');
  }
}

/// A board file with one `## OI-N — title` section per entry, padded so that
/// two entries added in different regions merge without a textual conflict.
String _board(Map<int, String> entries, {String heading = '# Open issues'}) {
  final b = StringBuffer('$heading\n\n');
  final keys = entries.keys.toList()..sort();
  for (final k in keys) {
    b.writeln('## OI-$k — ${entries[k]}');
    b.writeln();
    b.writeln('- **Status**: OPEN');
    b.writeln('- **Blocked on**: nothing');
    b.writeln('- **Verified**: never');
    b.writeln();
  }
  return b.toString();
}

void main() {
  late Directory tmp;
  late String repoRoot;

  setUpAll(() {
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('premerge_');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Builds a repo where `main` and `feature` each mint OI-2 for a DIFFERENT
  /// issue, on different board files so the merge is guaranteed clean, and
  /// installs the real hook.
  String _scenario({required bool collide}) {
    final work =
        '${tmp.path}/w${collide ? 'c' : 'n'}${DateTime.now().microsecondsSinceEpoch}';
    Directory(work).createSync(recursive: true);
    _run('git', ['init', '-b', 'main', work], tmp.path);
    _git(work, ['config', 'user.email', 't@t.t']);
    _git(work, ['config', 'user.name', 't']);
    _git(work, ['config', 'commit.gpgsign', 'false']);

    Directory('$work/docs/audit').createSync(recursive: true);
    Directory('$work/scripts').createSync(recursive: true);

    void writeBoards(Map<int, String> open, Map<int, String> closed) {
      File('$work/docs/audit/open_issues.md')
          .writeAsStringSync(_board(open), encoding: utf8);
      File('$work/docs/audit/closed_issues.md').writeAsStringSync(
          _board(closed, heading: '# Closed issues'),
          encoding: utf8);
    }

    // Copy the real scripts under test plus what they invoke.
    for (final f in const [
      'scripts/pre-merge-commit.sh',
      'scripts/_dart_bin.sh',
      'scripts/build_oi_index.dart',
      'scripts/check_oi_numbering_unique.dart',
      'scripts/oi_numbering_lib.dart',
    ]) {
      final src = File('$repoRoot/$f');
      if (src.existsSync()) src.copySync('$work/$f');
    }

    writeBoards({1: 'one'}, const {});
    _git(work, ['add', '-A']);
    _git(work, ['commit', '-m', 'base']);

    _git(work, ['checkout', '-b', 'feature']);
    // The feature side mints OI-2 (or OI-3 in the no-collision case) on the
    // CLOSED board -- a different FILE from main's addition, so git can always
    // combine the two without a conflict.
    writeBoards({1: 'one'}, {collide ? 2 : 3: 'branch entry'});
    _git(work, ['add', '-A']);
    _git(work, ['commit', '-m', 'branch mints']);

    _git(work, ['checkout', 'main']);
    writeBoards({1: 'one', 2: 'mainline two'}, const {});
    _git(work, ['add', '-A']);
    _git(work, ['commit', '-m', 'main mints']);

    // Install the REAL hook, exactly as setup-hooks.sh does (a cp).
    final hookDir = Directory('$work/.git/hooks');
    hookDir.createSync(recursive: true);
    File('$repoRoot/scripts/pre-merge-commit.sh')
        .copySync('$work/.git/hooks/pre-merge-commit');
    if (!Platform.isWindows) {
      _run('chmod', ['+x', '$work/.git/hooks/pre-merge-commit'], work);
    }
    return work;
  }

  test('BLOCKS a clean auto-merge that lands an OI-number collision', () {
    final work = _scenario(collide: true);

    // --no-ff would create the merge commit via a different path; the shape
    // this hook exists for is the AUTO-created merge commit, which is what a
    // plain `git merge` of a diverged branch produces.
    final merge = _run('git', ['merge', '--no-edit', 'feature'], work);

    expect(merge.exitCode, isNot(0),
        reason: 'the merge must be REFUSED. If this passes, a collision lands '
            'on main exactly as it did five times before this hook existed.\n'
            'stdout: ${merge.stdout}\nstderr: ${merge.stderr}');
    expect('${merge.stdout}${merge.stderr}', contains('OI-2'),
        reason: 'the operator must be told WHICH number clashed');

    // And the merge must not have been recorded.
    final head = _run('git', ['rev-list', '--parents', '-n', '1', 'HEAD'], work)
        .stdout
        .toString()
        .trim()
        .split(RegExp(r'\s+'));
    expect(head.length, lessThan(3),
        reason: 'a blocked merge must not have produced a merge commit');
  });

  test('a clean merge with NO collision is allowed through', () {
    // The mirror. Without it, a hook that refused every merge would satisfy the
    // test above and be strictly worse than no hook at all.
    final work = _scenario(collide: false);
    final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
    expect(merge.exitCode, 0,
        reason: 'distinct numbers on the two sides is the NORMAL merge; '
            'blocking it makes the hook unusable.\n'
            'stdout: ${merge.stdout}\nstderr: ${merge.stderr}');
  });

  test('leaves NOTHING staged — the hook must not mutate the index', () {
    // Contract 2. The first version of this hook `git add`-ed a regenerated
    // OPEN_INDEX.md here; the add could not reach the already-computed merge
    // tree, so it only left a stray staged file for the next commit to sweep
    // in. On the shared primary worktree that is the §4.13 index-mixing shape.
    final work = _scenario(collide: false);
    _run('git', ['merge', '--no-edit', 'feature'], work);

    final staged =
        _run('git', ['diff', '--cached', '--name-only'], work).stdout.toString().trim();
    expect(staged, isEmpty,
        reason: 'the hook left files STAGED after the merge: "$staged". '
            'A hook that stages work the operator did not stage is how one '
            'session\'s files end up in another session\'s commit.');

    final dirty =
        _run('git', ['status', '--porcelain'], work).stdout.toString().trim();
    expect(dirty, isEmpty,
        reason: 'the hook left the working tree dirty: "$dirty". It regenerates '
            'OPEN_INDEX.md to validate and must restore it, or a debugger '
            'cannot tell a hook side effect from a bad merge.');
  });
}
