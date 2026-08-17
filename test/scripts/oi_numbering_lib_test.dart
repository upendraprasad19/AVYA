// test/scripts/oi_numbering_lib_test.dart
//
// Unit tests for scripts/oi_numbering_lib.dart (the pure three-point predicate)
// plus an END-TO-END group that runs the REAL scripts/check_oi_numbering_unique.dart
// against real throwaway git repos.
//
// WHY BOTH. The predicate is pure and cheap to test, but this gate's one live
// failure was NOT in the predicate -- it was in the plumbing. The first
// end-to-end run against a branch KNOWN to be colliding reported PASS, because
// Process.runSync defaults to `systemEncoding`, which mangled the board's
// em-dash separator so `oiSectionRe` matched 0 of 77 headings. The predicate
// was correct throughout and every unit test would have passed. Only executing
// the gate against real git data exposed it. See the `e2e` group's
// 'unparseable mainline board' test, which pins the STRUCTURAL fix: an
// unreadable board must be UNDETERMINED, never clean.
//
// ENV SCRUBBING: run inside `pre-commit`, a test spawning git children inherits
// GIT_DIR / GIT_WORK_TREE, which override both `workingDirectory:` and
// `-C <path>` (feedback_mistake_git_hook_env_leak).

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/oi_numbering_lib.dart';

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

Map<String, String> _cleanEnv() {
  final env = <String, String>{};
  Platform.environment.forEach((k, v) {
    final u = k.toUpperCase();
    if (u.startsWith('GIT_')) return;
    if (u == 'GITHUB_EVENT_PATH' || u == 'GITHUB_REF' || u == 'PUSH_BEFORE') return;
    env[k] = v;
  });
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe,
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void _git(String cwd, List<String> args) {
  final r = _run('git', args, cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(" ")} failed in $cwd:\n${r.stderr}');
  }
}

/// A board file with the given `number -> title` entries, in the real format.
String _board(Map<int, String> entries, {String heading = '# Open issues'}) {
  final b = StringBuffer('$heading\n\n');
  entries.forEach((n, t) {
    b.writeln('## OI-$n — $t');
    b.writeln();
    b.writeln('- **Status**: OPEN');
    b.writeln('- **Blocked on**: nothing');
    b.writeln('- **Verified**: never');
    b.writeln();
  });
  return b.toString();
}

