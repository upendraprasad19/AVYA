---
scope: plan_engine
parent: ../../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Plan Engine V4 — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/shared/repositories/plan_engine/`.
> Root CLAUDE.md (../../../../CLAUDE.md) contains process invariants and a pointer index.

**File:** `lib/shared/repositories/plan_generator.dart`
**Model:** Hybrid — fixed workout structure per combo, dynamic exercises from Hive.

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

Pipeline stages:
0. **Progression (pre-pipeline, phase≥2)** → `ProgressionResolver.resolve()` scans `exlog_*` for each exercise's most-recent top set → suggested starting weight (3-band reps-rule + Epley 1RM ceiling), fed to Periodization via `previousWeights`. **⑦(a) (Batch 3b-i): detraining WEIGHT decay** — a user resuming after a training gap restarts lighter: the baseline is decayed by the IST day-gap since their last logged session (≤7d none · 8–21d −7.5% · 22–35d −17.5% · >35d −50%) BEFORE the reps-rule; the decayed `base` replaces the original weight in ALL FOUR reps-rule branches incl. the `<=0` floor (reduce-ONLY), Epley cap stays on the pre-decay 1RM, gap is a zone-canceling date-only diff (never re-zones the already-IST exlog date — Test #11.1 class). Kill-switch `disable_detraining_decay` (default ON; the reduce-only band table is extracted to shared `lib/core/utils/detrainingFactorForGap` — `_detrainingFactor` keeps its IST-string→gap conversion then delegates, and ⑦(b)'s session-time resume cut reuses it from an int gap). SoT `detraining_decay`; behavioral test `progression_resolver_decay_test.dart` (the Batch-0 scorecard CANNOT measure resolve() — it never invokes it + seeds no logs). **W2.1 (Batch 3b-ii): graded double progression** — the fixed 10/5 reps-rule becomes REP-RANGE-aware (from the ⑦a base): reps ≥ hi → progress, within → hold, below lo → back off ONLY on the top-2 most-recent DISTINCT calendar days BOTH below lo (2-consecutive; de-duped by (y,m,d)). Beginner auto-linear window (RAW `fitness_experience=='beginner'` AND training-age from `onboarding_completed_at` < 120d → always progress). Rep-ranges threaded via a `repRanges` param from `populated`; shared `parseRepRange` (`models.dart`) used by BOTH resolve() AND `_applyWave` (one parser, #1-bug-class; inertness pinned by `periodization_wave_reps_invariant_test.dart`). **Kill-switch `enable_graded_progression` DEFAULT OFF (ship-dark §4.6 — W2.1 can INCREASE load)** → verbatim fixed-10/5 (byte-identical; ⑦a decay independent, base/est1rm on the single-most-recent `lastSession` UNCHANGED; top-2 is ADDITIVE, ON-only). SoT `graded_progression`; behavioral test `progression_resolver_graded_test.dart`.
1. **Split Resolver** → `MuscleSlotDay[]` with granular muscle slots per day (8-10 P1-P5 slots per day, ordered by priority)
2. **Volume Filter** → Trims slots to `targetCount(experience, daysPerWeek)` by `slots.take(N)` — depends on split_resolver ordering
3. **Exercise Selector** → 5-attempt cascade within movement patterns (NEVER crosses boundaries)
4. **Sequencing Engine** → Orders by priority, then compound-first
5. **Periodization Engine** → Uses exercise-specific `rep_range` + archetype-based wave. **⑤ (Batch 4): physique-focus bring-up.** The user's `physique_focus` (profile) is translated to muscle-substring tokens (`TrainingHistoryAnalyzer.physiqueFocusToBodyFocus`; read via the try/catch `physiqueFocusMuscles()` helper) at the `effectiveBodyFocus` seam — the flag-gate + precedence GLUE lives in the behavior-tested `TrainingHistoryAnalyzer.resolveBodyFocus` (`plan_generator.dart:148-155`), which periodization turns into **+1 set per matching exercise** (the EXISTING bodyFocus mechanism — no periodization change). Explicit focus PRECEDES auto `weakMuscles()` and applies at ALL phases; balanced/strength/absent → [] → falls back to weakMuscles (phase≥2). Kill-switch `enable_physique_focus_bringup` DEFAULT OFF (ship-dark §4.6 — increases prescribed volume) → seam byte-identical. **The dedicated isolation SLOT is founder-deferred** (2026-07-13) — trade-not-add proven infeasible (`VolumeFilter` is POSITIONAL `take(N)`, NOT priority-sorted; focus muscle already kept on its theme day). SoT `physique_focus_bringup`; behavioral test `physique_focus_bringup_test.dart`.
6. **Superset Pairer** → Unchanged
7. **Cardio Finisher** → **④ (Batch 3a): goal-aware default.** With no stored `cardioPreference` (always, today — no preference UI), the finisher SHAPE now defaults to the goal instead of the blanket mildest mini-HIIT: `lose_fat→hiit`, `general_fitness→cycling`, `recompose→jump_rope` (only the 3 `FitnessGoals.cardio==true` goals attach a finisher). `CardioFinisher._defaultForGoal`; kill-switch `disable_cardio_goal_default` (default ON) reverts to verbatim `hate_cardio`. SoT `cardio_goal_default`; behavioral test `cardio_goal_default_test.dart`. The Batch-0 scorecard doesn't measure the finisher (post-selection stage) — the behavioral test is the proof.
8. **Warmup/Cooldown** → Now also auto-injects for custom templates. **Injury-filtered (U3, d3f8a1):** `WarmupCooldownSelector.attach(injuries:)` DROPS a hardcoded warmup/cooldown/cardio move whose `_moveInjuries` tag intersects the user's injuries (drop-not-substitute), with a guaranteed non-empty FLOOR (safe Slow Walking cardio fallback + Deep Breathing anchor). Main-cascade-selectable moves (Push Up/Band Pull Apart/Baithak) use their LIBRARY `injury_contraindications` so main+warmup agree; warmup-only moves use conservative tags (the library under-tags them). Threaded from `generateV4` + `template_service`; kill-switch `disable_warmup_injury_filter`. ⚠ The Batch-0 scorecard CANNOT prove this (warmup isn't in `plan.allExercises`) — `warmup_injury_filter_behavioral_test.dart` is the sole proof. The library's MAIN-move under-tagging (Push Up not shoulder-tagged) is a separate founder-directed audit batch.

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
5. `universalPool` — hardcoded bodyweight fallback (`exercise_selector.dart:493-505`, mirrored in `cascade_tracer.dart`). **Injury-filtered (U2, a1f6c3):** unlike attempts 1-4 (which exclude contraindications via `queryV4 injuryExclusions`), attempt-5 bypassed the injury filter until Ship 1 — it now skips a contraindicated pool pick, resolves each pool name to its EXACT-name library record (`repo.search` is substring, so "Push Up" also matches "Pike Push Up"), and — if the whole pool is contraindicated — SAFELY OMITS the slot (returns null → fewer-but-safe). Kill-switch `configBox['disable_injury_universal_filter']` (default ON).

**Injury vocabulary (U1/U4, a1f6c3):** injuries must be the canonical library tokens (`InjuryVocab.canonicalTokens` in `lib/core/utils/injury_vocab.dart` — ankle/elbow/hamstring/hip/knee/lower_back/neck/shoulder/wrist), NOT the legacy UI vocab (`back` never matched `lower_back`). Every writer (Edit-Profile chips, muster) normalizes via `InjuryVocab.normalize`; `generateV4` normalizes CENTRALLY so every generation caller is covered by one seam; each entry point reads via crash-safe `InjuryVocab.fromProfile`. SoT concept `injury_vocabulary_contract`.

**Slot capacity rule:** No muscle/pattern/type triple should appear in more slots per week than its exercise library pool depth supports. E.g., Rear Delts/shoulder_isolation/isolation has 3 library exercises → max 3 slots/week. Over-allocation → `universalPool` picks (Pike Push Up for rear delt slots) or `(none)` failures.

**Beginner-foundational pool constraint:** For Phase 1, `queryV4` requires BOTH `suitable_for` contains "Beginner" AND `is_foundational: true`. When adding/removing exercises from these pools, audit with `dart run test/plan_generator/sample_plans_report.dart`.

**A/B variants:** slotsB alternates anterior/posterior emphasis weekly (e.g., A=chest-heavy push, B=shoulder-heavy push)

**Verification tools:**
- `test/plan_generator/sample_plans_report.dart` — generates all 12 combos (3×experience × 4×days) for build_muscle/full_gym, emits `sample_plans_output.md`. Target: 0 attempt3/universalPool/none.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade; run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Plan generator picks wrong-target exercise | Cascade attempt3 drops `target_focus` + `exercise_type`, keeping only `movement_pattern` — results in a push instead of a chest-specific push. Root causes: (a) exercise library pool too shallow for the slot's triple, or (b) for Phase 1 beginners, `suitable_for` too restrictive (needs "Beginner" + `is_foundational: true`). Fix: either expand library `suitable_for` on the missing exercise OR adjust `split_resolver.dart` slot ordering so beginners don't hit the shallow pool at P1/P2. Verify with `dart run test/plan_generator/sample_plans_report.dart` (target: 0 attempt3/universalPool/none). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Plan generator returns wrong number of exercises | `VolumeFilter` uses `slots.take(targetCount(experience, daysPerWeek))` — depends on `split_resolver` emitting enough P1-P5 slots in priority order. If a split returns fewer slots than the advanced target (10 for 3-day), users get truncated output silently. When adding/reordering a split, count slots and confirm it covers the advanced case. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Pike Push Up assigned to rear delt slot | Sign that cascade exhausted `attempt1-4` and fell to `universalPool`. Indicates too many slots of the same muscle/pattern/type across the week — library pool depth insufficient. Cap rear delt slots to 3/week, lateral delt to 3/week, front delt to 1/week (current library depth). Fix in `split_resolver.dart`, NOT by editing the universal pool. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

- `test/plan_generator/sample_plans_report.dart` — full 12-combo sweep (3×experience × 4×days) for build_muscle/full_gym. Target: 0 attempt3/universalPool/none. Emits `sample_plans_output.md` for review.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade. Run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.
- `test/plan_engine_v4/` — granular pipeline-stage tests (split resolver, volume filter, exercise selector, periodization, superset pairer).
- `test/contracts/plan_generator_inputs_test.dart` — pins the goal × equipment × daysPerWeek input contract.

## See also

- `lib/features/train/CLAUDE.md` — generated plan is consumed by Train screen + Active Workout.
- `lib/features/onboarding/CLAUDE.md` — initial plan generated on Plan-screen tap.
- `docs/reference/exercise-library.md` — exercise_library Hive box schema (movement_pattern, suitable_for, equipment_needed, is_foundational).
