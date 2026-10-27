---
branch: workout-7b-deload
scope: Batch 7-B-1 — triggered-deload GENERATION-STASH (peak-equiv working_sets/reps at generation), ship-dark
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-7b-deload-bpass.md
---

# Plan-review record — Batch 7-B-1 (generation-stash)

The §4.12 ×2 review of the **Batch 7-B (triggered deload)** redesign plan produced a FURTHER split
(both reviewers, independently): the D2-D4 **eval/trigger** is not converged (dense *safety* defects —
e1RM polarity backwards, backstop dead-if-mis-placed, schedSwap completed-day data-loss) and becomes
its own unit **7-B-2**; the D1 **generation-stash** is near-converged and ships first as this branch
(**7-B-1**) — a de-risking base-persistence foundation (§4.11 spirit). This record covers 7-B-1 only.

## Ground-truth verified (base-persistence GT a0b7e7 + Round-1 ×2 + my own reads)
The deload cut is non-invertible (`_waveSets(base,3)=max(1,(base*0.6).floor())`, many-to-one; body-focus
+1 post-wave; phase≥2 generation non-deterministic — `weakMuscles`/`demotedExercises` read `DateTime.now()`)
AND week 4 uses variant **B** while week 1 uses A (`periodization_engine.dart:77/82`) — so the working
base CANNOT be recovered later; it MUST be persisted at generation. `scheduled_workouts` carries NO
exercise columns (`live_schema:36`); exercises round-trip only via `user_progress.plan_json` jsonb →
**Option A (additive `working_sets`/`working_reps`) needs NO migration, NO apply-gate.** `mergeScheduleEntry`
whole-map copy preserves the nested keys on restore.

## Round 1 (×2 context-blind, on the redesign plan) — 7-B-1 (D1) findings, all folded
Both reviewers gave 2 D1 must-fixes, both implemented:
1. **N1 linchpin (Reviewer A, HIGH):** `superset_pairer.dart:56` copyWith-mutates paired exercises AFTER
   periodization → thread `workingSets`/`workingReps` through `PlannedExercise.copyWith` (`?? this.workingSets`)
   so the stash survives, AND prove it via a FULL-`generateV4`-pipeline superset test (not periodization
   in isolation). DONE — `deload_working_base_stash_behavioral_test.dart` asserts a paired wk-4 exercise
   keeps its stash (non-vacuous: the persona DOES pair).
2. **Peak = full `_applyWave(ex, 2, …)` (both reviewers):** not bare `_waveSets(x,2)` (which misses the
   multiplier / min-4 clamp / rep-range path). DONE — exact `_applyWave(weekIdx=2)` on the same variant-B
   `ex` with matching isBeginner/isDeload/multiplier/archetype + the same body-focus +1.

## Round 2 (B-pass, on the implemented diff) — `docs/reviews/workout-7b-deload-bpass.md`
Context-blind adversarial review of the diff + a live test run.

## Implemented (green: analyze clean, plan_engine_v4 stage tests + the N1 test all pass)
- `PlannedExercise.workingSets` (int?) / `workingReps` (String?) — fields + copyWith (N1 idiom) + toMap (omit-when-null).
- `PeriodizationEngine.apply(stashWorkingBase)` — weekIdx-3 peak-equiv stash (pure stage; flag threaded).
- `generateV4` threads `PlanEngineFlags.triggeredDeloadEnabled` (ship-dark OFF). SoT `deload_working_base_stash`.

## Verdict: converged
Additive, write-only stash; flag OFF → byte-identical (proven). Inert until 7-B-2 CONSUMES it (un-deload).
The D2-D4 eval/trigger (the risky half) is deliberately NOT in this branch — its must-fixes are tracked
for 7-B-2's own focused plan + ×2. B-pass on the implemented diff before the `--no-ff` merge (§4.3 / platform).
