// Pure-predicate tests for scripts/skill_tuning_lib.dart (§5.1 enforcement).
//
// WHY THE GATE EXISTS, so a future reader does not weaken it back: on 2026-08-25
// a B-pass produced docs/reviews/2e9503eb-review.md with 4 findings and NOTHING
// was appended to the skill's Tuning history. §5.1 mandates it; nothing enforced
// it; it surfaced only when founder asked whether discipline had been followed.
//
// The two tests that matter are the near-miss pair at the bottom. A `contains`
// implementation passes every happy-path test in this file and still fails to
// catch a NEW review satisfied by an OLD entry's prose — which is the exact
// input-set-width trap this repo keeps re-learning.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/skill_tuning_lib.dart';

/// A skill file shaped like the real one: dated bullets under a tuning heading,
/// including an entry whose PROSE mentions another date. That prose line is the
/// whole point — it is what a naive `contains()` would match.
const _skill = '''
# Code Review (B-pass)

## 7. Tuning history

- **2026-08-20** — blast-radius **account** — 2 findings; 0 false_alarm.
  Review: docs/reviews/abc123-review.md
  Lens 6 found the P1 by asking its question one level OUT. Related to the
  2026-08-25 discussion of call-site tracing, and to the 2026-08-17 note.
- **2026-08-17** — blast-radius **platform** — 5 findings; 0 false_alarm.
  Review: docs/reviews/older-bpass.md
''';

