// test/scripts/migration_contains_uniqueness_lib_test.dart
//
// Unit tests for the pure logic behind
// scripts/check_migration_contains_assertion_uniqueness.dart
// (scripts/migration_contains_uniqueness_lib.dart). Pure — no disk/git I/O,
// synthetic diff text + synthetic migration content maps.
//
// Mutation proof (re-run directly by the coordinating session, not the
// building fork, which was stopped mid-task after being found editing a
// DIFFERENT gate's file and never reported a final count — see
// docs/audit/gate_test_ledger.yaml): neutering
// countOccurrencesNormalized to always `return 1` reddens 3 of the 10 tests
// in this file — its own two direct unit tests plus the
// `findAmbiguousMigrationAssertions ... (BAD)` integration test. Reverted;
// 10/10 green.
// Reverted; all 7 green again.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/migration_contains_uniqueness_lib.dart';

const _migrationWithTwoGuards = '''
CREATE OR REPLACE FUNCTION public.consume_quota(p_user_id uuid, p_limit int)
RETURNS void AS \$\$
BEGIN
  IF p_user_id IS NULL OR p_limit IS NULL THEN
    RAISE EXCEPTION 'consume_quota: null argument';
  END IF;
  IF p_limit < 0 THEN
    RAISE EXCEPTION 'consume_quota: invalid limit';
  END IF;
END;
\$\$ LANGUAGE plpgsql;
''';

String _diffFor(String file, List<String> addedLines) {
  final buf = StringBuffer();
  buf.writeln('+++ b/$file');
  for (final l in addedLines) {
    buf.writeln('+$l');
  }
  return buf.toString();
}

void main() {
  group('extractLiteralFragment', () {
    test('extracts from a RegExp(r"...") argument, stripping \\s+', () {
      final line =
          '''expect(sql.contains(RegExp(r"RAISE EXCEPTION\\s+'consume_quota:")), isTrue);''';
      final literal = extractLiteralFragment(line);
      expect(literal, isNotNull);
      expect(literal, contains('consume_quota'));
    });

    test('extracts from a bare string literal', () {
      final line =
          '''expect(sql.contains("RAISE EXCEPTION 'consume_quota: null argument'"), isTrue);''';
      final literal = extractLiteralFragment(line);
      expect(literal, 'RAISE EXCEPTION \'consume_quota: null argument\'');
    });

    test('returns null for a line with no .contains(', () {
      expect(extractLiteralFragment('final x = 1;'), isNull);
    });

    test('returns null for a too-short literal (< 8 chars)', () {
      expect(extractLiteralFragment('''expect(sql.contains('ok'), isTrue);'''),
          isNull);
    });
  });

  group('countOccurrencesNormalized', () {
    test('counts across whitespace-differing occurrences', () {
      const haystack = 'A B C\nA   B\nC A B C';
      expect(countOccurrencesNormalized(haystack, 'A B'), 3);
    });

    test('returns 0 for an absent literal', () {
      expect(countOccurrencesNormalized('hello world', 'goodbye'), 0);
    });
  });

  group('findAmbiguousMigrationAssertions', () {
    test('finds the ambiguous consume_quota assertion (BAD)', () {
      final diff = _diffFor('test/contracts/consume_quota_test.dart', [
        "final migration = latestMigrationDefining('consume_quota');",
        '''expect(sql.contains(RegExp(r"RAISE EXCEPTION\\s+'consume_quota:")), isTrue);''',
      ]);
      final findings = findAmbiguousMigrationAssertions(
        diffText: diff,
        migrationContents: {'129_consume_quota.sql': _migrationWithTwoGuards},
      );
      expect(findings, hasLength(1));
      expect(findings.first, contains('consume_quota_test.dart'));
    });

    test(
        'does NOT warn when the assertion pins the full unique message (GOOD mirror)',
        () {
      final diff = _diffFor('test/contracts/consume_quota_test.dart', [
        "final migration = latestMigrationDefining('consume_quota');",
        '''expect(sql.contains("RAISE EXCEPTION 'consume_quota: null argument'"), isTrue);''',
      ]);
      final findings = findAmbiguousMigrationAssertions(
        diffText: diff,
        migrationContents: {'129_consume_quota.sql': _migrationWithTwoGuards},
      );
      expect(findings, isEmpty);
    });

    test('does NOT examine a file that never calls latestMigrationDefining(',
        () {
      final diff = _diffFor('test/contracts/unrelated_test.dart', [
        '''expect(sql.contains(RegExp(r"RAISE EXCEPTION\\s+'consume_quota:")), isTrue);''',
      ]);
      final findings = findAmbiguousMigrationAssertions(
        diffText: diff,
        migrationContents: {'129_consume_quota.sql': _migrationWithTwoGuards},
      );
      expect(findings, isEmpty);
    });

    test('skips an assertion whose literal strips down to nothing useful',
        () {
      final diff = _diffFor('test/contracts/consume_quota_test.dart', [
        "final migration = latestMigrationDefining('consume_quota');",
        '''expect(sql.contains(RegExp(r"\\s+\\s*")), isTrue);''',
      ]);
      final findings = findAmbiguousMigrationAssertions(
        diffText: diff,
        migrationContents: {'129_consume_quota.sql': _migrationWithTwoGuards},
      );
      expect(findings, isEmpty);
    });
  });
}
