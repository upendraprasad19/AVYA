// test/scripts/bug_index_strict_test.dart
//
// Controls for the pure STRICT validation of the diagnose docs (`validateDiagnoseDocs`,
// `allowedBugIds`, `isDiagnoseDocName`), landing A2 of the merge-conflict-treadmill plan.
//
// WHAT CHANGED. docs/diagnoses/INDEX.md is a local build product now, so nothing commits it and
// Gate 25 (check_diagnose_index_fresh.dart, "every doc is findable in the index") is deleted.
// The builder's strict mode is what is left to refuse an index that would lose a doc, and the
// old builder had three holes this file closes: a doc with unparseable frontmatter was only a
// WARNING (the index silently lost it), a doc with no `date:` crashed the sort with a TypeError
// (`null as String`), and nothing compared `bug_id:` with the file name (Gate 25's id lookup).
//
// Each case names the mutant it kills (rule 21):
//   unparseable frontmatter is a problem       [validation lets it through / `continue` as before]
//   missing, empty and NON-ISO `date:`         [the date check dropped: TypeError in the sort; the
//                                               ISO rule dropped: a row the regression walk skips]
//   missing, empty and placeholder `symptom:` [the symptom self-check dropped; blockScalarRe unused]
//   `bug_id:` rule: suffix, stem, quoted       [suffix only (12 legacy docs red); no unquote (the
//                                               real 2026-10-23 doc red); id check dropped; the
//                                               quote guard `length >= 2` loosened (RangeError)]
//   the REAL corpus has zero problems          [any rule tightened past what the repo satisfies]

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bug_index_lib.dart';
import '../../scripts/local_indexes_lib.dart';

String _doc({String? bugId = 'abc123', String? date = '2026-10-01', String? symptom = 'it broke'}) {
  final b = StringBuffer('---\n');
  if (bugId != null) b.writeln('bug_id: $bugId');
  if (date != null) b.writeln('date: $date');
  if (symptom != null) b.writeln('symptom: $symptom');
  b.writeln('---\n# body');
  return b.toString();
}

DiagnoseValidation _validate(Map<String, String> docs) => validateDiagnoseDocs(
    [for (final e in docs.entries) DiagnoseDocInput(e.key, e.value)]);

