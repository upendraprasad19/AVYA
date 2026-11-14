# Focused plan — ⑦(b) session-time detraining resume banner (Batch 3 remaining half)

Branch `workout-resume-banner` off `266fa884` (Batch 3b-ii landed, CI-green). Precedes code per
§4.12 (this plan → ×2 context-blind review → `docs/plan-reviews/workout-resume-banner.md` converged
→ implement → B-pass → land). Item ⑦(b) — the second half of item ⑦ (⑦(a) phase-gen decay shipped
`cb1ec3c6`).

## Scope (single item ⑦(b))
When a user STARTS a workout after a training gap, show a non-shaming banner and apply a single
blanket day-level % cut to THAT session's suggested loads — no plan regeneration, session-only,
not persisted. Distinct from ⑦(a) (phase-gen decay, already shipped inside ProgressionResolver).

**Tier: PLATFORM (locked, round-1 P2).** `lib/features/train/**` is *feature* tier
(`blast_radius.yaml:89`) — NOT account. The D2 extraction edits `progression_resolver.dart` AND the
D5 kill-switch getter lands in `plan_engine_flags.dart` — both under
`lib/shared/repositories/plan_engine/**` = **platform** (`:67`, max-tier wins). Platform `requires:`
kill-switch + behavioral test + B-pass (all planned). Hermes NOT required (catastrophic-only). The
plan-review record + CI keystone gate key on branch `workout-resume-banner`.

## Round-1 review — folded (verdict: harden; architecture sound, no split)
Context-blind round-1 verified every ground-truth cite against code and confirmed D1 (double-count
avoided, not illusory), D2 (extraction byte-identical, decay test guards it), the provider-leak
avoidance, and the banner slot. Folded before this round-2: **P1** — a SECOND `lastPerformanceProvider`
reader I missed, the "TRY: {lastWeight+2.5}" hint line, fires under the cut's exact condition and would
contradict it → now in D3-ii + the reader contract (suppress TRY, keep LAST). **P2** — tier is
**platform** (plan_engine), not account. **P2** — D5 flag polarity was self-contradictory → locked
ship-dark `enable_…==true`. **P3** — D7 idempotency reframed (no run-once guard; would break swaps).
**P3** — IST/local band-boundary note (D4). **P3** — mis-fire test guards (-1/0 gap) added.

