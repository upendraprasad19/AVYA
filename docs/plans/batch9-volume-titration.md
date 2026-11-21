# Batch 9 — Volume Titration (W2.7) — Focused Implementation Plan (HARDENED, post Round-1)

> Branch `workout-titration-9` (off main `0163f7f9`). Blast radius **platform**
> (`lib/shared/repositories/plan_engine/**`). Ship-dark §4.6. Item **W2.7**:
> *phase-boundary-only* per-muscle set adjustment reusing W2.3 readiness + W2.4
> e1RM tracker, applied ONLY at a genuine NEXT-phase advance (no mid-phase re-adjust).
>
> **Status: Round-1 ×2 context-blind review DONE (both `needs-changes`, converged
> on 1 P0 + 2 P1 + P2s). All folded in below (see §6). Round-2 pending on THIS
> hardened plan.**

## 0. What W2.7 is (LOCKED)

At a genuine phase **N→N+1 advance**, use phase-**N** evidence to nudge each
**major muscle group**'s weekly direct-set volume by **±1 set**, clamped to
[MEV=8, MRV=20] direct sets/group/week. Fires ONCE per advance (the existing
phase-boundary cadence), never mid-phase, never on a preview/regen. Ship-dark:
`enable_volume_titration` default OFF → **byte-identical** to today.

## 1. Ground truth (Round-1 ×2 VERIFIED — every claim correct)

Both context-blind reviewers verified G1–G9 against code; all correct.

| # | Fact | Evidence |
|---|---|---|
| G1 | `bodyFocus` +1-set: per exercise, if any `primaryMuscles` substring-matches a bodyFocus token → `sets+1` (`break`). | `periodization_engine.dart:100-109` |
| G2 | 7-B-1 deload stash (weekIdx 3): `_applyWave(...,2,...)` peak + bodyFocus +1 → `copyWith(workingSets, workingReps)`. | `periodization_engine.dart:126-147` |
| G3 | `var weekPlans = PeriodizationEngine.apply(...)` closes :218; `SequencingEngine.sequence` :221; `SupersetPairer.pair` :224. | `plan_generator.dart:207-224` |
| G4 | Phase-boundary flow `autoGenerateNextPhaseIfNeeded:443 → generateAndSchedule:97/483 → generate:120`. | `workout_schedule_read_service.dart` |
| G5 | e1RM scan: trailing-35-IST-day, MAX-Epley/session, top-2 distinct dates, compound-only, SAFE polarity (no evidence → keep). | `deload_e1rm_scan.dart:45-140` |
| G6 | **Soreness is a single GLOBAL daily axis** (0/1/2), NOT per-muscle. Full-lib sweep found NO per-muscle soreness anywhere. | `readiness.dart:16-77` (+ sweep) |
| G7 | MEV=8/MRV=20 exist as `_mev`/`_mrv`, but scorecard Volume is a SOFT score on a `default_sets` proxy — NOT the periodized per-week count, NOT a hard gate. | `plan_scorecard.dart:46-47,158-189` |
| G8 | `PlannedExercise` has `primaryMuscles`/`sets`/`workingSets` + `copyWith(sets:/workingSets:)` preserving all fields. | `models.dart:117-211` |
| G9 | Flag pattern: `configBox['enable_*'] == true`, catch → false (default OFF). | `plan_engine_flags.dart:178-203` |

**Two Round-1 vocabulary confirmations (fold into impl):**
- Muscle tokens: `resolveDeltas` reads library `primary_muscles` (`ExerciseRepository.getByExactName`);
  `applyToWeeks` matches `PlannedExercise.primaryMuscles`, which `exercise_selector._buildExercise`
  (~:1118-1141) populates DIRECTLY from `ex['primary_muscles']`, preserved via `copyWith`. **Same
  vocabulary** — no injury-style drift — BUT `PlannedExercise.primaryMuscles` keeps library CASE
  ("Chest"), so any match MUST lower-case the muscle side (P2 case fix).
