// test/scripts/analyze_narrower_than_lib_lib_test.dart
//
// Unit tests for analyze_narrower_than_lib_lib.dart — the pure detection
// logic behind scripts/check_analyze_narrower_than_lib_in_tooling.dart.
// Mutation-proof per CLAUDE.md rule 24: `_isScopedNarrowerThanLib`'s `!` was
// deleted (inverting the verdict) and re-run against this file — see the
// gate_test_ledger.yaml evidence field for the exact count.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/analyze_narrower_than_lib_lib.dart';

String _diff(String file, String addedLine) => '+++ b/$file\n+$addedLine\n';

void main() {
  group('findScopedAnalyzeInTooling — BAD (must flag)', () {
    test('scoped single-file analyze in a .sh script', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/some_script.sh', 'flutter analyze lib/features/train/screen.dart'),
      );
      expect(violations, hasLength(1));
      expect(violations.first, contains('scripts/some_script.sh'));
      expect(violations.first, contains('lib/features/train/screen.dart'));
    });

    test('scoped multi-file analyze in a SKILL.md instruction', () {
      final violations = findScopedAnalyzeInTooling(
        _diff(
          '.claude/skills/some-skill/SKILL.md',
          'Run `flutter analyze lib/a.dart lib/b.dart` before committing.',
        ),
      );
      expect(violations, hasLength(1));
      expect(violations.first, contains('.claude/skills/some-skill/SKILL.md'));
    });

    test('scoped analyze in a scripts/*.dart file (e.g. a helper script body)', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/build_apk.dart', "'flutter analyze lib/core/router.dart',"),
      );
      expect(violations, hasLength(1));
    });

    test('narrow DIRECTORY (not lib/) still flags', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/helper.sh', 'flutter analyze lib/features/'),
      );
      expect(violations, hasLength(1));
    });

    test('scoped analyze after a shell operator (&&) still flags', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/helper.sh', 'dart run setup.dart && flutter analyze lib/x.dart'),
      );
      expect(violations, hasLength(1));
    });
  });

  group('findScopedAnalyzeInTooling — GOOD (must NOT flag)', () {
    test('MIRROR: bare "flutter analyze lib/" (whole tree) is fine', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/some_script.sh', 'flutter analyze lib/'),
      );
      expect(violations, isEmpty);
    });

    test('"flutter analyze lib" (no trailing slash) is fine', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/some_script.sh', 'flutter analyze lib'),
      );
      expect(violations, isEmpty);
    });

    test('bare "flutter analyze" with no path at all is fine', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/some_script.sh', 'flutter analyze'),
      );
      expect(violations, isEmpty);
    });

    test('REGRESSION: "flutter analyze" inside prose/echo text is not a real '
        'invocation (real line, scripts/pre-push.sh:111)', () {
      final violations = findScopedAnalyzeInTooling(
        _diff(
          'scripts/pre-push.sh',
          'echo "[pre-push] flutter analyze (always -- runs even when the '
              'suite is skipped)..."',
        ),
      );
      expect(violations, isEmpty);
    });

    test('flags only, no path, is fine', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/pre-push.sh', 'flutter analyze --no-fatal-infos'),
      );
      expect(violations, isEmpty);
    });

    test('lib/ plus flags is fine', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/pre-push.sh', 'flutter analyze lib/ --no-fatal-infos'),
      );
      expect(violations, isEmpty);
    });

    test('OUT OF SCOPE: identical scoped-analyze line, but file is a diagnose-doc', () {
      // The gate's caller restricts the git pathspec to scripts/*.sh,
      // scripts/*.dart, .claude/skills/**/*.md — docs/diagnoses/** is never
      // passed to `git diff`, so its content never reaches this function at
      // all. This test documents that the LIB itself is scope-agnostic (it
      // would flag this line if given it) — the exclusion is enforced by the
      // caller's pathspec, verified structurally in check_*.dart's own
      // pathspec literal, not re-derivable from the lib alone. Included here
      // as documentation, not as proof of the pathspec (that's the CLI's job).
      final violations = findScopedAnalyzeInTooling(
        _diff(
          'docs/diagnoses/2026-09-19-something-abc123.md',
          'flutter analyze lib/features/x/y.dart -> 0 issues.',
        ),
      );
      // The pure lib has no file-family awareness — it flags whatever it's
      // given. Real-world exclusion of docs/** happens one layer up, at the
      // git pathspec in check_analyze_narrower_than_lib_in_tooling.dart.
      expect(violations, hasLength(1));
    });

    test('unrelated added line with no "flutter analyze" at all', () {
      final violations = findScopedAnalyzeInTooling(
        _diff('scripts/some_script.sh', 'echo "hello world"'),
      );
      expect(violations, isEmpty);
    });
  });
}
