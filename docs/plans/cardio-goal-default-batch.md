# Batch 3a — ④ goal-aware cardio finisher default

Workout-generator overhaul item ④ (W1.3), split out of Batch 3 per the founder's
2026-07-13 decision (ship ④ now as its own small verified batch; ⑦+W2.1 resolver
rework = separate Batch 3b). Blast radius **platform** (`cardio_finisher.dart` is
plan_engine). Worktree `workout-progression` off `8bc6113f`. `feat` (no bug → no
diagnose-doc).

## Ground truth (self-verified against code, rule 11 — round 1)

- `cardio_finisher.dart:21` (pre-④): `final preference = cardioPreference ?? 'hate_cardio';`
  — a blanket fallback to the mildest ~5-min mini-HIIT for EVERYONE, because there is no
  `cardioPreference` UI/field anywhere (always null).
- `:19` `if (!FitnessGoals.of(goal).cardio) return weeks;` — the finisher attaches ONLY for
  cardio-enabled goals. Verified `fitness_goals.dart`: `lose_fat`/`general_fitness`/`recompose`
  = `cardio: true`; `build_muscle`/`strength` = `cardio: false`. So exactly 3 goals reach the
  default.
- `_buildFinisher` switch (`:73-85`) has cases `running` / `cycling` / `hiit` / `jump_rope` /
  (`hate_cardio`|default → mini-HIIT). The mapping tokens `hiit` / `cycling` / `jump_rope` are
  all existing cases, each with a bodyweight fallback (`_runningFinisher`/`_cyclingFinisher`
  branch on `hasGymEquipment`; hiit/jump_rope/mini are already bodyweight). So the change picks
  among BUILT options — no new content.

## Decision (founder, 2026-07-13)

**Recommended mapping** (locked approach = goal-keyed default, no new field):
- `lose_fat` → `hiit` (fullest ~10-min finisher — the goal most wanting calorie burn)
- `general_fitness` → `cycling` (~8-min balanced)
- `recompose` → `jump_rope` (~7.5-min moderate)
- `build_muscle`/`strength` unaffected (no finisher attaches — `cardio: false`).

## Change

1. `PlanEngineFlags.cardioGoalDefaultEnabled` — new kill-switch getter
   (`configBox['disable_cardio_goal_default'] != true`; safe-default ON when Hive absent, matching
   the existing `injuryUniversalFilterEnabled`/`warmupInjuryFilterEnabled` pattern).
2. `cardio_finisher.dart`: `preference = cardioPreference ?? _defaultForGoal(goal)`; new
   `_defaultForGoal(goal)` returns the goal-keyed token when the flag is ON, else `'hate_cardio'`
   (the **verbatim pre-④ behavior** — §4.6 old path preserved). The `default:` arm returns
   `'hate_cardio'` defensively (build_muscle/strength never reach it).

## Verification

- Behavioral test `cardio_goal_default_test.dart` (7/7): each of the 3 goals → its finisher
  (asserting the HIIT-only "Jump Squats", cycling's "Stationary Bike Sprints", "Jump Rope
  Intervals"); build_muscle/strength → no finisher (unchanged); non-vacuity (lose_fat ≠ old
  mini-HIIT "High Knees" first move); kill-switch ON → reverts to mini-HIIT.
- Batch-0 scorecard gate green — no regression (mean overall holds 86.8; ④ is a post-selection
  stage not in the main-plan invariants).

## Discipline

Platform-tier → plan-review record (`docs/plan-reviews/workout-progression.md`, review_rounds:2 =
ground-truth audit + context-blind review, converged, bpass:accepted) + self-B-pass before merge
(§4.3) + kill-switch (§4.6, done) + behavioral test (rule 21, done). SoT `cardio_goal_default`;
plan_engine/CLAUDE.md pipeline note updated. Single item, terminal in this batch (§4.2).

## NOT in scope

⑦ detraining decay + W2.1 graded progression (the `progression_resolver` rework) = Batch 3b, its
own focused plan + ×2 review. ⑦(b) session banner separate. ④'s cardio finisher does not touch
progression, injuries, or equipment filtering.