## Round-2 review — folded (verdict: harden → CONVERGED after fold; do not split)
Round-2 (context-blind, on the hardened plan) verified all 7 round-1 fixes SOUND against code:
TRY-suppression + overload compare-vs-target are wireable via the card's `ref` (no refactor); D1
disjoint holds — `lastWeight` = logged `sets.first['weight_kg']` (`train_provider.dart:81`), which ⑦a
NEVER mutates (⑦a decays only the plan-gen prescription); ship-dark flag pattern exact
(`plan_engine_flags.dart:47-54`); extraction byte-identical, `progression_resolver_decay_test:102-115`
pre-pins the bands (§4.11); swap re-inits WITH the cut (`swapExercise` wipes `setInputValues`
`:999-1010`, so fresh `lastWeight×factor` isn't clobbered). ONE MEDIUM folded — **F1: thread
`sessionDetrainingFactor` through `copyWith` + a REACTIVE test** (writer + test bullets above). Impl
notes folded: **F2** — compute the overload target the SAME way as the prefill (`lastWeight×factor`,
keep the `toString`/`toInt` display path `exercise_card.dart:85-86`) so an unedited set reads `==`→ (no
red↓); optional epsilon. **F3** — `_metaText` (`.../active_workout/exercise_card.dart:296-311`) prints
the ⑦a-decayed PRESCRIPTION `exercise.weight`, can exceed the cut prefill, but it's a static
prescription (pre-existing prefill-vs-prescription split), NOT a shame directive → note in the SoT entry.
**Paths:** bare filenames resolve to `lib/features/train/screens/active_workout/` (an unrelated
`widgets/exercise_card.dart` exists) — use full paths in code + SoT. **F4 (scope):** ⑦b keys off the
GLOBAL gap by design; the per-exercise-gap case stays uncovered — intended, not a defect.

## Ground-truth (self-verified against files at 266fa884)
- **Trigger:** `WorkoutRepository.getDaysSinceLastWorkout()` — `workout_repository.dart:1173-1193`.
  Global days since the most-recent `type=='workout_log'` row in `workoutBox`; `-1` if none.
  ⚠ Uses `DateTime.now()` (local, :1174), not IST. Sole caller today: `pattern_detector.dart:335`
  (missed-workout nudge, `daysSince < 4`). No active-workout caller.
- **Prefill (reader / apply-site):** `exercise_card.dart::_initControllers` `:66-90`. Two DISJOINT
  weight branches: (1) `:81-86` last-logged `lastPerf.lastWeight` (weight_reps/weighted_bodyweight
  & >0); (2) `:88-89` prescribed `exercise.weight` string — **already carries ⑦(a) decay** (baked at
  gen time). `lastPerformanceProvider` (`train_provider.dart:107`) is SHARED with the Train-screen
  preview card (`expandable_day_card.dart:217`) → NOT a safe apply-site (would leak the cut).
- **Session state (writer):** `ActiveWorkoutNotifier.startWorkout` `train_provider.dart:896` loads
  `ActiveWorkoutData`; session-only override fields already precedent there (~:763). One entry point.
- **Overload indicator:** `overload_indicator.dart:6-44` — compares entered `currentWeight` vs raw
  `lastPerf.lastWeight`: `>` green↑ / `==` warn→ / `<` red↓ (`:28-37`). Hides when lastWeight≤0 or
  currentWeight≤0 (`:21-23`).
- **No SoT concept** for active-workout suggested weight → ⑦(b) introduces a NEW writer/reader
  contract (SoT + `test/contracts/` behavioral test). Confirmed: sot_registry only has
  `detraining_decay` + `graded_progression` (both plan-gen, ProgressionResolver).

## Design decisions (proposed — pressure-test in ×2 review)
- **D1 — apply-site avoids the ⑦(a) double-count:** compute ONE session factor in `startWorkout`
  from `getDaysSinceLastWorkout()`, store on `ActiveWorkoutData` (session-only). Apply it in
  `exercise_card._initControllers` **ONLY to the `lastWeight` branch (:81-86)** — NEVER the prescribed
  `exercise.weight` branch (:88-89), which already has ⑦(a) baked in. The two branches are mutually
  exclusive, so ⑦(a) and ⑦(b) apply to disjoint inputs → no double-count by construction.
- **D2 — band factor SHARED with ⑦(a) (no 2nd copy of the constants — #1 bug class):** reuse ⑦(a)'s
  band→factor math. ⚠ VERIFY the raw constants in `progression_resolver.dart::_detrainingFactor`
  (do NOT trust CLAUDE.md prose: it says ≤7d none / 8-21d −7.5% / 22-35d −17.5% / >35d −50% — read
  the code). ⑦(a)'s `_detrainingFactor` is private + keyed on an exlog IST date-STRING; ⑦(b) needs a
  factor from an INT day-gap. Extract the band→factor as a shared pure `detrainingFactorForGap(int
  days)` in a neutral util; ⑦(a) keeps its string→gap conversion then calls the shared fn. §4.11
  gates-before-refactor: `progression_resolver_decay_test` pins ⑦(a)'s bands — extend it to the
  extracted fn so ⑦(a) is provably unchanged BEFORE the extraction commit.
- **D3 — the two "shame surfaces" honor "never shame" (round-1 P1+the indicator):** BOTH readers that
  compare against raw `lastWeight` must respect the cut:
  (i) **`_OverloadIndicator`** (`overload_indicator.dart:28-37`) — when a cut is active, compare
      `currentWeight` against the CUT TARGET, not raw lastWeight (hitting the reduced prefill reads
      neutral →, exceeding reads green↑). Thread the session factor into it.
  (ii) **The "TRY:" hint line** (`exercise_card.dart:559-578`, `suggestedWeight = lastWeight+2.5`) —
      VERIFIED: fires under the SAME `lastWeight>0` condition as the cut, so a cut prefill of 42.5 would
      show "TRY: 52.5KG ↑" (accent, arrow_up) right below = directly tells a returning user to ADD
      weight. **SUPPRESS the "TRY:" line when a cut is active** (the banner explains the lighter load).
      **KEEP the "LAST:" line** (`:538-556`) — honest factual history ("LAST: 50KG × 8"), not a directive.
- **D4 — trigger zone:** reuse `getDaysSinceLastWorkout()` as-is (local-now). Day-granularity bands
  tolerate a few hours' skew; not worth a new IST primitive. Boundary case (round-1 P3): ⑦a's IST gap
  vs ⑦b's local-now gap can straddle a band edge (7↔8 / 21↔22 / 35↔36) on non-IST-zone devices —
  harmless (disjoint inputs per D1, never both scale one number), negligible for the IST target user;
  note in the SoT entry.
- **D5 — kill-switch: LOCKED ship-dark default-OFF (round-1 P2).** Flag `enable_session_detraining_cut`,
  mirroring the GRADED pattern (`plan_engine_flags.dart:47-53`): `configBox.get('enable_session_detraining_cut')
  == true`, own try/catch → `false`. Default-OFF because ⑦(b) touches the interactive logging UI +
  overload indicator + hint lines (more visible than ⑦a's gen-time number) — ship dark, verify on the
  test account, flip after (§4.6). NOT `disable_…/!= true` (that polarity is default-ON — the round-1
  self-contradiction).
- **D6 — banner:** slot at `screen.dart:~196` (after progress bar, above exercise list). Copy the
  superset-chip template (`screen.dart:198-229`) — full-width `accentSoft`, non-shaming copy.
  Wardroom palette + DM Sans (load the brand soul for the copy).

## Writer/reader contract (new SoT concept `session_detraining_cut`)
- Writer: `startWorkout` (`train_provider.dart:896`) — computes ONE session factor from
  `getDaysSinceLastWorkout()` × `detrainingFactorForGap`, stores it on `ActiveWorkoutData`
  (session-only, alongside the superset-mode precedent ~`:763`; NOT persisted). **⚠ round-2 F1
  (MEDIUM): the new `sessionDetrainingFactor` field MUST be threaded through `copyWith`
  (`train_provider.dart:781-809`) as `sessionDetrainingFactor ?? this.sessionDetrainingFactor`
  (exactly like the superset fields `:804-807`) — else the 1×/sec timer `copyWith(elapsedSeconds:)`
  (`:914`) + the post-frame `copyWith(setInputValues:)` (`:950`) revert it to the ctor default (1.0)
  within one frame → banner vanishes, red↓ + TRY return. Field default = 1.0.**
- Readers — ALL `lastPerformanceProvider`/lastWeight consumers inside the active card must honor it
  (round-1 P1 — enumerate all four, not just prefill):
  1. `exercise_card._initControllers` prefill — **lastWeight branch only** (`:81-86`); prescribed
     branch (`:88-89`) UNTOUCHED (already ⑦a-decayed → D1 disjointness).
  2. `_OverloadIndicator` (`overload_indicator.dart:28-37`) — compare-vs-cut-target (D3-i).
  3. The "TRY:" hint line (`exercise_card.dart:559-578`) — SUPPRESS when cut active (D3-ii);
     "LAST:" line (`:538-556`) KEPT.
  4. The banner widget — visibility predicate `sessionFactor < 1.0`.
- Behavioral test (`test/contracts/session_detraining_cut_*`):
  - `workout_log` 25d back + logged exlog weight 50 → prefill lastWeight branch = 50 × 0.825 = 41.3;
    a no-history exercise's prescribed branch stays UNcut (locks D1).
  - Mis-fire guards (round-1 P3): `getDaysSinceLastWorkout()==-1` (first-ever) AND `==0` (only log
    today) → factor 1.0, NO cut, NO banner.
  - Banner visibility = `sessionFactor < 1.0` only (gap∈[-1,7] → 1.0 → hidden).
  - "TRY:" suppressed when cut active; "LAST:" retained.
  - Kill-switch OFF (default) → verbatim (no cut, no banner, byte-identical).
  - `detrainingFactorForGap` band table pinned (−1/0/7→1.0 · 8→0.925 · 22→0.825 · 36→0.5); ⑦a's
    `progression_resolver_decay_test` stays green post-extraction (§4.11).
  - **⚠ round-2 F1 — REACTIVE survival (not just the one-time prefill):** after `startWorkout` sets
    factor<1.0, fire `copyWith(elapsedSeconds:)` / `recordSetValues(...)` (or pump past the post-frame
    callback) and assert `state.sessionDetrainingFactor` is STILL <1.0. A prefill-only assertion passes
    even when `copyWith` drops the field — the [[feedback_source_grep_false_confidence]] class.

## Review focus areas (for the ×2 context-blind reviewers)
1. D1 disjoint-branch claim — ANY path where a prescribed-weight prefill also gets the ⑦(b) cut
   (double-count)? Re-verify the two branches are truly mutually exclusive at every call.
2. D2 extraction — does pulling `_detrainingFactor`'s band math to a shared fn regress ⑦(a)? (decay
   test must stay green; verify the string→gap path is preserved). Confirm the resulting blast tier.
3. Provider-leak — confirm the cut is NOT applied via `lastPerformanceProvider` (shared with Train
   preview). Session factor must live on `ActiveWorkoutData`, read only inside active-workout widgets.
4. D3 — does compare-vs-target fully remove the red↓, and does a genuine ↑ (user overrides upward)
   still read green? Edge: user manually edits weight back up.
5. Restore/reinstall — session-only state, nothing persisted → no restore entry needed (confirm).
6. Kill-switch quadrants — ⑦a-on/⑦b-on etc. behave sanely (D1 makes them independent).
7. Idempotency (round-1 P3 — CORRECTED mental model): `_initControllers` runs in `initState` (`:63`)
   AND `didUpdateWidget`-on-SWAP (`:149-151`), NOT on the ~1×/sec timer rebuild (that calls `build()`).
   The cut = `lastPerf.lastWeight` (immutable logged read) × session-constant factor → IDEMPOTENT on
   every invocation; it CANNOT compound. **NO run-once `_cutApplied` guard** — a guard would skip the
   cut on a legitimate swap (swapped-in exercise uncut). The `savedValues` restore (`:99-117`) overrides
   with captured values on re-init (also idempotent).
