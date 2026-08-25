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

    test('FAILS OPEN when the skill file cannot be read', () {
      final r = evaluateTuning(
        addedReviews: const [ReviewClaim('docs/reviews/x-review.md', '2026-08-25')],
        skillMarkdown: null,
      );
      expect(r.verdict, TuningVerdict.undetermined,
          reason: 'a gate that cannot read its own input must not block a '
              'commit — same contract as check_oi_numbering_unique');
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
}
