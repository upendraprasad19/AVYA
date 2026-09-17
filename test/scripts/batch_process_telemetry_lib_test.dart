import 'package:flutter_test/flutter_test.dart';

import '../../scripts/batch_process_telemetry_lib.dart';

void main() {
  group('parsePlanReviewRecord', () {
    test('reads review_rounds and mechanical_only from frontmatter', () {
      final report = parsePlanReviewRecord('''
---
branch: discipline-v2
review_rounds: 2
mechanical_only: true
verdict: converged
---
prose
''');
      expect(report.reviewRounds, 2);
      expect(report.mechanicalOnly, isTrue);
    });

    test('absent mechanical_only parses false; absent rounds parses 0', () {
      final report = parsePlanReviewRecord('---\nbranch: x\nverdict: converged\n---\n');
      expect(report.reviewRounds, 0);
      expect(report.mechanicalOnly, isFalse);
    });
  });

  group('parseEscapeLedger', () {
    test('counts open escapes, zero on empty ledger', () {
      expect(parseEscapeLedger('escapes: []\n').openEscapes, 0);
      expect(
        parseEscapeLedger('escapes:\n  - bug: a1b2c3\n    status: open\n  - bug: d4e5f6\n    status: closed_with_tightening\n')
            .openEscapes,
        1,
      );
    });

    test('unreadable ledger reports null, NOT zero (bad-news-vs-no-news)', () {
      expect(parseEscapeLedger('not: a ledger').openEscapes, isNull);
    });

    test('counts open escapes with CRLF line endings (Windows checkout)', () {
      expect(
        parseEscapeLedger('escapes:\r\n  - bug: a1b2c3\r\n    status: open\r\n')
            .openEscapes,
        1,
      );
    });
  });

  group('composeReport', () {
    test('renders one line per section, no exception on empty inputs', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 2, mechanicalOnly: false),
        openEscapes: 0,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
      );
      expect(out, contains('review_rounds=2'));
      expect(out, contains('open_s_escapes=0'));
      expect(out, contains('s_tier_fixes=2/3'));
    });

    test('unknown open-escape count renders unknown, NOT zero', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 2, mechanicalOnly: false),
        openEscapes: null,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
      );
      expect(out, contains('open_s_escapes=unknown'));
    });
  });
}
