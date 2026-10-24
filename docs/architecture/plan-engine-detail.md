# Plan Engine - moved-out detail

On-demand detail for `lib/shared/repositories/plan_engine/CLAUDE.md`. Everything here was moved VERBATIM out of the nested file (dated incident narratives, `CORRECTED <date>` histories, per-batch provenance, long pitfall bodies) to keep the auto-loaded file lean. The nested file keeps the current rule for each item and points here.

## Pipeline stage 0 - Progression (detraining decay + graded double progression)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 55-55, context-lean batch 2026-09-29)._

0. **Progression (pre-pipeline, phase≥2)** → `ProgressionResolver.resolve()` scans `exlog_*` for each exercise's most-recent top set → suggested starting weight (3-band reps-rule + Epley 1RM ceiling), fed to Periodization via `previousWeights`. **⑦(a) (Batch 3b-i): detraining WEIGHT decay** — a user resuming after a training gap restarts lighter: the baseline is decayed by the IST day-gap since their last logged session (≤7d none · 8–21d −7.5% · 22–35d −17.5% · >35d −50%) BEFORE the reps-rule; the decayed `base` replaces the original weight in ALL FOUR reps-rule branches incl. the `<=0` floor (reduce-ONLY), Epley cap stays on the pre-decay 1RM, gap is a zone-canceling date-only diff (never re-zones the already-IST exlog date — Test #11.1 class). Kill-switch `disable_detraining_decay` (default ON; the reduce-only band table is extracted to shared `lib/core/utils/detrainingFactorForGap` — `_detrainingFactor` keeps its IST-string→gap conversion then delegates, and ⑦(b)'s session-time resume cut reuses it from an int gap). SoT `detraining_decay`; behavioral test `progression_resolver_decay_test.dart` (the Batch-0 scorecard CANNOT measure resolve() — it never invokes it + seeds no logs). **W2.1 (Batch 3b-ii): graded double progression** — the fixed 10/5 reps-rule becomes REP-RANGE-aware (from the ⑦a base): reps ≥ hi → progress, within → hold, below lo → back off ONLY on the top-2 most-recent DISTINCT calendar days BOTH below lo (2-consecutive; de-duped by (y,m,d)). Beginner auto-linear window (RAW `fitness_experience=='beginner'` AND training-age from `onboarding_completed_at` < 120d → always progress). Rep-ranges threaded via a `repRanges` param from `populated`; shared `parseRepRange` (`models.dart`) used by BOTH resolve() AND `_applyWave` (one parser, #1-bug-class; inertness pinned by `periodization_wave_reps_invariant_test.dart`). **LIVE since 2026-09-16 (OI-53 batch 2); kill-switch `disable_graded_progression`** → verbatim fixed-10/5 (byte-identical; ⑦a decay independent, base/est1rm on the single-most-recent `lastSession` UNCHANGED; top-2 is ADDITIVE). SoT `graded_progression`; behavioral test `progression_resolver_graded_test.dart`.

## Pipeline stage 5 - Periodization (physique-focus bring-up)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 60-60, context-lean batch 2026-09-29)._

5. **Periodization Engine** → Uses exercise-specific `rep_range` + archetype-based wave. **⑤ (Batch 4): physique-focus bring-up.** The user's `physique_focus` (profile) is translated to muscle-substring tokens (`TrainingHistoryAnalyzer.physiqueFocusToBodyFocus`; read via the try/catch `physiqueFocusMuscles()` helper) at the `effectiveBodyFocus` seam — the flag-gate + precedence GLUE lives in the behavior-tested `TrainingHistoryAnalyzer.resolveBodyFocus` (`plan_generator.dart:148-155`), which periodization turns into **+1 set per matching exercise** (the EXISTING bodyFocus mechanism — no periodization change). Explicit focus PRECEDES auto `weakMuscles()` and applies at ALL phases; balanced/strength/absent → [] → falls back to weakMuscles (phase≥2). LIVE since 2026-09-16 (OI-53 batch 2); kill-switch `disable_physique_focus_bringup` → seam byte-identical. **The dedicated isolation SLOT is founder-deferred** (2026-07-13) — trade-not-add proven infeasible (`VolumeFilter` is POSITIONAL `take(N)`, NOT priority-sorted; focus muscle already kept on its theme day). SoT `physique_focus_bringup`; behavioral test `physique_focus_bringup_test.dart`.

## Pipeline stage 7 - Cardio Finisher (goal-aware default)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 62-62, context-lean batch 2026-09-29)._

7. **Cardio Finisher** → **④ (Batch 3a): goal-aware default.** With no stored `cardioPreference` (always, today — no preference UI), the finisher SHAPE now defaults to the goal instead of the blanket mildest mini-HIIT: `lose_fat→hiit`, `general_fitness→cycling`, `recompose→jump_rope` (only the 3 `FitnessGoals.cardio==true` goals attach a finisher). `CardioFinisher._defaultForGoal`; kill-switch `disable_cardio_goal_default` (default ON) reverts to verbatim `hate_cardio`. SoT `cardio_goal_default`; behavioral test `cardio_goal_default_test.dart`. The Batch-0 scorecard doesn't measure the finisher (post-selection stage) — the behavioral test is the proof.

## Pipeline stage 8 - Warmup/Cooldown (injury filter, WU-2 gym-cardio gate)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 63-63, context-lean batch 2026-09-29)._

8. **Warmup/Cooldown** → Now also auto-injects for custom templates. **Injury-filtered (U3, d3f8a1):** `WarmupCooldownSelector.attach(injuries:)` DROPS a hardcoded warmup/cooldown/cardio move whose `_moveInjuries` tag intersects the user's injuries (drop-not-substitute), with a guaranteed non-empty FLOOR (safe Slow Walking cardio fallback + Deep Breathing anchor). Main-cascade-selectable moves (Push Up/Band Pull Apart/Baithak) use their LIBRARY `injury_contraindications` so main+warmup agree; warmup-only moves use conservative tags (the library under-tags them). Threaded from `generateV4` + `template_service`; kill-switch `disable_warmup_injury_filter`. ⚠ The Batch-0 scorecard CANNOT prove this (warmup isn't in `plan.allExercises`) — `warmup_injury_filter_behavioral_test.dart` is the sole proof. The library's MAIN-move injury under-tagging was CLOSED by Batch 13-B (f4c1e8): 26 empty-`[]` strength rows (hinges/rows/overhead/loaded-core) tagged + 2 deepened (GHD Sit Up, Good Morning), clinically-nuanced at the time (13-B kept Push Up wrist-only and a controlled/machine/rehab pool untagged for variety). **SUPERSEDED by the v14 injury re-check (2026-10-23, d30de7):** the founder rejected that variety carve-out, so 104 rows gained 148 tags (every push-up variant is shoulder-tagged, Push Up is wrist + shoulder; Chin Up elbow only; Goblet Press, Lat Pulldown, the hip machines, the crunch/sit-up family, every curl and triceps row now tagged) and only a 33-row low-load / rehab pool stays untagged (`test/helpers/injury_safe_pool.dart`). SoT `exercise_injury_tags`; ALL 27 `_moveInjuries` keys == their library tags, pinned by `warmup_library_injury_mirror_test.dart`. **⑥ C2 (WU-2 gym-cardio gate, b7a4e2):** the gym-cardio warmup/finisher (`hasGymEquipment`) was ALWAYS-FALSE on the generated path — writer/reader drift: the reader (`WarmupCooldownSelector.attach:146` + `CardioFinisher.attach`) computed `equipmentList.any(contains('gym')||('full'))` but generateV4 passes `_getEquipmentList(tier)` = ITEM tokens (never those substrings). Fix: `cardio machine` added to the gym `tierItems`; generateV4 computes a flag-gated `hasGymEquipmentOverride` from the effective (exclusion-subtracted) equipment + passes it to BOTH attach methods (null → old predicate → `template_service` + `shared_contracts_test:826` byte-identical). Rides the SAME equipment-exclusions flag (now `disable_equipment_exclusions`, default ON) → the 2026-08-05 flip ALSO activated WU-2, so it is no longer a *pure* no-op (B1/C1's whole-Phase byte-identical NO-OP tests were narrowed to exempt `warmup`+`finisher`; coverage of the gym-cardio behavior moves to `wu2_gym_cardio_gate_behavioral_test.dart` — the sole proof, warmup/finisher not in `plan.allExercises`). ⚠ TESTING FOOTGUN: `Phase.toMap` serializes the days TWICE (`workouts` compat list + `week_plans[].workout_days[]`) — any plan-diff/byte-identical test must strip/handle BOTH. Kill-switch = the shared `disable_equipment_exclusions` (DEFAULT ON since 2026-08-05, e2d6b8 — so this WU-2 gate is now LIVE for every gym-tier user, no longer inert).

