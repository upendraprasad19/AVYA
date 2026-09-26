// test/contracts/hook_gate_placement_test.dart
//
// Pins WHERE the two expensive Flutter steps run, after the 2026-08-11 cost
// split (ADR-0018). scripts/pre-commit.sh cost ~14 min on EVERY commit
// regardless of diff size, and the two flutter steps dominated it; both moved
// to scripts/pre-push.sh, which fires once per batch rather than once per
// commit. (Exact per-phase seconds are contested between an in-session run and
// OI-102's board-verified figure — OI-102 owns that question. Nothing asserted
// in this file depends on the number.)
//
// TWO contracts, and the second is the one with teeth:
//
//   1. scripts/pre-commit.sh invokes flutter ONLY inside the two env-guarded
//      escape hatches (PRE_COMMIT_LEGACY / PRE_COMMIT_FULL). An unguarded call
//      creeping back re-imposes ~12 minutes on every commit, silently.
//
//   2. scripts/pre-push.sh runs `flutter analyze` ABOVE every early exit.
//      Asserted by CHARACTER INDEX, not presence — because presence is exactly
//      what the broken version also satisfies. PRE_PUSH_FULL, the origin/main
//      guard, the empty-range guard and the `feature`-tier skip ALL end in
//      `exit 0` (directly or via run_full_suite), so an analyze placed below
//      any of them never runs on the pushes that need it most. A feature-tier
//      BRANCH push skips the suite here, and if that branch has no open PR it
//      triggers no CI either (.github/workflows/test.yml fires on
//      `push: [main, develop]` + `pull_request` targeting them; of 28 non-main
//      branches on origin, 8 have a PR and ~20 do not). For that majority this
//      one call is the only compile check the push receives anywhere.
//
// The runtime counterpart is test/scripts/pre_push_analyze_always_e2e_test.dart,
// which executes the real script with a stub flutter and asserts analyze is the
// FIRST invocation. This file certifies the source order; that one certifies
// the order actually taken at runtime. Neither alone is sufficient.
//
// Comment-stripped per feedback_source_grep_strip_comments_first.md: both
// scripts discuss every one of these tokens at length in prose, so an
// unstripped grep would false-pass on the headers alone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An actual `flutter <subcommand>` INVOCATION in shell source.
///
/// Deliberately tolerant of arbitrary whitespace: round-2 review defeated a
/// two-literal matcher with `flutter  analyze` (double space).
///
/// Deliberately NARROW on the subcommand list rather than matching bare
/// `flutter`: the else branch legitimately contains prose like
/// `echo "... analyze + test suite run at pre-push"`, and a bare-word matcher
/// would red the suite for an echo. It also does not match the `flutter() {`
/// wrapper definition or its `flutter "$@"` body, neither of which is a call
/// to a subcommand.
final RegExp _flutterCall = RegExp(r'(?<![\w./-])flutter\s+(analyze|test|pub|build|run)\b');

