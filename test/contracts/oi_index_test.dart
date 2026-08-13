// test/contracts/oi_index_test.dart
//
// Controls for scripts/build_oi_index.dart, the generator behind
// docs/audit/OPEN_INDEX.md.
//
// WHY A TEST AND NOT JUST "IT RAN". docs/diagnoses/INDEX.md sat 237-of-344
// entries empty for months because its generator exited 0 while writing
// placeholders (c4e8a2). An index nobody validates looks identical to a working
// one right up until someone needs it. These pin the parse and the fail-closed
// behaviour so this index cannot rot the same way.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/build_oi_index.dart';

String _entry(String id, String title, String status,
        {String? blocked = 'none', String? verified = 'never'}) =>
    '## $id — $title\n\n'
    '- **Status**: $status\n'
    '${blocked == null ? '' : '- **Blocked on**: $blocked\n'}'
    '${verified == null ? '' : '- **Verified**: $verified\n'}'
    '- **Identified**: 2026-05-17\n\n';

void main() {
  group('parseOpenIssues', () {
    test('keeps OPEN entries and drops CLOSED ones', () {
      final issues = parseOpenIssues(
          _entry('OI-44', 'a thing', 'OPEN') +
              _entry('OI-45', 'closed thing', 'CLOSED · 2026-07-28 · `abc123`') +
              _entry('OI-46', 'another', 'OPEN'));
      expect(issues.map((i) => i.id), ['OI-44', 'OI-46']);
    });

    test('sorts numerically, not lexically', () {
      final issues = parseOpenIssues(_entry('OI-9', 'nine', 'OPEN') +
          _entry('OI-10', 'ten', 'OPEN') +
          _entry('OI-100', 'hundred', 'OPEN'));
      expect(issues.map((i) => i.id), ['OI-9', 'OI-10', 'OI-100'],
          reason: 'lexical order would put OI-10 and OI-100 before OI-9');
    });

    test('captures Blocked on and Verified', () {
      final issues = parseOpenIssues(_entry('OI-60', 'flip flags', 'OPEN',
          blocked: 'FOUNDER', verified: '2026-07-26'));
      expect(issues.single.blockedOn, 'FOUNDER');
      expect(issues.single.verified, '2026-07-26');
    });

    test('a line anchor points at the section header', () {
      final board = '# Board\n\n${_entry('OI-44', 'x', 'OPEN')}';
      expect(parseOpenIssues(board).single.line, 3);
    });

    test('fields from the NEXT section do not bleed into this one', () {
      final issues = parseOpenIssues(
          _entry('OI-44', 'first', 'OPEN', blocked: 'none', verified: 'never') +
              _entry('OI-45', 'second', 'OPEN',
                  blocked: 'FOUNDER', verified: '2026-07-26'));
      expect(issues[0].blockedOn, 'none');
      expect(issues[0].verified, 'never');
      expect(issues[1].blockedOn, 'FOUNDER');
    });

    test('a `#` wave header also ends a section', () {
      final issues = parseOpenIssues(
          '${_entry('OI-44', 'first', 'OPEN')}# Second wave\n\n'
          '${_entry('OI-45', 'second', 'OPEN', blocked: 'FOUNDER')}');
      expect(issues[0].blockedOn, 'none',
          reason: 'the wave header must stop the field scan');
    });

    test('CLOSED-only board yields nothing', () {
      expect(parseOpenIssues(_entry('OI-1', 'x', 'CLOSED')), isEmpty);
    });
  });

  group('OI-112 scar: an id minted twice must ERROR, never render', () {
    // Six ids (OI-100..105) existed twice on 2026-08-13 — once on `main`, once
    // on a branch — naming entirely different issues. The two boards MERGED
    // CLEANLY (git saw additions in different regions of one file), the
    // generator rendered the result and exited 0, and `closes-oi: OI-NN`
    // silently stopped naming one thing.

    test('a clean board reports nothing', () {
      expect(
          duplicateIds(
              _entry('OI-1', 'a', 'OPEN') + _entry('OI-2', 'b', 'OPEN')),
          isEmpty);
    });

    test('the same id twice is reported with its count', () {
      final d = duplicateIds(_entry('OI-104', 'one thing', 'OPEN') +
          _entry('OI-104', 'a DIFFERENT thing', 'OPEN'));
      expect(d, hasLength(1));
      expect(d.single, contains('OI-104'));
      expect(d.single, contains('2'));
    });

    // THE load-bearing case. An implementation written over parseOpenIssues'
    // result — the obvious one — passes every other test in this group and
    // fails this one, because that parser drops CLOSED entries before the
    // check can see them. The board is keyed by id regardless of status.
    test('an OPEN id colliding with a CLOSED one is still a duplicate', () {
      final board = _entry('OI-79', 'still open here', 'OPEN') +
          _entry('OI-79', 'closed over here', 'CLOSED · 2026-07-28 · `abc123`');
      expect(parseOpenIssues(board), hasLength(1),
          reason: 'precondition: the OPEN-only parse sees just one of these');
      expect(duplicateIds(board), hasLength(1),
          reason: 'but the duplicate check must see BOTH — scanning headers, '
              'not the OPEN-only result');
    });

    test('reports every duplicated id, in numeric order', () {
      // The ids MUST span digit widths or this test cannot fail for the
      // property it names. B-pass caught the first version using
      // OI-100..105 — six ids of identical width, where lexical and numeric
      // order COINCIDE, so a lexical `.sort()` passed it while the `reason:`
      // string claimed otherwise. Same shape as the sibling parseOpenIssues
      // sort test above, and the same lesson as Gate 44: a test that cannot
      // go red proves nothing.
      //
      // Numeric:  OI-9, OI-10, OI-100, OI-105
      // Lexical:  OI-10, OI-100, OI-105, OI-9   <- first AND last both differ
      final board = [9, 10, 100, 105]
          .map((n) => _entry('OI-$n', 'mine', 'OPEN') +
              _entry('OI-$n', 'theirs', 'OPEN'))
          .join();
      final d = duplicateIds(board);
      expect(d, hasLength(4));
      expect(d.first, contains('OI-9'),
          reason: 'numeric order — a lexical sort puts OI-10 first');
      expect(d.last, contains('OI-105'),
          reason: 'numeric order — a lexical sort puts OI-9 last');
    });

    test('the real 2026-08-13 shape: six ids duplicated at once', () {
      final board = [100, 101, 102, 103, 104, 105]
          .map((n) => _entry('OI-$n', 'mine', 'OPEN') +
              _entry('OI-$n', 'theirs', 'OPEN'))
          .join();
      expect(duplicateIds(board), hasLength(6));
    });

    test('three of the same id counts three, not two', () {
      final d = duplicateIds(_entry('OI-7', 'a', 'OPEN') +
          _entry('OI-7', 'b', 'OPEN') +
          _entry('OI-7', 'c', 'OPEN'));
      expect(d.single, contains('3'));
    });
  });

  group('missing fields are detectable (the generator fails closed on these)', () {
    test('absent Blocked on surfaces as empty, not as a default', () {
      final i = parseOpenIssues(_entry('OI-44', 'x', 'OPEN', blocked: null));
      expect(i.single.blockedOn, isEmpty,
          reason: 'silently defaulting would hide that nobody triaged it');
    });

    test('absent Verified surfaces as empty', () {
      final i = parseOpenIssues(_entry('OI-44', 'x', 'OPEN', verified: null));
      expect(i.single.verified, isEmpty);
    });
  });

  group('OI-68 scar: unknown vocabulary must ERROR, never vanish', () {
    // open_issues.md OI-68 records two withdrawn attempts at this mechanism and
    // says "read before re-attempting". Its third-generation failure verbatim:
    // "the format gate validated shape but not vocabulary — PENDING, BLOCKED,
    // REOPENED and a one-character IN-PROGRESS typo all passed the gate and
    // vanished from the digest." The first draft of this generator reproduced
    // it exactly, via `if (!status.startsWith('OPEN')) continue;`.
    for (final word in ['PENDING', 'BLOCKED', 'REOPENED', 'IN-PROGESS']) {
      test('"$word" is reported, not silently dropped', () {
        final board = _entry('OI-44', 'x', word);
        expect(unrecognisedStatuses(board), hasLength(1),
            reason: '$word must be named as unrecognised');
        expect(unrecognisedStatuses(board).single, contains('OI-44'));
        expect(parseOpenIssues(board), isEmpty,
            reason: 'and it must NOT silently appear as open either');
      });
    }

    test('the known vocabulary is accepted', () {
      final board = _entry('OI-1', 'a', 'OPEN') +
          _entry('OI-2', 'b', 'IN_PROGRESS') +
          _entry('OI-3', 'c', 'CLOSED · 2026-07-28 · `abc123`');
      expect(unrecognisedStatuses(board), isEmpty);
      expect(parseOpenIssues(board).map((i) => i.id), ['OI-1', 'OI-2']);
    });

    test('a section with NO status line is reported', () {
      expect(unrecognisedStatuses('## OI-9 — t\n\n- **Identified**: x\n'),
          hasLength(1));
    });

    test('a trailing qualifier does not change the word', () {
      expect(statusWord('CLOSED · 2026-07-28 · `abc123`'), 'CLOSED');
      expect(statusWord('**OPEN**'), 'OPEN');
      expect(statusWord('IN-PROGRESS'), 'IN_PROGRESS');
    });

    test('a doubly-bolded OPEN still parses (sibling-parser parity)', () {
      // check_closes_oi_cited.dart already stripped `**` from values; the two
      // disagreeing on the same board text is how one gate fires and the other
      // stays silent.
      final board = _entry('OI-44', 'x', '**OPEN**');
      expect(unrecognisedStatuses(board), isEmpty);
      expect(parseOpenIssues(board), hasLength(1));
    });
  });

  group('renderIndex', () {
    test('one line per issue, and the count is stated', () {
      final issues = parseOpenIssues(
          _entry('OI-44', 'first', 'OPEN') + _entry('OI-45', 'second', 'OPEN'));
      final out = renderIndex(issues);
      expect(out, contains('**2 open.**'));
      expect('\n'.allMatches(out).length, lessThan(30),
          reason: 'size discipline — an index as large as the board is not an index');
      expect(out, contains('| OI-44 |'));
      expect(out, contains('open_issues.md#L'));
    });

    test('a pipe in a title cannot break the table', () {
      final issues = parseOpenIssues(_entry('OI-44', 'a | b', 'OPEN'));
      expect(renderIndex(issues), contains(r'a \| b'));
    });

    test('a long title is truncated on a word boundary', () {
      final issues =
          parseOpenIssues(_entry('OI-44', List.filled(40, 'word').join(' '), 'OPEN'));
      final title = issues.single.title;
      expect(title.length, lessThanOrEqualTo(75));
      expect(title, endsWith('…'));
      expect(title, isNot(contains('wor…')));
    });
  });
}
