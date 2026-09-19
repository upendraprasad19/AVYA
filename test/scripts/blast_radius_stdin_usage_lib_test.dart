// test/scripts/blast_radius_stdin_usage_lib_test.dart
//
// Unit tests for the pure logic behind scripts/check_blast_radius_stdin_usage.dart
// (scripts/blast_radius_stdin_usage_lib.dart). Pure, no I/O.
//
// Mutation proof (run directly by the coordinating session, not the building
// fork — see docs/audit/gate_test_ledger.yaml): neutering isPositionalMisuse
// to always return false reddens exactly the 4 BAD-case tests below (4 of
// 11 total). Reverted; 11/11 green.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/blast_radius_stdin_usage_lib.dart';

void main() {
  group('isPositionalMisuse', () {
    test('BAD: piped without the trailing dash', () {
      final isViolation = isPositionalMisuse(
          'git diff --name-only main head | dart run scripts/blast_radius_from_diff.dart');
      expect(isViolation, isTrue);
    });

    test('BAD: piped via \$DART_BIN without the trailing dash', () {
      expect(
        isPositionalMisuse(
            'git diff --name-only main head | "\$DART_BIN" run scripts/blast_radius_from_diff.dart'),
        isTrue,
      );
    });

    test('BAD: piped with an explicit path arg instead of dash', () {
      expect(
        isPositionalMisuse(
            'git diff --name-only main head | dart run scripts/blast_radius_from_diff.dart lib/foo.dart'),
        isTrue,
      );
    });

    test('GOOD mirror: piped WITH the trailing dash (the actual fix)', () {
      expect(
        isPositionalMisuse(
            'git diff --name-only main head | dart run scripts/blast_radius_from_diff.dart -'),
        isFalse,
      );
    });

    test('GOOD: bare invocation, no pipe, no args', () {
      expect(
        isPositionalMisuse('dart run scripts/blast_radius_from_diff.dart'),
        isFalse,
      );
    });

    test('GOOD: bare invocation, no pipe, explicit path arg', () {
      expect(
        isPositionalMisuse(
            'dart run scripts/blast_radius_from_diff.dart lib/features/auth/foo.dart'),
        isFalse,
      );
    });

    test('GOOD: prose mention with no dart-run/pipe shape', () {
      expect(
        isPositionalMisuse(
            "See blast_radius_from_diff.dart's behavior for details."),
        isFalse,
      );
    });

    test('GOOD: markdown table row mentioning the filename (no real pipe invocation)', () {
      expect(
        isPositionalMisuse(
            '| Blast-radius helper | `blast_radius_from_diff.dart` computes the tier |'),
        isFalse,
      );
    });

    test('GOOD: trailing dash inside markdown backticks', () {
      expect(
        isPositionalMisuse(
            '`git diff --name-only main head | dart run scripts/blast_radius_from_diff.dart -`'),
        isFalse,
      );
    });

    test(
        'GOOD: real committed usage — trailing dash followed by shell '
        'redirection (pre-push.sh:168 verbatim shape)', () {
      expect(
        isPositionalMisuse(
            r'  | "$DART_BIN" run scripts/blast_radius_from_diff.dart - 2>/dev/null \'),
        isFalse,
      );
    });

    test('BAD: dash followed by a genuine second argument (not redirection)',
        () {
      expect(
        isPositionalMisuse(
            'git diff --name-only main head | dart run scripts/blast_radius_from_diff.dart - extra_arg'),
        isTrue,
      );
    });
  });
}
