// test/contracts/closes_oi_cited_test.dart
//
// Controls for the `closes-oi:` commit-msg gate
// (scripts/check_closes_oi_cited.dart).
//
// The convention at docs/audit/open_issues.md:17 — "every commit that closes
// one cites `closes-oi: OI-NN`" — was followed in 5 citation lines across 3 of
// the last 400 commits, and enforced by nothing. A board that documents a
// practice nobody performs is worse than one that documents none.
//
// These exercise the PURE decision functions. The gate deliberately compares the
// HEAD blob against the staged blob rather than parsing diff text: the OI-58a
// version-bump exemption burned three designs that each parsed diff output and
// was bypassed by feeding the parser something it mis-read.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_closes_oi_cited.dart';

String _board(Map<String, String> statuses) {
  final b = StringBuffer('# Open Issues\n\n');
  statuses.forEach((oi, status) {
    b.writeln('## $oi — some title\n');
    b.writeln('- **Status**: $status · 2026-07-28 · detail');
    b.writeln('- **Identified**: 2026-05-17\n');
  });
  return b.toString();
}

void main() {
  group('parseBoardStatuses', () {
    test('reads one status per OI section', () {
      final m = parseBoardStatuses(
          _board({'OI-47': 'OPEN', 'OI-51': 'CLOSED', 'OI-58': 'OPEN'}));
      expect(m, {'OI-47': 'OPEN', 'OI-51': 'CLOSED', 'OI-58': 'OPEN'});
    });

    test('takes the FIRST status line, not a later mention', () {
      const board = '## OI-47 — t\n\n'
          '- **Status**: OPEN — blocked\n'
          '- **Note**: was **Status**: CLOSED in an earlier draft\n';
      expect(parseBoardStatuses(board), {'OI-47': 'OPEN'});
    });

    test('a section with no status line is omitted, not guessed', () {
      expect(parseBoardStatuses('## OI-99 — t\n\n- **Identified**: x\n'), isEmpty);
    });

    test('bolded status renders the same', () {
      expect(parseBoardStatuses('## OI-47 — t\n\n- **Status**: **CLOSED** · x\n'),
          {'OI-47': 'CLOSED'});
    });
  });

  group('newlyClosed', () {
    test('OPEN -> CLOSED is a transition', () {
      expect(
          newlyClosed({'OI-47': 'OPEN'}, {'OI-47': 'CLOSED'}), ['OI-47']);
    });

    test('CLOSED -> CLOSED is not (an untouched historical entry)', () {
      expect(newlyClosed({'OI-47': 'CLOSED'}, {'OI-47': 'CLOSED'}), isEmpty);
    });

    test('OPEN -> OPEN is not', () {
      expect(newlyClosed({'OI-47': 'OPEN'}, {'OI-47': 'OPEN'}), isEmpty);
    });

    test('a NEW already-closed section is not a transition', () {
      // Found and fixed in the same breath. Demanding a citation there is noise,
      // not discipline — nothing was ever open to close.
      expect(newlyClosed({}, {'OI-80': 'CLOSED'}), isEmpty);
    });

    test('IN_PROGRESS -> CLOSED counts', () {
      expect(newlyClosed({'OI-47': 'IN_PROGRESS'}, {'OI-47': 'CLOSED'}),
          ['OI-47']);
    });

    test('multiple transitions come back sorted', () {
      expect(
          newlyClosed({'OI-51': 'OPEN', 'OI-47': 'OPEN'},
              {'OI-51': 'CLOSED', 'OI-47': 'CLOSED'}),
          ['OI-47', 'OI-51']);
    });

    test('the real f15cb1f3 shape: two closed at once', () {
      final before = parseBoardStatuses(
          _board({'OI-47': 'OPEN', 'OI-51': 'OPEN', 'OI-58': 'OPEN'}));
      final after = parseBoardStatuses(
          _board({'OI-47': 'CLOSED', 'OI-51': 'CLOSED', 'OI-58': 'OPEN'}));
      expect(newlyClosed(before, after), ['OI-47', 'OI-51']);
    });
  });

  group('citedOis', () {
    test('picks up citations anywhere in the body', () {
      expect(citedOis('subject\n\nbody\n\ncloses-oi: OI-47\ncloses-oi: OI-51\n'),
          {'OI-47', 'OI-51'});
    });

    test('is case-insensitive on the key and normalises the id', () {
      expect(citedOis('Closes-OI: oi-47'), {'OI-47'});
    });

    test('an empty body cites nothing', () {
      expect(citedOis(''), isEmpty);
    });

    test('a near-miss does not count as a citation', () {
      expect(citedOis('this closes OI-47 eventually'), isEmpty,
          reason: 'prose is not the trailer; the gate wants the machine form');
    });
  });

  group('the three directions the gate must get right', () {
    test('transition WITHOUT citation -> the OI is reported missing', () {
      final closed = newlyClosed({'OI-47': 'OPEN'}, {'OI-47': 'CLOSED'});
      final cited = citedOis('docs: tidy up the board\n');
      expect(closed.where((o) => !cited.contains(o)), ['OI-47']);
    });

    test('transition WITH citation -> nothing missing', () {
      final closed = newlyClosed({'OI-47': 'OPEN'}, {'OI-47': 'CLOSED'});
      final cited = citedOis('docs: close it\n\ncloses-oi: OI-47\n');
      expect(closed.where((o) => !cited.contains(o)), isEmpty);
    });

    test('no transition -> silent, so ordinary commits pay nothing', () {
      expect(newlyClosed({'OI-47': 'OPEN'}, {'OI-47': 'OPEN'}), isEmpty);
    });

    test('closing TWO but citing ONE reports only the uncited one', () {
      final closed = newlyClosed(
          {'OI-47': 'OPEN', 'OI-51': 'OPEN'},
          {'OI-47': 'CLOSED', 'OI-51': 'CLOSED'});
      final cited = citedOis('closes-oi: OI-47\n');
      expect(closed.where((o) => !cited.contains(o)), ['OI-51']);
    });
  });
}
