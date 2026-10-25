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

import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';

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

/// Every spawn goes through test/helpers/spawn.dart, whose environment has git's
/// location variables REMOVED (and the rest of the canonical control-variable
/// scrub).
///
/// A test that spawns its own git repo inherits GIT_DIR / GIT_WORK_TREE when it
/// runs inside a git hook -- and the pre-commit gate loop runs exactly this
/// suite that way. Those variables OVERRIDE `workingDirectory`, so without this
/// the test silently operates on the REAL repo (feedback_mistake_git_hook_env_leak).
///
/// They must be UNSET, not set to ''. Dart merges `environment` over the parent
/// rather than replacing it, so `{'GIT_DIR': ''}` leaves GIT_DIR defined-but-
/// empty and git reports `fatal: not in a git directory` -- which is how the
/// first version of this file failed. (The helper passes
/// `includeParentEnvironment: false` with a map that simply lacks them.)
ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String> env = const {}}) {
  return runSpawn(
    exe,
    args,
    why: 'pre_merge_commit_e2e: $exe ${args.join(' ')}',
    workingDirectory: cwd,
    extraEnv: env,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
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

  /// Install the REAL hook, exactly as setup-hooks.sh does (a cp).
  void installHook(String work, {bool old = false}) {
    final hookDir = Directory('$work/.git/hooks');
    hookDir.createSync(recursive: true);
    File(old
            ? '$repoRoot/test/scripts/fixtures/pre_a2_hooks/pre-merge-commit.sh.txt'
            : '$repoRoot/scripts/pre-merge-commit.sh')
        .copySync('$work/.git/hooks/pre-merge-commit');
    if (!Platform.isWindows) {
      _run('chmod', ['+x', '$work/.git/hooks/pre-merge-commit'], work);
    }
  }

  /// Builds a repo where `main` and `feature` each mint OI-2 for a DIFFERENT
  /// issue, on different board files so the merge is guaranteed clean, and
  /// installs the real hook.
  ///
  /// A2 (merge-conflict-treadmill): the OPEN index is a local build product. By
  /// default it is NEITHER tracked NOR ignored (the three pre-A2 cases below).
  /// [ignoreIndex] commits a `.gitignore` for it (the A2 state); [trackIndex]
  /// commits a STALE copy (the pre-A2 state); [staleOnDisk] leaves a stale copy of
  /// an ignored index on disk; [withinFile] makes the two sides add the SAME
  /// `## OI-N` to ONE board file in different regions (a clean merge with two
  /// headings, the case the hook's first check exists for).
  ///
  /// [builderExit] replaces the board builder with a program that exits with that code
  /// (a crash is 254, a bad argument 2: neither is the builder's own 0 / 1 / 3 contract).
  /// [trackIndex] together with [ignoreIndex] force-adds the stale copy: a TRACKED path that
  /// `.gitignore` also matches, the state of a pre-A2 branch that edited the index and kept it
  /// through the modify/delete conflict. [oldHook] installs the FROZEN A0 hook
  /// (test/scripts/fixtures/pre_a2_hooks) instead of the current one.
  String _scenario({
    required bool collide,
    bool ignoreIndex = false,
    bool trackIndex = false,
    bool staleOnDisk = false,
    bool withinFile = false,
    int? builderExit,
    bool oldHook = false,
  }) {
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

    // Copy the real scripts under test plus EVERYTHING they import, through the
    // closure helper: a builder that gains an import (A2 gave both index builders a
    // shared lib) must never break this fixture again.
    copyScriptClosure(repoRoot, work, const [
      'scripts/pre-merge-commit.sh',
      'scripts/_dart_bin.sh',
      'scripts/build_oi_index.dart',
      'scripts/check_oi_numbering_unique.dart',
    ]);

    if (withinFile) {
      // Padding between the two insertion points keeps the merge CLEAN.
      File('$work/docs/audit/open_issues.md')
          .writeAsStringSync(_board({1: 'one', 10: 'ten', 20: 'twenty', 30: 'thirty'}));
      File('$work/docs/audit/closed_issues.md')
          .writeAsStringSync(_board(const {}, heading: '# Closed issues'));
    } else {
      writeBoards({1: 'one'}, const {});
    }
    if (ignoreIndex) {
      File('$work/.gitignore').writeAsStringSync('docs/audit/OPEN_INDEX.md\n');
    }
    if (trackIndex) {
      File('$work/docs/audit/OPEN_INDEX.md').writeAsStringSync('stale tracked index\n');
    }
    if (builderExit != null) {
      File('$work/scripts/build_oi_index.dart')
          .writeAsStringSync("import 'dart:io';\nvoid main() => exit($builderExit);\n");
    }
    _git(work, ['add', '-A']);
    if (trackIndex && ignoreIndex) _git(work, ['add', '-f', 'docs/audit/OPEN_INDEX.md']);
    _git(work, ['commit', '-m', 'base']);
    if (staleOnDisk) {
      File('$work/docs/audit/OPEN_INDEX.md').writeAsStringSync('stale ignored index\n');
    }

    if (withinFile) {
      final board = File('$work/docs/audit/open_issues.md');
      final base = board.readAsStringSync();
      _git(work, ['checkout', '-b', 'feature']);
      // The feature side adds OI-5 right after the heading ...
      board.writeAsStringSync(base.replaceFirst('# Open issues\n\n',
          '# Open issues\n\n## OI-5 — feature five\n\n- **Status**: OPEN\n- **Blocked on**: nothing\n- **Verified**: never\n\n'));
      _git(work, ['add', '-A']);
      _git(work, ['commit', '-m', 'feature mints OI-5']);
      _git(work, ['checkout', 'main']);
      // ... and main adds a DIFFERENT OI-5 (collide) or OI-6 at the very end.
      board.writeAsStringSync('$base## OI-${collide ? 5 : 6} — main number\n\n'
          '- **Status**: OPEN\n- **Blocked on**: nothing\n- **Verified**: never\n\n');
      _git(work, ['add', '-A']);
      _git(work, ['commit', '-m', 'main mints']);
      installHook(work, old: oldHook);
      return work;
    }

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

    installHook(work, old: oldHook);
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

  // ------------------------------------------------------------------------------------------
  // A2 (merge-conflict-treadmill): OPEN_INDEX.md is an IGNORED local build product.
  //
  // The hook keys on `git check-ignore -q`, NOT on `ls-files`, so there are three states and a
  // case for each: ignored (here), tracked (the pre-A2 path, byte for byte) and neither (the
  // three tests above). When the index is ignored the hook only VALIDATES: no backup (nothing
  // to leak when mktemp fails), no restore (it would `rm -f` the build it just made), no NOTE
  // (it told the user to `git add` an ignored file), and a failed WRITE of the ignored output
  // (the builder's exit 3) is a warning, never a reason to block a merge.
  // ------------------------------------------------------------------------------------------

  /// Everything a merge printed, for message assertions.
  String out(ProcessResult r) => '${r.stdout}\n${r.stderr}';

  group('A2: ignored OPEN_INDEX.md validates only', () {
    test('a within-file duplicate OI is still BLOCKED', () {
      final work = _scenario(collide: true, withinFile: true, ignoreIndex: true);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(out(merge), isNot(contains('CONFLICT')),
          reason: 'the fixture must be a CLEAN auto-merge, or it proves nothing');
      expect(merge.exitCode, isNot(0),
          reason: 'two `## OI-5` headings in one board must refuse the merge.\n${out(merge)}');
      expect(out(merge), contains('OI-5'));
      expect(out(merge), contains('did not validate'));
    });

    test('a clean merge is allowed; the fresh build is KEPT, nothing staged, no NOTE, no leak', () {
      final work = _scenario(collide: false, withinFile: true, ignoreIndex: true);
      final leak = Directory('${tmp.path}/tmpdir_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync();
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work,
          env: {'TMPDIR': leak.path});
      expect(merge.exitCode, 0, reason: out(merge));

      final idx = File('$work/docs/audit/OPEN_INDEX.md');
      expect(idx.existsSync(), isTrue, // file-only: a generated FILE
          reason: 'the build is a local product and must survive the hook: a restore of an '
              'ignored index would `rm -f` it (_INDEX_EXISTED=0).');
      final text = idx.readAsStringSync();
      expect(text, startsWith('<!-- local-build: '));
      expect(text, contains('OI-5'));
      expect(text, contains('OI-6'));

      expect(out(merge), isNot(contains('NOTE')),
          reason: 'the stale-index NOTE tells the user to `git add` an IGNORED file');
      expect(
          _run('git', ['diff', '--cached', '--name-only'], work).stdout.toString().trim(), isEmpty);
      expect(_run('git', ['status', '--porcelain'], work).stdout.toString().trim(), isEmpty);
      expect(leak.listSync(), isEmpty,
          reason: 'an ignored index takes NO backup: a leftover tmp file in TMPDIR is a leak');
    });

    test('a STALE ignored index on disk is rebuilt, not restored', () {
      final work =
          _scenario(collide: false, withinFile: true, ignoreIndex: true, staleOnDisk: true);
      // The file is PRESENT here, which is the only state in which a backup could be taken: the
      // scenarios without a file on disk cannot tell a hook that backs up from one that does not.
      final leak = Directory('${tmp.path}/tmpdir_stale_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync();
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work, env: {'TMPDIR': leak.path});
      expect(merge.exitCode, 0, reason: out(merge));
      expect(leak.listSync(), isEmpty,
          reason: 'an ignored index takes NO backup, even when the file exists: a leftover tmp file is a leak');
      final text = File('$work/docs/audit/OPEN_INDEX.md').readAsStringSync();
      expect(text, isNot(contains('stale ignored index')),
          reason: 'the old hook backed the file up and put the STALE copy back');
      expect(text, startsWith('<!-- local-build: '));
      expect(out(merge), isNot(contains('stale relative')));
      expect(out(merge), isNot(contains('git add')));
    });

    test('a failing mktemp changes nothing: the check still runs and still blocks', () {
      // staleOnDisk: the index file EXISTS, the only state in which a backup (and so a mktemp) is tried.
      final work = _scenario(collide: true, withinFile: true, ignoreIndex: true, staleOnDisk: true);
      Directory('$work/stubbin').createSync();
      File('$work/stubbin/mktemp').writeAsStringSync('#!/bin/sh\nexit 1\n');
      _run('chmod', ['+x', '$work/stubbin/mktemp'], work);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work,
          env: {'PATH': '$work/stubbin:${Platform.environment['PATH']}'});
      expect(out(merge), isNot(contains('SKIPPING')),
          reason: 'an ignored index needs no backup, so a broken mktemp must not skip the render check');
      expect(merge.exitCode, isNot(0), reason: out(merge));
      expect(out(merge), contains('did not validate'));
    });

    test('a WRITE failure (a non-empty directory at the path) warns and lets a clean merge through', () {
      final work = _scenario(collide: false, withinFile: true, ignoreIndex: true);
      Directory('$work/docs/audit/OPEN_INDEX.md').createSync();
      File('$work/docs/audit/OPEN_INDEX.md/keep.txt').writeAsStringSync('x');
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, 0,
          reason: 'validation passed; only the write of a regenerable output failed.\n${out(merge)}');
      expect(out(merge), contains('could not write'));
      expect(File('$work/docs/audit/OPEN_INDEX.md/keep.txt').existsSync(), isTrue, // file-only: fixture file
          reason: 'a directory with content is reported, never deleted');
    });

    test('...while a duplicate OI still blocks when the write would also fail', () {
      final work = _scenario(collide: true, withinFile: true, ignoreIndex: true);
      Directory('$work/docs/audit/OPEN_INDEX.md').createSync();
      File('$work/docs/audit/OPEN_INDEX.md/keep.txt').writeAsStringSync('x');
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, isNot(0), reason: out(merge));
      expect(out(merge), contains('did not validate'));
    });
  });

  group('A2: a TRACKED OPEN_INDEX.md keeps the pre-A2 path byte for byte', () {
    test('backed up, rebuilt to validate, RESTORED, NOTE printed, nothing staged', () {
      final work = _scenario(collide: false, withinFile: true, trackIndex: true);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, 0, reason: out(merge));
      expect(File('$work/docs/audit/OPEN_INDEX.md').readAsStringSync(), 'stale tracked index\n',
          reason: 'a tracked file is restored exactly as the merge left it');
      expect(out(merge), contains('stale relative to the merged'),
          reason: 'the tracked path still tells the user to regenerate and commit');
      expect(
          _run('git', ['diff', '--cached', '--name-only'], work).stdout.toString().trim(), isEmpty);
      expect(_run('git', ['status', '--porcelain'], work).stdout.toString().trim(), isEmpty);
    });
  });

  // A builder that exits with something other than its own contract (0 / 1 / 3): a crash is 254
  // (a compile error, an uncaught exception), a mistaken argument 2. The hook's rule is "exit 3
  // warns, ANYTHING else non-zero blocks"; three plausible rewrites of it (`-eq 1`, `-ge 3`, a
  // wider warn branch) each wave a crashed validator through with no message.
  group('A2: a builder that does not follow its exit-code contract blocks the merge', () {
    for (final code in const [1, 2, 254]) {
      test('exit $code from the board builder -> the merge is BLOCKED, never reported as a write failure', () {
        final work = _scenario(collide: false, withinFile: true, ignoreIndex: true, builderExit: code);
        final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
        expect(out(merge), isNot(contains('CONFLICT')), reason: 'the fixture must be a CLEAN auto-merge');
        expect(merge.exitCode, isNot(0), reason: 'exit $code must not be waved through\n${out(merge)}');
        expect(out(merge), contains('did not validate'));
        expect(out(merge), isNot(contains('could not write')),
            reason: 'only exit 3 means "validation passed, the write failed"');
      });
    }
  });

  group('A2: a TRACKED OPEN_INDEX.md that .gitignore ALSO matches is still tracked', () {
    test('the pre-A2 path runs: backed up, rebuilt, RESTORED, nothing staged, a clean tree', () {
      // `git check-ignore` WITHOUT --no-index never reports a tracked path as ignored. Adding
      // --no-index (a natural-looking change) would turn this into the validate-only path, which
      // keeps the rebuilt file and leaves a tracked file modified after every merge.
      final work = _scenario(collide: false, withinFile: true, trackIndex: true, ignoreIndex: true);
      expect(_run('git', ['ls-files', '--', 'docs/audit/OPEN_INDEX.md'], work).stdout.toString().trim(),
          'docs/audit/OPEN_INDEX.md',
          reason: 'precondition: tracked');
      expect(_run('git', ['check-ignore', '-q', '--', 'docs/audit/OPEN_INDEX.md'], work).exitCode, 1,
          reason: 'precondition: git says a tracked path is NOT ignored');
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, 0, reason: out(merge));
      expect(File('$work/docs/audit/OPEN_INDEX.md').readAsStringSync(), 'stale tracked index\n',
          reason: 'restored exactly as the merge left it');
      expect(_run('git', ['status', '--porcelain'], work).stdout.toString().trim(), isEmpty,
          reason: 'no tracked file may be left modified by the hook');
      expect(out(merge), contains('stale relative to the merged'));
    });
  });

  // Hooks are copies: for a while after A2 merges, a machine runs the FROZEN A0 hook against an
  // A2 tree (the tree moves with `git merge --ff-only`, the hook only with `setup-hooks.sh`).
  group('A2: the OLD (A0) hook against an A2 tree', () {
    test('a within-file duplicate OI is still BLOCKED (the A2 builder fails closed for the old hook too)', () {
      final work = _scenario(collide: true, withinFile: true, ignoreIndex: true, oldHook: true);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, isNot(0), reason: out(merge));
      expect(out(merge), contains('OI-5'));
      expect(out(merge), contains('did not validate'));
    });

    test('a clean merge is allowed and leaves nothing staged', () {
      final work = _scenario(collide: false, withinFile: true, ignoreIndex: true, oldHook: true);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, 0, reason: out(merge));
      expect(_run('git', ['diff', '--cached', '--name-only'], work).stdout.toString().trim(), isEmpty);
    });

    test('a STALE ignored index on disk: the old hook puts the stale copy BACK and tells the user to `git add` it', () {
      // The two differences the SessionStart warning names. The old hook knows only "tracked or not":
      // an index that exists is backed up, rebuilt to validate, compared, and RESTORED, and the
      // difference is reported with advice that fails for an ignored path (`git add` exits 1).
      final work = _scenario(collide: false, withinFile: true, ignoreIndex: true, staleOnDisk: true, oldHook: true);
      final merge = _run('git', ['merge', '--no-edit', 'feature'], work);
      expect(merge.exitCode, 0, reason: out(merge));
      expect(File('$work/docs/audit/OPEN_INDEX.md').readAsStringSync(), 'stale ignored index\n',
          reason: 'the old hook restores what it found');
      expect(out(merge), contains('git add docs/audit/OPEN_INDEX.md'),
          reason: 'advice that no longer applies: the path is ignored');
      expect(_run('git', ['status', '--porcelain'], work).stdout.toString().trim(), isEmpty);
    });
  });
}
