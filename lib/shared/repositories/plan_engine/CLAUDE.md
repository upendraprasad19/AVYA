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
8. **Warmup/Cooldown** → Now also auto-injects for custom templates. **Injury-filtered (U3, d3f8a1):** `WarmupCooldownSelector.attach(injuries:)` DROPS a hardcoded warmup/cooldown/cardio move whose `_moveInjuries` tag intersects the user's injuries (drop-not-substitute), with a guaranteed non-empty FLOOR (safe Slow Walking cardio fallback + Deep Breathing anchor). Main-cascade-selectable moves (Push Up/Band Pull Apart/Baithak) use their LIBRARY `injury_contraindications` so main+warmup agree; warmup-only moves use conservative tags (the library under-tags them). Threaded from `generateV4` + `template_service`; kill-switch `disable_warmup_injury_filter`. ⚠ The Batch-0 scorecard CANNOT prove this (warmup isn't in `plan.allExercises`) — `warmup_injury_filter_behavioral_test.dart` is the sole proof. The library's MAIN-move under-tagging (Push Up not shoulder-tagged) is a separate founder-directed audit batch. **⑥ C2 (WU-2 gym-cardio gate, b7a4e2):** the gym-cardio warmup/finisher (`hasGymEquipment`) was ALWAYS-FALSE on the generated path — writer/reader drift: the reader (`WarmupCooldownSelector.attach:146` + `CardioFinisher.attach`) computed `equipmentList.any(contains('gym')||('full'))` but generateV4 passes `_getEquipmentList(tier)` = ITEM tokens (never those substrings). Fix: `cardio machine` added to the gym `tierItems`; generateV4 computes a flag-gated `hasGymEquipmentOverride` from the effective (exclusion-subtracted) equipment + passes it to BOTH attach methods (null → old predicate → `template_service` + `shared_contracts_test:826` byte-identical). Rides the SAME `enable_equipment_exclusions` flag → flipping it ALSO activates WU-2, so it is no longer a *pure* no-op (B1/C1's whole-Phase byte-identical NO-OP tests were narrowed to exempt `warmup`+`finisher`; coverage of the gym-cardio behavior moves to `wu2_gym_cardio_gate_behavioral_test.dart` — the sole proof, warmup/finisher not in `plan.allExercises`). ⚠ TESTING FOOTGUN: `Phase.toMap` serializes the days TWICE (`workouts` compat list + `week_plans[].workout_days[]`) — any plan-diff/byte-identical test must strip/handle BOTH. Kill-switch = the shared `enable_equipment_exclusions`.

**Triggered deload (W2.4 — the deload WAVE is conditional, runtime).** The week-4 deload the
periodization wave generates (`_waveNames[3]`, `weekIdx 3`) can be UN-DELOADED to a working week at
runtime — the generator still always emits the deload; a rollover-time evaluator decides whether to
lift it. Two ship-dark pieces (`enable_triggered_deload`; the eval ALSO needs `enable_readiness`):
**7-B-1 GENERATION-STASH** (here, `periodization_engine.apply(stashWorkingBase:)`) — the deload week
stashes each exercise's PEAK-equivalent `working_sets`/`working_reps` (SoT `deload_working_base_stash`);
**7-B-2 EVAL** (`lib/core/services/deload_evaluator.dart` from `day_rollover_service`, NOT plan_engine)
— SAFE-polarity `shouldLift = notBackstop && notDeloadPhase && readinessGood && e1rmNoFatigue` (all
POSITIVE-evidence; else KEEP), then a per-exercise full-row un-deload of the wk4 `schedule_*` rows +
the `current_plan` blob week_plans[3] (`week_character` 'deload'→'working'). Local-only user-scoped
state (`last_actual_deload_phase` backstop + `deload_evaluated_for_phase_N`), NO migration. SoT
`triggered_deload_eval`; behavioral `deload_eval_behavioral_test.dart`.

