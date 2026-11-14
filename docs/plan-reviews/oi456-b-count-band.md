---
branch: oi456-b-count-band
date: 2026-11-04
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/db0dd5d9690f-review.md
---

# Plan-review record: OI-456 piece B, the exercise count band (platform)

Keystone record for the 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED:** the change touches `lib/shared/repositories/plan_engine/` (allocator, budget tables) and
the nested CLAUDE.md of that folder; `dart run scripts/blast_radius_from_diff.dart` on those paths is run before the
commit and its output recorded in the commit body.

## What this branch is

Piece B of OI-456 (`docs/plans/2026-11-04-oi456-b-count-band.md`, v6): the exercise count is a band. Every day SEATS its
exercises at 2 sets up to the level's maximum (beginner 5, intermediate 6, advanced 8), a force step meets the floor
(5 from 45 minutes, 4 from 25, 3 below; founder decision D-A, 2026-11-04 "option 2") with the clock as the only thing it
may override (never a session cap or weekly top, at most 300 s over the day's budget), then every exercise grows to 3
sets and on to the weekly bands. `plan_generator.dart` is NOT touched (rule 14 holds). Execution mode: INLINE.

## Rounds

Piece B was SPLIT from the original OI-456 design after three non-converging rounds on the combined design (CLAUDE.md
4.12.1; see `docs/plan-reviews/exercise-count-band.md`). Reviewed on its own, three fresh context-blind Sonnet reviewers:

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| B#1 | v4 | 2 P1 (+6 P2) | the force step cannot use `ledger.fits` (it reads a negative `secondsLeft` as no room even for 0 seconds); `countForced` broke the gate's time exemption, and the gate path was cited wrong. Both folded into v5 |
| B#2 | v5 | 1 P1 (+6 P2) | the floor was a cliff at 30 minutes with unbounded forcing outside the four swept values: floor is now a step function over 15..180 minutes and forcing is bounded (300 s). The non-forced "skip" walk was dead code (pass A already skips): deleted. `countForced` became a map to named slots. Folded into v6 |
| B#3 | v6 | 0 | CONVERGED. Six P2 folded at build time (the reservation test intent, A2 order, `count_limited` docs, the belowFloor check excluding count-limited groups, `hardMax`, a dropped mutant) |

Findings per round fell 2 -> 1 -> 0 P1, each a definition or bound, not a new mechanism.

## Ground truth

- The clock arithmetic (24 / 37 / 50 / 76 minutes of main work at 30 / 45 / 60 / 90; 2-set costs H 6.3, M 5.6, I 4.28,
  B 3.4 minutes) was recomputed independently by reviewers B#1 and B#3 from `SessionBudget.exerciseSeconds` and
  `warmCoolMinutes`, and again by the proof test's literal expectations.
- Every file:line the plan cites was read by at least two reviewers.
- Measured result (`test/plan_generator/rest_by_type_report.md`): the tester persona holds 6 / 6 / 6 / 6 at 60 minutes
  (was 4 / 6 / 4 / 9 before piece A, 6 / 6 / 7 / 6 after it), 4 at 30, 6 at 45 and 90; beginner 5, advanced 8.

## Honest residue

- Seating at 2 sets first means accessories can take weekly top before a lead lift grows: a lead lift can end at 2 sets.
  Stated in the plan, the nested CLAUDE.md and the report; `boundBy` names the blocking group.
- The floor of 4 at 25-29 minutes follows the step function; the founder fixed only the 30-minute value.
- The golden hash fixture was regenerated wholesale (it stores hashes only, so no before/after count table exists); the
  evidence is the measured report, the 7,200-run injury sweeps (0 thin days in 14 of 20 blocks, a shoulder+elbow pair residue of 4 to 22 days in the other six, no empty day) and the sweep inside
  `exercise_count_band_behavioral_test.dart`.