- `workingSets` is written ONLY at `periodization_engine.dart:146` (weekIdx==3 && stashWorkingBase) —
  grep-confirmed no other writer in lib/. So `workingSets != null` is a correct proxy for
  "deload flag was ON at gen"; the 7-B-2 un-deload (`deload_evaluator.dart:249-259 _liftExercise`)
  reads serialized `working_sets`→sets, so titrating workingSets pre-serialization reaches an
  un-deloaded week 4 (F1 composition).

### Ground-truth CORRECTION (folded): soreness is global, not per-muscle (G6)

Per-muscle signal = **e1RM trend only** (per-exercise → per-major-group). Global
soreness = a **systemic damper**, not a per-muscle input.

## 2. Design (HARDENED — smallest correct; composes with deload + bodyFocus)

Three new pieces + one shared extraction + one flag + one shared muscle-group map.
**`PeriodizationEngine.apply()` signature is NOT changed** — titration is a
separate pure post-pass on the `weekPlans` `apply()` already returns (G3).

### 2a. Shared major-muscle-group map (fixes P1 fragmentation)

Extract the scorecard's `_muscleToGroup` (token→major group, e.g. `upper chest`→
`Chest`) to `lib/shared/repositories/plan_engine/muscle_groups.dart` as
`String? muscleGroupOf(String token)` that does **`.toLowerCase().trim()`** (matching
the scorecard's `_groupOf` at `plan_scorecard.dart:49` EXACTLY, so `_groupOf` becomes a
thin delegate — parity by construction, no baseline drift). The map CONTENT stays
byte-identical to today's `_muscleToGroup` — extending it would move the frozen Batch-0
D3 scorecard baseline (D4 gate), so it is NOT extended in this batch. `plan_scorecard.dart`
imports it (removes the duplicate; de-drift). Titration keys deltas AND clamps on
**major group**, so [8,20] (a per-group R5 landmark) is science-valid and "±1 per
muscle" means ±1 per major group, not per fragmented sub-token.

