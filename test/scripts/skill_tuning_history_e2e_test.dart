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

/// Subprocess environment with git/CI leakage removed.
///
/// git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into every hook, and
/// they override BOTH `workingDirectory:` and `git -C <path>`. Without this the
/// fixture silently reads the REAL repo whenever the suite runs inside
/// pre-commit (feedback_mistake_git_hook_env_leak). Removed, not set to '' —
/// an empty GIT_DIR is still an override.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_');
  });
  return env;
}

late final String _gate;
late final String _lib;

ProcessResult _git(String cwd, List<String> args) => Process.runSync(
      'git',
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

ProcessResult _runGate(String cwd, {List<String> args = const []}) =>
    Process.runSync(
      'dart',
      ['run', 'scripts/check_skill_tuning_history.dart', ...args],
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
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
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
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
      '.claude/skills/code-review/SKILL.md': _skillWithEntry,
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
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    File('${d.path}/.claude/skills/code-review/SKILL.md')
        .writeAsStringSync(_skillWithEntry); // working tree only — NOT staged

    expect(_runGate(d.path).exitCode, 1,
        reason: 'what is committed is what must be checked');
  });

  test('--warn-only reports without blocking', () {
    final d = _repo({
      'docs/reviews/2e9503eb-review.md': _review,
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path, args: ['--warn-only']);
    expect(r.exitCode, 0);
    expect('${r.stdout}${r.stderr}', contains('WARN'));
  });

  test('FAILS OPEN when the skill file is absent entirely', () {
    final d = _repo({'docs/reviews/2e9503eb-review.md': _review});
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path);
    expect(r.exitCode, 0,
        reason: 'an unreadable input must never wedge a commit');
    expect('${r.stdout}${r.stderr}', contains('SKIPPED'));
  });

  test('FAILS OPEN when the review carries no parseable date', () {
    final d = _repo({
      'docs/reviews/x-review.md': '# no frontmatter here\n',
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
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
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
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
      '.claude/skills/code-review/SKILL.md': _skillWithEntry, // names 2e9503eb
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
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
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
      '.claude/skills/code-review/SKILL.md': _skillWithoutEntry,
    });
    addTearDown(() => _cleanup(d));
    final r = _runGate(d.path);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('real-bpass'));
  });
}
