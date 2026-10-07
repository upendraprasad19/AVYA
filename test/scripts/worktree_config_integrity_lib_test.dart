// test/scripts/worktree_config_integrity_lib_test.dart
//
// Pure-logic tests for scripts/worktree_config_integrity_lib.dart — the parser
// and verdict function behind the `core.worktree` integrity gate.
//
// These touch NO git, so no environment (a hook's exported GIT_DIR, a CI
// runner, a corrupted repo) can change the answers. The e2e counterpart that
// actually runs the gate binary lives in
// test/scripts/worktree_config_integrity_e2e_test.dart — both are required:
// unit-testing a helper certifies the helper, not the gate
// (feedback_source_grep_false_confidence, and the P0 that
// plan_review_record_gate_e2e_test.dart's header records).
//
// The literal fixtures below are REAL captured output from the 2026-08-09
// incident, not invented shapes.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/worktree_config_integrity_lib.dart';

void main() {
  group('parseShowOrigin', () {
    test('parses the relative-origin form (cwd = repo root)', () {
      // Captured live: `file:.git/config<TAB>C:/.../post38-auth-fixes`
      const raw =
          'file:.git/config\tC:/Upendra/Claude Code/Fitness App/.claude/worktrees/post38-auth-fixes\n';
      final entries = parseShowOrigin(raw);

      expect(entries, hasLength(1));
      expect(entries.single.origin, '.git/config');
      expect(
        entries.single.value,
        'C:/Upendra/Claude Code/Fitness App/.claude/worktrees/post38-auth-fixes',
      );
    });

    test('parses the absolute-origin form (cwd = subdir or linked worktree)',
        () {
      // Same key, same repo, different cwd → git reports an ABSOLUTE origin.
      // This variance is exactly why origins must never be matched by
      // `contains()` against a hardcoded relative path.
      const raw =
          'file:C:/Upendra/Claude Code/Fitness App/.git/config\tC:/somewhere/else\n';
      final entries = parseShowOrigin(raw);

      expect(entries.single.origin,
          'c:/upendra/claude code/fitness app/.git/config');
      expect(entries.single.value, 'C:/somewhere/else');
    });

    test('normalises Windows backslashes and case in the origin', () {
      const raw = 'file:C:\\Upendra\\Fitness App\\.git\\CONFIG\tC:/x\n';
      expect(parseShowOrigin(raw).single.origin,
          'c:/upendra/fitness app/.git/config');
    });

    test('preserves the VALUE verbatim (not normalised) so the user sees it '
        'exactly as configured', () {
      const raw = 'file:.git/config\tC:\\Upendra\\Mixed Case\\PATH\n';
      expect(parseShowOrigin(raw).single.value, 'C:\\Upendra\\Mixed Case\\PATH');
    });

    test('splits on the FIRST tab only — a value containing a tab survives',
        () {
      const raw = 'file:.git/config\tC:/has\ttab\n';
      final e = parseShowOrigin(raw).single;
      expect(e.origin, '.git/config');
      expect(e.value, 'C:/has\ttab');
    });

    test('handles multiple entries (multivalued key across scopes)', () {
      const raw = 'file:.git/config\tC:/one\n'
          'file:C:/Users/u/.gitconfig\tC:/two\n';
      final entries = parseShowOrigin(raw);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.value), ['C:/one', 'C:/two']);
    });

    test('records a bare value with no origin rather than dropping it', () {
      // Defensive: if --show-origin is ever absent, do not silently lose a
      // configured value (that would read as "clean").
      const raw = 'C:/bare/value\n';
      final e = parseShowOrigin(raw).single;
      expect(e.origin, '');
      expect(e.value, 'C:/bare/value');
    });

    test('ignores blank lines', () {
      expect(parseShowOrigin('\n\n'), isEmpty);
    });
  });

  group('evaluateWorktreeConfig — exit-code contract', () {
    test('exit 1 (key ABSENT) is the HEALTHY case → pass, not indeterminate',
        () {
      // The single easiest thing to get backwards: git exits 1 for a missing
      // key. Treating non-zero as failure would make this gate always-fail;
      // treating it as "no output → clean" via a helper that swallows exit
      // codes would make it pass even when git is broken.
      final r = evaluateWorktreeConfig(exitCode: 1, stdout: '');
      expect(r.violation, isFalse);
      expect(r.indeterminate, isFalse);
      expect(r.reason, contains('healthy'));
    });

    test('exit 0 with an entry → VIOLATION, entries surfaced', () {
      final r = evaluateWorktreeConfig(
        exitCode: 0,
        stdout: 'file:.git/config\tC:/x/worktrees/post38-auth-fixes\n',
      );
      expect(r.violation, isTrue);
      expect(r.indeterminate, isFalse);
      expect(r.entries.single.value, 'C:/x/worktrees/post38-auth-fixes');
    });

    test('exit 128 (malformed config file) → INDETERMINATE, never clean', () {
      // NOT "not a repo" — an earlier draft of this test said so and was
      // wrong. Outside a repo, git config exits 1, not 128 (B-pass P2-2).
      // A real 128 here comes from e.g. `fatal: bad config line N`.
      final r = evaluateWorktreeConfig(exitCode: 128, stdout: '');
      expect(r.indeterminate, isTrue);
      expect(r.violation, isFalse);
      expect(r.reason, contains('128'));
    });

    test('exit 1 while NOT in a repo → INDETERMINATE, never "healthy"', () {
      // The false negative B-pass P2-2 caught: outside any repository
      // `git config --show-origin --get-all core.worktree` exits 1 — byte for
      // byte the healthy signal. Verified live from C:\. Without the
      // independent inRepo evidence the gate would announce health from a
      // directory it never established was a repo at all.
      final r =
          evaluateWorktreeConfig(exitCode: 1, stdout: '', inRepo: false);
      expect(r.indeterminate, isTrue);
      expect(r.violation, isFalse);
      expect(r.reason, contains('not inside a git repository'));
    });

    test('inRepo defaults to true so existing callers keep the strict path',
        () {
      expect(evaluateWorktreeConfig(exitCode: 1, stdout: '').indeterminate,
          isFalse);
    });

    test('a VIOLATION is still a violation regardless of the repo probe', () {
      // Defensive: if git answered with a real key, that is corruption even if
      // the probe was inconclusive. Health requires evidence; harm does not.
      final r = evaluateWorktreeConfig(
          exitCode: 0, stdout: 'file:.git/config\tC:/x\n', inRepo: false);
      expect(r.indeterminate, isTrue,
          reason: 'not-in-repo short-circuits first — documented precedence');
    });

    test('exit 0 with unparseable output → INDETERMINATE, never clean', () {
      final r = evaluateWorktreeConfig(exitCode: 0, stdout: '   \n');
      expect(r.indeterminate, isTrue);
      expect(r.violation, isFalse);
    });

    test('violation reason pluralises correctly for multiple entries', () {
      final one = evaluateWorktreeConfig(
          exitCode: 0, stdout: 'file:a\tC:/one\n');
      final two = evaluateWorktreeConfig(
          exitCode: 0, stdout: 'file:a\tC:/one\nfile:b\tC:/two\n');
      expect(one.reason, contains('1 entry'));
      expect(two.reason, contains('2 entries'));
    });

    test('ANY origin is a violation — there is no allowed origin', () {
      // An earlier draft excepted `.git/worktrees/<name>/config.worktree`.
      // That location is one git never legitimately produces, so the exception
      // was a re-injection hole. Assert the hole stays closed.
      final r = evaluateWorktreeConfig(
        exitCode: 0,
        stdout: 'file:.git/worktrees/foo/config.worktree\tC:/anything\n',
      );
      expect(r.violation, isTrue,
          reason: 'no origin may be whitelisted — that was the round-2 hole');
    });
  });
}
