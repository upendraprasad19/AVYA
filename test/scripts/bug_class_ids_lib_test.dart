// test/scripts/bug_class_ids_lib_test.dart
//
// Unit tests for scripts/bug_class_ids_lib.dart (the pure parser and checker behind
// scripts/check_bug_class_numbers_unique.dart, landing B of the merge-conflict-treadmill plan,
// OI-167). Plan: docs/plans/bug-class-uniqueness.md section 5, tests 1-10.
//
// Every fixture here is built to reach ONE branch of the library: a duplicate that only differs
// by leading zeros, a fence indented like the real ones, a stray row after each of the three
// table terminators, a fixture that ENDS on a lower id than its maximum (the 2026-09-07 `tail -1`
// mistake). Expectations are literal values, never recomputed from the code under test.

@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bug_class_ids_lib.dart';

/// A minimal SKILL.md: a prelude, the index table under its heading, then a `---` rule.
String _skill(List<String> rows, {List<String> after = const ['---', '', '## 3. Red flags']}) {
  return [
    '# Skill',
    '',
    '### Bug-class index (bodies live elsewhere)',
    '',
    '| id | title | trigger | regression test |',
    '|---|---|---|---|',
    ...rows,
    '',
    ...after,
    '',
  ].join('\n');
}

String _row(String id, String title) => '| $id | $title | a trigger | - |';

String _classes(List<String> headings) => ['# Bodies', '', ...headings.expand((h) => [h, 'body', ''])].join('\n');

CatalogReport _check(String classes, String skill) => checkBugClassNumbers(classes, skill);

List<String> _ids(Iterable<ClassHeading> hs) => hs.map((h) => h.id.toString()).toList();

