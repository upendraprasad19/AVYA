---
branch: workout-adherence-8a2cap
scope: ⑧ Batch 8 UNIT 2-cap (W2.5 repeat-content) — ExerciseSelector.buildPinnedDays + generateV4/generate pinnedExercisesByDay param (ship-dark)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-8a2cap-bpass.md
---

# Plan-review record — ⑧ 8-A / UNIT 2-cap (repeat-phase pinned-selection capability)

Plan: `scratchpad/batch8_unit2_pinned_capability_plan.md` (the converged half after the Round-2 ×2
review of UNIT 2 recommended SPLITTING it into **2-cap** [this: the `buildPinnedDays` capability +
generateV4 param, ship-dark-inert] + **2-int** [the `generateAndSchedule` `repeatContent` integration
+ G5 shape-gate + kill-switch, its own focused plan + ×2, pending]). §4.12 ×2 context-blind review;
every load-bearing seam re-verified against code while coding. **Converged — implemented.** PLATFORM
tier (`plan_engine/**`). NOT a `fix:` (a NEW capability) → no diagnose-doc required (rule 22). No migration.

## Ground-truth verified (against code, file:line)
- **generateV4 seam** (`plan_generator.dart:129-139`): selection finalized at `populated` (`pickV4` →
  `List<PopulatedDay>`); the tail from `:142` (allNames → Stage-0 `resolve()` decay iff
  `previousWeights==null && phase>=2` → periodization joins by exerciseName) runs UNCHANGED. `generate()`
  (`:36-63`) delegates — now forwards `pinnedExercisesByDay` AND `equipmentExclusions` (the facade
  previously dropped the latter — Round-2 nit).
- **PopulatedDay frame fields** (`exercise_selector.dart:587-591`): `PopulatedDay(name/focus/dayType/
  intensity FROM the MuscleSlotDay frame, exercisesA/B from cascade)` — so `intensity`/`dayType` (the
  periodization inputs) are FRAME properties → reproduced from `filteredDays[i]` (MF-2). `exercisesB =
  exercisesA` mirrors pickV4's `slotsB==null` branch (`:566`).
- **The filters the cascade runs internally** (a pin bypasses `pickV4`): equipment-EXCLUSION
  (`exercise_repository.dart:282-285`), equipment-TIER (`:287-296`), injury (`:324-334`). att-5's
  own drops (`exercise_selector.dart:891-906`) confirm the mirror predicates.
- **`getByExactName`** (`exercise_repository.dart:42-51`) exact case-insensitive; **`getCustomExercises`**
  (`:376`, injects `id` from key); **`_buildExercise`** (`:947`) / **`_buildCustomExercise`** (`:742`)
  in-class privates → `buildPinnedDays` (co-located static) reaches all three, no queryV4 round-trip.

## Round 1 / Round 2 (context-blind, on the UNIT-2 plan) — folded
- **SPLIT 2-cap / 2-int** (both reviewers): UNIT 2 was too large; ship the converged capability half
  first, inert. Done — this record is 2-cap.
- **"repeat" = pinned SELECTION, not blob-copy** (both reviewers): copying the prior plan's cooked
  `suggested_weight` + re-decaying double-decays AND bypasses the in-cascade injury/equipment filters.
  Pinning only the SELECTION re-decays the ACTUAL last-log by name + re-filters for free. Adopted.
- **G5 goal-match gate is a 2-int concern, not 2-cap** (Reviewer B): the prior phase's `goal` is
  persisted NOWHERE (`Phase.toMap` has no goal; schedule rows have no goal) → the faithfulness gate
  (prior goal+days == current) lives at the CALLER (2-int), not in the capability. 2-cap's
  `intensity`/`dayType` come from the current frame; faithful only when they match — documented on the
  method + the param.
- **Caller passes `previousWeights: null`** so Stage-0 re-decays (a pre-baked map SKIPS it) — the
  `generate`/`generateV4` default is already null, so the obligation is satisfied by not overriding it.

## Two implementation-time corrections (self-caught while coding, verified against code)
1. **Injury refilter is UNGATED, not att-5-gated.** The pre-implementation note said mirror att-5's
   `applyInjuryUniversalFilter && _isContraindicated` skip — but a pinned pick REPLACES an att1-4
   selection, and att1-4's injury filter (`exercise_repository.dart:324-334`) is UNGATED (the
   `disable_injury_universal_filter` switch governs ONLY the att-5 universal pool). Mirroring the gated
   att-5 would let a user who added an injury since the prior phase get the old contraindicated lift
   repeated. Filtered UNGATED (safety). Pinned by test (3).
2. **Equipment-TIER is NOT re-applied.** The compaction summary had broadened the filter set to include
   tier; the written plan lists only injury + equipment-exclusion. Tier is a SOFT heuristic the cascade
   itself RELAXES at attempt-4 — a same-tier full_gym plan legitimately contains att4 tier-relaxed
   moves. Re-applying a strict tier filter would silently DROP those att4 picks from a faithful repeat
   (fewer exercises, no safety gain) and break the "pinning a plan's own selection reproduces it"
   invariant. A genuine tier CHANGE is the user's swap / "fresh" choice, not a silent drop. Only the
   HARD constraints (injury + equipment-EXCLUSION) filter. Pinned by tests (2) + (4).

## Verdict: converged
`ExerciseSelector.buildPinnedDays` (resolve → HARD-constraint refilter → build → MF-1 fresh-fill →
frame-metadata PopulatedDay) + `generateV4`/`generate` `pinnedExercisesByDay` param (null →
byte-identical). Ship-dark: no production caller supplies pins (2-int wires it). `flutter analyze`
clean; 7/7 behavioral (`repeat_phase_pinned_selection_behavioral_test.dart`); 176/176 plan_engine
regression (incl. the v4 cascade-mirror diagnostic) green. SoT `repeat_phase_pinned_selection`.
B-pass runs on the implemented diff before the `--no-ff` merge (§4.3 / platform).

## Post-B-pass (staging b7d05691feda) — 1 P1 + 5 P2, all fixed in-batch
The fresh context-blind B-pass (`docs/reviews/workout-adherence-8a2cap-bpass.md`) caught a **real P1
the ×2 plan-review missed** and 5 P2s. All accepted + fixed:
- **P1 (exercisesB collapse):** `buildPinnedDays` set `exercisesB == exercisesA` unconditionally, but
  the split's `slotsB` is non-null on the tested 4-day combo and periodization reads `exercisesB` for
  weeks 2 & 4 — so a repeat would DUPLICATE weeks 1/3, and all 7 original tests (week-1 only) were
  blind to it. Root-fixed: the param value became a per-day record `({List<String> a, List<String> b})`;
  A pins → weeks 1/3, B pins → weeks 2/4; a B-absent day derives a fresh B-variant (never `B=A`).
  Tests now assert week-2. (This corrects the pre-B-pass verdict's "exercisesB=exercisesA" note above.)
- **P1 (tier cross-phase):** re-confirmed tier stays caller-gated — UNIT 2-int now gates the repeat on
  equipment-TIER-unchanged (alongside goal + daysPerWeek). Contract note added to the docstring/SoT.
- **P2 ×4:** test (1) de-tautologized to facade-parity; a new synthetic-name A/B-distinct test proves
  live dispatch; the MF-1 "(none)" overclaim softened; `getCustomExercises` hoisted to a lazy single scan.

Re-verified post-fix: `flutter analyze` clean; **8/8** behavioral (incl. week-2 / A-B-distinct / facade
parity); 176/176 plan_engine regression green. **bpass: accepted.**
