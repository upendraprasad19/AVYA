---
branch: workout-progression
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-progression-bpass.md
---

# Plan review — workout-progression (Batch 3a: ④ goal-aware cardio finisher default)

Item ④ of the workout-generator overhaul, split out of Batch 3 per the founder's 2026-07-13
decision (ship ④ now as its own small verified batch; ⑦+W2.1 `progression_resolver` rework =
separate Batch 3b). Blast radius **platform** (`cardio_finisher.dart` is plan_engine). `feat`
(no bug → no diagnose-doc). One item, terminal in this batch (§4.2).

## Founder decision (2026-07-13, AskUserQuestion)

**Recommended mapping** (the reserved "quick nod"): `lose_fat`→`hiit`, `general_fitness`→`cycling`,
`recompose`→`jump_rope`. Approach was already LOCKED (goal-keyed default, no new field); the founder
nodded the exact tokens. Also chose **SPLIT** — ④ ships now; the ⑦+W2.1 resolver rework is its own
Batch 3b.

## Review rounds (≥2, before + on the diff)

- **Round 1 — ground-truth audit (self, against code, rule 11):** confirmed `cardio_finisher.dart:21`
  blanket `?? 'hate_cardio'`; the `FitnessGoals.of(goal).cardio` gate (exactly 3 cardio goals, no
  4th); the mapping tokens are all existing `_buildFinisher` cases with bodyweight fallbacks; the
  `PlanEngineFlags` kill-switch pattern.
- **Round 2 — context-blind adversarial review + B-pass (on the plan + implemented diff):**
  `VERDICT: accepted`, all six dimensions verified clean, zero P0/P1/P2. Confirmed the subtle
  correctness hinge (`plan_generator.dart:170` passes the ORIGINAL `goal`, so `recompose→jump_rope`),
  the kill-switch verbatim revert, test non-vacuity, and NO scorecard regression (finishers are
  structurally invisible to the Batch-0 matrix). Two P3 doc nits — one fixed in-batch, one confirmed
  non-blocking. (docs/reviews/workout-progression-bpass.md.)

## Ground-truth verification (true)

Self-verified: `_buildFinisher` cases (cycling/hiit/jump_rope all present); `fitness_goals.dart`
cardio flags (lose_fat/general_fitness/recompose = true; build_muscle/strength = false; no
endurance); the kill-switch getter mirrors the sibling `injuryUniversalFilterEnabled`/
`warmupInjuryFilterEnabled`; no `lib/` caller passes a non-null `cardioPreference`. Every cited line
read directly.

## Verdict: converged

Behavioral test `cardio_goal_default_test.dart` 7/7 (3 goals → their finisher, unchanged non-cardio
goals, non-vacuity, kill-switch revert); Batch-0 scorecard gate green (no regression); analyze clean;
SoT `cardio_goal_default` + plan_engine CLAUDE.md updated. B-pass accepted. No open issues.
