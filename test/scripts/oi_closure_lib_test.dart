// Unit tests for scripts/oi_closure_lib.dart — the predicate behind
// check_closes_oi_performed.dart (the MIRROR of check_closes_oi_cited.dart).
//
// No subprocess here, so no @Timeout: the real-merge coverage lives in
// closes_oi_performed_e2e_test.dart, which spawns git and the gate for real.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/oi_closure_lib.dart';

/// A board fragment in the exact shape the real files use — `## OI-NN — title`
/// with an em-dash, then a `- **Status**:` bullet. The em-dash is deliberate,
/// not decoration: the encoding bug that made check_oi_numbering_unique report
/// PASS against an empty board corrupted precisely this character.
String board(Map<String, String> entries) => entries.entries
    .map((e) => '## ${e.key} — a title with an em-dash\n\n'
        '- **Status**: ${e.value}\n'
        '- **Blocked on**: nothing\n')
    .join('\n');

void main() {
  group('citationsAcross', () {
    test('collects citations from every message, not just the first', () {
      final out = citationsAcross([
        'fix(x): something\n\ncloses-oi: OI-150',
        'docs(y): another\n\ncloses-oi: OI-58',
      ]);
      expect(out, {'OI-150', 'OI-58'},
          reason: 'a merged range is many commits; reading only one of them '
              'would miss the citation on any commit but that one');
    });

    test('is case-insensitive and de-duplicates', () {
      final out = citationsAcross([
        'a\n\nCloses-OI: OI-150',
        'b\n\ncloses-oi: oi-150',
      ]);
      expect(out, {'OI-150'});
    });

    test('returns empty when nothing is cited', () {
      expect(citationsAcross(['chore: no citation here', '']), isEmpty);
    });

    test('does not match prose that merely mentions an OI number', () {
      final out = citationsAcross(['fix: relates to OI-150 but does not close it']);
      expect(out, isEmpty,
          reason: 'the citation is the `closes-oi:` key, not any mention of a '
              'number — otherwise every "Related: OI-NN" line would demand a '
              'close that was never claimed');
    });
  });

  group('mergedBoardStatuses', () {
    test('reads entries from BOTH boards', () {
      final out = mergedBoardStatuses(
        openContent: board({'OI-1': 'OPEN'}),
        closedContent: board({'OI-2': 'CLOSED'}),
      );
      expect(out, {'OI-1': 'OPEN', 'OI-2': 'CLOSED'},
          reason: 'a legitimately-closed OI lives in closed_issues.md; reading '
              'only the open board would call every correct close "unknown"');
    });

    test('OPEN wins when an OI is on both boards', () {
      final out = mergedBoardStatuses(
        openContent: board({'OI-9': 'OPEN'}),
        closedContent: board({'OI-9': 'CLOSED'}),
      );
      expect(out['OI-9'], 'OPEN',
          reason: 'a stale closed entry must not vouch for a ticket still '
              'sitting on the open board — err toward flagging');
    });

    test('tolerates an absent closed board', () {
      final out = mergedBoardStatuses(
        openContent: board({'OI-1': 'OPEN'}),
        closedContent: '',
      );
      expect(out, {'OI-1': 'OPEN'});
    });
  });

  group('unsatisfiedCitations', () {
    test('a cited OI that reads CLOSED satisfies the gate', () {
      final v = unsatisfiedCitations({'OI-150'}, {'OI-150': 'CLOSED'});
      expect(v.unperformed, isEmpty);
      expect(v.unknown, isEmpty);
    });

    // THE OI-150 SHAPE — the measured bug this gate exists for.
    test('a cited OI still reading OPEN is UNPERFORMED', () {
      final v = unsatisfiedCitations({'OI-150'}, {'OI-150': 'OPEN'});
      expect(v.unperformed, ['OI-150'],
          reason: 'c2534257 carried `closes-oi: OI-150` and the board still '
              'read OPEN at the merge; that is the whole bug');
      expect(v.unknown, isEmpty);
    });

    test('IN_PROGRESS is also unperformed — only CLOSED satisfies', () {
      final v = unsatisfiedCitations({'OI-7'}, {'OI-7': 'IN_PROGRESS'});
      expect(v.unperformed, ['OI-7'],
          reason: 'the mirror of the sibling gate, which treats anything other '
              'than CLOSED as not-closed');
    });

    // The two failure kinds must stay separable — they need different fixes.
    test('a cited OI on NEITHER board is UNKNOWN, not unperformed', () {
      final v = unsatisfiedCitations({'OI-999'}, {'OI-1': 'OPEN'});
      expect(v.unknown, ['OI-999']);
      expect(v.unperformed, isEmpty,
          reason: 'a dangling citation needs a different fix (typo or '
              'renumber) than a board write, so collapsing the two lists would '
              'send the reader after the wrong thing');
    });

    test('separates the two kinds within a single merge', () {
      final v = unsatisfiedCitations(
        {'OI-150', 'OI-999', 'OI-2'},
        {'OI-150': 'OPEN', 'OI-2': 'CLOSED'},
      );
      expect(v.unperformed, ['OI-150']);
      expect(v.unknown, ['OI-999']);
    });

    test('output is sorted, so the failure message is stable across runs', () {
      final v = unsatisfiedCitations(
        {'OI-30', 'OI-11', 'OI-22'},
        {'OI-30': 'OPEN', 'OI-11': 'OPEN', 'OI-22': 'OPEN'},
      );
      expect(v.unperformed, ['OI-11', 'OI-22', 'OI-30']);
    });

    test('no citations means nothing to satisfy', () {
      final v = unsatisfiedCitations({}, {'OI-1': 'OPEN'});
      expect(v.unperformed, isEmpty);
      expect(v.unknown, isEmpty);
    });
  });
}
