// E2E for scripts/check_skill_tuning_history.dart — runs the REAL gate against a
// real git repo with a real staged index.
//
// The pure test covers the predicate. This covers the half the predicate cannot
// see: that the gate reads the STAGED blob (not the working tree), that it exits
// non-zero on a violation, and that it fails OPEN rather than wedging a commit.
//
// The staged-vs-working-tree distinction is not theoretical. OI-72 found a review
// file could satisfy the catastrophic gate while never entering history, because
// the gate read the working tree. A test that only wrote files to disk without
// staging them would pass against a gate carrying that same bug.

// File-level timeout: this spawns REAL `dart run` subprocesses, each paying the
// flutter/bin/dart wrapper cost (3.4-10.5s for a no-op per CLAUDE.md). The
// default 30s holds when run alone and does not when the full suite runs many
// files in parallel. Sibling e2e files all carry one; this one did not, and the
// full suite is what surfaced it.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

/// Subprocess environment with git/CI leakage removed.
///
/// git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into every hook, and
/// they override BOTH `workingDirectory:` and `git -C <path>`. Without this the
/// fixture silently reads the REAL repo whenever the suite runs inside
/// pre-commit (feedback_mistake_git_hook_env_leak). Removed, not set to '' —
/// an empty GIT_DIR is still an override.
/// (Now done by the shared spawn helper: `runSpawn` / `hermeticEnvironment`.)
late final String _gate;
late final String _lib;

ProcessResult _git(String cwd, List<String> args) => runSpawn(
      'git',
      args,
      why: 'git ${args.join(' ')} in the skill-tuning fixture',
      workingDirectory: cwd,
      runInShell: true,
    );

ProcessResult _runGate(String cwd, {List<String> args = const []}) =>
    runSpawn(
      dartBin(),
      ['run', 'scripts/check_skill_tuning_history.dart', ...args],
      why: 'check_skill_tuning_history.dart against a fixture repo',
      workingDirectory: cwd,
      runInShell: true,
    );

const _skillWithEntry = '''
# Code Review (B-pass)

## 7. Tuning history

- **2026-08-25** — blast-radius **account** — 4 findings; 0 false_alarm.
  Review: docs/reviews/2e9503eb-review.md
''';

const _skillWithoutEntry = '''
# Code Review (B-pass)

## 7. Tuning history

- **2026-08-20** — blast-radius **account** — 2 findings; 0 false_alarm.
''';

const _review = '''---
reviewed_at: 2026-08-25T09:30:00+05:30
staged_against: 2e9503eb
verdict: accepted
---

# Code Review — 2e9503eb
''';