void main() {
  group('1 heading shapes', () {
    test('a heading with and without a title', () {
      final s = scanHeadings('### 2.1 Writer drift\n### 2.2\n');
      expect(_ids(s.headings), ['2.1', '2.2']);
      expect(s.headings[0].title, 'Writer drift');
      expect(s.headings[1].title, '');
      expect(s.headings[0].line, 1);
      expect(s.headings[1].line, 2);
      expect(s.lookalikes, isEmpty);
    });

    test('the superseded-entry shape is neither an id nor a lookalike', () {
      final s = scanHeadings('### 2.5.archived-2026-01-01 old text\n### 2.6 Real\n');
      expect(_ids(s.headings), ['2.6']);
      expect(s.lookalikes, isEmpty);
    });

    test('shapes that look like a heading but are not accepted are lookalikes', () {
      final s = scanHeadings([
        '#### 2.7 deeper',
        '### 2.7x suffix',
        '### 2.124: Title',
        '###2.124',
        '##### 2.9 five',
        '',
      ].join('\n'));
      expect(s.headings, isEmpty);
      expect(s.lookalikes.map((n) => n.line).toList(), [1, 2, 3, 4, 5]);
    });

    test('leading zeros parse to the same id, so 2.05 and 2.5 are a duplicate', () {
      final s = scanHeadings('### 2.05 A\n### 2.5 B\n');
      expect(_ids(s.headings), ['2.5', '2.5']);
      final r = _check('### 2.05 A\n\n### 2.5 B\n', _skill([_row('2.5', 'A')]));
      expect(r.findings.map((f) => f.message), contains('id 2.5 is used by 2 headings (lines 1, 3)'));
    });

    test('a number too large for an int is a finding, not an exception', () {
      final s = scanHeadings('### 2.${'9' * 40} huge\n');
      expect(s.headings, isEmpty);
      expect(s.lookalikes.single.line, 1);
    });
  });

  group('2 fences', () {
    test('backtick and tilde fences hide a heading', () {
      final s = scanHeadings('```\n### 2.9 in a fence\n```\n~~~\n### 2.8 in a tilde fence\n~~~\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('a fence opened with two spaces of indent still hides a COLUMN-0 heading', () {
      final s = scanHeadings('  ```sh\n### 2.9 inside\n  ```\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('a closer of a different character does not close', () {
      final s = scanHeadings('```\n~~~\n### 2.9 still inside\n```\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('a shorter closer does not close', () {
      final s = scanHeadings('````\n```\n### 2.9 still inside\n````\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('an unclosed fence swallows the rest of the text', () {
      final s = scanHeadings('### 2.1 real\n```\n### 2.9 swallowed\n### 2.8 swallowed\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('four spaces of indent is NOT a fence', () {
      final s = scanHeadings('    ```\n### 2.9 visible\n');
      expect(_ids(s.headings), ['2.9']);
    });

    test('a line that merely starts with an inline code span is not a fence', () {
      final s = scanHeadings('```code``` then prose\n### 2.9 visible\n');
      expect(_ids(s.headings), ['2.9']);
    });

    test('a lookalike inside a fence is ignored', () {
      final s = scanHeadings('```\n### 2.124: Title\n```\n');
      expect(s.lookalikes, isEmpty);
    });
  });

  test('3 CRLF text parses like LF text', () {
    final lf = scanHeadings('### 2.1 A\n### 2.2 B\n');
    final crlf = scanHeadings('### 2.1 A\r\n### 2.2 B\r\n');
    expect(_ids(crlf.headings), _ids(lf.headings));
    expect(crlf.headings[0].title, 'A');
    // a heading WITHOUT a title ends in the carriage return itself: it only parses if the CR is stripped
    final bare = scanHeadings('### 2.3\r\n### 2.4 X\r\n');
    expect(_ids(bare.headings), ['2.3', '2.4']);
    expect(bare.lookalikes, isEmpty);
    final idx = scanIndex(_skill([_row('2.1', 'A')]).replaceAll('\n', '\r\n'));
    expect(idx!.rows.single.id.toString(), '2.1');
  });

  group('4 duplicates', () {
    test('two, then three headings with one id name every line', () {
      var r = _check(_classes(['### 2.1 A', '### 2.1 B']), _skill([_row('2.1', 'A')]));
      expect(r.findings.single.message, 'id 2.1 is used by 2 headings (lines 3, 6)');
      expect(r.findings.single.line, 3);
      expect(r.findings.single.file, kBugClassesPath);
      r = _check(_classes(['### 2.1 A', '### 2.1 B', '### 2.1 C']), _skill([_row('2.1', 'A')]));
      expect(r.findings.single.message, 'id 2.1 is used by 3 headings (lines 3, 6, 9)');
    });

    test('rows only', () {
      final r = _check(_classes(['### 2.1 A']), _skill([_row('2.1', 'A'), _row('2.1', 'A')]));
      expect(r.findings.single.file, kBugClassSkillPath);
      expect(r.findings.single.message, 'id 2.1 is used by 2 index rows (lines 7, 8)');
    });

    test('both files at once give two findings', () {
      final r = _check(
        _classes(['### 2.1 A', '### 2.1 A']),
        _skill([_row('2.1', 'A'), _row('2.1', 'A')]),
      );
      expect(r.findings.length, 2);
    });
  });

  group('5 set difference', () {
    test('a heading without a row, and a row without a heading', () {
      final r = _check(_classes(['### 2.1 A', '### 2.2 B']), _skill([_row('2.1', 'A'), _row('2.3', 'C')]));
      final msgs = r.findings.map((f) => f.message).toList();
      expect(msgs, contains('id 2.2 has a heading but no row in the SKILL.md index'));
      expect(msgs, contains('id 2.3 has an index row but no heading in bug-classes.md'));
      expect(r.findings.length, 2);
    });
  });

  group('6 ordering in the real disorder', () {
    test('the next free id is the numeric maximum, not the last-positioned id', () {
      // 2.61 sits above 2.53-2.60 in the real file; the fixture ENDS on a lower id.
      final ids = [
        const BugClassId(2, 53),
        const BugClassId(2, 61),
        const BugClassId(2, 62),
        const BugClassId(2, 54),
        const BugClassId(2, 41),
        const BugClassId(2, 40),
      ];
      expect(nextFreeId(ids).toString(), '2.63');
    });

    test('numeric, not lexical: 2.100 is above 2.99 and 2.9', () {
      expect(nextFreeId([const BugClassId(2, 9), const BugClassId(2, 99), const BugClassId(2, 100)]).toString(), '2.101');
      expect(nextFreeId([const BugClassId(2, 100), const BugClassId(2, 9)]).toString(), '2.101');
    });

    test('through the report: a file ending on a lower id still yields max + 1', () {
      final r = _check(
        _classes(['### 2.10 A', '### 2.100 B', '### 2.9 C']),
        _skill([_row('2.10', 'A'), _row('2.100', 'B'), _row('2.9', 'C')]),
      );
      expect(r.findings, isEmpty);
      expect(r.nextFree.toString(), '2.101');
    });

    test('ids compare as integer pairs', () {
      expect(const BugClassId(2, 9).compareTo(const BugClassId(2, 10)), lessThan(0));
      expect(const BugClassId(3, 1).compareTo(const BugClassId(2, 99)), greaterThan(0));
      expect(const BugClassId(2, 5) == const BugClassId(2, 5), isTrue);
    });
  });

  group('7 index section bounds', () {
    test('a stray row after the --- rule is not read', () {
      final idx = scanIndex(_skill([_row('2.1', 'A')], after: ['---', '| 2.9 | stray | t | - |']));
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
    });

    test('a stray row after a ## heading is not read', () {
      final idx = scanIndex(_skill([_row('2.1', 'A')], after: ['## 3. Next', '| 2.9 | stray | t | - |']));
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
    });

    test('a stray row after a ### heading is not read', () {
      final idx = scanIndex(_skill([_row('2.1', 'A')], after: ['### Another table', '| 2.9 | stray | t | - |']));
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
    });

    test('a row above the index heading is not read', () {
      final idx = scanIndex('| 2.8 | early | t | - |\n${_skill([_row('2.1', 'A')])}');
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
    });

    test('a missing index section returns null', () {
      expect(scanIndex('# Skill\n\n| 2.1 | A | t | - |\n'), isNull);
    });

    test('a row without spaces around the bars parses', () {
      final idx = scanIndex(_skill(['|2.5|Title|trigger|-|']));
      expect(idx!.rows.single.id.toString(), '2.5');
      expect(idx.rows.single.title, 'Title');
    });

    test('a row with fewer than four cells, and a row without an id, are malformed', () {
      final idx = scanIndex(_skill(['| 2.5 | Title |', '| not-an-id | x | y | z |']));
      expect(idx!.rows, isEmpty);
      expect(idx.malformed.length, 2);
    });

    test('the header and separator rows are neither rows nor malformed', () {
      final idx = scanIndex(_skill([_row('2.1', 'A')]));
      expect(idx!.malformed, isEmpty);
      expect(idx.rows.length, 1);
    });

    test('an escaped bar inside the title does not split the cell', () {
      final idx = scanIndex(_skill([r'| 2.5 | a \| b | trigger | - |']));
      expect(idx!.rows.single.title, r'a \| b');
    });
  });

  group('8 next free id', () {
    test('with a gap it is still max + 1', () {
      expect(nextFreeId([const BugClassId(2, 1), const BugClassId(2, 7)]).toString(), '2.8');
    });

    test('the maximum only in the rows is found', () {
      final r = _check(_classes(['### 2.1 A']), _skill([_row('2.1', 'A'), _row('2.7', 'Z')]));
      expect(r.nextFree.toString(), '2.8');
    });

    test('the maximum only in the headings is found', () {
      final r = _check(_classes(['### 2.1 A', '### 2.7 Z']), _skill([_row('2.1', 'A')]));
      expect(r.nextFree.toString(), '2.8');
    });

    test('no major-2 id gives null', () {
      expect(nextFreeId(const <BugClassId>[]), isNull);
      expect(nextFreeId([const BugClassId(3, 4)]), isNull);
    });
  });

  group('9 lookalikes, majors and numeric headings in SKILL.md', () {
    test('a lookalike heading in bug-classes.md is a finding naming the line', () {
      final r = _check('### 2.1 A\n\n### 2.2: B\n', _skill([_row('2.1', 'A')]));
      expect(r.findings.map((f) => '${f.file}:${f.line}').toList(), ['$kBugClassesPath:3']);
      expect(r.findings.single.message, contains('looks like a class heading'));
    });

    test('a lookalike heading in SKILL.md is a finding', () {
      final skill = '${_skill([_row('2.1', 'A')])}\n##### 2.9 odd\n';
      final r = _check(_classes(['### 2.1 A']), skill);
      expect(r.findings.single.file, kBugClassSkillPath);
    });

    test('a non-2 major is a finding in a heading and in a row', () {
      final r = _check(_classes(['### 2.1 A', '### 3.1 B']), _skill([_row('2.1', 'A'), _row('3.1', 'B')]));
      final msgs = r.findings.map((f) => f.message).toList();
      expect(msgs.where((m) => m == 'id 3.1 is not in major 2').length, 2);
      expect(r.nextFree.toString(), '2.2', reason: 'a stray major 3 must not redirect --next');
    });

    test('a numeric ### N.M heading inside SKILL.md is a finding', () {
      final skill = '${_skill([_row('2.1', 'A')])}\n### 2.5 A body in the wrong file\n';
      final r = _check(_classes(['### 2.1 A']), skill);
      expect(r.findings.single.file, kBugClassSkillPath);
      expect(r.findings.single.message, contains('class bodies belong in bug-classes.md'));
    });
  });

  group('10 title pairing', () {
    test('equal titles pass; case and punctuation do not matter', () {
      final r = _check(
        _classes(['### 2.1 Writer/reader field drift']),
        _skill([_row('2.1', 'writer reader FIELD drift')]),
      );
      expect(r.findings, isEmpty);
    });

    test('a different class under the same id is a finding', () {
      final r = _check(
        _classes(['### 2.1 A completely different heading text']),
        _skill([_row('2.1', 'Unrelated index wording here')]),
      );
      expect(r.findings.single.message, contains('names different classes'));
      expect(r.findings.single.file, kBugClassSkillPath);
      expect(r.findings.single.line, 7);
    });

    test('only the first 16 alphanumeric characters are compared', () {
      final r = _check(
        _classes(['### 2.1 Sixteen chars here, and then a long tail that differs']),
        _skill([_row('2.1', 'Sixteen chars here, plus other words')]),
      );
      expect(r.findings, isEmpty);
    });

    test('an empty title on either side is a finding', () {
      var r = _check(_classes(['### 2.1']), _skill([_row('2.1', 'A')]));
      expect(r.findings.single.message, contains('empty title'));
      r = _check(_classes(['### 2.1 A']), _skill([_row('2.1', '   ')]));
      expect(r.findings.single.message, contains('empty title'));
    });

    test('a short title that is a prefix of the other side passes', () {
      final r = _check(
        _classes(['### 2.2 IST date-key drift in the receipt path']),
        _skill([_row('2.2', 'IST date-key drift')]),
      );
      expect(r.findings, isEmpty);
    });

    test('two different short titles are a finding', () {
      final r = _check(_classes(['### 2.2 abc']), _skill([_row('2.2', 'xyz')]));
      expect(r.findings.single.message, contains('names different classes'));
    });

    test('an id duplicated in either file is not paired', () {
      final r = _check(
        _classes(['### 2.1 First meaning', '### 2.1 Second meaning']),
        _skill([_row('2.1', 'Something else entirely')]),
      );
      expect(r.findings.length, 1, reason: 'only the duplicate finding, no pairing noise');
      expect(r.findings.single.message, contains('is used by 2 headings'));
    });
  });

  group('the report', () {
    test('a missing index section is flagged and yields no per-heading flood', () {
      final r = _check(_classes(['### 2.1 A']), '# Skill\n');
      expect(r.indexSectionMissing, isTrue);
      expect(r.findings, isEmpty);
    });

    test('findings come out ordered by file then line', () {
      final r = _check(
        _classes(['### 2.1 A', '### 2.1 A', '### 2.2 B']),
        _skill([_row('2.1', 'A'), _row('2.9', 'Z')]),
      );
      final order = r.findings.map((f) => '${f.file}:${f.line}').toList();
      final sorted = [...order]..sort();
      expect(order, sorted);
    });

    test('a clean catalog has no findings', () {
      final r = _check(_classes(['### 2.1 A', '### 2.2 B']), _skill([_row('2.1', 'A'), _row('2.2', 'B')]));
      expect(r.findings, isEmpty);
      expect(r.headings.length, 2);
      expect(r.rows.length, 2);
      expect(r.indexSectionMissing, isFalse);
    });
  });
  group('B-pass boundary and mirror cases', () {
    test('the 16th alphanumeric character is compared, the 17th is not', () {
      var r = _check(_classes(['### 2.1 Alpha beta gamma Delta']), _skill([_row('2.1', 'Alpha beta gamma Dxlta')]));
      expect(r.findings.single.message, contains('names different classes'));
      r = _check(_classes(['### 2.1 Alpha beta gamma Delta']), _skill([_row('2.1', 'Alpha beta gamma Dexta')]));
      expect(r.findings, isEmpty);
    });

    test('digits are part of the title, underscores and punctuation are not', () {
      var r = _check(_classes(['### 2.1 Writer drift v1']), _skill([_row('2.1', 'Writer drift v2')]));
      expect(r.findings.single.message, contains('names different classes'));
      r = _check(_classes(['### 2.1 a_b c']), _skill([_row('2.1', 'ab, c')]));
      expect(r.findings, isEmpty);
    });

    test('a title in another script pairs by its letters and is never "empty"', () {
      const hi = 'मेरा वर्ग';
      const other = 'अलग शीर्षक';
      var r = _check(_classes(['### 2.1 $hi']), _skill([_row('2.1', hi)]));
      expect(r.findings, isEmpty);
      r = _check(_classes(['### 2.1 $hi']), _skill([_row('2.1', other)]));
      expect(r.findings.single.message, contains('names different classes'));
    });

    test('a line separator character inside a title does not stop the heading parsing', () {
      final title = 'A${String.fromCharCode(0x2028)}B';
      final s = scanHeadings('### 2.1 $title\n');
      expect(s.headings.single.title, title);
      expect(s.lookalikes, isEmpty);
    });

    test('a heading indented one to three spaces is a lookalike finding, four is code', () {
      final s = scanHeadings(' ### 2.1 X\n  ### 2.2 X\n   ### 2.3 X\n    ### 2.4 X\n');
      expect(s.headings, isEmpty);
      expect(s.lookalikes.map((n) => n.line).toList(), [1, 2, 3]);
    });

    test('a level 1 or level 2 numbered heading is a lookalike finding', () {
      final s = scanHeadings('## 2.9 Two\n# 2.8 One\n');
      expect(s.lookalikes.map((n) => n.line).toList(), [1, 2]);
    });

    test('a prose line that starts with #N.M is read as a heading that did not parse (by design)', () {
      final s = scanHeadings('#2.5 for details\n');
      expect(s.lookalikes.single.line, 1);
    });

    test('a row with three cells is malformed, with or without the trailing bar', () {
      expect(scanIndex(_skill(['| 2.5 | Title | trigger |']))!.rows, isEmpty);
      expect(scanIndex(_skill(['| 2.5 | Title | trigger |']))!.malformed.length, 1);
      expect(scanIndex(_skill(['| 2.5 | Title | trigger']))!.rows, isEmpty);
    });

    test('a strikethrough run of two tildes does not open a fence', () {
      final s = scanHeadings('~~struck~~ text\n### 2.9 Nine\n');
      expect(_ids(s.headings), ['2.9']);
    });

    test('a rule with trailing spaces or leading spaces still ends the index table', () {
      var idx = scanIndex(_skill([_row('2.1', 'A')], after: ['--- ', '| 2.9 | stray | t | - |']));
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
      idx = scanIndex(_skill([_row('2.1', 'A')], after: ['  ---', '| 2.9 | stray | t | - |']));
      expect(idx!.rows.map((r) => r.id.toString()).toList(), ['2.1']);
    });

    test('an indented row parses', () {
      final idx = scanIndex(_skill(['  | 2.5 | A | t | - |']));
      expect(idx!.rows.single.id.toString(), '2.5');
    });

    test('a would-be closer that carries text does not close the fence', () {
      final s = scanHeadings('```\n```sh\n### 2.9 inside\n```\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('a fence indented three spaces hides a heading', () {
      final s = scanHeadings('   ```\n### 2.9 inside\n   ```\n### 2.1 real\n');
      expect(_ids(s.headings), ['2.1']);
    });

    test('an id cell with a note after the number is malformed', () {
      final idx = scanIndex(_skill(['| 2.1 (was 2.9) | A | t | - |']));
      expect(idx!.rows, isEmpty);
      expect(idx.malformed.length, 1);
    });

    test('aligned separator rows with one or two dashes are not malformed', () {
      final idx = scanIndex(_skill(['|--|--|--|--|', '|:--|--:|:-:|---|', _row('2.1', 'A')]));
      expect(idx!.malformed, isEmpty);
      expect(idx.rows.length, 1);
    });

    test('findings are ordered by line within one file, not by the order the checks ran', () {
      const classes = '# Bodies\n\n### 2.7: lookalike\nbody\n\n### 2.1 A\n\n### 2.1 A\n';
      final r = _check(classes, _skill([_row('2.1', 'A')]));
      final lines = r.findings.where((f) => f.file == kBugClassesPath).map((f) => f.line).toList();
      expect(lines, [3, 6]);
    });

    test('an unclosed fence is a finding in either file, naming the opening line', () {
      var r = _check('### 2.1 A\n\n```\n### 2.1 hidden duplicate\n', _skill([_row('2.1', 'A')]));
      expect(r.findings.single.file, kBugClassesPath);
      expect(r.findings.single.line, 3);
      expect(r.findings.single.message, contains('never closed'));
      r = _check(_classes(['### 2.1 A']), '${_skill([_row('2.1', 'A')])}\n```\nopen\n');
      expect(r.findings.single.file, kBugClassSkillPath);
      expect(r.findings.single.message, contains('never closed'));
    });

    test('a heading inside an HTML comment still counts (documented, fails closed)', () {
      final r = _check('### 2.1 A\n\n<!--\n### 2.2 B\n-->\n', _skill([_row('2.1', 'A')]));
      expect(r.findings.single.message, contains('id 2.2 has a heading but no row'));
    });

    test('a numeric sub-heading of another major in SKILL.md is not a bug-class body', () {
      final skill = '${_skill([_row('2.1', 'A')])}\n### 5.1 Output subsection\n';
      final r = _check(_classes(['### 2.1 A']), skill);
      expect(r.findings, isEmpty);
    });
  });
}