**Deload "why" (W3.1 — Batch 10 explainability).** The eval ALSO stamps a per-phase workoutBox
key `deload_reason_phase_<P>` (via `WorkoutScheduleReadService.deloadReasonKeyPrefix` +
`deloadPhaseFromWeek4` — the SAME phase source as the flag/marker) with a pure non-shaming
one-liner (`lib/core/utils/deload_reason.dart` `deloadDecisionReason`: structural-before-evidence
precedence, each evidence branch had-data-gated, keyed on the ACTUAL outcome `liftedAny` —
`_liftWeekFour` now returns `bool`, so a `shouldLift`-but-nothing-lifted case shows a matching,
not contradictory, subtext). `WorkoutScheduleReadService.currentDeloadReason` reads the SAME key
via the SAME derivation (writer==reader by construction) gated on `triggeredDeloadEnabled`; the
Train `PhaseArcStrip` renders it only on the deload week (`currentWeek==4`) → null / not-week-4 →
byte-identical to 7-A. Additive, LOCAL-only, no migration. SoT `deload_decision_reason`;
behavioral `deload_reason_test.dart` (pure) + a `deload_eval_behavioral_test.dart` round-trip.
The adherence-gate "why" (W3.1's other half) is a copy-only non-shaming lead-in in
`advance_choice_sheet.dart` (no completion %, per the codified non-shaming brand soul).

**Repeat-content generation (W2.5 — pin the prior phase's selection).** ⑧ 8-A/2-cap adds a
SHIP-DARK capability: `generateV4`/`generate` accept
`Map<int,({List<String> a, List<String> b})>? pinnedExercisesByDay` (per day: variant-A names for
weeks 1/3, variant-B names for weeks 2/4 — a single-list `B=A` would DUPLICATE weeks 1/3 because
periodization reads `exercisesB` for the B-weeks; B-absent derives a fresh B-variant, never a
collapse); when non-null, Stage 2 calls `ExerciseSelector.buildPinnedDays(frames: filteredDays, …)`
instead of `pickV4` — slotting the prior phase's exercise NAMES into the CURRENT split frames, then the tail
(Stage 0 decay + periodization, `:142+`) runs UNCHANGED (so the ACTUAL last-logged weight re-decays
BY NAME; a plan-blob copy would double-decay an already-cooked `suggested_weight` + bypass the
in-cascade filters). A pin resolves via `getByExactName` else the user's `custom_exercise_*` rows
(else drop). It re-applies ONLY the HARD constraints the cascade bypassed — equipment-EXCLUSION +
UNGATED injury `_isContraindicated` (att1-4 semantics, NOT att-5's kill-switched skip: a newly-injured
user never gets the old contraindicated lift repeated) — but NOT the SOFT equipment-tier (att4
relaxes it; re-filtering would drop a same-tier att4 pick — the CALLER gates same-tier). An
all-dropped variant FRESH-FILLS via `pickV4([frame])` (MF-1: degrades to at worst a fresh
generation's safe slot-omission, never a bespoke `(none)`). `null` → verbatim `pickV4` →
byte-identical. The production caller (`generateAndSchedule` repeatContent) + kill-switch
`enable_adherence_gate` land in UNIT 2-int. SoT `repeat_phase_pinned_selection`; behavioral
`repeat_phase_pinned_selection_behavioral_test.dart`.

**Volume titration (W2.7 — Batch 9, phase-boundary per-group set nudge).** At a genuine FRESH
phase advance, `VolumeTitration.applyToWeeks` (a PURE post-pass on the `PeriodizationEngine.apply`
output in `plan_generator.dart`, right after Stage 4 + before Sequencing) nudges each MAJOR MUSCLE
GROUP's weekly direct sets by ±1, clamped [MEV=8, MRV=20], from `VolumeTitration.resolveDeltas(phase)`:
per-group e1RM trend (trailing-35-IST-day `exlog_*`, the shared `lib/core/utils/e1rm.dart`
`sessionMaxE1rm` — ONE Epley loop for both W2.4 deload + this, byte-identical, pinned by
`deload_eval_behavioral_test`) aggregated exercise→group via the shared `muscle_groups.dart`
`muscleGroupOf` (the scorecard's `_muscleToGroup`, now DELEGATED here — content byte-identical so
the frozen D3 baseline is unmoved) + a GLOBAL readiness soreness damper (soreness is a single daily
axis, NOT per-muscle). SAFE polarity: −1 on demonstrated e1RM DECLINE alone; +1 ONLY with POSITIVE
readiness recovery (≥3 rows, <40% beat-up) — so with readiness ship-dark (0 rows) it only ever TRIMS.
TWO inert seams: kill-switch `enable_volume_titration` (DEFAULT OFF → `resolveDeltas` `{}`) AND opt-in
`applyVolumeTitration` — the orchestrator applies it ONLY when the caller passes true, and the two
advance callers (`autoGenerateNextPhaseIfNeeded` `:483` + `graduation_screen._onPro` `:644`) pass
`pins == null` so a low-adherence REPEAT never gains volume; every other caller (coach-regen /
edit-profile / previews / hotel / onboarding) defaults false → untouched. `applyToWeeks({})` returns
the SAME list reference → byte-identical. Per-group ±1 clamps on the weekly aggregate, one exercise
bumped once/week (dedup), groups processed in sorted order (determinism). Composes with 7-B-1: the
deload week's stashed `workingSets` is titrated symmetrically (self-gated on `workingSets != null`)
so a triggered un-deload restores the TITRATED peak (F1). ⚠ ~17 qualifier-tagged isolation lifts +
8 empty-`primary_muscles` rows map to null → never titrated (conservative; small groups below MEV).
The Batch-0 scorecard CANNOT measure this (it scores a `default_sets` SELECTION proxy, not periodized
sets) — the behavioral test is the sole proof. SoT `volume_titration`; behavioral
`volume_titration_behavioral_test.dart` + `e1rm_test.dart`.

**ID-keyed history (W3.3 — Batch 11-A, forward-only, Hive-local).** New `exlog_*`
rows carry the library `exercise_id` (`WorkoutWriteService.logExercise` optional
`exerciseId`, STICKY — a null-id re-log keeps a prior id; threaded from
`ExerciseData.exerciseId` on the active-workout path + the manual swap/add/
create picker paths (`swap_sheets.dart` reads the picked row's `id`;
`SwapExerciseData` gained an `id` field), and from the coach `_executeLogSet`
ONLY when the id resolves to a real library exercise). When
`enable_exercise_id_history` is ON, `ProgressionResolver.resolve` matches a plan
exercise to logged history by id — **INCLUSIVE** with name (id-matched ∪
name-matched, the MORE-RECENT wins; graded session-lists unioned) via a parallel
`lastSessionById`/`allById` index keyed on non-empty ids only — so a rename/swap no
longer SPLITS an exercise's weight history. `plan_generator` threads each plan
exercise's `exerciseId` (parallel to `repRanges`). Ship-dark **DEFAULT OFF**
(`PlanEngineFlags.exerciseIdHistoryEnabled`) → indices null → name-only,
byte-identical. Forward-only: legacy/restored/no-id rows fall to the name index
(restore does NOT reconstruct the Hive `exercise_id`). ⚠ The Hive library id is
**Hive-LOCAL** — the cloud `workout_log_exercises.exercise_id` is a SEPARATE
name-derived onConflict identity; the library id MUST NOT be projected upward
(would shift the natural key → duplicate rows). SoT `exercise_id_history` (+ the
`hive_field_name_exlog` collision note); behavioral
`exlog_exercise_id_behavioral_test.dart` + absence gate
`sync_exlog_no_library_id_test.dart`.

**Injury-substitute preference (①.1d — Batch 11-C, ship-dark).** When
`enable_injury_substitute_pref` is ON, `_cascadeFill` re-ranks the already-safe
(POST-injury-filter), same-`movement_pattern` `queryV4` candidate list to PREFER a
curated `InjurySubstitutes` sub (map/joint-friendlier order, EXACT lowercased name
match) over queryV4's compound/priority sort — at all 4 attempt-return sites via the
pure `_selectCandidate`. It runs on the post-filter list → can NEVER surface a
contraindicated exercise; a PREFERENCE (falls through to `candidates.first` when no
curated sub is a candidate). The flag is resolved ONCE in `generateV4` →
`applyInjurySubstitutePreference` threaded pickV4/buildPinnedDays → `_fillSlots` →
`_cascadeFill` (mirrors `applyInjuryUniversalFilter`). DEFAULT OFF → verbatim
`candidates.first` (byte-identical). The pure-Dart `cascade_tracer.dart` mirrors it
(`_selectCandidateName`); `query_v4_mirror.dart` UNCHANGED; `generator_matrix.dart`'s
trace call is NOT wired (param defaults false → frozen D3 baseline unmoved). Curated
map covers 6 of 9 `InjuryVocab` tokens (ankle/neck/hamstring → no subs → fallthrough),
each verified same-pattern-safe vs `exercise_library.json` (RDL dropped from lower_back
— under-tagging gap). ⚠ L6 `_applyHistoryAdjustments` (phase≥2) may re-swap a curated
pick that's in the user's `demoted` set (still injury-filtered → safe). SoT
`injury_safe_substitute_preference`; behavioral
`injury_substitute_preference_behavioral_test.dart`. **11-B (W3.4 cross-phase variety)
extends the SAME `_selectCandidate` with an `avoidNames` tiebreak (below).**

**Cross-phase variety (W3.4 — Batch 11-B, ship-dark).** On a genuine FRESH phase
advance (pins==null), `WorkoutScheduleReadService.previousPhaseNamesByDay()` reads the
just-finished phase's per-day A/B picks (getWeek(1)/getWeek(2), LOWERCASED — the SAME
rows repeatPinsFrom reads, via the shared `_exerciseNamesOfRow`/`_namesByDayIndex`
parsers, but WITHOUT the G5 gate) and threads them as `previousPhaseByDay` → generateV4
→ pickV4 (indexed per-day avoidA/avoidB) → `_fillSlots` → `_cascadeFill` →
`_selectCandidate._preferNovel`, which PREFERS a same-`movement_pattern` sibling NOT
used last phase. **SOFT** bias — feeds `_selectCandidate` ONLY, NEVER
queryV4/pickedNames/excludeNames → can never hard-empty a slot (BOUNDED: falls to
`pool.first` when only last-phase picks remain). Composes with ①.1d (injury-sub selects
the pool, variety breaks ties within it). Ship-dark `enable_cross_phase_variety` — the
service-layer gate is inside `previousPhaseNamesByDay` (OFF → `{}` → no getWeek reads →
avoidNames empty → byte-identical). The pure-Dart `cascade_tracer.dart` mirrors it
(`_preferNovelName`); `generator_matrix.dart` NOT wired → frozen D3 baseline unmoved.
attempt-5 pool is NOT variety-eligible; buildPinnedDays UNCHANGED (variety ⟂ pins). No
migration (reads existing schedule_* rows). SoT `cross_phase_variety`; behavioral
`cross_phase_variety_behavioral_test.dart`.

**Plateau escalation (W3.5 — Batch 12-A, PRO, ship-dark).** rung-2 (+sets): at a
genuine FRESH phase advance a plateaued MAJOR GROUP earns +1 weekly direct set,
MERGED into the W2.7 titration delta map so ONE clamped `applyToWeeks` pass applies
both. A "plateau" = a COMPOUND lift whose MAX-Epley e1RM is FLAT ((max−min)/max ≤ 5%)
across ≥3 dated sessions spanning ≥28d in a trailing 63-IST-day window
(`PlateauScan.plateauedGroups`, reusing the SHARED `e1rm_history.buildE1rmByDate` +
`ExerciseRepository.isCompoundByExactName` + `muscleGroupOf`). `mergePlateauSetDeltas`
`putIfAbsent`s +1 ONLY where titration left a group ABSENT → a declining group's −1
ALWAYS wins (no double-bump; never +sets a fatiguing/declining group), and the
[MEV,MRV] clamp caps it. **rung-1 (deload when plateaued+fatigued) needs NO code — it
is ALREADY delivered by W2.4's `readiness.good` keep in `deload_evaluator`: a plateau
keep-term wired into `shouldLift` would be PROVABLY DEAD (it can only engage when
`readiness.good` is already false, since `_fatiguePresent` is that predicate's strict
complement), so 12-A does NOT touch `deload_evaluator.dart`.** rung-3 (exercise
rotation) is Batch 12-B. THREE inert seams: `enable_plateau_escalation` DEFAULT OFF
(merge returns the input map unchanged → applyToWeeks identity → byte-identical); ALSO
gated on `enable_readiness` (the fatigue gate needs readiness rows — mirrors
DeloadEvaluator's guard); OPT-IN `applyPlateauEscalation` threaded generate/generateV4
→ generateAndSchedule → the two `pins == null` advance callers (autoGenerate +
graduation._onPro). Fatigue = persistent readiness red/yellow (≥3 rows in 14d, strict
majority `level != green`) — the SAME data/window/predicate as `_readinessGood`.
`phase >= 2` self-gate (PRO — free is phase 1; advance callers are PRO-gated →
inherits the server-verified `phases_2_to_12`). ⚠ Drift hygiene (#1 class): the exlog→
e1RM map-build loop is now the SHARED `e1rm_history.buildE1rmByDate` (extracted
byte-identical from `DeloadE1rmScan` + `VolumeTitration`; the file now holding the
literal `exlog_` scan) and the compound predicate is `ExerciseRepository
.isCompoundByExactName` (from `DeloadE1rmScan._isCompound`) — both refactors pinned by
the existing deload/titration behavioral tests. NO migration/restore (Hive-read-only;
exlog+readiness already sync+restore); `generator_matrix`/`cascade_tracer` NOT wired →
frozen D3 baseline unmoved. SoT `plateau_escalation`; behavioral
`plateau_escalation_behavioral_test.dart` + pure `plateau_scan_test.dart`.

**Plateau rotation (W3.5 — Batch 12-B, PRO, ship-dark).** rung-3: at a genuine FRESH
phase advance the plateaued COMPOUND lifts (SAME detector as rung-2 —
`PlateauScan.plateauedExerciseNames`, the per-exercise sibling of `plateauedGroups`,
LOWERCASED, SAME gates) are SOFT-avoided in the cascade so each ROTATES to a
same-`movement_pattern` sibling next phase. Computed in `generateV4` (guarded
`applyPlateauEscalation && pinnedExercisesByDay == null` → statement before the pins
ternary) → threaded as `pickV4`'s new `plateauAvoidNames` → UNIONED GLOBALLY into every
day's `avoidA`/`avoidB` (alongside 11-B's `previousPhaseByDay` names) → the SAME
`_fillSlots`/`_cascadeFill`/`_selectCandidate._preferNovel` seam. **SOFT + BOUNDED** —
feeds `_selectCandidate` ONLY (never queryV4/excludeNames) on a guaranteed-non-empty
pool → never empties a slot / wrong pattern / disturbs the attempt-5 injury floor; on a
shallow pool `_preferNovel` falls to `pool.first` (the stuck lift RETAINED, no crash).
**Reuses `enable_plateau_escalation` (NO new flag), INDEPENDENT of
`enable_cross_phase_variety`** (rotation fires under the plateau flag alone). DEFAULT OFF
/ opt-in false → `plateauAvoid {}` → the union `{...listA, ...{}}` ≡ `listA.toSet()` →
byte-identical. Rotation is a SWAP (slot-count-neutral; a rotated-in sibling may carry ±1
base `default_sets`, bounded — pre-existing 11-B behavior). **rung-2 (+sets) and rung-3
(rotation) BOTH fire (no cross-gate)** — the +1 lands on the fresh sibling's group,
MRV-clamped; safe. **rung-1 explainability NOT built** (terminal won't-do: out-of-scope
for a rotation batch, causally imprecise — deload is fatigue-driven — and re-coupling
`deload_evaluator→plateau_scan` or a generation-time stash would break pure-compute).
`cascade_tracer._preferNovelName` + `generator_matrix` UNCHANGED → frozen D3 baseline
unmoved. ⚠ L6 `_applyHistoryAdjustments` (phase≥2, demoted/customs) may re-add a rotated
lift — consistent with rung-3 being SOFT (the behavioral test seeds no swap/custom
history → L6 skipped → deterministic). No migration/restore (Hive-read-only). SoT
`plateau_rotation`; behavioral `plateau_rotation_behavioral_test.dart`.

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

**Equipment exclusion filter (⑥ B1):** an item-level PURE-EXCLUSION filter — a user subtracts canonical equipment they lack (from slice C's `equipment_exclusions` profile field). Derived ONCE in `generateV4` (mirroring the injury seam `plan_generator.dart:92`): flag-gated (`PlanEngineFlags.equipmentExclusionsEnabled`, **ship-dark DEFAULT OFF** §4.6) + `EquipmentVocab.floorSanitizedExclusions` (normalize→canonical + STRIP none/bodyweight so the bodyweight floor is never excludable). Threaded as a `Set<String>` to EVERY pick path: `queryV4` att1-4 (the drop ~`:282` is placed BEFORE the `:288` tier block + **KEPT at att4** — an excluded item is a HARD constraint, unlike the soft tier heuristic att4 relaxes), the **att5 pool skip** (mirrors U2's injury skip; the per-pattern bodyweight floor keeps the slot non-empty — fewer-but-safe, never a `(none)`), the L2 custom-append, and the L6 demote-swap. Reads every `equipment_needed` crash-safe + normalizing via `EquipmentVocab.fromProfile` (so it's correct for un-normalized community rows before B2). The `queryV4 exclusions` param is REQUIRED (compile-time thread enforcement). PURE exclusion (drop iff `equipment_needed` intersects exclusions; `equipment_tier` filter UNTOUCHED) — the intersection design regressed 41 tier-selectable exercises at empty; no-op at empty → byte-identical. Cardio finisher + warmup gym-cardio are now gym-gated + exclusion-aware via ⑥ C2 (WU-2 — see stage 8; diagnose b7a4e2); cooldown stays unfiltered (static stretches). SoT `equipment_exclusion_filter`; behavioral `equipment_exclusion_filter_behavioral_test.dart`; scorecard exclusion personas in `generator_matrix.dart` (mirror + cascade_tracer carry the same drop). Kill-switch `enable_equipment_exclusions`.

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
| Pike Push Up assigned to rear delt slot | TWO distinct causes: (a) a WRONG-PATTERN pool ENTRY — Pike Push Up (a vertical push) was mis-filed under `shoulder_isolation`, Dead Bug/Side Plank (core) under pull/hip — fixed by CORRECTING `universalPoolV4` itself (Batch 13-A `c3f9b2`, pinned by `universal_pool_mirror_test`, mirror lockstep with `cascade_tracer.dart`); (b) FREQUENCY of falling to attempt-5 — too many slots of one muscle/pattern/type vs pool depth — cap rear delt 3/week, lateral delt 3/week, front delt 1/week in `split_resolver.dart`, NOT the pool. Contradiction resolved: the pool is the right fix for a wrong PATTERN entry; split_resolver is the right fix for over-ALLOCATION frequency. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) + Batch 13-A c3f9b2 |

## Tests pinning the rules here

- `test/plan_generator/sample_plans_report.dart` — full 12-combo sweep (3×experience × 4×days) for build_muscle/full_gym. Target: 0 attempt3/universalPool/none. Emits `sample_plans_output.md` for review.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade. Run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.
- `test/plan_engine_v4/` — granular pipeline-stage tests (split resolver, volume filter, exercise selector, periodization, superset pairer).
- `test/contracts/plan_generator_inputs_test.dart` — pins the goal × equipment × daysPerWeek input contract.

## See also

- `lib/features/train/CLAUDE.md` — generated plan is consumed by Train screen + Active Workout.
- `lib/features/onboarding/CLAUDE.md` — initial plan generated on Plan-screen tap.
- `docs/reference/exercise-library.md` — exercise_library Hive box schema (movement_pattern, suitable_for, equipment_needed, is_foundational).