## Triggered deload (W2.4)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 65-76, context-lean batch 2026-09-29)._

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

## Deload why (W3.1)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 78-108, context-lean batch 2026-09-29)._

**Deload "why" (W3.1 — Batch 10 explainability).** The eval ALSO stamps a per-phase workoutBox
key `deload_reason_phase_<P>` (via `WorkoutScheduleReadService.deloadReasonKeyPrefix` +
`deloadPhaseFromWeek4` — the SAME phase source as the flag/marker) with a pure non-shaming
one-liner (`lib/core/utils/deload_reason.dart` `deloadDecisionReason`: structural-before-evidence
precedence, each evidence branch had-data-gated, keyed on the ACTUAL outcome `liftedAny` —
`_liftWeekFour` now returns `bool`, so a `shouldLift`-but-nothing-lifted case shows a matching,
not contradictory, subtext). `WorkoutScheduleReadService.currentDeloadReason` reads the SAME key
via the SAME derivation (writer==reader by construction) gated on `triggeredDeloadEnabled`; the
Train `PhaseArcStrip` renders it only on the deload week (`currentWeek==4`) → null / not-week-4 →
byte-identical to 7-A. Additive, LOCAL-only, no migration.

**LIVE since 2026-09-06** (OI-53 flag 4; kill-switch `disable_deload_reason_line`), and the
stored VALUE changed with the flip. Unit B (diagnose `c5a8f3`) found the stamped reason can
outlive the week it describes: two BLOB-rewriting paths re-stamp week 4 back to `deload` after a
lift (`workout_schedule_read_service.dart:388` and `:227`) while `deload_evaluator.dart:79`'s
idempotency flag blocks any correction and NOTHING in `lib/` deletes the key. The key now holds a
MAP `{week_character, text}` — `week_character` is `liftedAny ? 'working' : 'deload'`, the same
predicate the copy already branches on — and the pure
`WorkoutScheduleReadService.validatedDeloadReason` returns the text ONLY while that character
still equals week 4's in `currentWaveCharacters()` (the BLOB the strip renders, deliberately not
the scheduled rows), compared lowercase+trimmed on both sides. Mismatch in EITHER direction, a
legacy bare String, a malformed map or a blob under 4 weeks all → no line. That validator is a
SEPARATE pure function on purpose: inline, its nulls were indistinguishable from the enclosing
`catch`, and three guard-deletion mutations reddened zero tests.
⚠ It cannot see the AI-coach regen, which writes rows and no blob (OI-166).