void main() {
  late String preCommit;
  late String prePush;
  // RAW (comments intact) — Gate 32 reads the installed hook as a whole file,
  // comments included, so the anchor assertion below must too.
  late String preCommitRaw;

  setUpAll(() {
    final pc = File('scripts/pre-commit.sh');
    final pp = File('scripts/pre-push.sh');
    expect(pc.existsSync(), isTrue, reason: 'scripts/pre-commit.sh must exist');
    expect(pp.existsSync(), isTrue, reason: 'scripts/pre-push.sh must exist');
    preCommitRaw = pc.readAsStringSync();
    preCommit = _stripShellComments(preCommitRaw);
    prePush = _stripShellComments(pp.readAsStringSync());
  });

  group('pre-commit runs flutter ONLY behind an escape hatch', () {
    test('both escape hatches are present', () {
      expect(preCommit.contains('PRE_COMMIT_LEGACY'), isTrue,
          reason: 'PRE_COMMIT_LEGACY=1 is the §4.6 old-path-preserved hatch for '
              'this platform-tier change — it must restore analyze + the '
              'contract subset verbatim');
      expect(preCommit.contains('PRE_COMMIT_FULL'), isTrue,
          reason: 'PRE_COMMIT_FULL=1 must keep working (analyze + full suite)');
    });

    test('the DEFAULT (else) branch invokes no flutter command', () {
      // THE LOAD-BEARING ASSERTION, and the one the first version of this file
      // got wrong. That version asserted only that every flutter call sat
      // between the hatch `if` and its closing `fi` — a range which CONTAINS
      // the else branch. Round-1 review put the two calls back into the else
      // body (the single most natural way this regression returns: someone
      // "restores" the step in place) and the suite stayed green while every
      // commit paid the full cost again. Assert the else body directly.
      final ifAt = preCommit.indexOf(r'if [ "${PRE_COMMIT_FULL:-0}" = "1" ]');
      expect(ifAt, greaterThanOrEqualTo(0),
          reason: 'the hatch chain must lead with PRE_COMMIT_FULL (strongest '
              'first, so setting both never yields the weaker gate)');
      final fiAt = preCommit.indexOf('\nfi\n', ifAt);
      expect(fiAt, greaterThan(ifAt),
          reason: 'the hatch chain must be closed by a lone `fi`');
      final elseAt = preCommit.lastIndexOf('\nelse\n', fiAt);
      expect(elseAt, greaterThan(ifAt),
          reason: 'the hatch chain must have an else branch — that IS the '
              'default, lean path');

      final elseBody = preCommit.substring(elseAt, fiAt);
      expect(_flutterCall.hasMatch(elseBody), isFalse,
          reason: 'the DEFAULT path must invoke no flutter command. Found one '
              'in the else body:\n$elseBody\nThat silently restores ~12 min to '
              'every commit — the exact regression this file exists to catch, '
              'and the exact mutation that defeated its first version.');
    });

    test('no flutter call escapes the hatch chain entirely', () {
      // The mirror of the assertion above: that one guards the else body, this
      // one guards everywhere else in the file. Both are needed — a call added
      // above the chain is just as costly as one added inside the else.
      //
      // Matched by REGEX, not by two literal strings. Round-2 review defeated
      // the literal version with `flutter  analyze` (two spaces): green suite,
      // full cost restored. Whitespace between the command and its subcommand
      // is invisible to a reader and free to a mutator, so it must be free to
      // the matcher too.
      final ifAt = preCommit.indexOf(r'if [ "${PRE_COMMIT_FULL:-0}" = "1" ]');
      final fiAt = preCommit.indexOf('\nfi\n', ifAt);

      final matches = _flutterCall.allMatches(preCommit).toList();
      expect(matches, isNotEmpty,
          reason: 'flutter analyze/test must still exist inside the hatches — '
              'the point is to gate them, not delete them');
      for (final m in matches) {
        expect(m.start > ifAt && m.start < fiAt, isTrue,
            reason: 'an UNGUARDED "${m.group(0)}" at index ${m.start} is '
                'outside the hatch chain ($ifAt..$fiAt) and therefore runs on '
                'every commit.');
      }
    });

    test('Gate 32 can still identify the installed hook', () {
      // check_hooks_installed.dart accepts a hook containing EITHER
      // 'scripts/pre-commit.sh' OR 'flutter analyze'. After this batch the
      // latter appears only inside a hatch, so the former must be present or
      // the gate hangs off an optional string. (It was 0-occurrence before this
      // batch too — this repairs a pre-existing latent breakage.)
      // Asserted against the COMMENT-STRIPPED source on purpose (round-2
      // review): the gate itself reads the raw file, so a comment would satisfy
      // it — but a comment is the first thing a cleanup pass removes, and the
      // gate would then fail with the misleading message "does not invoke
      // scripts/pre-commit.sh". Requiring the anchor to survive comment
      // stripping forces it to be a real statement (HOOK_SOURCE=...).
      expect(preCommit.contains('scripts/pre-commit.sh'), isTrue,
          reason: 'scripts/check_hooks_installed.dart:40 looks for this literal '
              'path in the INSTALLED hook (a verbatim cp of this file) to '
              'prove the hook is ours. It must live in CODE, not a comment.');
      expect(preCommitRaw.contains('scripts/pre-commit.sh'), isTrue,
          reason: 'sanity: the raw file the gate actually reads must contain it '
              'too (implied by the stripped check, asserted so a future change '
              'to the stripper cannot silently void this pair)');
    });

    test('the default path still runs the gate loop', () {
      // Guards against "made it fast by removing everything".
      expect(preCommit.contains('scripts/check_*.dart'), isTrue,
          reason: 'the 71-gate loop is what pre-commit still IS — and Gate 33 '
              'detects wiring via this literal glob');
      expect(preCommit.contains('validate_audit_closure.dart'), isTrue,
          reason: 'Gate 40 must still run at commit time');
    });
  });

  group('pre-push runs analyze above every early exit', () {
    test('analyze is present and unconditional', () {
      expect(prePush.contains('flutter analyze'), isTrue,
          reason: 'analyze moved here from pre-commit; without it a '
              'feature-tier branch push has no compile check anywhere');
    });

    test('analyze precedes PRE_PUSH_FULL, both fail-safes, and the feature skip',
        () {
      final analyze = prePush.indexOf('flutter analyze');
      expect(analyze, greaterThanOrEqualTo(0));

      // Each of these ends in `exit 0`. Analyze must precede ALL of them.
      const exits = <String, String>{
        'PRE_PUSH_FULL': 'the explicit-override early return',
        'rev-parse --verify --quiet origin/main': 'the absent-origin fail-safe',
        r'-z "$RANGE_FILES"': 'the empty-range fail-safe',
        r'"$TIER" = "feature"': 'the feature-tier skip',
      };

      exits.forEach((token, what) {
        final at = prePush.indexOf(token);
        expect(at, greaterThanOrEqualTo(0),
            reason: '$what ($token) must still exist — this test assumes the '
                'tiering it guards is intact');
        expect(analyze, lessThan(at),
            reason: 'flutter analyze (index $analyze) must come BEFORE $what '
                '(index $at). Below it, analyze is dead code on exactly the '
                'pushes with no other check: that path exits 0 first.');
      });
    });

    test('the tiered full suite is unchanged', () {
      // This batch moved analyze; it deliberately did NOT retier the suite.
      expect(prePush.contains('run_full_suite'), isTrue);
      expect(prePush.contains('blast_radius_from_diff.dart'), isTrue);
    });
  });
}

/// Strips shell comments (`#!` shebang, full-line `# ...`, inline ` # ...`) so
/// assertions match real CODE, not the explanatory headers — which discuss
/// every token asserted above. Safe for these hooks: they contain no `#` inside
/// string literals (verified).
String _stripShellComments(String shell) {
  final out = StringBuffer();
  for (final line in shell.split('\n')) {
    if (line.trimLeft().startsWith('#')) continue; // full-line comment / shebang
    final idx = line.indexOf(' #'); // inline comment (space-hash to EOL)
    out.writeln(idx >= 0 ? line.substring(0, idx) : line);
  }
  return out.toString();
}
