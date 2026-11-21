---
branch: oi458-upper-repeats
date: 2026-11-05
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0f6cd0697ee2-review.md
---

# Plan-review record: OI-458, the Upper day repeats its week's Push and Pull accessories (platform)

Keystone record for the 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, L (plan engine):** `lib/shared/repositories/plan_engine/exercise_selector.dart`, its nested CLAUDE.md,
the SoT registry and two test fixtures. `plan_generator.dart` is NOT touched (rule 14 holds). Execution mode: INLINE.

## What this branch is

An `upper` day soft-avoids the names the earlier push, pull and shoulders_arms days of the same plan hold, per variant,
through the existing `_preferNovel` tiebreak (plan `docs/plans/2026-11-05-oi458-upper-day-variety.md`, v2).

## Rounds

Three fresh context-blind Sonnet reviewers; each verified claims against the code and the live test run.

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| #1 | v1 | 2 P1 (+6 P2) | the golden fixture would redden and was not re-recorded; the 5-day build_muscle split (Upper + Core vs Shoulders + Arms) was unmeasured and its feeder day was not collected. Folded into v2 |
| #2 | v2 | 1 P0, 1 P1 (+4 P2) | my own error: the pairs ratchet in the test still read 42 (the edit missed a reformatted line), so the test was red and the first mutation table proved nothing. Fixed, baseline asserted green, mutants re-run (8 of 8 red); citations and coverage wording corrected |
| #3 | v2 + fixes | 0 (2 P2, documentation) | CONVERGED. The ratchet, golden and shoulders_arms folds verified real; every numeric literal agrees across test, plan, record and diagnose doc; two P2 folded (a `useB` line citation off by one, this cell) |

| B-pass | merged tree d4cee2e8 | 0 P0 / 0 P1 / 3 P2 | all three fixed (core-list path proof, the repeat phase's one-frame fresh fill seeded, an injured sweep + exact control); review file `docs/reviews/0f6cd0697ee2-review.md` |

## Ground truth

- 409 repeated Upper-day names in 42 of 72 generated plans before, 70 in 38 after (real `PlanGenerator.generateV4`).
- 326 of 999 golden keys changed, every one a 4-day or 5-day plan (verified by key-set comparison by reviewer #2).
- Mutation table re-run with the unmutated test asserted green first.

## Honest residue

- Three B-variant mutants (core-list B guard, the fresh-fill and core-list B seeds) cannot be killed on the shipped library: identical output with and without them. Stated in the diagnose doc.
- 70 repeated names remain: shallow cascade-attempt pools; the avoid is soft by design.
- `topUpDays` (injured users) can re-add a name; the 4-day lose_fat / general_fitness split (Upper Push / Upper Pull) and
  the 4-day strength split have no `upper` day, so the avoid does nothing there.