SoT `deload_decision_reason`; behavioral `deload_reason_test.dart` (pure) +
`deload_eval_behavioral_test.dart` (round-trip through the real evaluator) +
`deload_reason_staleness_behavioral_test.dart` (the staleness contract, 20 assertions).
The adherence-gate "why" (W3.1's other half) is a copy-only non-shaming lead-in in
`advance_choice_sheet.dart` (no completion %, per the codified non-shaming brand soul).

## Repeat-content generation (W2.5)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 110-138, context-lean batch 2026-09-29)._

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
byte-identical. The production caller (`generateAndSchedule` repeatContent) lands in UNIT 2-int.
**LIVE since 2026-09-16 (OI-53 batch 2); kill-switch `disable_adherence_gate`** — see
`plan_engine_flags.dart`'s `adherenceGateEnabled` doc comment for the full call-site picture: two
independent trigger computations that are NOT symmetric (the automatic path redundantly re-checks
the flag before `_buildRepeatPins`; the choice-sheet path did not, until a B-pass finding moved the
check into `_buildRepeatPins` itself so both callers are now protected by the one method they share)
and the coverage that closes the gap that shape left.
SoT `repeat_phase_pinned_selection`; behavioral
`repeat_phase_pinned_selection_behavioral_test.dart` (the pinning MECHANISM — UNIT 2-cap —
drives `PlanGenerator.generateV4(pinnedExercisesByDay:)` directly and does not exercise the flag
itself; that gap is closed by `repeat_content_scheduling_test.dart` (UNIT 2-int, the
`last_phase_profile` write) and `pro_phase_advance_behavioral_test.dart`'s "repeatContent gated on
flag AND completion" group (the actual gating decision, end-to-end, mutation-proven)).

## Volume titration (W2.7)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 140-163, context-lean batch 2026-09-29)._

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
readiness recovery (≥3 rows, <40% beat-up). ⚠ **CORRECTED 2026-09-01:** this used to read "with readiness ship-dark (0 rows) it only ever TRIMS" — readiness went LIVE 2026-09-01, so rows DO accumulate; titration is inert only because enable_volume_titration is still OFF and short-circuits at volume_titration.dart:60 BEFORE _recovered() runs -- _recovered() itself has NO readiness gate.
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

## ID-keyed history (W3.3)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 165-187, context-lean batch 2026-09-29)._

**ID-keyed history (W3.3 — Batch 11-A, forward-only, Hive-local).** New `exlog_*`
rows carry the library `exercise_id` (`WorkoutWriteService.logExercise` optional
`exerciseId`, STICKY — a null-id re-log keeps a prior id; threaded from
`ExerciseData.exerciseId` on the active-workout path + the manual swap/add/
create picker paths (`swap_sheets.dart` reads the picked row's `id`;
`SwapExerciseData` gained an `id` field), and from the coach `_executeLogSet`
ONLY when the id resolves to a real library exercise). **LIVE since 2026-09-16
(OI-53)** — `ProgressionResolver.resolve` matches a plan exercise to logged
history by id — **INCLUSIVE** with name (id-matched ∪ name-matched, the
MORE-RECENT wins; graded session-lists unioned) via a parallel
`lastSessionById`/`allById` index keyed on non-empty ids only — so a rename/swap no
longer SPLITS an exercise's weight history. `plan_generator` threads each plan
exercise's `exerciseId` (parallel to `repRanges`). Kill-switch
`disable_exercise_id_history` (`PlanEngineFlags.exerciseIdHistoryEnabled`) → indices
null → name-only, byte-identical. Forward-only: legacy/restored/no-id rows fall to
the name index
(restore does NOT reconstruct the Hive `exercise_id`). ⚠ The Hive library id is
**Hive-LOCAL** — the cloud `workout_log_exercises.exercise_id` is a SEPARATE
name-derived onConflict identity; the library id MUST NOT be projected upward
(would shift the natural key → duplicate rows). SoT `exercise_id_history` (+ the
`hive_field_name_exlog` collision note); behavioral
`exlog_exercise_id_behavioral_test.dart` + absence gate
`sync_exlog_no_library_id_test.dart`.

## Injury-substitute preference (11-C)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 189-209, context-lean batch 2026-09-29)._

**Injury-substitute preference (①.1d — Batch 11-C).** **LIVE since 2026-09-16
(OI-53)** — `_cascadeFill` re-ranks the already-safe (POST-injury-filter),
same-`movement_pattern` `queryV4` candidate list to PREFER a curated
`InjurySubstitutes` sub (map/joint-friendlier order, EXACT lowercased name
match) over queryV4's compound/priority sort — at all 4 attempt-return sites via the
pure `_selectCandidate`. It runs on the post-filter list → can NEVER surface a
contraindicated exercise; a PREFERENCE (falls through to `candidates.first` when no
curated sub is a candidate). The flag is resolved ONCE in `generateV4` →
`applyInjurySubstitutePreference` threaded pickV4/buildPinnedDays → `_fillSlots` →
`_cascadeFill` (mirrors `applyInjuryUniversalFilter`). Kill-switch
`disable_injury_substitute_pref` → verbatim `candidates.first` (byte-identical).
The pure-Dart `cascade_tracer.dart` mirrors it
(`_selectCandidateName`); `query_v4_mirror.dart` UNCHANGED; `generator_matrix.dart`'s
trace call is NOT wired (param defaults false → frozen D3 baseline unmoved). Curated
map covers 5 of 9 `InjuryVocab` tokens (ankle/elbow/hamstring/neck → no subs → fallthrough; v14 tagged every elbow-pattern row, so elbow has no safe curated sub left),
each verified same-pattern-safe vs `exercise_library.json` (RDL dropped from lower_back
— under-tagging gap). ⚠ L6 `_applyHistoryAdjustments` (phase≥2) may re-swap a curated
pick that's in the user's `demoted` set (still injury-filtered → safe). SoT
`injury_safe_substitute_preference`; behavioral
`injury_substitute_preference_behavioral_test.dart`. **11-B (W3.4 cross-phase variety)
extends the SAME `_selectCandidate` with an `avoidNames` tiebreak (below).**

## Cross-phase variety (W3.4)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 211-228, context-lean batch 2026-09-29)._

**Cross-phase variety (W3.4 — Batch 11-B).** **LIVE since 2026-09-16 (OI-53)** — on
a genuine FRESH phase advance (pins==null),
`WorkoutScheduleReadService.previousPhaseNamesByDay()` reads the
just-finished phase's per-day A/B picks (getWeek(1)/getWeek(2), LOWERCASED — the SAME
rows repeatPinsFrom reads, via the shared `_exerciseNamesOfRow`/`_namesByDayIndex`
parsers, but WITHOUT the G5 gate) and threads them as `previousPhaseByDay` → generateV4
→ pickV4 (indexed per-day avoidA/avoidB) → `_fillSlots` → `_cascadeFill` →
`_selectCandidate._preferNovel`, which PREFERS a same-`movement_pattern` sibling NOT
used last phase. **SOFT** bias — feeds `_selectCandidate` ONLY, NEVER
queryV4/pickedNames/excludeNames → can never hard-empty a slot (BOUNDED: falls to
`pool.first` when only last-phase picks remain). Composes with ①.1d (injury-sub selects
the pool, variety breaks ties within it). Kill-switch `disable_cross_phase_variety` —
the service-layer gate is inside `previousPhaseNamesByDay` (kill-switch ON → `{}` → no
getWeek reads → avoidNames empty → byte-identical). The pure-Dart `cascade_tracer.dart` mirrors it
(`_preferNovelName`); `generator_matrix.dart` NOT wired → frozen D3 baseline unmoved.
attempt-5 pool is NOT variety-eligible; buildPinnedDays UNCHANGED (variety ⟂ pins). No
migration (reads existing schedule_* rows). SoT `cross_phase_variety`; behavioral
`cross_phase_variety_behavioral_test.dart`.

## Plateau escalation (W3.5, 12-A)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 230-260, context-lean batch 2026-09-29)._

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

## Plateau rotation (W3.5, 12-B)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 262-287, context-lean batch 2026-09-29)._

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
`crossPhaseVarietyEnabled`** (rotation fires under the plateau flag alone). DEFAULT OFF
/ opt-in false → `plateauAvoid {}` → the union `{...listA, ...{}}` ≡ `listA.toSet()` →
byte-identical. Rotation is a SWAP (slot-count-neutral; a rotated-in sibling may carry ±1
base `default_sets`, bounded — pre-existing 11-B behavior). **rung-2 (+sets) and rung-3
(rotation) BOTH fire (no cross-gate)** — the +1 lands on the fresh sibling's group,
MRV-clamped; safe. **rung-1 explainability NOT built** (terminal won't-do: out-of-scope
for a rotation batch, causally imprecise — deload is fatigue-driven — and re-coupling
`deload_evaluator→plateau_scan` or a generation-time stash would break pure-compute).
`cascade_tracer._preferNovelName` + `generator_matrix` UNCHANGED → frozen D3 baseline
unmoved. ⚠ L6 `_applyHistoryAdjustments` (phase≥2, demoted) may re-add a rotated
lift — consistent with rung-3 being SOFT (the behavioral test seeds no swap/custom
history → L6 skipped → deterministic). No migration/restore (Hive-read-only). SoT
`plateau_rotation`; behavioral `plateau_rotation_behavioral_test.dart`.

## Cascade attempt 5 - universalPool injury filter (U2)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 306-306, context-lean batch 2026-09-29)._

5. `universalPool` — hardcoded bodyweight fallback (`exercise_selector.dart:493-505`, mirrored in `cascade_tracer.dart`). **Injury-filtered (U2, a1f6c3):** unlike attempts 1-4 (which exclude contraindications via `queryV4 injuryExclusions`), attempt-5 bypassed the injury filter until Ship 1 — it now skips a contraindicated pool pick, resolves each pool name to its EXACT-name library record (`repo.search` is substring, so "Push Up" also matches "Pike Push Up"), and — if the whole pool is contraindicated — SAFELY OMITS the slot (returns null → fewer-but-safe). Kill-switch `configBox['disable_injury_universal_filter']` (default ON).

## Injury vocabulary (U1/U4)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 308-308, context-lean batch 2026-09-29)._

**Injury vocabulary (U1/U4, a1f6c3):** injuries must be the canonical library tokens (`InjuryVocab.canonicalTokens` in `lib/core/utils/injury_vocab.dart` — ankle/elbow/hamstring/hip/knee/lower_back/neck/shoulder/wrist), NOT the legacy UI vocab (`back` never matched `lower_back`). Every writer (Edit-Profile chips, muster) normalizes via `InjuryVocab.normalize`; `generateV4` normalizes CENTRALLY so every generation caller is covered by one seam; each entry point reads via crash-safe `InjuryVocab.fromProfile`. SoT concept `injury_vocabulary_contract`.

## Equipment exclusion filter (B1)

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 310-310, context-lean batch 2026-09-29)._

