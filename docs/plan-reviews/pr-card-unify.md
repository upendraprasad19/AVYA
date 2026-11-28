---
branch: pr-card-unify
scope: One personal-records card on Home and Train (Train's duplicate key-lift PR reader deleted) and the coach's plateau insight on the plan engine's e1RM scan
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6976a9f52b48-review.md
---

# Plan-review record — one PR card + one plateau definition (83e031, 8300e1)

Plan: `docs/plans/pr-card-unify.md`; mockup `docs/mockups/2026-11-26-pr-card-unify-v1.html`
(founder-approved). Two context-blind review rounds (one Sonnet reviewer each, read-only, on the
PROSE plan before any product code: §4.12.5 needs no CI loop for a plan with no draft diff; the
second round on the plan as revised after the first). Founder decisions D1-D7 recorded in the plan.

## Round 1 — needs-changes (2 P1, 4 P2, 2 P3), all folded (plan section 9)
- P1 stale SoT line ranges are a parity ERROR: a remap step after the last edit of each commit.
- P1 doc gaps (day_swap comment, registry note, Train CLAUDE.md).
- P2 a lapsed lifter would be told to adjust: founder D7 (last session within 14 days, honest
  "over your last N weeks" copy). P2 empty Train state made founder decision D6. P2 test strength.
- P3 token-watch count 6 -> 5; library seeding; the day-swap list has no member pin (checked).

## Round 2 — converged (0 P0/P1, 2 P2, 4 P3), all folded (plan section 10)
Recency maths in IST strings inside the scan; orphan `getExtendedWeeklyWorkoutCounts` deleted;
registry list completed (whole-entry removals, `method:` keys); boundary, pick-rule, rounding and
window tests; TRAIN-14 doc. Plan-engine wrappers verified byte-identical by the reviewer.