void main() {
  // -------------------------------------------------------------------------
  group('parseBoard', () {
    test('reads `## OI-N — title` headings', () {
      final b = parseBoard(_board({7: 'seven', 42: 'forty two'}));
      expect(b, {7: 'seven', 42: 'forty two'});
    });

    test('ignores non-heading lines and other heading levels', () {
      const src = '''
# Title
### OI-9 — wrong level
Some prose mentioning OI-5 — not a heading.
## OI-3 — real
## Not an OI heading
''';
      expect(parseBoard(src), {3: 'real'});
    });

    test('requires the em-dash separator the real board uses', () {
      // A hyphen is NOT the separator. This is the exact property the
      // systemEncoding bug destroyed -- pinning it here means a future encoding
      // regression shows up as a parse failure rather than a silent clean pass.
      expect(parseBoard('## OI-3 - hyphen not em-dash'), isEmpty);
      expect(parseBoard('## OI-3 — em-dash'), {3: 'em-dash'});
    });

    test('empty input yields an empty map, not an error', () {
      expect(parseBoard(''), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('findCollisions — the three legs', () {
    test('fires when the branch mints a number mainline also minted', () {
      final c = findCollisions(
        base: {1: 'one'},
        head: {1: 'one', 9: 'branch nine'},
        mainline: {1: 'one', 9: 'mainline nine'},
      );
      expect(c, hasLength(1));
      expect(c.single.number, 9);
      expect(c.single.headTitle, 'branch nine');
      expect(c.single.mainlineTitle, 'mainline nine');
    });

    test('LEG 1: a title EDIT to a pre-existing number is not a collision', () {
      // The false positive a two-point comparison would produce, and the reason
      // the merge-base is in the predicate at all.
      final c = findCollisions(
        base: {5: 'original wording'},
        head: {5: 'reworded on this branch'},
        mainline: {5: 'original wording'},
      );
      expect(c, isEmpty);
    });

    test('LEG 2: a number only this branch has is not a collision', () {
      final c = findCollisions(
        base: {1: 'one'},
        head: {1: 'one', 2: 'brand new'},
        mainline: {1: 'one'},
      );
      expect(c, isEmpty);
    });

    test('LEG 3: same number, same title = already carries mainline\'s entry', () {
      // Merged, rebased or cherry-picked. Not a collision.
      final c = findCollisions(
        base: {1: 'one'},
        head: {1: 'one', 9: 'shared issue'},
        mainline: {1: 'one', 9: 'shared issue'},
      );
      expect(c, isEmpty);
    });

    test('LEG 3 normalizes whitespace and case, not meaning', () {
      expect(
        findCollisions(
          base: {},
          head: {9: '  Shared   Issue '},
          mainline: {9: 'shared issue'},
        ),
        isEmpty,
      );
      expect(
        findCollisions(
          base: {},
          head: {9: 'shared issue but different'},
          mainline: {9: 'shared issue'},
        ),
        hasLength(1),
      );
    });

    test('reports every colliding number, sorted', () {
      final c = findCollisions(
        base: {},
        head: {12: 'b12', 3: 'b3', 7: 'b7'},
        mainline: {3: 'm3', 7: 'm7', 12: 'm12'},
      );
      expect(c.map((e) => e.number), [3, 7, 12]);
    });
  });

  // -------------------------------------------------------------------------
  group('mergeBoards / crossFileDuplicates / nextFreeNumber', () {
    test('open and closed share ONE number space', () {
      expect(mergeBoards({1: 'o'}, {2: 'c'}), {1: 'o', 2: 'c'});
    });

    test('a number on BOTH boards is reported, not silently merged away', () {
      final d = crossFileDuplicates({4: 'open four'}, {4: 'closed four'});
      expect(d, hasLength(1));
      expect(d.single.number, 4);
      expect(d.single.openTitle, 'open four');
      expect(d.single.closedTitle, 'closed four');
    });

    test('nextFreeNumber spans BOTH boards — the split that causes the bug', () {
      // Eyeballing only open_issues.md is exactly how a taken number gets
      // re-minted; the ceiling must come from the union.
      expect(nextFreeNumber([{10: 'a'}, {124: 'b'}]), 125);
      expect(nextFreeNumber([]), 1);
      expect(nextFreeNumber([<int, String>{}]), 1);
    });
  });

  // -------------------------------------------------------------------------
  group('e2e — the real gate against real repos', () {
    late String gate;
    late String lib;
    late Directory tmp;

    setUpAll(() {
      gate = File('scripts/check_oi_numbering_unique.dart').absolute.path;
      lib = File('scripts/oi_numbering_lib.dart').absolute.path;
      expect(File(gate).existsSync(), isTrue);
      expect(File(lib).existsSync(), isTrue);
    });

    setUp(() => tmp = Directory.systemTemp.createTempSync('oinum_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows handle lag */}
    });

    /// Builds `origin` (bare) + `main` + a feature branch, each with its own
    /// board, and returns the feature checkout's path with the gate copied in.
    String _scenario({
      required Map<int, String> baseOpen,
      required Map<int, String> mainOpen,
      required Map<int, String> branchOpen,
      Map<int, String> branchClosed = const {},
    }) {
      final origin = '${tmp.path}/origin.git';
      final work = '${tmp.path}/work';
      _run('git', ['init', '--bare', '-b', 'main', origin], tmp.path);
      _run('git', ['init', '-b', 'main', work], tmp.path);
      _git(work, ['config', 'user.email', 't@t.t']);
      _git(work, ['config', 'user.name', 't']);
      Directory('$work/docs/audit').createSync(recursive: true);
      Directory('$work/scripts').createSync(recursive: true);

      void writeBoards(Map<int, String> open, Map<int, String> closed) {
        File('$work/docs/audit/open_issues.md')
            .writeAsStringSync(_board(open), encoding: utf8);
        File('$work/docs/audit/closed_issues.md').writeAsStringSync(
            _board(closed, heading: '# Closed issues'),
            encoding: utf8);
      }

      // Base commit -> becomes the merge-base.
      writeBoards(baseOpen, const {});
      _git(work, ['add', '-A']);
      _git(work, ['commit', '-m', 'base']);
      _git(work, ['remote', 'add', 'origin', origin]);
      _git(work, ['push', '-u', 'origin', 'main']);

      // Feature branch off the base.
      _git(work, ['checkout', '-b', 'feature']);

      // main advances independently (committed on main, pushed to origin).
      _git(work, ['checkout', 'main']);
      writeBoards(mainOpen, const {});
      _git(work, ['add', '-A']);
      // --allow-empty: some scenarios deliberately give main the SAME board as
      // the base (e.g. the title-edit case), so there is nothing to commit and
      // a plain `git commit` exits non-zero. The commit still has to exist —
      // it is what makes origin/main advance past the merge-base.
      _git(work, ['commit', '--allow-empty', '-m', 'main advances']);
      _git(work, ['push', 'origin', 'main']);

      // Back to the feature branch with its own board.
      _git(work, ['checkout', 'feature']);
      writeBoards(branchOpen, branchClosed);
      _git(work, ['add', '-A']);
      _git(work, ['commit', '--allow-empty', '-m', 'branch mints']);

      File(gate).copySync('$work/scripts/check_oi_numbering_unique.dart');
      File(lib).copySync('$work/scripts/oi_numbering_lib.dart');
      return work;
    }

    /// The Dart binary to spawn the gate with.
    ///
    /// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to
    /// the flutter_tester binary, not dart, so `<tester> run script.dart` never
    /// returns and the suite hangs instead of failing. Cost this suite one
    /// >10-minute hang before it was caught.
    ///
    /// The rest of the repo's e2e suites spawn a plain `'dart'` (PATH), which
    /// is the Flutter WRAPPER — ~4.0s of SDK-lock and git work per call, paid
    /// 8 times here. Prefer the SDK exe beside it, exactly as
    /// scripts/_dart_bin.sh does, and fall back to `'dart'` so a layout this
    /// guess does not match still runs.
    String _dartBin() {
      final override = Platform.environment['DART_BIN_OVERRIDE'];
      if (override != null && File(override).existsSync()) return override;
      final which = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        ['dart'],
        stdoutEncoding: utf8,
      );
      if (which.exitCode == 0) {
        final first = (which.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) {
          final dir = File(first).parent.path.replaceAll(r'\', '/');
          for (final c in [
            '$dir/cache/dart-sdk/bin/dart.exe',
            '$dir/cache/dart-sdk/bin/dart',
          ]) {
            if (File(c).existsSync()) return c;
          }
        }
      }
      return 'dart';
    }

    ProcessResult _runGate(String cwd) =>
        _run(_dartBin(), ['run', 'scripts/check_oi_numbering_unique.dart'], cwd);

    test('FAILS on a real cross-branch collision', () {
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one', 2: 'branch two'},
      );
      final r = _runGate(work);
      expect(r.exitCode, 1, reason: 'stdout:${r.stdout}\nstderr:${r.stderr}');
      expect(r.stderr, contains('OI-2'));
      expect(r.stderr, contains('branch two'));
      expect(r.stderr, contains('mainline two'));
      expect(r.stderr, contains('Next free is OI-3'));
    });

    test('PASSES when the branch mints an uncontested number', () {
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one', 3: 'branch three'},
      );
      final r = _runGate(work);
      expect(r.exitCode, 0, reason: 'stderr:${r.stderr}');
      expect(r.stdout, contains('PASS'));
    });

    test('PASSES when the branch only edits a pre-existing title', () {
      final work = _scenario(
        baseOpen: {1: 'one', 2: 'two'},
        mainOpen: {1: 'one', 2: 'two'},
        branchOpen: {1: 'one', 2: 'two, reworded on the branch'},
      );
      final r = _runGate(work);
      expect(r.exitCode, 0, reason: 'stderr:${r.stderr}');
    });

    test('FAILS when one number sits on BOTH boards', () {
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one'},
        branchOpen: {1: 'one', 5: 'open five'},
        branchClosed: {5: 'closed five'},
      );
      final r = _runGate(work);
      expect(r.exitCode, 1, reason: 'stdout:${r.stdout}\nstderr:${r.stderr}');
      expect(r.stderr, contains('BOTH boards'));
    });

    test('an UNPARSEABLE mainline board is UNDETERMINED, never clean', () {
      // THE REGRESSION THIS GATE ACTUALLY SHIPPED WITH, in structural form.
      // A mainline board full of content that yields zero headings must not be
      // read as "mainline claims no numbers", which would make every branch
      // number look uncontested and report a confident PASS.
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one', 2: 'branch two'},
      );
      // Rewrite origin/main's board with hyphens instead of em-dashes: real
      // bytes, real size, zero parseable headings -- exactly what a mis-decode
      // produces.
      _git(work, ['checkout', 'main']);
      File('$work/docs/audit/open_issues.md').writeAsStringSync(
          '# Open issues\n\n## OI-1 - one\n\n## OI-2 - mainline two\n',
          encoding: utf8);
      // Scoped add, NOT `-A`. _scenario copies the gate + lib into
      // work/scripts/ as UNTRACKED files; an `add -A` here commits them onto
      // main, and the `checkout feature` below then DELETES them because
      // feature does not track them. The gate dies with "Could not find file"
      // (exit 255) and the test reports a crash instead of the behaviour it is
      // asserting -- which is exactly what happened before this comment.
      _git(work, ['add', 'docs/audit/open_issues.md']);
      _git(work, ['commit', '-m', 'mangle']);
      _git(work, ['push', 'origin', 'main']);
      _git(work, ['checkout', 'feature']);

      final r = _runGate(work);
      expect(r.exitCode, 0,
          reason: 'fails OPEN, it is an undetermined input.\n'
              'stdout: ${r.stdout}\nstderr: ${r.stderr}');
      expect(r.stderr, contains('ZERO parsed'),
          reason: 'must SAY the board did not parse, not stay quiet');
      expect(r.stderr, contains('em-dash'),
          reason: 'must name the likely cause, not just the symptom');
      expect(r.stderr, contains('UNDETERMINED'));
      expect(r.stdout, contains('SKIPPED'),
          reason: 'must say the check did not run');
      expect(r.stdout, isNot(contains('PASS:')),
          reason: 'must never print a clean verdict it did not earn');
    });

    test('no origin/main is UNDETERMINED, not clean', () {
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one', 2: 'branch two'},
      );
      _git(work, ['remote', 'remove', 'origin']);
      _run('git', ['update-ref', '-d', 'refs/remotes/origin/main'], work);
      final r = _runGate(work);
      expect(r.exitCode, 0, reason: 'offline must never wedge a commit');
      expect(r.stderr, contains('UNDETERMINED'));
    });

    test('--warn-only downgrades a real collision to exit 0', () {
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one', 2: 'branch two'},
      );
      final r = _run(_dartBin(),
          ['run', 'scripts/check_oi_numbering_unique.dart', '--warn-only'], work);
      expect(r.exitCode, 0);
      expect(r.stderr, contains('OI-2'), reason: 'still REPORTS, just does not block');
    });

    // ---- THE MERGE PLACEMENTS ---------------------------------------------
    //
    // Everything above returns the FEATURE checkout, so every scenario tested
    // the one placement where HEAD has diverged from origin/main. Review round
    // 1 (2026-08-17) showed the gate was a structural no-op at the other two
    // documented placements -- the pre-merge-commit hook and CI on a push to
    // main -- because there `merge-base(HEAD, origin/main) == origin/main`, so
    // `base == mainline`, and legs 1 and 2 become mutually exclusive: leg 3 is
    // unreachable for every possible input. Deleting the gate's invocation from
    // pre-merge-commit.sh would have reddened NOTHING.
    //
    // These two tests are the ones that would have caught that.

    // The shape MUST merge cleanly, or it tests nothing. A collision where both
    // sides append the same number to the SAME file conflicts textually, and
    // git stops -- that case was never the danger, because the operator sees it.
    // The dangerous shape, and the one every real incident took, is two
    // additions git can combine without complaint. Here main mints OI-2 on the
    // OPEN board while the branch mints OI-2 on the CLOSED board: different
    // files, guaranteed clean merge, and `mergeBoards` is what brings them back
    // into one number space where the clash is visible.
    String _cleanMergeScenario() => _scenario(
          baseOpen: {1: 'one'},
          mainOpen: {1: 'one', 2: 'mainline two'},
          branchOpen: {1: 'one'},
          branchClosed: {2: 'branch two'},
        );

    test('e2e — MID-MERGE (the pre-merge-commit placement) sees the collision',
        () {
      final work = _cleanMergeScenario();
      // Stand where the hook stands: on main, mid-merge.
      _git(work, ['checkout', 'main']);
      final merge =
          _run('git', ['merge', '--no-commit', '--no-ff', 'feature'], work);
      expect(merge.exitCode, 0,
          reason: 'the scenario must merge CLEANLY, else it exercises the case '
              'git already catches: ${merge.stdout}${merge.stderr}');
      expect(File('$work/.git/MERGE_HEAD').existsSync(), isTrue,
          reason: 'the mid-merge state is what this placement inspects');

      final r = _runGate(work);
      expect(r.exitCode, 1,
          reason: 'a collision landing THROUGH a clean merge is the whole point '
              'of this placement; exit 0 here means the gate is decorative');
      expect(r.stderr, contains('OI-2'));
      expect(r.stderr, contains('mid-merge'),
          reason: 'the verdict must name which comparison it made, so a reader '
              'can tell a real check from a degenerate one');
    });

    test('e2e — AT THE MERGE COMMIT (the CI-on-main placement) sees it too', () {
      final work = _cleanMergeScenario();
      _git(work, ['checkout', 'main']);
      _git(work, ['merge', '--no-ff', '--no-edit', 'feature']);
      // HEAD is now a 2-parent merge commit and, as on CI after a push to main,
      // HEAD is ahead of origin/main -- the exact shape that degenerated.
      final parents =
          _run('git', ['rev-list', '--parents', '-n', '1', 'HEAD'], work)
              .stdout
              .toString()
              .trim()
              .split(RegExp(r'\s+'));
      expect(parents.length, greaterThanOrEqualTo(3),
          reason: 'this test is meaningless unless HEAD really is a merge commit');

      final r = _runGate(work);
      expect(r.exitCode, 1,
          reason: 'CI is the authoritative placement; a landed collision must '
              'fail the build');
      expect(r.stderr, contains('OI-2'));
      expect(r.stderr, contains('merge commit'));
    });

    test('e2e — a clean merge with NO collision still passes at the merge commit',
        () {
      // The mirror. Without this, a gate that simply failed on every merge
      // would satisfy both tests above and be just as useless in the other
      // direction.
      final work = _scenario(
        baseOpen: {1: 'one'},
        mainOpen: {1: 'one', 2: 'mainline two'},
        branchOpen: {1: 'one'},
        branchClosed: {3: 'branch three'},
      );
      _git(work, ['checkout', 'main']);
      _git(work, ['merge', '--no-ff', '--no-edit', 'feature']);
      final r = _runGate(work);
      expect(r.exitCode, 0,
          reason: 'distinct numbers on both sides is the NORMAL merge; blocking '
              'it would make the hook unusable');
    });
  });
}
