---
scope: plan_engine
parent: ../../../../CLAUDE.md
created: 2026-05-18
updated: 2026-09-29
status: active
---

# Plan Engine V4 — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/shared/repositories/plan_engine/`.
> Root CLAUDE.md (../../../../CLAUDE.md) contains process invariants and a pointer index.
> Narrative detail (dated corrections, worked examples, batch provenance) lives in
> `docs/architecture/plan-engine-detail.md`; this file keeps the live contract for each item.

**File:** `lib/shared/repositories/plan_generator.dart`
**Model:** Hybrid — fixed workout structure per combo, dynamic exercises from Hive.
**Do NOT modify `plan_generator.dart` without explicit instruction (root CLAUDE.md §4.4 rule 14).**

## Inputs
- `goal`: build_muscle | lose_fat | general_fitness | strength
- `equipment`: bodyweight | home_dumbbells | basic_gym | full_gym
- `daysPerWeek`: 3 | 4 | 5 | 6

## Process
1. Select workout split structure (e.g., 4-day muscle = Push/Pull/Legs/Upper)
2. For each day, query Hive exerciseBox:
   ```
   WHERE category = target_category
   AND equipment_needed matches user equipment
   AND suitable_for includes user experience
   ORDER BY exercise_type = 'compound' DESC
   LIMIT 6
   ```
3. Build 4-week phase with progressive overload defaults
4. Output: phase object with weeks, days, exercises, sets, reps, rest

## Output Shape
```dart
Phase {
  int phase;           // 1-12
  String name;         // "Foundation"
  String focus;        // "Movement patterns & baseline strength"
  String weeks;        // "1-4"
  int dailyCalories;
  int proteinGrams;
  List<WorkoutDay> workouts;
}
```

**FREE:** Phase 1 only (4 weeks). **PRO:** Generate new phases 2-12.

## V4 Pipeline (MuscleSlot Architecture)

**Key change:** CSpec (category-based) replaced by MuscleSlot (muscle-level targeting).

Items marked (D) have full narrative in `docs/architecture/plan-engine-detail.md`.

Pipeline stages:
0. **Progression (pre-pipeline, phase≥2)** → `ProgressionResolver.resolve()` scans `exlog_*` for each exercise's most-recent top set → suggested starting weight (3-band reps-rule + Epley 1RM ceiling), fed to Periodization via `previousWeights`. (D) Detraining decay: kill-switch `disable_detraining_decay` (default ON), reduce-ONLY, band table `lib/core/utils/detrainingFactorForGap`, SoT `detraining_decay`, test `progression_resolver_decay_test.dart`. Graded double progression: LIVE since 2026-09-16, kill-switch `disable_graded_progression` → verbatim fixed-10/5; shared `parseRepRange` (`models.dart`) used by BOTH resolve() AND `_applyWave`; SoT `graded_progression`; tests `progression_resolver_graded_test.dart`, `periodization_wave_reps_invariant_test.dart`.
1. **Split Resolver** → `MuscleSlotDay[]` with granular muscle slots per day (8-10 P1-P5 slots per day, ordered by priority)
2. **Volume Filter** → Trims slots to `targetCount(experience, daysPerWeek)` by `slots.take(N)` — depends on split_resolver ordering
3. **Exercise Selector** → 5-attempt cascade within movement patterns (NEVER crosses boundaries)
4. **Sequencing Engine** → Orders by priority, then compound-first
5. **Periodization Engine** → Uses exercise-specific `rep_range` + archetype-based wave. (D) Physique-focus bring-up: `physique_focus` → `effectiveBodyFocus` seam (`TrainingHistoryAnalyzer.resolveBodyFocus`, `plan_generator.dart:148-155`) → +1 set per matching exercise; LIVE since 2026-09-16; kill-switch `disable_physique_focus_bringup`; SoT `physique_focus_bringup`; test `physique_focus_bringup_test.dart`.
6. **Superset Pairer** → Unchanged
7. **Cardio Finisher** → (D) goal-aware default when no `cardioPreference` (`CardioFinisher._defaultForGoal`); kill-switch `disable_cardio_goal_default` (default ON); SoT `cardio_goal_default`; test `cardio_goal_default_test.dart`.
8. **Warmup/Cooldown** → also auto-injects for custom templates. (D) Injury-filtered: `WarmupCooldownSelector.attach(injuries:)` DROPS a contraindicated move (drop-not-substitute, non-empty floor); kill-switch `disable_warmup_injury_filter`; sole proof `warmup_injury_filter_behavioral_test.dart`; SoT `exercise_injury_tags`. WU-2 gym-cardio gate: `generateV4` passes a flag-gated `hasGymEquipmentOverride` (effective, exclusion-subtracted equipment) to BOTH `WarmupCooldownSelector.attach` and `CardioFinisher.attach`; rides `disable_equipment_exclusions` (DEFAULT ON since 2026-08-05, LIVE); sole proof `wu2_gym_cardio_gate_behavioral_test.dart`. ⚠ `Phase.toMap` serializes days TWICE (`workouts` + `week_plans[].workout_days[]`) — plan-diff/byte-identical tests must handle BOTH.

