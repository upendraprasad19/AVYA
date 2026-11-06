---
branch: oi454-quads
date: 2026-11-06
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/f43b3e0fb8c1-review.md
---

# Plan-review record: OI-454, Quads reach their weekly floor in the 6-day build_muscle split (platform)

Keystone record for the 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, L (plan engine):** `lib/shared/repositories/plan_engine/` (`split_resolver.dart`, `budget_muscle_groups.dart`,
`session_budget.dart`, `session_set_allocator.dart`, `periodization_engine.dart`, `volume_titration.dart`, `plan_engine_flags.dart`,
and one argument block in `plan_generator.dart` under the founder's rule-14 waiver), its nested CLAUDE.md, the SoT registry and
the generator golden. Execution mode: INLINE.

## What this branch is

Legs B swaps its Glutes isolation slot for a Quads compound slot, and `SessionBudgetContext.quadPrimaryCreditsGlutes` (false for
6-day build_muscle only) stops a quad-first exercise from crediting Glutes in the allocator, week 2 and titration. A kill switch
`disable_quad_legs_b` restores both. Plan `docs/plans/2026-11-06-oi454-quads-floor.md` (v2 after round 1, revised after round 2
and the B-pass).

## Rounds

Four fresh context-blind Sonnet reviewers in two rounds (two lenses each: mechanism and scope / measurement in round 1; test honesty
and docs / board / numbers in round 2). Each verified claims against the code, the shipped library and the files.

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| #1 | v1 | 0 P0, 1 P1 (+6 P2) | the Trap Bar Deadlift (Quads first, a hip hinge) would have escaped the Glutes cap; the explanation "the advanced personas are short because the day is full" contradicted the allocator's own labels (bodyweight is `co_group_limited`); the sweep asserted Quads only; the two closure rows were stale; the knee-injured case was unmeasured. Folded into v2: Hamstrings guard, shared predicate `hasQuadLegsBSplit`, production-path tops / caps / minutes / floors / labels, recompose and knee tests, ledger rows, OI-477 filed for the short personas |
| #2 | v2 | 0 P0, 0 P1 (2 P2 + P3) | phases 2 to 5 and a glutes focus were not run; the plan's week-2 / titration wording overreached (titration does not run on a real plan); the `creditedOf` table lacked a leading-unmapped-token row; docs carried stale counts and line numbers. Folded: phase loop, focus test, rows, 8-shape control precondition, four more mutants, citations re-derived |

| B-pass | tree fb168dd4 (merged with main 1118d3b1) | 0 P0 / 0 P1 / 2 P2 | the missing kill switch (added, 4 mutants) and the claims the reviewer could not run (the golden, scorecard, injury sweeps and `keep_all_slots_selection_test` are run on the final tree); six P3 fixed or stated. Review file `docs/reviews/f43b3e0fb8c1-review.md` |

## Ground truth

- Founder case Quads 8 -> 12 of 12 to 16 (Glutes 16 -> 13 credited, Hamstrings 11 -> 12), measured on the real `PlanGenerator.generateV4`.
- 60 of 998 golden personas changed, every one `grid|*|build_muscle|6d|*` (key-set comparison by round-1 and round-2 reviewers); a
  global rule changed 745 and was rejected.
- 24 mutants, 24 red, baseline asserted green first, tree compared with a snapshot afterwards.
- Stated residue: OI-477 (6-day personas still short: 5 of 12 at 90 minutes, 9 of 12 at 60), OI-475 (3, 4 and 5-day splits),
  the stated glute-credit cost, the knee-injured Legs B, a repeat phase replaying a pre-change plan.
