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

    test('a non-status key ending in "status: open" does NOT count (B-pass anchor)', () {
      expect(
        parseEscapeLedger('escapes:\n  - open_status: open\n  - my_status: open\n')
            .openEscapes,
        0,
      );
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
        gateFailures7d: 3,
        topGate: 'check_smoke_test',
      );
      expect(out, contains('review_rounds=2'));
      expect(out, contains('open_s_escapes=0'));
      expect(out, contains('s_tier_fixes=2/3'));
      expect(out, contains('gate_failures_7d=3'));
      expect(out, contains('top_gate=check_smoke_test'));
    });

    test('unknown open-escape count renders unknown, NOT zero', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 2, mechanicalOnly: false),
        openEscapes: null,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
        gateFailures7d: null,
        topGate: null,
      );
      expect(out, contains('open_s_escapes=unknown'));
    });

    test('missing-dir nulls render unknown per field, NOT zero', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 0, mechanicalOnly: false),
        openEscapes: null,
        recentDiagnoseDocs: null,
        sTierDocs: 1,
        recentReviewFiles: null,
        gateFailures7d: null,
        topGate: null,
      );
      expect(out, contains('s_tier_fixes=1/unknown'));
      expect(out, contains('review_files_7d=unknown'));
      expect(out, contains('gate_failures_7d=unknown'));
      expect(out, contains('top_gate=unknown'));
      expect(out, isNot(contains('s_tier_fixes=0/')));
      expect(out, isNot(contains('s_tier_fixes=/')));
    });

    test('gate_failures_7d renders count + top gate; zero renders none', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 2, mechanicalOnly: false),
        openEscapes: 0,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
        gateFailures7d: 2,
        topGate: 'check_smoke_test',
      );
      expect(out, contains('gate_failures_7d=2 top_gate=check_smoke_test'));

      final zero = composeReport(
        record: const PlanReviewStats(reviewRounds: 0, mechanicalOnly: false),
        openEscapes: 0,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
        gateFailures7d: 0,
        topGate: null,
      );
      expect(zero, contains('gate_failures_7d=0 top_gate=none'));
      expect(zero, isNot(contains('top_gate=unknown')));
    });
  });

  group('parseGateFailuresLog', () {
    const now = 1789674000;

    test('counts recent lines and picks the most frequent gate', () {
      final s = parseGateFailuresLog(
        '$now check_alpha\n'
        '${now - 10} check_alpha\n'
        '${now - 20} check_beta\n'
        '${now - 691200} check_old\n',
        now,
      );
      expect(s.unparseable, isFalse);
      expect(s.recentTotal, 3);
      expect(s.topGate, 'check_alpha');
    });

    test('7-day window boundary: >= now-604800 counts, one second older is out',
        () {
      final s = parseGateFailuresLog(
        '${now - 604800} check_edge_in\n'
        '${now - 604801} check_edge_out\n',
        now,
      );
      expect(s.recentTotal, 1);
      expect(s.topGate, 'check_edge_in');
    });

    test('non-numeric first token is skipped, never fatal', () {
      final s = parseGateFailuresLog(
        'garbage line\n'
        '$now check_alpha\n',
        now,
      );
      expect(s.unparseable, isFalse);
      expect(s.recentTotal, 1);
      expect(s.topGate, 'check_alpha');
    });

    test('empty/garbage content sets unparseable — caller renders unknown, '
        'never 0', () {
      expect(parseGateFailuresLog('', now).unparseable, isTrue);
      expect(parseGateFailuresLog('not a log\n', now).unparseable, isTrue);
      final s = parseGateFailuresLog('', now);
      expect(s.recentTotal, 0);
      expect(s.topGate, isNull);
    });

    test('parseable log with all lines outside the window is genuine zero', () {
      final s = parseGateFailuresLog('${now - 691200} check_old\n', now);
      expect(s.unparseable, isFalse);
      expect(s.recentTotal, 0);
      expect(s.topGate, isNull);
    });
  });
}