void main() {
  group('isDiagnoseDocName: the ONE predicate of builder, validation and stamp inputs', () {
    test('a diagnose doc is a .md that is not INDEX / README / TEMPLATE', () {
      expect(isDiagnoseDocName('2026-10-01-thing-abc123.md'), isTrue);
      expect(isDiagnoseDocName('INDEX.md'), isFalse);
      expect(isDiagnoseDocName('README.md'), isFalse);
      expect(isDiagnoseDocName('TEMPLATE.md'), isFalse);
    });

    test('an editor backup and a non-markdown file never count', () {
      expect(isDiagnoseDocName('2026-10-01-thing-abc123.md~'), isFalse);
      expect(isDiagnoseDocName('2026-10-01-thing-abc123.txt'), isFalse);
      expect(isDiagnoseDocName('.2026-10-01-thing-abc123.md.swp'), isFalse);
    });
  });

  group('allowedBugIds', () {
    test('the 6-character suffix and the whole stem', () {
      expect(allowedBugIds('2026-05-04-restore-completeness-pull-239999.md'),
          {'2026-05-04-restore-completeness-pull-239999', '239999'});
    });

    test('a name with no 6-character suffix allows only the stem', () {
      expect(allowedBugIds('2026-05-16-health-write-service.md'),
          {'2026-05-16-health-write-service'});
    });

    test('a suffix of the wrong length is not an id', () {
      expect(allowedBugIds('2026-10-01-thing-abc12.md'), {'2026-10-01-thing-abc12'});
      expect(allowedBugIds('2026-10-01-thing-abc1234.md'), {'2026-10-01-thing-abc1234'});
    });
  });

  group('validateDiagnoseDocs', () {
    test('a good doc passes and carries `_path`', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc()});
      expect(v.problems, isEmpty);
      expect(v.entries, hasLength(1));
      expect(v.entries.single['_path'], 'docs/diagnoses/2026-10-01-thing-abc123.md');
      expect(v.entries.single['bug_id'], 'abc123');
    });

    test('no frontmatter at all is a problem (the old builder only WARNED and lost the doc)', () {
      final v = _validate({'2026-10-01-thing-abc123.md': '# just prose\n'});
      expect(v.entries, isEmpty);
      expect(v.problems.single, contains('2026-10-01-thing-abc123.md'));
      expect(v.problems.single, contains('no parseable frontmatter'));
    });

    test('an UNCLOSED frontmatter is a problem', () {
      final v = _validate({'2026-10-01-thing-abc123.md': '---\nbug_id: abc123\ndate: 2026-10-01\n'});
      expect(v.problems.single, contains('no parseable frontmatter'));
    });

    test('a missing date: is a problem (it used to be a TypeError in the sort)', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(date: null)});
      expect(v.entries, isEmpty);
      expect(v.problems.single, contains('missing `date:`'));
    });

    test('an EMPTY date: is a problem', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(date: '""').replaceAll('""', '')});
      expect(v.problems.single, contains('missing `date:`'));
    });

    test('a date: that is only quotes or blanks is a problem too (the parser keeps the quotes)', () {
      for (final blank in ['""', "''", '"  "']) {
        final v = _validate({'2026-10-01-thing-abc123.md': _doc(date: blank)});
        expect(v.entries, isEmpty, reason: blank);
        expect(v.problems.single, contains('`date:`'), reason: blank);
      }
    });

    // Gate 25 is gone, so this rule is the only guard on the date. The chronological table sorts on
    // the raw string and the merge-commit regression walk keeps only rows whose first cell is
    // YYYY-MM-DD (regression_catalog_lib.dart); validate_diagnose_doc_lib.dart enforces the newer
    // required fields only for a date that STARTS with it. Any other shape sorted wrongly and
    // silently dropped that doc's regression test from the walk (B-pass seat 1, F2).
    test('a date: that is not a BARE YYYY-MM-DD is a problem naming the value', () {
      for (final bad in [
        '"2026-10-24"', // quoted: valid YAML, but every reader of the index wants it bare
        "'2026-10-24'",
        'soon',
        '24/10/2026',
        '2026-10-24T09:00:00',
        '2026-10-2', // one digit short
        '2026-10-24 and later',
        '20261024',
      ]) {
        final v = _validate({'2026-10-01-thing-abc123.md': _doc(date: bad)});
        expect(v.entries, isEmpty, reason: bad);
        expect(v.problems.single, contains('`date:` "$bad" is not a bare YYYY-MM-DD'), reason: bad);
      }
    });

    test('a bare date is kept AS WRITTEN in the entry (the table, the sort and the walk read that)', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(date: '2026-10-24')});
      expect(v.problems, isEmpty);
      expect(v.entries.single['date'], '2026-10-24');
    });

    test('a missing symptom: is a problem', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(symptom: null)});
      expect(v.problems.single, contains('missing `symptom:`'));
    });

    test('a block scalar with NO body is a problem (c4e8a2: the index sat 237 of 344 entries empty)', () {
      for (final ind in ['>', '|', '>-', '|2']) {
        final v = _validate({'2026-10-01-thing-abc123.md': '---\nbug_id: abc123\ndate: 2026-10-01\nsymptom: $ind\n---\n'});
        expect(v.problems, hasLength(1), reason: 'indicator $ind');
        expect(v.problems.single, contains('symptom'), reason: 'indicator $ind');
      }
    });

    test('a folded body that is itself only an indicator is a problem (the placeholder check)', () {
      final v = _validate({
        '2026-10-01-thing-abc123.md': '---\nbug_id: abc123\ndate: 2026-10-01\nsymptom: >\n  >\n---\n'
      });
      expect(v.problems.single, contains('block-scalar indicator'));
    });

    test('a folded symptom: block is fine', () {
      final v = _validate({
        '2026-10-01-thing-abc123.md':
            '---\nbug_id: abc123\ndate: 2026-10-01\nsymptom: >-\n  the coach timed out\n  mid reply\n---\n'
      });
      expect(v.problems, isEmpty);
    });

    test('a missing bug_id: is a problem', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(bugId: null)});
      expect(v.problems.single, contains('bug_id'));
      expect(v.problems.single, contains('is missing'));
    });

    test('a bug_id that is neither the suffix nor the stem is a problem, naming both', () {
      final v = _validate({'2026-10-01-thing-abc123.md': _doc(bugId: 'zzz999')});
      expect(v.entries, isEmpty);
      expect(v.problems.single, contains('"zzz999"'));
      expect(v.problems.single, contains('abc123'));
      expect(v.problems.single, contains('2026-10-01-thing-abc123'));
    });

    test('the bug_id may be the WHOLE STEM (the 12 legacy docs)', () {
      final v = _validate({
        '2026-05-16-health-write-service.md': _doc(bugId: '2026-05-16-health-write-service'),
        '2026-06-01-logpr-bypass.md': _doc(bugId: '2026-06-01-logpr-bypass'),
      });
      expect(v.problems, isEmpty);
      expect(v.entries, hasLength(2));
    });

    test('a QUOTED bug_id is compared unquoted (one real doc is written that way)', () {
      for (final q in ['"abc123"', "'abc123'"]) {
        final v = _validate({'2026-10-01-thing-abc123.md': _doc(bugId: q)});
        expect(v.problems, isEmpty, reason: q);
        // The index still renders the RAW value, exactly as the pre-A2 builder did.
        expect(v.entries.single['bug_id'], q);
      }
    });

    test('a quoted WRONG id and mismatched quotes still fail', () {
      expect(_validate({'2026-10-01-thing-abc123.md': _doc(bugId: '"zzz999"')}).problems, hasLength(1));
      expect(_validate({'2026-10-01-thing-abc123.md': _doc(bugId: '"abc123\'')}).problems, hasLength(1));
    });

    test('a bug_id that is a LONE quote character is a problem, not a RangeError', () {
      // One character that both starts and ends with a quote: an unguarded `substring(1, 0)`.
      for (final q in ['"', "'"]) {
        final v = _validate({'2026-10-01-thing-abc123.md': _doc(bugId: q)});
        expect(v.entries, isEmpty, reason: q);
        expect(v.problems.single, contains('bug_id'), reason: q);
      }
    });

    test('several problems on ONE doc are one line; good docs still pass beside bad ones', () {
      final v = _validate({
        '2026-10-01-bad-aaaaaa.md': _doc(bugId: 'nope', date: null, symptom: null),
        '2026-10-02-good-bbbbbb.md': _doc(bugId: 'bbbbbb'),
      });
      expect(v.problems, hasLength(1));
      expect(v.problems.single, allOf(contains('missing `date:`'), contains('missing `symptom:`'), contains('bug_id')));
      expect(v.entries.map((e) => e['bug_id']), ['bbbbbb']);
    });
  });

  test('the REAL diagnose corpus has zero problems (the rule is satisfiable by every doc in the repo)', () {
    final names = diagnoseDocNames(Directory.current.path);
    expect(names.length, greaterThan(600),
        reason: 'the scan must have seen the real corpus, or this proves nothing');
    final v = validateDiagnoseDocs([
      for (final n in names) DiagnoseDocInput(n, File('docs/diagnoses/$n').readAsStringSync()),
    ]);
    expect(v.problems, isEmpty,
        reason: 'a doc the strict builder refuses would fail the CI build step for every PR');
    expect(v.entries.length, names.length);
  });
}