void main() {
  group('reviewedOnFrom — line-anchored date extraction', () {
    test('reads a well-formed frontmatter date', () {
      expect(
        reviewedOnFrom('---\nreviewed_at: 2026-08-25T09:30:00+05:30\n---\n'),
        '2026-08-25',
      );
    });

    test('returns null when the key is absent', () {
      expect(reviewedOnFrom('---\nverdict: accepted\n---\n'), isNull);
    });

    test('IGNORES a mid-line mention — the key must start the line', () {
      // Prose such as "the reviewed_at: field should say 2026-01-01" must not
      // be mistaken for frontmatter. The keystone plan-review gate parses the
      // same way, and a session already lost a CI run to a bullet header the
      // anchored parser read as null.
      expect(
        reviewedOnFrom('Note that reviewed_at: 2026-01-01 is the format.\n'),
        isNull,
      );
    });
  });

  group('hasTuningEntryFor — the dated-bullet shape', () {
    test('finds an entry for a date that has one', () {
      expect(hasTuningEntryFor(_skill, '2026-08-20'), isTrue);
      expect(hasTuningEntryFor(_skill, '2026-08-17'), isTrue);
    });

    test('NEAR MISS: a date appearing only in another entry PROSE does not '
        'count', () {
      // 2026-08-25 appears in _skill — inside the 08-20 entry's body. A
      // `contains(isoDate)` implementation returns true here and the gate goes
      // silently inert for every future review. This is the test that fails if
      // anyone "simplifies" the matcher.
      expect(hasTuningEntryFor(_skill, '2026-08-25'), isFalse);
    });

    test('NEAR MISS: a plain date line without the bullet+bold shape does not '
        'count', () {
      expect(hasTuningEntryFor('2026-08-25 — ran a review\n', '2026-08-25'),
          isFalse);
    });
  });

  group('evaluateTuning — the verdict a caller acts on', () {
    test('no review added → notApplicable, never a claimed PASS', () {
      final r = evaluateTuning(addedReviews: const [], skillMarkdown: _skill);
      expect(r.verdict, TuningVerdict.notApplicable);
    });

    test('review added WITHOUT its entry → missingEntry, and names the file',
        () {
      final r = evaluateTuning(
        addedReviews: const [
          ReviewClaim('docs/reviews/2e9503eb-review.md', '2026-08-25'),
        ],
        skillMarkdown: _skill,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
      final violations = r.offendingPaths;
      expect(violations, hasLength(1));
      expect(violations.single, contains('2e9503eb'));
    });

    test('review added WITH its entry → satisfied', () {
      final r = evaluateTuning(
        addedReviews: const [
          ReviewClaim('docs/reviews/abc123-review.md', '2026-08-20'),
        ],
        skillMarkdown: _skill,
      );
      expect(r.verdict, TuningVerdict.satisfied);
      expect(r.offendingPaths, isEmpty);
    });

    test('TWO reviews, one entry present → only the uncovered one is named', () {
      final r = evaluateTuning(
        addedReviews: const [
          // The 08-20 entry NAMES this one, so it is covered.
          ReviewClaim('docs/reviews/abc123-review.md', '2026-08-20'),
          ReviewClaim('docs/reviews/bbb-review.md', '2026-08-25'),
        ],
        skillMarkdown: _skill,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
      final violations = r.offendingPaths;
      expect(violations, hasLength(1));
      expect(violations.single, contains('bbb'));
    });

    test('P0: a same-dated entry about a DIFFERENT review does NOT satisfy this '
        'one', () {
      // The B-pass proved this live: SKILL.md already carried a 2026-08-25
      // bullet for the oi60-client-blockers review, so the next review written
      // that same day would have been reported SATISFIED by an entry describing
      // somebody else's batch. Date is not identity — two reviews on one
      // calendar date is ordinary here, not exotic.
      final r = evaluateTuning(
        addedReviews: const [
          ReviewClaim('docs/reviews/some-other-batch-bpass.md', '2026-08-20'),
        ],
        skillMarkdown: _skill, // its 08-20 entry names abc123-review.md
      );
      expect(r.verdict, TuningVerdict.missingEntry,
          reason: 'the dated entry describes abc123, not this review');
      expect(r.offendingPaths.single, contains('some-other-batch'));
    });

    test('the entry may name the review with or without the .md extension', () {
      expect(
        hasTuningEntryForReview(_skill, '2026-08-20', 'docs/reviews/abc123-review.md'),
        isTrue,
      );
      expect(
        hasTuningEntryForReview(_skill, '2026-08-17', 'docs/reviews/older-bpass.md'),
        isTrue,
      );
    });

    test('the reference must sit INSIDE its own dated block, not a neighbour',
        () {
      // older-bpass.md is named under the 08-17 header. Asking whether the
      // 08-20 entry covers it must be false, or the block scan is not scoping.
      expect(
        hasTuningEntryForReview(_skill, '2026-08-20', 'docs/reviews/older-bpass.md'),
        isFalse,
      );
    });

    test('an unreadable archive no longer silences the gate (A1)', () {
      // This used to FAIL OPEN (undetermined). The archive is now only the LEGACY
      // route: null means "no legacy entries", and a review with no `## Tuning
      // entry` section of its own is missing its entry.
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-review.md', '2026-08-25')],
        skillMarkdown: null,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
    });

    test('FAILS OPEN when the review has no parseable date', () {
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-review.md', null)],
        skillMarkdown: _skill,
      );
      expect(r.verdict, TuningVerdict.undetermined);
      expect(r.offendingPaths, hasLength(1));
    });

    test('undetermined is NOT reported as satisfied — the two must not collapse',
        () {
      // The reason the predicate returns an enum rather than a bool: a caller
      // given `false` cannot tell "nothing to check" from "could not check",
      // and would report a PASS it never established.
      final cannotRead = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-review.md', '2026-08-25')],
        skillMarkdown: null,
      );
      final nothingToDo =
          evaluateTuning(addedReviews: const [], skillMarkdown: _skill);
      expect(cannotRead.verdict, isNot(nothingToDo.verdict));
      expect(cannotRead.verdict, isNot(TuningVerdict.satisfied));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // The same-day `(x)` disambiguator (2026-08-30). SKILL.md's own convention
  // for a second review on one date is `- **2026-08-29 (d)** — …`, and FIVE
  // such headers already existed while the matcher required the date to be
  // immediately closed by `**` — so it matched none of them. Found when the
  // gate blocked this batch's own correctly-written `(b)` entry.
  group('same-day (x) disambiguator', () {
    const twoOnOneDate = '''
# Code Review (B-pass)

## 7. Tuning history

- **2026-08-30 (b)** — blast-radius **platform** — 3 findings.
  Review: docs/reviews/second-review.md
- **2026-08-30** — blast-radius **platform** — 6 findings.
  Review: docs/reviews/first-review.md
- **2026-08-17** — blast-radius **platform** — 5 findings.
  Review: docs/reviews/older-bpass.md
''';

    test('a suffixed header counts as a dated bullet', () {
      expect(hasTuningEntryFor(twoOnOneDate, '2026-08-30'), isTrue);
    });

    test('a suffixed entry satisfies its OWN review', () {
      expect(
        hasTuningEntryForReview(
            twoOnOneDate, '2026-08-30', 'docs/reviews/second-review.md'),
        isTrue,
        reason: 'the `(b)` entry names this review — rejecting it forces the '
            'author to flatten the date and lose the disambiguation the '
            'convention exists for',
      );
    });

    // Round-2 review P3: with `[^)]*` the suffix group stopped at the FIRST
    // `)`, so a nested-paren disambiguator matched nothing — and, worse,
    // failed to terminate the block above it.
    test('a NESTED-paren disambiguator is still a header, and still terminates',
        () {
      const nested = '''
## 7. Tuning history

- **2026-08-30** — 6 findings.
  Review: docs/reviews/first-review.md
- **2026-08-29 (see note (details))** — 3 findings.
  Review: docs/reviews/nested-paren-review.md
''';
      expect(hasTuningEntryFor(nested, '2026-08-29'), isTrue,
          reason: 'a nested-paren suffix is still a dated header');
      expect(
        hasTuningEntryForReview(
            nested, '2026-08-29', 'docs/reviews/nested-paren-review.md'),
        isTrue,
        reason: 'and it satisfies its own review');
      expect(
        hasTuningEntryForReview(
            nested, '2026-08-30', 'docs/reviews/nested-paren-review.md'),
        isFalse,
        reason: 'THE DANGEROUS HALF: if the nested header does not terminate '
            'the 08-30 block, that block swallows it and the 08-30 entry is '
            'credited with naming an 08-29 review — a false PASS of the exact '
            'check this function exists to make.',
      );
    });

    test(
        'a suffixed header still TERMINATES the previous block — no false PASS',
        () {
      // The subtler half. If `anyDatedHeader` did not match `(b)` headers, the
      // FIRST entry's block would swallow the `(b)` entry below it, and the
      // first entry would be credited with naming `second-review` — an OLD
      // entry satisfying a NEW review, the exact failure the block scan
      // exists to prevent. Ordered so the plain header precedes nothing that
      // should belong to it.
      const plainFirst = '''
## 7. Tuning history

- **2026-08-30** — blast-radius **platform** — 6 findings.
  Review: docs/reviews/first-review.md
- **2026-08-30 (b)** — blast-radius **platform** — 3 findings.
  Review: docs/reviews/second-review.md
''';
      expect(
        hasTuningEntryForReview(
            plainFirst, '2026-08-30', 'docs/reviews/first-review.md'),
        isTrue,
        reason: 'the plain entry names its own review');
      // And the reverse direction: each entry is credited only with the
      // review IT names, never its neighbour's.
      expect(
        hasTuningEntryForReview(
            plainFirst, '2026-08-30', 'docs/reviews/unrelated-review.md'),
        isFalse,
        reason: 'neither block names this review, so neither may satisfy it',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // The in-review route (merge-conflict-treadmill A1): a review carries its own
  // `## Tuning entry` section, so no two PRs ever edit the same archive line.
  // ─────────────────────────────────────────────────────────────────────────
  group('inReviewEntry — the review carries its own tuning entry', () {
    const fm = '---\nreviewed_at: 2026-10-24T10:00:00+05:30\nblast_radius: platform\n---\n\n# Review\n\n';
    const bullet = '- **2026-10-24** - blast-radius **platform** - 2 findings; 0 false_alarm; tuning: none.';

    String doc(String body, {String frontmatter = fm}) => '$frontmatter$body';
    InReviewCheck check(String review, {String date = '2026-10-24', String? tier = 'platform'}) =>
        inReviewEntry(review, date, tier);

    test('a well-formed section satisfies', () {
      expect(check(doc('## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a blank line between the heading and the bullet is fine', () {
      expect(check(doc('## Tuning entry\n\n\n$bullet\n')).ok, isTrue);
    });

    test('the date must equal reviewed_at', () {
      final r = check(doc('## Tuning entry\n- **2026-10-23** - blast-radius **platform** - x.\n'));
      expect(r.ok, isFalse);
      expect(r.problem, contains('2026-10-23'));
      expect(r.problem, contains('2026-10-24'));
    });

    test('a tier mismatch fails and names both sides', () {
      final r = check(doc('## Tuning entry\n- **2026-10-24** - blast-radius **account** - x.\n'));
      expect(r.ok, isFalse);
      expect(r.problem, allOf(contains('account'), contains('platform')));
    });

    test('a tier with a suffix passes (first word only)', () {
      expect(check(doc('## Tuning entry\n- **2026-10-24** - blast-radius **platform** (L tier: auth) - x.\n')).ok,
          isTrue);
      expect(check(doc('## Tuning entry\n- **2026-10-24** - blast-radius platform (L tier: auth) - x.\n')).ok,
          isTrue);
    });

    test('an unbolded header passes, and the tier word is case-insensitive', () {
      expect(check(doc('## Tuning entry\n- **2026-10-24** - Blast-Radius PLATFORM - x.\n')).ok, isTrue);
    });

    test('a template placeholder or free-text frontmatter tier skips the tier check', () {
      expect(frontmatterBlastRadius('---\nblast_radius: <feature|account|platform|catastrophic>\n---\n'), isNull);
      expect(frontmatterBlastRadius('---\nblast_radius: "platform"\n---\n'), 'platform');
      expect(frontmatterBlastRadius("---\nblast_radius: 'Account (L)'\n---\n"), 'account');
      expect(frontmatterBlastRadius('blast_radius: platform\n'), isNull, reason: 'outside the leading --- block');
      expect(
          check(doc('## Tuning entry\n- **2026-10-24** - blast-radius **account** - x.\n'), tier: null).ok, isTrue);
    });

    test('the dated bullet may carry the same-day (b) disambiguator', () {
      expect(check(doc('## Tuning entry\n- **2026-10-24 (b)** - blast-radius **platform** - x.\n')).ok, isTrue);
    });

    for (final fence in ['```', '````', '~~~']) {
      test('a heading inside a $fence fence does not count', () {
        final r = check(doc('$fence\n## Tuning entry\n$bullet\n$fence\n'));
        expect(r.ok, isFalse);
        expect(r.problem, contains('no `## Tuning entry` heading'));
      });
    }

    test('a closing fence must be at least as long as the opener', () {
      // ```` opened, ``` is NOT a closer, so the heading below stays inside the fence.
      expect(check(doc('````\n```\n## Tuning entry\n$bullet\n````\n')).ok, isFalse);
      // ...and a longer closer does close it.
      expect(check(doc('```\ncode\n`````\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a heading inside an HTML comment does not count', () {
      expect(check(doc('<!--\n## Tuning entry\n$bullet\n-->\n')).ok, isFalse);
    });

    test('a fence containing a comment opener stays a fence (the comment is inert)', () {
      // Two-pass strip-comments-first would eat everything from <!-- to the next --> and
      // could hide or expose the real heading; the single pass keeps the fence a fence.
      expect(check(doc('```\n<!--\n```\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a comment containing a fence opener stays a comment (the fence is inert)', () {
      expect(check(doc('<!--\n```\n-->\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a fence opener whose info string holds a comment opener is still a fence', () {
      // CommonMark: the info string is opaque. Deciding the comment first would open a
      // comment that the closing fence cannot end, hiding the real heading below it.
      expect(check(doc('```<!--\ncode\n```\n## Tuning entry\n$bullet\n')).ok, isTrue);
      // ...and the heading INSIDE that fence stays inert.
      expect(check(doc('```<!--\n## Tuning entry\n$bullet\n```\n')).ok, isFalse);
    });

    test('a header tier that is not one of the four (n/a, free text) skips the check', () {
      expect(check(doc('## Tuning entry\n- **2026-10-24** - blast-radius n/a - x.\n')).ok, isTrue);
      expect(check(doc('## Tuning entry\n- **2026-10-24** - blast-radius (see note) - x.\n')).ok, isTrue);
    });

    test('a comment opened and closed on one line does not swallow the next heading', () {
      expect(check(doc('<!-- note -->\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('an unclosed fence names the line it opened on', () {
      final r = check(doc('text\n```dart\ncode\n## Tuning entry\n$bullet\n'));
      expect(r.ok, isFalse);
      expect(r.problem, contains('fence opened at line'));
    });

    test('an unclosed comment names the line it opened on', () {
      final r = check(doc('<!-- never closed\n## Tuning entry\n$bullet\n'));
      expect(r.ok, isFalse);
      expect(r.problem, contains('comment opened at line'));
    });

    test('a heading with trailing words does not count', () {
      expect(check(doc('## Tuning entry (draft)\n$bullet\n')).ok, isFalse);
      expect(check(doc('## Tuning entry\t\n$bullet\n')).ok, isTrue, reason: 'trailing whitespace is allowed');
    });

    test('an indented heading does not count (column 0 only)', () {
      expect(check(doc('  ## Tuning entry\n$bullet\n')).ok, isFalse);
    });

    test('a valid dated bullet with no heading fails', () {
      expect(check(doc('$bullet\n')).ok, isFalse);
    });

    test('the dated bullet must be the FIRST non-blank line after the heading', () {
      final r = check(doc('## Tuning entry\nSome prose first.\n$bullet\n'));
      expect(r.ok, isFalse);
      expect(r.problem, contains('not a dated bullet'));
    });

    test('a heading with nothing after it fails', () {
      expect(check(doc('## Tuning entry\n\n\n')).ok, isFalse);
    });

    test('the FIRST qualifying heading is judged; a later good one cannot rescue it', () {
      final r = check(doc('## Tuning entry\nprose\n\n## Tuning entry\n$bullet\n'));
      expect(r.ok, isFalse);
    });

    test('an UPPER-CASE header tier is lower-cased before it is compared', () {
      final r = check(doc('## Tuning entry\n- **2026-10-24** - blast-radius **ACCOUNT** - x.\n'));
      expect(r.ok, isFalse);
      expect(r.problem, allOf(contains('account'), contains('platform')));
    });

    test('a colon after blast-radius is read too', () {
      final r = check(doc('## Tuning entry\n- **2026-10-24** - blast-radius: account - x.\n'));
      expect(r.ok, isFalse);
      expect(r.problem, allOf(contains('account'), contains('platform')));
      expect(check(doc('## Tuning entry\n- **2026-10-24** - blast-radius: platform - x.\n')).ok, isTrue);
    });

    test('the frontmatter tier is read from the leading block only, never past its closing ---', () {
      const noTier = '---\nreviewed_at: 2026-10-24T10:00:00+05:30\n---\n\nblast_radius: account\n\n';
      expect(frontmatterBlastRadius(noTier), isNull);
      expect(check(doc('## Tuning entry\n$bullet\n', frontmatter: noTier), tier: frontmatterBlastRadius(noTier)).ok,
          isTrue);
    });

    test('a BOM or leading blank lines before the frontmatter do not switch the tier or date reads off', () {
      final bom = String.fromCharCode(0xFEFF);
      expect(frontmatterBlastRadius('$bom---\nblast_radius: platform\n---\n'), 'platform');
      expect(frontmatterBlastRadius('\n\n---\nblast_radius: platform\n---\n'), 'platform');
      expect(reviewedOnFrom('$bom---\nreviewed_at: 2026-10-24T10:00:00+05:30\n---\n'), '2026-10-24');
      expect(reviewedOnFrom('${bom}reviewed_at: 2026-10-24T10:00:00+05:30\n'), '2026-10-24',
          reason: 'the key itself is the first line, so only the BOM stands in front of it');
      expect(check('$bom${doc('## Tuning entry\n$bullet\n')}').ok, isTrue);
    });

    test('a backtick fence whose info string holds a backtick is not a fence; a tilde one is', () {
      expect(check(doc('``` a`b\n## Tuning entry\n$bullet\n')).ok, isTrue);
      expect(check(doc('~~~ a`b\n## Tuning entry\n$bullet\n~~~\n')).ok, isFalse);
    });

    test('a fence opener indented 4 spaces is code, not a fence; 3 spaces is a fence', () {
      expect(check(doc('    ```\n## Tuning entry\n$bullet\n')).ok, isTrue);
      expect(check(doc('   ```\n## Tuning entry\n$bullet\n   ```\n')).ok, isFalse);
    });

    test('a closer indented 4 spaces does not close the fence; 3 spaces does', () {
      final r = check(doc('```\ntext\n    ```\n## Tuning entry\n$bullet\n'));
      expect(r.ok, isFalse);
      expect(r.problem, contains('never closed'));
      expect(check(doc('```\ntext\n   ```\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a comment opener quoted in an inline code span does not open a comment', () {
      expect(check(doc('The scanner opens on `<!--` anywhere.\n\n## Tuning entry\n$bullet\n')).ok, isTrue);
      expect(check(doc('Quoted ``a ` <!-- b`` here.\n\n## Tuning entry\n$bullet\n')).ok, isTrue);
    });

    test('a backslash-escaped opener is literal; an even run of backslashes is not an escape', () {
      expect(check(doc('Write \\<!-- to quote it.\n\n## Tuning entry\n$bullet\n')).ok, isTrue);
      expect(check(doc('Write \\\\<!-- opens one.\n\n## Tuning entry\n$bullet\n')).ok, isFalse);
    });

    test('MIRROR: a real mid-line opener still opens a comment, an unmatched backtick does not hide it', () {
      final r = check(doc('text <!-- hidden\n\n## Tuning entry\n$bullet\n'));
      expect(r.ok, isFalse);
      expect(r.problem, allOf(contains('comment opened at line'), contains('backticks')));
      expect(check(doc('a ` b <!-- c\n\n## Tuning entry\n$bullet\n')).ok, isFalse,
          reason: 'a backtick with no closing run is literal text');
      expect(check(doc('a `x` <!-- c --> d\n\n## Tuning entry\n$bullet\n')).ok, isTrue,
          reason: 'a comment that closes on its own line hides nothing');
    });

    test('a CRLF review passes', () {
      final crlf = doc('## Tuning entry\n$bullet\n').replaceAll('\n', '\r\n');
      expect(check(crlf).ok, isTrue);
    });
  });

  group('evaluateTuning — the two routes', () {
    const section = '---\nreviewed_at: 2026-10-24T10:00:00+05:30\nblast_radius: platform\n---\n\n'
        '## Tuning entry\n- **2026-10-24** - blast-radius **platform** - 1 finding.\n';
    const bare = '---\nreviewed_at: 2026-10-24T10:00:00+05:30\nblast_radius: platform\n---\n\n# no section\n';

    test('a section satisfies with the archive ABSENT (the in-review route does not read it)', () {
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-bpass.md', '2026-10-24', body: section)],
        skillMarkdown: null,
      );
      expect(r.verdict, TuningVerdict.satisfied);
    });

    test('a review WITHOUT a section and a null archive is missingEntry, never undetermined', () {
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-bpass.md', '2026-10-24', body: bare)],
        skillMarkdown: null,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
      expect(r.offendingPaths.single, contains('no `## Tuning entry` heading'));
    });

    test('a legacy archive entry that names the review still satisfies it', () {
      const archive = '- **2026-10-24** - blast-radius **platform** - 1 finding.\n  Review: docs/reviews/x-bpass.md\n';
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-bpass.md', '2026-10-24', body: bare)],
        skillMarkdown: archive,
      );
      expect(r.verdict, TuningVerdict.satisfied);
    });

    test('a same-dated archive entry about ANOTHER review does not satisfy it', () {
      const archive = '- **2026-10-24** - blast-radius **platform** - 1 finding.\n  Review: docs/reviews/other-bpass.md\n';
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-bpass.md', '2026-10-24', body: bare)],
        skillMarkdown: archive,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
    });

    test('an unreadable staged body cannot satisfy the in-review route', () {
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-bpass.md', '2026-10-24')],
        skillMarkdown: null,
      );
      expect(r.verdict, TuningVerdict.missingEntry);
    });
  });

  group('countDatedHeaders — what the freeze counts', () {
    test('counts bullets, suffixed bullets and indented sub-bullets; ignores prose dates', () {
      const md = '''
# Tuning history

- **2026-08-20** - one
  - **2026-08-21 (b)** - sub-bullet entry
- **2026-08-22** - two
Prose mentioning 2026-08-23 and **2026-08-24** inline does not count.
''';
      expect(countDatedHeaders(md), 3);
      expect(datedHeaderLines(md), hasLength(3));
      expect(isDatedHeaderLine('- **2026-08-20** - x'), isTrue);
      expect(isDatedHeaderLine('Prose 2026-08-20'), isFalse);
    });

    test('an in-place edit of a header keeps the count', () {
      expect(countDatedHeaders('- **2026-08-20** - a\n'), countDatedHeaders('- **2026-08-20** - edited text\n'));
    });
  });
}