**Equipment exclusion filter (⑥ B1):** an item-level PURE-EXCLUSION filter — a user subtracts canonical equipment they lack (from slice C's `equipment_exclusions` profile field). Derived ONCE in `generateV4` (mirroring the injury seam `plan_generator.dart:92`): flag-gated (`PlanEngineFlags.equipmentExclusionsEnabled` — **FLIPPED ON 2026-08-05, diagnose `e2d6b8`**; kill-switch is now `disable_equipment_exclusions`, DEFAULT ON. It was ship-dark DEFAULT OFF from 2026-07-16 until then, during which the Customize UI collected + synced exclusions the generator ignored. ⚠ Flipping it ALSO activated ⑥ C2's WU-2 gym-cardio gate — see stage 8 — so gym-cardio warmup/finisher now reaches EVERY gym-tier user, not only exclusion-setters) + `EquipmentVocab.floorSanitizedExclusions` (normalize→canonical + STRIP none/bodyweight so the bodyweight floor is never excludable). Threaded as a `Set<String>` to EVERY pick path: `queryV4` att1-4 (the drop ~`:282` is placed BEFORE the `:288` tier block + **KEPT at att4** — an excluded item is a HARD constraint, unlike the soft tier heuristic att4 relaxes), the **att5 pool skip** (mirrors U2's injury skip; the per-pattern bodyweight floor keeps the slot non-empty — fewer-but-safe, never a `(none)`), and the L6 demote-swap (the L2 custom-append was removed 2026-10-21, diagnose d4b8e1). Reads every `equipment_needed` crash-safe + normalizing via `EquipmentVocab.fromProfile` (so it's correct for un-normalized community rows before B2). The `queryV4 exclusions` param is REQUIRED (compile-time thread enforcement). PURE exclusion (drop iff `equipment_needed` intersects exclusions; `equipment_tier` filter UNTOUCHED) — the intersection design regressed 41 tier-selectable exercises at empty; no-op at empty → byte-identical. Cardio finisher + warmup gym-cardio are now gym-gated + exclusion-aware via ⑥ C2 (WU-2 — see stage 8; diagnose b7a4e2); the gym-cardio gate itself does not extend to cooldown (cooldown has no gym-cardio picks to gate — it stays static stretches). This does NOT mean cooldown is unfiltered: cooldown exercise selection still goes through the same injury (U2) + equipment-exclusion pool logic as every other slot. SoT `equipment_exclusion_filter`; behavioral `equipment_exclusion_filter_behavioral_test.dart`; scorecard exclusion personas in `generator_matrix.dart` (mirror + cascade_tracer carry the same drop). Kill-switch `disable_equipment_exclusions` (DEFAULT ON since 2026-08-05, diagnose e2d6b8 — the `enable_` key is retired).