**Documented blind set (Round-2 R2-P2 — conservative, safe):** `muscleGroupOf` (exact-string
map) leaves ~49/258 library rows unmapped — ~24 correctly excluded (full-body cardio, vague
mobility), but ~17 clearly-assignable isolation lifts lost to a parenthesized qualifier
(`Triceps (Long Head)`, `Biceps (long head)`, `Calves (Gastrocnemius)`, `Lateral Delts`,
`Lower Abs`, `Obliques (lateral flexion)`, `Lats (Width)`, `Chest (inner)`, `Forearms
(extensors)`) + 8 empty-`primary_muscles` rows. These muscles are simply never titrated — a
CONSERVATIVE miss (they're small groups sitting below MEV=8 in real plans, so −1 never fired
for them anyway, and the undercount can't push +1 past MRV=20). Acceptable for a ship-dark
first cut; NOT worth destabilizing the frozen baseline. The behavioral test therefore seeds a
BARE-token lift (primary `Chest`) for its +1/−1 cases, never a qualifier-tagged/empty-primary one.

### 2b. Shared Epley extraction (fixes P2; de-drifts a duplicate loop)

Co-extract `_sessionMaxE1rm` + its private `_toDouble` + `_toInt` from
`deload_e1rm_scan.dart` → `lib/core/utils/e1rm.dart` (`double? sessionMaxE1rm(Map log)`
+ the two coercers, or keep them private helpers in that file). `DeloadE1rmScan`
calls it → **byte-identical** (pinned by `deload_eval_behavioral_test` + new
`e1rm_test.dart`). NOTE: a THIRD Epley at `progression_resolver.dart:139` takes a
`_TopSet` record (not a `Map log`) — different signature, **left as-is** (not
unified; acknowledged, not implied).

### 2c. `VolumeTitration` (new `lib/shared/repositories/plan_engine/volume_titration.dart`)

**`resolveDeltas({required int phase}) → Map<String,int>`** (group→±1), Hive read, crash-safe:
- Gate: `!PlanEngineFlags.volumeTitrationEnabled || phase < 2` → `const {}`.
- Per-EXERCISE e1RM trend (reuse `sessionMaxE1rm`): trailing-35-IST-day `exlog_*`,
  top-2 distinct dated sessions → `dropped` (latest<prior) vs `held/gained` (latest≥prior);
  only exercises with ≥2 dated sessions are evaluable. Map exercise → **major group**
  via `muscleGroupOf(getByExactName(name)['primary_muscles'])` (each primary token;
  an exercise can contribute to multiple groups). A group is `dropped` if ≥1 of its
  evaluable exercises dropped; `heldOrGained` if it has ≥1 evaluable exercise and none dropped.
- Readiness recovery evidence (POSITIVE-evidence polarity): read `readiness_<date>`
  rows in the window. `n = count`, `beatUp = count(soreness>=2)`. `sufficient = n >= 3`.
  `systemicFatigue = sufficient && beatUp >= max(2, (0.4*n).ceil())`.
  `recovered = sufficient && !systemicFatigue`.
- **Decision per group** (SAFE polarity — −1 is the safe direction, +1 the risky one):
  - `dropped` → **−1** (pull volume back — fires on e1RM alone, no readiness needed).
  - `heldOrGained && recovered` → **+1** (add volume ONLY with positive recovery evidence).
  - else (heldOrGained but not recovered / insufficient readiness / systemicFatigue /
    no evaluable exercise) → **omit** (hold). ⚠ **CORRECTED 2026-09-01 — readiness is LIVE; the parenthetical below describes the pre-flip world only.** ⟹ with readiness ship-dark (0 rows),
    titration ONLY ever trims on demonstrated decline; +1 unlocks once readiness has
    adoption. Honest, safe, incremental.
- Deterministic: build the map, then return entries **sorted by group key** (so
  downstream processing order is stable across Hive `box.keys` insertion-order variance).

**`applyToWeeks(List<WeekPlan> weeks, Map<String,int> deltas) → List<WeekPlan>`** — pure:
- **`if (deltas.isEmpty) return weeks;` as the LITERAL first statement** → `identical(weeks, applyToWeeks(weeks,{}))` (byte-identical inertness; no per-week rebuild).
- Iterate `deltas` entries in sorted-group order. For weeks 0/1/2 (NOT deload week 3):
  compute the group's **weekly base sets** = Σ `sets` over that week's exercises whose
  ANY `primaryMuscles` token maps (lower-cased, via `muscleGroupOf`) to the group.
  Track a per-week `bumpedExerciseIds` set so a single exercise is adjusted **at most
  once per week** (fixes multi-group double-bump).
  - `+1` AND `weeklyBase < MRV(20)` → `sets+1` on the FIRST not-yet-bumped matching exercise.
  - `−1` AND `weeklyBase > MEV(8)` → `sets-1` on the FIRST not-yet-bumped matching
    exercise with `sets>1` (floor 1).
- **Deload-week (idx 3) `workingSets` symmetry**: for a week-3 exercise with
  `workingSets != null` (stash present), apply the SAME group ±1 to `workingSets` **using
  the SAME clamp decision computed from the PEAK week (idx 2)** — i.e. only bump
  workingSets if the peak-week weeklyBase was under MRV (mirrors the visible bump so an
  un-deloaded wk4 == titrated peak, no boundary asymmetry). Floor 1. Visible deload `sets`
  untouched (recovery). `workingSets == null` (deload flag OFF at gen) → nothing to do.

`_mevPerWeek=8`/`_mrvPerWeek=20`: local consts citing R5 + `plan_scorecard.dart:46-47`
(same source-of-numbers, distinct measurement context — deliberately not one symbol).

### 2d. Orchestrator wiring (opt-in — fixes the P0 seam-reach breach)

Thread `bool applyVolumeTitration = false` through `generate`→`generateV4` AND
`generateAndSchedule` (mirror `stashWorkingBase`/`pinnedExercisesByDay`). In `generateV4`,
right after `apply` (:218):
```dart
var weekPlans = PeriodizationEngine.apply( ... );          // unchanged
if (applyVolumeTitration) {                                  // opt-in intent, default false
  final deltas = VolumeTitration.resolveDeltas(phase: phase); // {} unless flag ON && phase>=2
  weekPlans = VolumeTitration.applyToWeeks(weekPlans, deltas);
}
// Stage 3 Sequencing (:221, unchanged) ...
```
**`applyVolumeTitration` is passed as `pins == null` at EXACTLY the two `generateAndSchedule`
call sites, and defaults `false` everywhere else** (Round-2 R2-P1 correction — the two flip
sites ALSO serve repeat advances, so hardcoding `true` would let a low-adherence repeat gain
volume; the `pins == null` seam distinguishes a FRESH advance (titrate) from a repeat-content
advance (no titration — a low-adherence repeat must NOT gain volume)):
- `workout_schedule_read_service.dart:483` (`autoGenerateNextPhaseIfNeeded`'s `generateAndSchedule`
  call) → `applyVolumeTitration: pins == null`. ⚠ autoGenerate is NOT unconditionally "fresh":
  `pro_phase_advance.dart:86-100` (splash/card auto-advance) feeds it `repeatContent = adherenceGate
  && completionRate<threshold`, so it builds `pins` for a LOW-adherence repeat — `pins==null`
  correctly suppresses titration on that live sub-path.
- `graduation_screen.dart:644` (the single `_onPro` `generateAndSchedule` call) →
  `applyVolumeTitration: pins == null`. Fresh-vs-repeat is `pins = choice==AdvanceChoice.repeat ?
  … : null` at `:634` — so `pins==null` == the fresh choice.
- Everything else keeps the `false` default → inert regardless of the flag: coach-regen
  (`regenerate_plan_planner.dart:189`), edit-profile (`generateAndScheduleFromDate:257`), both
  previews (`preview_plan_provider` / graduation preview — call `generateV4` directly, never
  `generateAndSchedule`), hotel (`:116` phase=1, doubly inert), onboarding first-plan (`:453` phase=1),
  login-restore/rebuild paths.

So titration fires **iff** `enable_volume_titration` ON **AND** `pins == null` (a FRESH advance)
**AND** `phase>=2`. Gating on the flag alone was the P0; the `pins == null` intent is the fix.

### 2e. Flag

```dart
/// W2.7 (Batch 9): phase-boundary per-major-group ±1 weekly-set titration from
/// phase-N e1RM trend (+ readiness recovery evidence for the +1 direction),
/// clamped [MEV,MRV]. Ship-dark DEFAULT OFF. Applied ONLY when the caller passes
/// applyVolumeTitration:true (genuine fresh advance) — flag OFF OR intent false OR
/// phase<2 → resolveDeltas {} → applyToWeeks identity → byte-identical.
static bool get volumeTitrationEnabled { try { return HiveService.instance.configBox.get('enable_volume_titration') == true; } catch (_) { return false; } }
```

## 3. Inertness proof (Round-1 PROVEN; encode the caveat)

- Flag OFF → `resolveDeltas` returns `{}` before any Hive/exlog read → `applyToWeeks`
  early-returns the SAME reference → byte-identical (Phase.toMap double-serializes days —
  identity satisfies both).
- Intent `false` (all non-advance callers) → the post-pass is not even entered → identical.
- No downstream stage reads `sets`: SequencingEngine sorts by CNS/name/type; SupersetPairer
  pairs by `primaryMuscles` — both preserve titrated `sets` via `copyWith` (so the
  pre-sequencing insertion point is safe).
- **Test caveat (Round-1)**: assert `identical(before, applyToWeeks(before, {}))`, not just
  deep-equality — the empty-early-return must be the literal first statement.

**4 titration×deload quadrants** (all sane; `workingSets != null` self-gates the deload branch):
OFF/OFF byte-identical · OFF/ON = Batch-7 unchanged · ON/OFF adjusts wks 0-2 only
(workingSets null) · ON/ON adjusts wks 0-2 + wk-3 workingSets symmetrically → un-deload
restores titrated peak.

## 4. SoT + tests + docs

- **SoT** `docs/sot_registry.yaml`: `volume_titration` — writer `volume_titration.dart`
  (`resolveDeltas`/`applyToWeeks`), reader = generated `week_plans` set counts; `behavioral_test_path`.
- **Naming glossary** `docs/naming_conventions.md`: add `volume_titration` + `enable_volume_titration` (§4.7).
- **Behavioral test** `test/contracts/volume_titration_behavioral_test.dart`:
  (a) OFF → `identical` inertness; intent-false callers identical flag-ON vs OFF;
  (b) `+1` group delta bumps exactly one matching exercise's weekly sets, clamped at MRV,
  and only ONE bump when the group's exercise also matches another group (dedup);
  (c) `−1` trims, floored at MEV/1; (d) deload-week visible sets untouched, `workingSets`
  adjusted symmetrically when present; (e) `resolveDeltas`: dropped-e1RM group → −1;
  held+recovered (seed ≥3 readiness rows, low soreness) → +1; held + 0 readiness rows →
  HOLD (no +1); phase<2 / flag-OFF → `{}`; deterministic across `box.keys` order.
- **Shared** `test/contracts/e1rm_test.dart`: `sessionMaxE1rm` MAX-Epley (high-rep out-e1RMs
  heaviest); DeloadE1rmScan byte-identical (existing test).
- **Scorecard**: point `plan_scorecard.dart` at the shared `muscleGroupOf`; add a
  titration-ON persona family to `generator_matrix.dart` (A/B: flag OFF vs ON; target
  still 0 attempt3/universalPool/none, group volume non-regressed).
- **Nested CLAUDE.md** `plan_engine/CLAUDE.md`: "Volume titration (W2.7)" note.
- No diagnose-doc (`feat:`, not `fix:`). No migration / no restore entry (Hive-read-only;
  exlog + readiness already sync+restore).

## 5. Composition summary
- **bodyFocus**: titration operates on already-bodyFocus-adjusted `sets` (post-apply). Independent.
- **deload (F1)**: titration bumps base + wk-3 `workingSets` symmetrically → deload cut / un-deload
  act on the titrated base. Self-gated by `workingSets != null`.
- **plateau (W3.5, Batch 12, future)**: its "+sets" rung must check titration didn't already bump
  the group this phase (Round-2 #11 of the overhaul plan) — a Batch-12 concern, noted forward.

## 6. REVIEW ROUND 1 (×2 context-blind) — findings + resolutions

Both reviewers `needs-changes`, convergent. Ground truth G1–G9 all verified correct.

| # | Sev | Finding | Resolution (this hardened plan) |
|---|---|---|---|
| R1-1 | P0 | Titration wired in the SHARED `generateV4` seam → fires on coach-regen / edit-profile / previews (all pass phase≥2), not just the phase boundary. §2c "coach-regen hardcodes phase" REFUTED (`regenerate_plan_planner.dart:189`). Violates LOCKED phase-boundary-only. | §2d **opt-in `applyVolumeTitration` bool**, true only at fresh-advance sites; all else inert. |
| R1-2 | P1 | [8,20] clamp on RAW library sub-tokens (chest→4 tokens) → +1 fires per sub-token unconditionally (group gains +K); −1 never fires; group can exceed MRV while every sub-token reads in-band. | §2a **aggregate to major group** via shared `muscleGroupOf` (reuse scorecard `_muscleToGroup`). |
| R1-3 | P1 | Damper dead + unsafe polarity: readiness ship-dark (0 rows) → `systemicFatigue=false` always → +1 rides e1RM alone; "no data"=="recovered" inverts the house positive-evidence convention. | §2c **+1 requires positive recovery evidence** (`recovered`); −1 on e1RM-drop alone. 0 readiness → hold. |
| R1-4 | P2 | Compound matching several delta'd tokens bumped once per token (+2/+3). | §2b group-agg + per-week `bumpedExerciseIds` dedup. |
| R1-5 | P2 | Epley extraction under-specs deps (`_toDouble`/`_toInt`); a 3rd Epley at `progression_resolver.dart:139` (diff signature). | §2b **co-extract all three**; progression_resolver Epley left as-is (acknowledged). |
| R1-6 | P2 | Wk-3 `workingSets` bump not re-clamped vs peak MRV → boundary asymmetry (un-deloaded wk4 = peak+1 while wk2 = peak). | §2c **same clamp decision on workingSets** (from peak-week weeklyBase). |
| R1-7 | P2 | Non-deterministic bump target (Hive `box.keys` order + multi-muscle exercises). | §2c/§2d **sorted-group iteration** + stable day/exercise order. |
| R1-8 | P2 | Case mismatch: `PlannedExercise.primaryMuscles` keeps library case ("Chest") vs lower-cased tokens. | §2a `muscleGroupOf` lower-cases input; match lower-cases the muscle side. |
| R1-9 | P2 | Missing naming-glossary entry (§4.7). | §4 add `volume_titration`/`enable_volume_titration`. |

**Inertness: PROVEN. Deload composition: SOUND** (modulo R1-6, now fixed). No ground-truth
defect. The unit stays ONE coherent W2.7 slice (the fixes are refinements, not a split signal).

## 7. Open questions for the Round-2 reviewer (verify the hardening against code)
1. Is the opt-in `applyVolumeTitration` threaded correctly, and are the ONLY `true` sites the
   genuine fresh advances (splash auto-advance + graduation fresh-branch, repeat-branch false)?
   Confirm coach-regen / edit-profile / both previews / hotel / onboarding pass false.
2. Does `muscleGroupOf` (extracted `_muscleToGroup`) cover the real `primary_muscles` tokens in
   `exercise_library.json`? Any high-frequency token that maps to null (→ silently untitrated)?
3. Is the group `weeklyBase` (Σ periodized `sets` across a week for a group) actually in a
   range where [8,20] binds meaningfully (not always no-op, not always clamping)?
4. Does the `bumpedExerciseIds` dedup + sorted-group order fully restore determinism?
5. Any NEW defect introduced by the hardening (the corrections themselves — §4.12)?

## 8. REVIEW ROUND 2 (context-blind, on the HARDENED plan) — CONVERGED

Round-2 verified the hardening against code. Confirmed correct: opt-in default-false
neutralizes every non-advance caller; positive-evidence polarity fix; determinism;
deload-workingSets symmetry (peak-week weeklyBase IS computable in the post-pass);
byte-identical inertness (early-return before any map touch). Findings + resolutions:

| # | Sev | Finding | Resolution |
|---|---|---|---|
| R2-1 | P1 | Both `generateAndSchedule` flip-sites ALSO serve repeat advances; `autoGenerateNextPhaseIfNeeded` is NOT unconditionally fresh (`pro_phase_advance.dart:86` feeds `repeatContent`). Hardcoding `true` → a low-adherence repeat gains volume. | §2d **`applyVolumeTitration: pins == null`** at both call sites (`:483` + `:644`). |
| R2-2 | P2 | `muscleGroupOf` leaves ~49/258 rows unmapped (~17 qualifier-tagged isolation lifts + 8 empty-primary) → those muscles never titrated. | §2a **documented blind set** (conservative/safe — small groups below MEV); map kept identical to preserve the frozen D3 baseline; behavioral test seeds bare-token lifts. |
| R2-3 | P2 | `muscleGroupOf` must `.toLowerCase().trim()` (not just lower-case) so `_groupOf` delegates without baseline drift. | §2a **trim added**; `_groupOf` → thin delegate. |

**VERDICT: CONVERGED** (review_rounds=2, ground_truth_verified=true). The 3 fixes are
surgical (one seam correction + two doc/parity notes) — the reviewer confirmed "converges
without a third full round," so no forbidden 5th-review. Proceed to implement, then the
self-initiated ≥platform B-pass on the actual diff BEFORE the `--no-ff` merge (§4.3).
