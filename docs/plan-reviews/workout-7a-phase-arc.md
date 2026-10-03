---
branch: workout-7a-phase-arc
scope: Batch 7-A — W3.2 phase arc (read-only Train-screen periodization-wave strip), ship-dark
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-7a-phase-arc-bpass.md
---

# Plan-review record — Batch 7-A (phase arc, W3.2)

The §4.12 ×2 review of the original **Batch 7** (W2.4 deload + W3.2 phase arc) SPLIT the unit:
the two context-blind Round-1 reviewers both verified 7-A's design against code and found it
**near-converged**, while 7-B (deload) was **not converged** (structural — base-recovery + backstop
marker). Per §4.12 ("keep surfacing new material issues ⇒ split, ship the smallest converged
piece") 7-A ships first; 7-B is redesigned separately. This record covers 7-A only.

## Ground-truth verified (against current code, post-Batch-6)
`periodization_engine.dart:129` stamps `weekCharacter: _waveNames[weekIdx]` per week (baseline/
overreach/peak/deload), serialized as **snake_case `week_character`** via `WeekPlan.toMap`
(`models.dart:79`); the `current_plan` blob lives at `workoutBox['current_plan']`
(`workout_schedule_read_service.dart:86/132`); NO `lib/features/train/` code read `week_character`
before this (7-A adds the first reader); `getCurrentWeekNumber()` is pure date math (:535).

## Round 1 (×2 context-blind, on the combined plan) — 7-A findings, all folded
Two required fixes for 7-A: (a) read the **snake_case** `week_character` key (NOT camelCase — else
the strip is always empty); (b) do NOT modify the `plan_screen.dart:195` 'mid-deload' onboarding
copy — it stays accurate while `enable_triggered_deload` (a DIFFERENT, not-yet-shipped 7-B flag)
is OFF. Both folded: the reader uses `'week_character'`; `plan_screen.dart` is untouched by this diff.

## Round 2 (B-pass, on the hardened implementation) — `docs/reviews/workout-7a-phase-arc-bpass.md`
Context-blind adversarial review of the implemented diff (reader + facade + `phaseArcEnabled` flag +
`phaseArcProvider` + `PhaseArcStrip` + Train-screen wiring + the 8-test behavioral suite). Verified
the two Round-1 fixes landed, ship-dark byte-identical (flag OFF → `SizedBox.shrink`), crash-safety,
read-only (no engine coupling), Riverpod correctness, and Wardroom/house-rule compliance.

## Implemented (green: analyze clean 6 items, 8/8 behavioral tests pass)
- `WorkoutScheduleReadService.currentWaveCharacters()` — crash-safe read of `week_plans[].week_character`
  (+ `WorkoutScheduleService` facade passthrough).
- `PlanEngineFlags.phaseArcEnabled` — kill-switch `enable_phase_arc`, ship-dark DEFAULT OFF (§4.6).
- `phaseArcProvider` (+ `PhaseArcData`) — flag-gated, watches `currentPlanProvider`; OFF/no-plan → null.
- `PhaseArcStrip` — Wardroom-styled 4-week wave strip, THIS week highlighted; null → renders nothing.
- Wired after `WeekSelector` on the Train screen. SoT concept `phase_arc_display`.

## Verdict: converged
Pure read-only display of already-stamped data; ship-dark OFF → byte-identical. The copy/behavior
change (making week 4's deload conditional) is 7-B; the onboarding 'mid-deload' copy correctly stays
until `enable_triggered_deload` flips (founder-gated, post-APK — NOT a §4.2 deferral: changing it now
would make it inaccurate). B-pass on the implemented diff before the `--no-ff` merge (§4.3 / platform).