## Core-list pool (Batch B1, ship-dark)

Plan `docs/plans/2026-10-22-library-core-list-pool.md`; spec `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §4.

**Why.** The 5-attempt cascade picks from every row whose tags fit, so retired, skill and improvised rows reach plans by accident (OI-385..388). The core list is an explicit per-level choice: 73 beginner / 91 intermediate / 67 advanced rows on library v13, 66 rows on no list.

**Data (library v13).** Every row carries `core_levels`, `discipline`, `gym_availability`, `requires_coaching`, `high_impact`; kept rows carry `variant_family`. `slot_focus` (19 rows) and `slot_pattern` (12 rows) are ON-only overlays: queryV4 (OFF) and the exercise display keep reading `target_focus` / `movement_pattern` until the flip copies the overlays in.

**Path.** `pickV4` delegates to `_pickCoreList` when `enable_core_list_pool` is ON and `CoreListSelector.hasCoreFields` (a stale v12 box delegates nothing). Per day, variant A then B; per slot, `rankedPool`:

1. Hard filter: pattern, a `core_levels` key, discipline not `calisthenics_skill` / `olympic`, `canPerform` (or queryV4's tier rule when the floor is off), exclusions, `_isContraindicated`, not already picked.
2. Core rows at the effective level; else family fill (rows of a family that is core at this level, core only at a HIGHER level, `suitable_for` the level); else drop. A lower level's core row never fills (D6).
3. Implement preference (OI-387/388): when the capability set holds anything beyond the improvised tokens, arm/shoulder/pull slots drop improvised rows if an implement row remains. Keyed on capability, so a bodyweight user who owns dumbbells gets it too.
4. Order: demoted (L6) last, then B's soft avoid of A's picks, then foundational first in phase 1 (a preference, Ruling 7), sub-focus match, exercise type, `priority_tier`, foundational, id.

The pick goes through `_selectCandidate` with previous-phase, plateau, soft-avoid and demoted names as avoid names, because its curated injury-substitute narrowing re-sorts the pool. `typeFor` types a `["calisthenics","compound"]` row as compound (OI-385).

**Empty variants (Ruling 12).** An emptied variant copies the other. If both are empty, the day re-runs with core rows of an EASIER or equal level, nearest first (never a harder-only row, never a `core_levels: []` row; B-pass F2), copies again, and only then falls back to the OFF cascade. On shipped data only the 2 shoulder-injured bodyweight intermediate personas reach the any-level step; the flip needs 0 after Batch C.

**Evidence.** OFF identity: `test/plan_generator/generator_golden_test.dart` (998 personas). Behaviour: `test/contracts/core_list_pool_behavioral_test.dart` (31 tests; 18 mutations, each reddening its named test). ON world: `test/plan_generator/core_list_pool_gate_test.dart`, hard zeros over the 998 personas, report `test/plan_generator/core_list_pool_report.md`. Known cost, accepted by D6 and a flip criterion: promoted bodyweight users get thin ON sessions (intermediate min 1 exercise/day vs 3 OFF; advanced mean 4.67 vs 8.56) until Batch C adds 84 core rows.

## Thin-day top-up (OI-401, live, kill-switch `disable_thin_day_topup`)

Plan `docs/plans/2026-10-24-thin-day-topup.md` (r3, two converged review rounds); diagnose `docs/diagnoses/2026-10-24-thin-day-topup-2d04d7.md`; founder decision 2026-10-23, option (b).

**Why.** The cascade drops a slot when no safe candidate exists (the safe-omission rule), and nothing refills the day. After the v14 injury tags an injured user could get one or two exercises, or none (see the diagnose for the before and after tables). A repeat phase also dropped now-contraindicated pins and refilled a variant only when it was EMPTY.

**Where.** `ExerciseSelector.topUpDays` runs on the finished `List<PopulatedDay>` at three exits: the end of `pickV4`'s cascade, the B1 `_pickCoreList` return, and the end of `buildPinnedDays`. `plan_generator.dart` is not edited (rule 14). The pure rules live in `thin_day_topup.dart` (`ThinDayTopUp.floor` 3, `neighbours`, `applies`, `anchors`); the orchestration stays in the selector because it needs the private `_selectCandidate` and `_buildExercise`.

**What.** Injured users only (`injuries.isEmpty` returns the same list instance). Per variant under the floor: for each of the day's own (muscle, pattern) anchors in slot-priority order, try the anchor's OWN pattern first (B was built with A's names hard-excluded, and a repeat phase drops pins without touching the slot), then its neighbouring patterns, closest first; one move per anchor per round, rounds until the floor or no progress; then `core` with no muscle anchor; then stop. Every candidate is a `queryV4` row with the cascade's own injury, capability, exclusion and experience filters, so the stage cannot hand an injured user a tagged move or one the equipment forbids. Phase 1 asks for `is_foundational` rows first, then relaxes; the `core` stage does so in EVERY phase (without it `queryV4`'s compound-first sort handed an advanced user Dragon Flag from phase 2, plan R13), and a `calisthenics_skill` or `olympic` row is never added at any stage. A `(pattern, muscle)` query that returns nothing is never repeated for that variant. There is ONE new `queryV4` call site (the exercise-seam allowlist moved 16 to 17).

**Avoid sets (soft, lower-cased).** A avoids the previous phase's picks, the plateau names and B's names (not for an alias day, not for `strength`). B avoids the same plus A's names after A's own top-up. Unlike the OFF cascade, which hard-EXCLUDES A's names from B, this is a re-order inside `_selectCandidate`, so a B emptied only by that exclusion can repeat A's moves instead of falling to a neighbour or core. With the curated-substitute preference on, the pool narrows to the curated subs first, so a repeat of a curated sub is possible. The L6 demoted names (phase 2+) are stronger than a soft avoid: they leave the candidate pool unless they are all that is left, because the cascade's L6 post-pass (`_applyHistoryAdjustments`) has already run and a soft avoid loses to the substitute narrowing (found by the full suite, `core_list_pool_behavioral_test.dart`; regression `thin_day_topup_behavioral_test.dart`, "demoted + the injury-substitute preference").

**Aliasing.** `alias = identical(input A, input B)`, computed before anything is rebuilt; an alias day is topped up once and B is that list, so `PeriodizationEngine` (which reads `exercisesB` on weeks 2 and 4) sees the same names. A pinned B that merely equals A in content is not an alias and is topped up on its own.

**Residual (OI-408).** A bodyweight beginner with shoulder + lower_back injuries on a 5- or 6-day upper-body day keeps `Plank, Dead Bug`: `VolumeFilter.targetCount('beginner', 5|6)` is 4, so the day is trimmed before the selector runs, and the founder's "then stop" ends the stages. Three ways to change it, none decided: anchors from the untrimmed split (needs a `plan_generator.dart` input, rule 14), a last stage "any safe move", or Batch C rows.

**Scorecard.** `CascadeTracer`, `QueryV4Mirror` and `generator_matrix.dart` mirror per-slot cascade attempts and never call the selector, and a top-up has no slot, so the scorecard cannot see this feature; the injury sweep and the behavioural file are the proof.

**B1 ON.** The top-up is path-independent and uses the OFF-path candidate rules, also when the core-list pool is ON. Whether a top-up under B1 should be core-list-only belongs to B1's flip review (`docs/ship_dark_pending_review.yaml`, `enable_core_list_pool`).

**Evidence.** `test/contracts/thin_day_topup_behavioral_test.dart` (real `generateV4` personas whose thin day is asserted first with the kill-switch set, plus direct `topUpDays` calls on a seeded library), `test/plan_engine_v4/thin_day_topup_test.dart` (pure rules), `thin_day_topup_flag_test.dart`, the five-block sweep `test/plan_generator/injury_floor_sweep_test.dart`, and the generator golden (2 keys moved).

## Session set budget (Batch B2, ship-dark `enable_session_set_budget`, DEFAULT OFF)

Plan `docs/plans/2026-10-22-session-set-budget.md` (r6). Founder decisions F1 (rule 14 waived for the `generateV4` wiring only), F2 (empty `session_duration_minutes` = 60), F3 (a focus group may reach 25 weekly sets), F4 (user-added exercises are never trimmed or counted; library repeat pins are budgeted), F5 (focus session cap 12).

**Why.** Off, nothing reads the user's minutes: `VolumeFilter.targetCount` fixes the exercise count, `PeriodizationEngine` forces a 4-set minimum and a phase multiplier. The in-tree OFF table (`session_set_budget_report.md`, last section; build_muscle full_gym, phase 1, week 1, median day with warm-up and cool-down) runs from 41 to 116 minutes and ignores the minutes the user gave: advanced 4-day 116.2, advanced 6-day 104.9, intermediate 4-day 93.3.

**Time model.** `exerciseSeconds = 1.20 x (overhead + sets x work + (sets - 1) x rest)`; archetypes H / M / I / B (work 23 / 35 / 47 / 40 s, overhead 120 / 90 / 45 / 30 s). Rest by day intensity: strength 150, hypertrophy 75, endurance 38. The day's budget is `(minutes - warmCoolMinutes(minutes)) x 60 - finisherSeconds`, with `warmCoolMinutes` = 6 to 14 minutes; the stored lead-in and cool-down items scale with the minutes (`warmCoolItemSeconds`: 60 s at 30, 180 s at 60, 300 s at 90).

**Bands and caps.** Per budget group (`BudgetMuscleGroups`, ten groups): a weekly (bottom, top) band and a session cap by goal and level (build_muscle intermediate 12 to 16, cap 8). Focus group: top 25, cap 12. A lighter (deload-archetype) phase pins every group's top to the band bottom. Max 5 sets per exercise. The level is the EFFECTIVE level (a beginner at phase 5 is budgeted as advanced).

**Allocator.** `SessionSetAllocator.allocate` runs in `generateV4` before `PeriodizationEngine.apply`, ahead of `SequencingEngine.sequence`, so its rank is the split's slot-priority order. Pass A admits by priority rank across the whole week (every day's lead lift first, with a reservation so one group cannot starve another day's lead lift); the empty-day guard puts a day's first exercise on when nothing else fits (`timeForcedFirst` when the time was already spent, `capForcedFirst` when a weekly room was gone: the gate requires 0 of the second); pass C raises groups to their bottom; pass D takes focus groups toward 25. Five reasons a group stays below its bottom: `not_trained_by_split`, `time_limited`, `co_group_limited`, `cap_limited`, and `copy_day_limited` (a copied B day that equals its A day is frozen). A day whose B list equals A's is allocated once; 6-day plans allocate A only. **Lead-lift policy:** the lead lift is protected from the week (the reservation) and from an empty day (the guard), NOT from the clock: a lead lift the time cannot afford reads `sets: 0` and is dropped (measured: 0 of 9,966 allocated days in the grid).

**Consumers.** Each takes the same `SessionBudgetContext` and builds its own `BudgetLedger` over it: `PeriodizationEngine.apply` (base sets = the allocation, week 2 +1 where the ledger allows, week 4 `max(1, floor(0.6 x own allocated))`, deload stash = the exercise's own allocation), `VolumeTitration.applyToWeeks` (band bottom as MEV, ledger as MRV; a zero delta is skipped), and `WarmupCooldownSelector.attach`, which reads the context for its minutes only. The coach's `SwapService.shortenDay` prices a day through `budgetedDaySeconds` when the flag is ON (OFF keeps the old sets x (60 + rest) sum).

**Not budgeted (Ruling 8).** A row is budgeted only if `SessionBudget.isBudgeted` says so: not custom, not timed / cardio / distance, and its name in `ctx.archetypeByName`. Others keep their sets and only spend time, at their own rest (rep-based customs at the day's rest). A cardio / distance / timed row whose `reps` names minutes works that long per set (`longEffortWorkSeconds`, capped at 7200 s); seconds, metres and rep prescriptions keep the table (B = 40 s a set).

**Display (Ruling 13).** `SessionBudget.estimateDaySecondsFromPlanDay` prices a stored plan day (id lookup, then an exact-name lookup that rejects alias matches; a corrupt number is clamped); `budgetedDayMinutes` / `budgetedDaySeconds` / `homeCardMinutes` (`session_estimate.dart`) are what Train (`WorkoutDayData.budgetMinutes`), Home and the coach read; a pricing failure reports `session_estimate_day_minutes` and returns null. OFF keeps `totalSets x 2.5`.

**What the ON gate measured (2026-10-25, 1,847 runs, `session_set_budget_report.md`).**
(a) Time: 3,965 of 33,204 plan days (12%) run longer than the user's minutes by some amount, median 0.70 minutes over, 911 over by more than a minute, worst 5.5. The gate's limit is minutes + 2: the model reserves `warmCoolMinutes` while the stored warm-up and cool-down items vary by day type (Ruling 3). Seven days exceed the limit, and all seven are the forced lead lift (below). Display equals the oracle to 1e-6 s on all 33,204 days.
(b) The one allowed overage is the forced lead lift: on a 30-minute 3-day home_dumbbells day, library timed / distance rows alone can spend the whole budget (Ruling 8), the guard still puts one budgeted exercise on, and the day runs up to 5.5 minutes over (`timeForcedFirst`: 14 days).
(c) Unused minutes: the median is 0.5 at 30 minutes, 3.3 at 60 and 27.2 at 90. The report does not attribute the 90-minute leftover to one constraint; the places it can come from are the fixed exercise count (`VolumeFilter.targetCount`), the 5-set exercise max, the session caps and the weekly tops (F3: leftover time stays unused).
(d) The founder case (intermediate build_muscle full_gym 6 days 90 minutes) trains Quads 8 weekly sets while Glutes sits at its top (`co_group_limited`).
(e) Floors by label (group-runs): `time_limited` 13,022, `cap_limited` 3,702, `co_group_limited` 3,538, `not_trained_by_split` 85.
(f) A repeat phase (`pinnedExercisesByDay`) takes the previous phase's exercise names, which came out of an allocation that dropped what did not fit the minutes then, and the allocator never adds exercises. A user who moves from 30 to 90 minutes between phases and repeats keeps the short list; a fresh pick would not (the repeat gate, `pro_phase_advance.dart`, tests adherence only).
All are flip-review questions, terminal in `docs/audit/session-set-budget.closure.yaml`.

**Evidence.** `session_set_allocator_behavioral_test.dart`, `session_set_budget_consumers_test.dart` (pinned OFF grids), `keep_all_slots_selection_test.dart`, `session_set_budget_wiring_test.dart`, `session_estimate_display_test.dart`, `test/plan_engine_v4/session_budget_test.dart`, `budget_muscle_groups_test.dart`, the ON-world gate `test/plan_generator/session_set_budget_gate_test.dart` (its oracle restates the constants, the archetype rule, the muscle mapper and the band tables; zeros for time, caps, tops, lighter phase, lost lead lifts, empty days and display; report `session_set_budget_report.md`), and the OFF identity `test/plan_generator/generator_golden_test.dart` (998 personas).

## Common pitfalls - full rows

_Moved verbatim from `lib/shared/repositories/plan_engine/CLAUDE.md` (original lines 324-332, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|
| Plan generator picks wrong-target exercise | Cascade attempt3 drops `target_focus` + `exercise_type`, keeping only `movement_pattern` — results in a push instead of a chest-specific push. Root causes: (a) exercise library pool too shallow for the slot's triple, or (b) for Phase 1 beginners, `suitable_for` too restrictive (needs "Beginner" + `is_foundational: true`). Fix: either expand library `suitable_for` on the missing exercise OR adjust `split_resolver.dart` slot ordering so beginners don't hit the shallow pool at P1/P2. Verify with `dart run test/plan_generator/sample_plans_report.dart` (target: 0 attempt3/universalPool/none). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Plan generator returns wrong number of exercises | `VolumeFilter` uses `slots.take(targetCount(experience, daysPerWeek))` — depends on `split_resolver` emitting enough P1-P5 slots in priority order. If a split returns fewer slots than the advanced target (10 for 3-day), users get truncated output silently. When adding/reordering a split, count slots and confirm it covers the advanced case. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Pike Push Up assigned to rear delt slot | TWO distinct causes: (a) a WRONG-PATTERN pool ENTRY — Pike Push Up (a vertical push) was mis-filed under `shoulder_isolation`, Dead Bug/Side Plank (core) under pull/hip — fixed by CORRECTING `universalPoolV4` itself (Batch 13-A `c3f9b2`, pinned by `universal_pool_mirror_test`, mirror lockstep with `cascade_tracer.dart`); (b) FREQUENCY of falling to attempt-5 — too many slots of one muscle/pattern/type vs pool depth — cap rear delt 3/week, lateral delt 3/week, front delt 1/week in `split_resolver.dart`, NOT the pool. Contradiction resolved: the pool is the right fix for a wrong PATTERN entry; split_resolver is the right fix for over-ALLOCATION frequency. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) + Batch 13-A c3f9b2 |
| **A bodyweight user is prescribed something needing equipment** | ⑦ **OI-89, 2026-08-28.** `equipment_tier` is a CURATION hint and was OVER-TAGGED — Chin Up sat in the bodyweight tier needing a pull-up bar. Never key a safety check on it. The check is `EquipmentCapability.canPerform(equipment_needed, effective)` where `effective = tierItems[tier] ∪ equipment_owned − equipment_exclusions` (`EquipmentVocab.effectiveItems`). `capability` is a **required, non-defaulted** parameter on `pickV4` / `_fillSlots` / `_cascadeFill` / `buildPinnedDays` / `_applyHistoryAdjustments` so the compiler enumerates every call site — do not give it a default. `null` means DO NOT ENFORCE — flag off, or Hive unreadable. It does NOT mean "an empty set", which would delete everything because `canPerform` fails CLOSED. ⚠ **Corrected 2026-08-28 (⑧ OI-144):** `null` used to ALSO mean "a tier above bodyweight", and that second meaning is gone. The floor applies at EVERY tier and capability **subsumes** queryV4's tier block (`exercise_repository.dart:334` — `else if`, never both, or the tier block stays binding and owning something can never widen the pool). Safe only because OI-89 flipped the tier invariant to EQUALITY, so `equipment_tier` carries no information `equipment_needed` lacks; if that is ever relaxed, revisit. An UNRECOGNISED tier resolves to `bodyweight` in both producers — `effectiveItems` fails OPEN there, a branch only reachable once the bodyweight gate was removed. | OI-89 + OI-144, diagnoses `f7b2c4` / `c9a7e2` / `b6f4d1` / `d3a8f5` |
| **A capability filter empties a slot instead of substituting** | Filtering shrinks pools, and a pool that empties falls to `universalPoolV4`, which picks by NAME and bypasses `queryV4` — so it must apply the capability drop ITSELF, exactly as it already does for exclusions. Its per-pattern **pure-bodyweight tails** are what guarantee a survivor; `equipment_exclusion_filter_behavioral_test` pins that invariant and reddened on `horizontal_pull`/`vertical_pull`/`elbow_flexion` the moment OI-89 retagged Pull Up / Chin Up / Inverted Row off the floor. | OI-89 |
| **A pattern satisfies the floor invariant and STILL leaves slots empty** | Measured, not hypothetical: taking six patterns to exactly **3** baseline rows passed the "≥3 baseline, ≥1 core" test and left **331 empty slots**. The invariant describes the LIBRARY; the empty slots are a property of the GENERATOR running over it — `pickedNames` dedups across a whole plan, so a 3-row pool is exhausted inside one week, and `suitableFor` narrows it further for advanced users. **6–7 per pattern is the working number**, calibrated on the two that already worked (`horizontal_push` 6 rows / zero missing, `hip_isolation` 5 / zero). Assert on the generator's OUTPUT, not on row counts. | OI-89, wave 2 (E274–E294) |
| **The scorecard is green in every world** | `test/plan_generator/` runs through `CascadeTracer` + `QueryV4Mirror`, which are MIRRORS. Before 2026-08-28 they did not model the capability flag, so the harness reported **byte-identical numbers with it ON and OFF**. `universal_pool_mirror_test` pins the pool DATA equal; nothing pins the mirrors' BEHAVIOUR. **When you add a filter to production, add it to both mirrors in the same commit**, and sanity-check by toggling the new input — if nothing moves, the harness cannot see it. | OI-89 |