**Runtime / phase-boundary features** (contract only; full narrative per feature in the detail doc):

- **Triggered deload (W2.4).** Generator ALWAYS emits the week-4 deload; a rollover evaluator (`lib/core/services/deload_evaluator.dart` from `day_rollover_service`, NOT plan_engine) may un-deload it, SAFE polarity (`shouldLift = notBackstop && notDeloadPhase && readinessGood && e1rmNoFatigue`). Flag `enable_triggered_deload` (also needs `enable_readiness`); generation-stash `periodization_engine.apply(stashWorkingBase:)`; local-only state, NO migration. SoT `triggered_deload_eval`, `deload_working_base_stash`; test `deload_eval_behavioral_test.dart`.
- **Deload "why" (W3.1).** Workout box key `deload_reason_phase_<P>` holds a MAP `{week_character, text}` (writer: the evaluator; reader `WorkoutScheduleReadService.currentDeloadReason` → `PhaseArcStrip`, week 4 only); pure `validatedDeloadReason` returns text ONLY while `week_character` still equals week 4's in `currentWaveCharacters()`. LIVE since 2026-09-06; kill-switch `disable_deload_reason_line`. ⚠ Blind to the AI-coach regen (OI-166). SoT `deload_decision_reason`; tests `deload_reason_test.dart`, `deload_reason_staleness_behavioral_test.dart`.
- **Repeat-content (W2.5).** `generateV4(pinnedExercisesByDay:)` → `ExerciseSelector.buildPinnedDays` instead of `pickV4`; re-applies only HARD constraints (exclusions + ungated injury); `null` → byte-identical. LIVE since 2026-09-16; kill-switch `disable_adherence_gate` (flag check inside `_buildRepeatPins`). SoT `repeat_phase_pinned_selection`; tests `repeat_phase_pinned_selection_behavioral_test.dart`, `pro_phase_advance_behavioral_test.dart`.
- **Volume titration (W2.7).** Pure post-pass `VolumeTitration.applyToWeeks` at a FRESH advance, ±1 set per muscle group, clamped [MEV=8, MRV=20]. Inert seams: `enable_volume_titration` (DEFAULT OFF) AND opt-in `applyVolumeTitration` (only the two `pins == null` advance callers). SoT `volume_titration`; test `volume_titration_behavioral_test.dart`.
- **ID-keyed history (W3.3).** `exlog_*` rows carry the Hive-LOCAL library `exercise_id`; `ProgressionResolver.resolve` matches id INCLUSIVE with name. Kill-switch `disable_exercise_id_history`. ⚠ NEVER project the library id to the cloud (`workout_log_exercises.exercise_id` is a separate name-derived onConflict identity). SoT `exercise_id_history`; tests `exlog_exercise_id_behavioral_test.dart`, `sync_exlog_no_library_id_test.dart`.
- **Injury-substitute preference (11-C).** `_cascadeFill` re-ranks post-injury-filter candidates via pure `_selectCandidate`; can never surface a contraindicated exercise. Kill-switch `disable_injury_substitute_pref`; mirrored in `cascade_tracer.dart`. SoT `injury_safe_substitute_preference`; test `injury_substitute_preference_behavioral_test.dart`.
- **Cross-phase variety (W3.4).** SOFT `_preferNovel` bias from `previousPhaseNamesByDay()`; never feeds queryV4/excludeNames. Kill-switch `disable_cross_phase_variety`. SoT `cross_phase_variety`; test `cross_phase_variety_behavioral_test.dart`.
- **Plateau escalation (W3.5 12-A) + rotation (12-B), PRO, ship-dark.** rung-2 (+1 set via `mergePlateauSetDeltas`, `putIfAbsent`, declining group's −1 wins) and rung-3 (SOFT-avoid via `plateauAvoidNames`); rung-1 needs no code (`deload_evaluator.dart` NOT touched). ONE flag `enable_plateau_escalation` DEFAULT OFF (rotation adds NO new flag), also gated on `enable_readiness`, opt-in `applyPlateauEscalation`. SoT `plateau_escalation`, `plateau_rotation`; tests `plateau_escalation_behavioral_test.dart`, `plateau_rotation_behavioral_test.dart`, `plateau_scan_test.dart`.
- Common to all of the above: `generator_matrix.dart`/`cascade_tracer.dart` scorecard cannot measure them (behavioral tests are the proof); flag-off/`null` inputs are byte-identical.

**Exercise count targets (per day):**

| Experience | 3-day | 4-day | 5-day | 6-day |
|---|---|---|---|---|
| Beginner | 6 | 5 | 4 | 4 |
| Intermediate | 8 | 7 | 6 | 6 |
| Advanced | 10 | 9 | 8 | 8 |

Inverse pattern: fewer training days → more exercises per session. More experience → more total volume. Defined in `VolumeFilter.targetCount(experience, daysPerWeek)`.

**Movement patterns (11):** horizontal_push, vertical_push, horizontal_pull, vertical_pull, knee_dominant, hip_dominant, core, elbow_flexion, elbow_extension, shoulder_isolation, hip_isolation

**Cascade attempts:**
1. `attempt1Exact` — all fields match (movement_pattern + target_focus + exercise_type + subFocus + suitable_for + foundational)
2. `attempt2DropSubFocus` — drop subFocus
3. `attempt3DropTypeAndTarget` — drop target_focus + exercise_type (keep movement_pattern only)
4. `attempt4DropEquipment` — drop equipment_tier
5. `universalPool` — hardcoded bodyweight fallback (`exercise_selector.dart:493-505`, mirrored in `cascade_tracer.dart`). (D) **Injury-filtered (U2):** skips a contraindicated pool pick (EXACT-name library lookup — `repo.search` is substring) and, if the whole pool is contraindicated, SAFELY OMITS the slot (null → fewer-but-safe). Kill-switch `configBox['disable_injury_universal_filter']` (default ON).

**Injury vocabulary (U1/U4):** injuries must be canonical library tokens (`InjuryVocab.canonicalTokens` in `lib/core/utils/injury_vocab.dart` — ankle/elbow/hamstring/hip/knee/lower_back/neck/shoulder/wrist), NOT the legacy UI vocab. Every writer normalizes via `InjuryVocab.normalize`; `generateV4` normalizes CENTRALLY; readers use crash-safe `InjuryVocab.fromProfile`. SoT `injury_vocabulary_contract`.

**Equipment exclusion filter (⑥ B1):** (D) item-level PURE-EXCLUSION filter from the `equipment_exclusions` profile field, derived ONCE in `generateV4` (`PlanEngineFlags.equipmentExclusionsEnabled`; FLIPPED ON 2026-08-05, diagnose `e2d6b8`; kill-switch `disable_equipment_exclusions`, DEFAULT ON — the `enable_` key is retired). `EquipmentVocab.floorSanitizedExclusions` strips none/bodyweight (floor never excludable). Threaded to EVERY pick path: `queryV4` att1-4 (KEPT at att4 — HARD constraint), att5 pool skip, L2 custom-append, L6 demote-swap; the `queryV4 exclusions` param is REQUIRED. `equipment_tier` filter UNTOUCHED; no-op at empty. SoT `equipment_exclusion_filter`; test `equipment_exclusion_filter_behavioral_test.dart`.

**Slot capacity rule:** No muscle/pattern/type triple should appear in more slots per week than its exercise library pool depth supports. E.g., Rear Delts/shoulder_isolation/isolation has 3 library exercises → max 3 slots/week. Over-allocation → `universalPool` picks (Pike Push Up for rear delt slots) or `(none)` failures.

**Beginner-foundational pool constraint:** For Phase 1, `queryV4` requires BOTH `suitable_for` contains "Beginner" AND `is_foundational: true`. When adding/removing exercises from these pools, audit with `dart run test/plan_generator/sample_plans_report.dart`.

**A/B variants:** slotsB alternates anterior/posterior emphasis weekly (e.g., A=chest-heavy push, B=shoulder-heavy push)

**Verification tools:**
- `test/plan_generator/sample_plans_report.dart` — generates all 12 combos (3×experience × 4×days) for build_muscle/full_gym, emits `sample_plans_output.md`. Target: 0 attempt3/universalPool/none.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade; run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.

## Common pitfalls

Full pitfall bodies (D): `docs/architecture/plan-engine-detail.md`.

| Pitfall | How to avoid | Source |
|---|---|---|
| Plan generator picks wrong-target exercise | Cascade attempt3 keeps only `movement_pattern`. Causes: shallow library pool, or Phase 1 `suitable_for` too restrictive. Fix: expand library `suitable_for` OR adjust `split_resolver.dart` slot ordering; verify with `sample_plans_report.dart` (target 0 attempt3/universalPool/none). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Plan generator returns wrong number of exercises | `VolumeFilter` `slots.take(targetCount(...))` depends on `split_resolver` emitting enough P1-P5 slots (advanced 3-day needs 10). Count slots when adding/reordering a split. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Pike Push Up assigned to rear delt slot | (a) wrong-pattern pool ENTRY → fix `universalPoolV4` (Batch 13-A `c3f9b2`, `universal_pool_mirror_test`, lockstep with `cascade_tracer.dart`); (b) attempt-5 FREQUENCY → cap rear delt 3/wk, lateral delt 3/wk, front delt 1/wk in `split_resolver.dart`, NOT the pool. | (relocated 2026-05-18) + Batch 13-A c3f9b2 |
| **A bodyweight user is prescribed something needing equipment** | OI-89 (2026-08-28): `equipment_tier` is a CURATION hint — never key a safety check on it. The check is `EquipmentCapability.canPerform(equipment_needed, effective)`, `effective = tierItems[tier] ∪ equipment_owned − equipment_exclusions` (`EquipmentVocab.effectiveItems`). `capability` is a **required, non-defaulted** param on `pickV4` / `_fillSlots` / `_cascadeFill` / `buildPinnedDays` / `_applyHistoryAdjustments` — do not give it a default. `null` = DO NOT ENFORCE (flag off / Hive unreadable), NOT an empty set (`canPerform` fails CLOSED). The floor applies at EVERY tier; capability SUBSUMES queryV4's tier block (`exercise_repository.dart:334`, `else if`, never both). Unrecognised tier → `bodyweight`. | OI-89 + OI-144, diagnoses `f7b2c4` / `c9a7e2` / `b6f4d1` / `d3a8f5` |
| **A capability filter empties a slot instead of substituting** | A pool that empties falls to `universalPoolV4` (picks by NAME, bypasses `queryV4`) — it must apply the capability drop ITSELF, as it does for exclusions. Its per-pattern pure-bodyweight tails guarantee a survivor; `equipment_exclusion_filter_behavioral_test` pins that. | OI-89 |
| **A pattern satisfies the floor invariant and STILL leaves slots empty** | The invariant describes the LIBRARY; empty slots are a property of the GENERATOR over it (`pickedNames` dedups across a plan; `suitableFor` narrows further). Working number: **6–7 baseline rows per pattern**. Assert on the generator's OUTPUT, not row counts. | OI-89, wave 2 (E274–E294) |
| **The scorecard is green in every world** | `test/plan_generator/` runs through MIRRORS (`CascadeTracer` + `QueryV4Mirror`). **When you add a filter to production, add it to both mirrors in the same commit**, and toggle the new input to confirm the harness can see it; `universal_pool_mirror_test` pins pool DATA only. | OI-89 |

## Tests pinning the rules here

- `test/plan_generator/sample_plans_report.dart` — full 12-combo sweep (3×experience × 4×days) for build_muscle/full_gym. Target: 0 attempt3/universalPool/none. Emits `sample_plans_output.md` for review.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade. Run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.
- `test/plan_engine_v4/` — granular pipeline-stage tests (split resolver, volume filter, exercise selector, periodization, superset pairer).
- `test/contracts/plan_generator_inputs_test.dart` — pins the goal × equipment × daysPerWeek input contract.
- `test/contracts/bodyweight_capability_leak_test.dart` — ⑦ OI-89 behavioural proof on the PRODUCTION path (`pickV4` → `_cascadeFill`), oracle reading `equipmentNeeded` off the built `PlannedExercise`, never `equipment_tier`.
- `test/contracts/equipment_tier_consistency_test.dart` — `derive(equipment_needed) == equipment_tier`, **EQUALITY on both sides** since OI-89 (it was a subset, and the tolerated over-tag side is what shipped Chin Up to bodyweight users), plus the per-pattern floor.
- `test/plan_generator/scorecard_gate_test.dart` — 606 personas. **Equipment violations are a hard `== 0`** since OI-89, promoted from a `≤ 201` ceiling.

## See also

- `lib/features/train/CLAUDE.md` — generated plan is consumed by Train screen + Active Workout.
- `lib/features/onboarding/CLAUDE.md` — initial plan generated on Plan-screen tap.
- `docs/reference/exercise-library.md` — exercise_library Hive box schema (movement_pattern, suitable_for, equipment_needed, is_foundational).
- Detail: docs/architecture/plan-engine-detail.md — moved-out narratives (dated corrections, worked examples, batch provenance) for every (D) item above.