/// A real git repo carrying the gate + its lib, with [files] STAGED.
Directory _repo(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('skilltuning_e2e_');
  final root = dir.path;
  Directory('$root/scripts').createSync(recursive: true);
  File('$root/scripts/check_skill_tuning_history.dart')
      .writeAsStringSync(File(_gate).readAsStringSync());
  File('$root/scripts/skill_tuning_lib.dart')
      .writeAsStringSync(File(_lib).readAsStringSync());

  _git(root, ['init', '-q']);
  _git(root, ['config', 'user.email', 't@t.t']);
  _git(root, ['config', 'user.name', 't']);
  // Seed a commit so HEAD exists — the gate falls back to HEAD for the skill
  // file when it is not staged, and that path must be exercisable.
  File('$root/seed.txt').writeAsStringSync('seed\n');
  _git(root, ['add', 'seed.txt']);
  _git(root, ['commit', '-q', '-m', 'seed']);

  files.forEach((rel, body) {
    final f = File('$root/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
    _git(root, ['add', rel]);
  });
  return dir;
}


/// Remove a fixture directory without ever failing the test.
///
/// On Windows a child process that has just exited can still hold a handle into
/// the directory, and `deleteSync` then throws PathAccessException — which the
/// full suite reported as a SECOND failure stacked on top of the real one (a
/// timeout), obscuring it. Cleanup is hygiene, not an assertion: the OS reaps
/// %TEMP% regardless, so a failure here must never redden a test.
void _cleanup(Directory d) {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
      return;
    } catch (_) {
      sleep(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  setUpAll(() {
    _gate = '${Directory.current.path}/scripts/check_skill_tuning_history.dart';
    _lib = '${Directory.current.path}/scripts/skill_tuning_lib.dart';
  });

  test('BLOCKS: a review added with no matching tuning entry', () {
    final d = _repo({
      'docs/reviews/2e9503eb-review.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));

    final r = _runGate(d.path);
    expect(r.exitCode, 1,
        reason: 'this is the 2026-08-25 omission, reproduced: a 4-finding '
            'review committed with the tuning history untouched');
    expect('${r.stdout}${r.stderr}', contains('2e9503eb'));
  });

  test('PASSES: the same review WITH its entry', () {
    final d = _repo({
      'docs/reviews/2e9503eb-review.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithEntry,
    });
    addTearDown(() => _cleanup(d));
    expect(_runGate(d.path).exitCode, 0);
  });

  test('PASSES: a commit that adds no review at all', () {
    final d = _repo({'lib/whatever.dart': 'void main() {}\n'});
    addTearDown(() => _cleanup(d));
    expect(_runGate(d.path).exitCode, 0);
  });

  test('reads the STAGED blob, not the working tree', () {
    // Stage a skill file WITHOUT the entry, then fix the working-tree copy.
    // A gate reading the working tree would pass; the committed content is
    // still wrong, which is the OI-72 failure shape.
    final d = _repo({
      'docs/reviews/2e9503eb-review.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    File('${d.path}/.claude/skills/code-review/tuning-history.md')
        .writeAsStringSync(_skillWithEntry); // working tree only — NOT staged

    expect(_runGate(d.path).exitCode, 1,
        reason: 'what is committed is what must be checked');
  });

  test('--warn-only reports without blocking', () {
    final d = _repo({
      'docs/reviews/2e9503eb-review.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path, args: ['--warn-only']);
    expect(r.exitCode, 0);
    expect('${r.stdout}${r.stderr}', contains('WARN'));
  });

  test('an ABSENT archive no longer silences the gate (A1): no section -> BLOCKS', () {
    // This used to FAIL OPEN ("an unreadable input must never wedge a commit"). The
    // archive is only the legacy route now; the review's own `## Tuning entry`
    // section is judged regardless, so a missing archive proves nothing either way.
    final d = _repo({'docs/reviews/2e9503eb-review.md': _review});
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('2e9503eb'));
  });

  test('FAILS OPEN when the review carries no parseable date', () {
    final d = _repo({
      'docs/reviews/x-review.md': '# no frontmatter here\n',
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    expect(_runGate(d.path).exitCode, 0);
  });

  test('BLOCKS a `-bpass.md` review too — the MAJORITY naming convention', () {
    // Measured 2026-08-25: of 164 files in docs/reviews/, 81 end `-bpass.md`
    // and 79 end `-review.md`, and the skill Tuning history cites `-bpass.md`
    // for most recent entries. The first version of this gate matched only
    // `-review.md`, so it was blind to the more common name — the omission it
    // exists to catch, reopened by an over-narrow pattern. Round 1 found it.
    final d = _repo({
      'docs/reviews/some-batch-bpass.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));

    final r = _runGate(d.path);
    expect(r.exitCode, 1,
        reason: 'a bpass review is a review; the suffix is not the identity');
    expect('${r.stdout}${r.stderr}', contains('some-batch-bpass'));
  });

  test('P0: a same-dated entry about a DIFFERENT review does NOT satisfy this one',
      () {
    // Live at the time this was written: SKILL.md already carried a 2026-08-25
    // bullet for the oi60-client-blockers review, so the very next review
    // written that same day would have been reported SATISFIED by an entry
    // describing somebody else's batch. The gate built to stop the skill's
    // self-evolution loop decaying would have silently passed its own first
    // real use. Date alone is not identity.
    final d = _repo({
      'docs/reviews/a-totally-different-batch-bpass.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithEntry, // names 2e9503eb
    });
    addTearDown(() => _cleanup(d));

    final r = _runGate(d.path);
    expect(r.exitCode, 1,
        reason: 'the 2026-08-25 entry describes 2e9503eb, not this review');
    expect('${r.stdout}${r.stderr}', contains('a-totally-different-batch'));
  });

  test('the generated INDEX.md is NOT treated as a review', () {
    final d = _repo({
      'docs/reviews/INDEX.md': '# Reviews',
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    expect(_runGate(d.path).exitCode, 0);
  });

  test('a dateless file does not MASK a dated one that is missing its entry',
      () {
    // The first version returned undetermined the moment ANY candidate was
    // unparseable, so one stray .md silenced the gate for a real review beside
    // it. The dated one must still be judged.
    final d = _repo({
      'docs/reviews/stray-notes.md': '# no frontmatter',
      'docs/reviews/real-bpass.md': _review,
      '.claude/skills/code-review/tuning-history.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('real-bpass'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // merge-conflict-treadmill A1: the entry lives INSIDE the review; the archive
  // is frozen on non-merge commits; renames are not a way around the gate.
  // ─────────────────────────────────────────────────────────────────────────
  group('A1: in-review entry, frozen archive', () {
    const archive = '.claude/skills/code-review/tuning-history.md';
    const intro = '# Code Review tuning history\n\n## 7. Tuning history\n\n';
    const entryA = '- **2026-08-20** — blast-radius **account** — 2 findings.\n  Review: docs/reviews/old-bpass.md\n';
    const entryB = '- **2026-08-21** — blast-radius **account** — 1 finding.\n  Review: docs/reviews/old2-bpass.md\n';
    const withSection = '''---
reviewed_at: 2026-10-24T10:00:00+05:30
blast_radius: platform
---

# Review

## Tuning entry
- **2026-10-24** - blast-radius **platform** - 1 finding; 0 false_alarm; tuning: none.
''';
    const noSection = '---\nreviewed_at: 2026-10-24T10:00:00+05:30\nblast_radius: platform\n---\n\n# Review\n';

    Directory initRepo() {
      final dir = Directory.systemTemp.createTempSync('skilltuning_a1_');
      final root = dir.path;
      Directory('$root/scripts').createSync(recursive: true);
      File('$root/scripts/check_skill_tuning_history.dart').writeAsStringSync(File(_gate).readAsStringSync());
      File('$root/scripts/skill_tuning_lib.dart').writeAsStringSync(File(_lib).readAsStringSync());
      _git(root, ['init', '-q', '-b', 'main']);
      _git(root, ['config', 'user.email', 't@t.t']);
      _git(root, ['config', 'user.name', 't']);
      addTearDown(() => _cleanup(dir));
      return dir;
    }

    void put(String root, Map<String, String> files, {bool stage = true}) {
      files.forEach((rel, body) {
        final f = File('$root/$rel');
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(body);
        if (stage) _git(root, ['add', rel]);
      });
    }

    void commit(String root, Map<String, String> files, String msg) {
      put(root, files);
      _git(root, ['commit', '-q', '-m', msg]);
    }

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    test('a `## Tuning entry` section satisfies the gate with the archive ABSENT', () {
      final d = initRepo();
      commit(d.path, {'seed.txt': 's\n'}, 'seed');
      put(d.path, {'docs/reviews/new-bpass.md': withSection});
      final r = _runGate(d.path);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('PASS'));
    });

    test('BLOCKS: a review with no section, naming the heading and the template', () {
      final d = initRepo();
      commit(d.path, {'seed.txt': 's\n'}, 'seed');
      put(d.path, {'docs/reviews/new-bpass.md': noSection});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), allOf(contains('no `## Tuning entry` heading'), contains('## Tuning entry'), contains('2026-10-24')));
    });

    test('BLOCKS: wrong date and a tier mismatch inside the section', () {
      final d = initRepo();
      commit(d.path, {'seed.txt': 's\n'}, 'seed');
      put(d.path, {'docs/reviews/a-bpass.md': withSection.replaceFirst('- **2026-10-24**', '- **2026-10-23**')});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('2026-10-23'));
      _git(d.path, ['reset', '-q']);
      File('${d.path}/docs/reviews/a-bpass.md').deleteSync();
      put(d.path, {'docs/reviews/b-bpass.md': withSection.replaceFirst('blast-radius **platform**', 'blast-radius **account**')});
      final r2 = _runGate(d.path);
      expect(r2.exitCode, 1, reason: out(r2));
      expect(out(r2), allOf(contains('account'), contains('platform')));
    });

    test('FREEZE: a non-merge commit that grows the archive fails, with the restore command', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryB'});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), allOf(contains('FROZEN'), contains('git restore --source=HEAD --staged --worktree'), contains('2026-08-21')));
    });

    test('FREEZE holds even when the commit also adds a valid review (the codes combine)', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryB', 'docs/reviews/new-bpass.md': withSection});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('FROZEN'));
    });

    test('FREEZE: shrinking the archive passes; so does an in-place edit of a header', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA$entryB'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA'});
      expect(_runGate(d.path).exitCode, 0, reason: 'shrink');
      put(d.path, {archive: '$intro$entryA$entryB'.replaceFirst('2 findings', '3 findings (edited)')});
      expect(_runGate(d.path).exitCode, 0, reason: 'in-place edit keeps the count');
    });

    test('FREEZE: a staged-only archive (no HEAD blob) is not growth', () {
      // Kills "HEAD-absent counted as zero": a brand-new archive file with entries would
      // otherwise read as growth and block the commit that introduces it.
      final d = initRepo();
      commit(d.path, {'seed.txt': 's\n'}, 'seed');
      put(d.path, {archive: '$intro$entryA$entryB'});
      final r = _runGate(d.path);
      expect(r.exitCode, 0, reason: out(r));
    });

    test('FREEZE: --warn-only reports without blocking', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryB'});
      final r = _runGate(d.path, args: ['--warn-only']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), allOf(contains('WARN'), contains('FROZEN')));
      expect('${r.stdout}', allOf(contains('WARN'), contains('FROZEN')), reason: 'warn-only writes to stdout');
      expect('${r.stderr}', isEmpty, reason: 'warn-only must not write to stderr');
    });

    test('a dated SUB-bullet counts as growth', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA  - **2026-08-22** - sub-bullet\n'});
      expect(_runGate(d.path).exitCode, 1);
    });

    test('FREEZE: the output lists at most 5 added entries, counts all of them, prints FAIL on stderr and no PASS', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      final seven = [for (var i = 1; i <= 7; i++) '- **2026-09-0$i** - blast-radius **account** - n.\n'].join();
      put(d.path, {archive: '$intro$entryA$seven'});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('adds 7 dated entries'));
      expect('+ - **2026-09-0'.allMatches(out(r)).length, 5, reason: 'the list is capped at 5\n${out(r)}');
      expect('${r.stderr}', contains('FAIL'));
      expect(out(r), isNot(contains('PASS')), reason: 'a PASS line beside the FAIL reads as a contradiction');
    });

    test('FREEZE: a DUPLICATED header is growth and is reported as exactly one added entry', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryA'});
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), allOf(contains('adds 1 dated entry'), contains('+ - **2026-08-20**')));
    });

    test('the review section is read from the STAGED blob: a working-tree-only section does not count', () {
      final d = initRepo();
      commit(d.path, {'seed.txt': 's\n'}, 'seed');
      put(d.path, {'docs/reviews/new-bpass.md': noSection});
      put(d.path, {'docs/reviews/new-bpass.md': withSection}, stage: false);
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: 'what is committed is what must be checked\n${out(r)}');
    });

    test('the freeze reads the STAGED archive: growth staged and then undone in the working tree still fails', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryB'});
      put(d.path, {archive: '$intro$entryA'}, stage: false);
      final r = _runGate(d.path);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('FROZEN'));
    });

    test('the freeze reads the STAGED archive: growth only in the working tree is not this commit', () {
      final d = initRepo();
      commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
      put(d.path, {archive: '$intro$entryA$entryB'}, stage: false);
      expect(_runGate(d.path).exitCode, 0);
    });

    test('MODIFYING an existing review (status M) is not an add: it needs no section', () {
      final d = initRepo();
      commit(d.path, {'docs/reviews/old-bpass.md': noSection}, 'review');
      put(d.path, {'docs/reviews/old-bpass.md': '${noSection}triage note\n'});
      final r = _runGate(d.path);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('no review file added'));
    });

    group('mid-merge exemption', () {
      /// main and branch b both change things; `git merge --no-commit --no-ff b` leaves
      /// MERGE_HEAD and a staged merged archive that is LONGER than HEAD's.
      Directory merging({Map<String, String> base = const {}, Map<String, String> onB = const {}}) {
        final d = initRepo();
        commit(d.path, {'seed.txt': 's\n', archive: '$intro$entryA', ...base}, 'base');
        _git(d.path, ['checkout', '-q', '-b', 'b']);
        commit(d.path, onB, 'branch work');
        _git(d.path, ['checkout', '-q', 'main']);
        commit(d.path, {'main-only.txt': 'm\n'}, 'main work');
        _git(d.path, ['merge', '--no-commit', '--no-ff', 'b']);
        return d;
      }

      test('a merge that brings archive growth from the other side is exempt', () {
        final d = merging(onB: {archive: '$intro$entryA$entryB'});
        expect(File('${d.path}/.git/MERGE_HEAD').existsSync(), isTrue);
        final r = _runGate(d.path);
        expect(r.exitCode, 0, reason: out(r));
      });

      test('a LEGACY review (archive entry, no section) arriving through a merge passes', () {
        final d = merging(onB: {
          'docs/reviews/old2-bpass.md': noSection.replaceAll('2026-10-24', '2026-08-21'),
          archive: '$intro$entryA$entryB',
        });
        final r = _runGate(d.path);
        expect(r.exitCode, 0, reason: out(r));
        expect(out(r), contains('PASS'));
      });

      test('a review arriving through a merge is still JUDGED: no entry anywhere fails', () {
        final d = merging(onB: {'docs/reviews/orphan-bpass.md': noSection});
        final r = _runGate(d.path);
        expect(r.exitCode, 1, reason: out(r));
        expect(out(r), contains('orphan-bpass'));
      });

      test('a linked worktree mid-merge is exempt (MERGE_HEAD lives under the common dir)', () {
        // Kills a hardcoded `.git/MERGE_HEAD`: in a linked worktree `.git` is a FILE.
        final d = initRepo();
        commit(d.path, {'seed.txt': 's\n', archive: '$intro$entryA'}, 'base');
        _git(d.path, ['checkout', '-q', '-b', 'b']);
        commit(d.path, {archive: '$intro$entryA$entryB'}, 'branch work');
        _git(d.path, ['checkout', '-q', 'main']);
        final wt = '${d.path}-wt';
        _git(d.path, ['worktree', 'add', '-q', '-b', 'wtb', wt]);
        addTearDown(() => _cleanup(Directory(wt)));
        Directory('$wt/scripts').createSync(recursive: true);
        File('$wt/scripts/check_skill_tuning_history.dart').writeAsStringSync(File(_gate).readAsStringSync());
        File('$wt/scripts/skill_tuning_lib.dart').writeAsStringSync(File(_lib).readAsStringSync());
        _git(wt, ['config', 'user.email', 't@t.t']);
        _git(wt, ['config', 'user.name', 't']);
        _git(wt, ['merge', '--no-commit', '--no-ff', 'b']);
        expect(File('$wt/.git').statSync().type, FileSystemEntityType.file, reason: 'a linked worktree');
        final r = _runGate(wt);
        expect(r.exitCode, 0, reason: out(r));
      });

      for (final asDir in [true, false]) {
        test('MERGE_HEAD present as ${asDir ? "a directory" : "an empty file"} is treated as mid-merge', () {
          // Portable (no chmod 000): existence is the test, not readability.
          final d = initRepo();
          commit(d.path, {archive: '$intro$entryA'}, 'seed archive');
          put(d.path, {archive: '$intro$entryA$entryB'});
          expect(_runGate(d.path).exitCode, 1, reason: 'no MERGE_HEAD yet: frozen');
          if (asDir) {
            Directory('${d.path}/.git/MERGE_HEAD').createSync();
          } else {
            File('${d.path}/.git/MERGE_HEAD').writeAsStringSync('');
          }
          final r = _runGate(d.path);
          expect(r.exitCode, 0, reason: out(r));
        });
      }
    });

    group('renames', () {
      test('a renamed review WITHOUT a section fails; WITH a section passes', () {
        final d = initRepo();
        commit(d.path, {'docs/reviews/old-bpass.md': noSection}, 'review');
        _git(d.path, ['mv', 'docs/reviews/old-bpass.md', 'docs/reviews/renamed-bpass.md']);
        final r = _runGate(d.path);
        expect(r.exitCode, 1, reason: 'git hides the add behind a rename unless --no-renames\n${out(r)}');
        expect(out(r), contains('renamed-bpass'));

        put(d.path, {'docs/reviews/renamed-bpass.md': withSection});
        expect(_runGate(d.path).exitCode, 0);
      });

      test('a rename arriving through a MERGE is not forced through --no-renames', () {
        final d = initRepo();
        commit(d.path, {'seed.txt': 's\n', 'docs/reviews/old-bpass.md': noSection}, 'base');
        _git(d.path, ['checkout', '-q', '-b', 'b']);
        _git(d.path, ['mv', 'docs/reviews/old-bpass.md', 'docs/reviews/new-bpass.md']);
        _git(d.path, ['commit', '-q', '-m', 'rename on branch']);
        _git(d.path, ['checkout', '-q', 'main']);
        commit(d.path, {'main-only.txt': 'm\n'}, 'main work');
        _git(d.path, ['merge', '--no-commit', '--no-ff', 'b']);
        final r = _runGate(d.path);
        expect(r.exitCode, 0,
            reason: 'with --no-renames always on, new-bpass.md would read as an ADD and block every sync '
                'that carries a rename from main\n${out(r)}');
      });
    });
  });
}
