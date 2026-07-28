// test/contracts/bug_index_frontmatter_test.dart
//
// Regression controls for the YAML block-scalar bug that left 237 of 344
// entries in `docs/diagnoses/INDEX.md` with no symptom text.
//
// CLAUDE.md §4.1.5 makes grepping that index the MANDATORY first step before
// any root-cause hypothesis. While the generator emitted `— >` for every doc
// using `symptom: >`, ~70% of bug history was unsearchable by symptom — and the
// file still looked populated, so nothing surfaced it.
//
// Organised by ATTACK, not by code path: each test names the concrete input
// shape that produced a wrong index entry, and each was run against the real
// helper before being written down.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bug_index_lib.dart';

String _doc(String frontmatter) => '---\n$frontmatter\n---\n\n# body\n';

void main() {
  group('block scalars fold to their body, not their indicator', () {
    test('THE BUG: `symptom: >` yielded the bare indicator', () {
      final fm = parseFrontmatter(_doc('bug_id: aaa111\n'
          'symptom: >\n'
          '  the coach timed out mid-reply\n'));
      expect(fm!['symptom'], 'the coach timed out mid-reply');
      expect(summarize(fm['symptom']), isNot(matches(r'^[|>]')),
          reason: 'this exact value is what rendered as "— >" for 237 entries');
    });

    test('every chomping variant is recognised', () {
      for (final ind in ['|', '|-', '|+', '>', '>-', '>+']) {
        final fm = parseFrontmatter(_doc('symptom: $ind\n  real text here\n'));
        expect(fm!['symptom'], 'real text here', reason: 'indicator $ind');
      }
    });

    test('folded joins with a space; literal keeps the line break', () {
      expect(
          parseFrontmatter(_doc('symptom: >\n  one\n  two\n'))!['symptom'],
          'one two');
      expect(
          parseFrontmatter(_doc('symptom: |\n  one\n  two\n'))!['symptom'],
          'one\ntwo');
    });
  });

  group('a blank line is CONTENT, not a terminator', () {
    // The naive rule ("consume while more-indented than the key") stops at the
    // first blank line, because a blank line is not indented. 36 diagnose docs
    // have a paragraph break inside `symptom:`. Truncating there STILL passes a
    // placeholder check — the value is no longer literally `>` — so this is the
    // failure mode that would have shipped a vacuous fix.
    test('text after an internal blank line survives (the 9f4ab2 shape)', () {
      final fm = parseFrontmatter(_doc('symptom: >-\n'
          '  Hypothetical — no production occurrence yet.\n'
          '\n'
          '  If the natural-key columns ever become NULLable the upsert would\n'
          '  silently merge unrelated rows, producing data loss.\n'));
      expect(fm!['symptom'], contains('data loss'),
          reason: 'truncating at the blank line drops the entire real symptom '
              'while looking fixed');
      expect(summarize(fm['symptom']), contains('data loss'),
          reason: 'summarize must flatten paragraphs, not take only the first');
    });

    test('trailing blank lines are not kept', () {
      final fm = parseFrontmatter(_doc('symptom: >\n  text\n\n\nconcept: x\n'));
      expect(fm!['symptom'], 'text');
      expect(fm['concept'], 'x');
    });
  });

  group('scalar termination', () {
    test('a following key at column 0 is not swallowed', () {
      final fm = parseFrontmatter(_doc('symptom: >\n'
          '  the symptom\n'
          'concept: sync_natural_key_guard\n'
          'status: fixed\n'));
      expect(fm!['symptom'], 'the symptom');
      expect(fm['concept'], 'sync_natural_key_guard');
      expect(fm['status'], 'fixed');
    });

    test('a plain scalar that merely STARTS with > is left alone', () {
      final fm = parseFrontmatter(_doc('symptom: > 5 rows affected\n'));
      expect(fm!['symptom'], '> 5 rows affected',
          reason: 'only a BARE indicator opens a block scalar');
    });

    test('CRLF frontmatter parses identically', () {
      final fm = parseFrontmatter(
          '---\r\nsymptom: >\r\n  windows checkout\r\n---\r\n\r\nbody\r\n');
      expect(fm!['symptom'], 'windows checkout');
    });
  });

  group('summarize', () {
    test('flattens newlines so one grep can match across paragraphs', () {
      expect(summarize('a\n\nb\nc'), 'a b c');
    });

    test('empty and absent fall back rather than rendering blank', () {
      expect(summarize(null, fallback: '(no symptom)'), '(no symptom)');
      expect(summarize('   ', fallback: '(no symptom)'), '(no symptom)');
    });

    test('truncates on a word boundary with an ellipsis', () {
      final out = summarize('word ' * 100, maxLen: 40);
      expect(out.length, lessThanOrEqualTo(41));
      expect(out, endsWith('…'));
      expect(out, isNot(contains('wor…')), reason: 'must not cut mid-word');
    });

    test('a short value is returned untouched', () {
      expect(summarize('brief symptom'), 'brief symptom');
    });
  });
}
