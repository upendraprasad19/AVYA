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
