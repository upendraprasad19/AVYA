---
branch: workout-adherence-8a2int
scope: ⑧ Batch 8 UNIT 2-int (W2.5 repeat-content) — generateAndSchedule repeatContent + G5 gate + last_phase_profile + facade thread (ship-dark)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-8a2int-bpass.md
---

# Plan-review record — ⑧ UNIT 2-int (repeat-content scheduling)

Plan: `scratchpad/batch8_unit2int_repeatcontent_plan.md` (full ×2 detail). §4.12 ×2 context-blind
review. **Converged — implemented.** PLATFORM tier (the kill-switch lives in `plan_engine/**`). NOT a
`fix:` (a NEW capability) → no diagnose-doc. No migration (config-only). Consumes the shipped 2-cap
`buildPinnedDays` (branch merged `4e52d24e`, CI-green).

## Ground-truth verified (against code, file:line — reviewers rated 100% accurate)
- `generateAndSchedule` (`workout_schedule_read_service.dart:97-`): calls `generate()` (now
  pin-capable), 4-week row-writer stamps `phase`/`week`/`exercises`/`workout_day_index`; overwrites
  `plan_start_date`. `autoGenerateNextPhaseIfNeeded` (`:433`) is the advance; the REAL production
  caller is the FACADE `workout_schedule_service.dart:132` (`splash_screen.dart:262`). `getWeek(w)`
  (`:517`) walks by DATE (ignores the row `week` field). `PlannedExercise.toMap` name key =
  `exercise_name` (`models.dart:215`). Profile fields: `primary_goal`/`equipment_access`/`days_per_week`
  (`splash_screen.dart:248-250`) — the `equipment` arg IS `equipment_access`.

## ×2 review (context-blind) — 3 P1s (R1) + 1 P1 (R2), all folded → converged
**Round 1 (needs-changes):** P1a `aByIdx.keys.max` crashes on empty map → guard + union keys; P1b the
FACADE isn't threaded (real caller path) → forward `repeatContent`; P1c the whole-phase MF-1 fallback
is a proven NO-OP (generator deterministic — grep Random/shuffle=0; buildPinnedDays per-variant
fresh-fills) → DROPPED. + P2s: 6-day `getWeek(2)` comment, `equipment_tier`→store PARAMS (no such
profile field; it's `equipment_access`), stale-baseline (mid-phase regen → safe over-conservative
fresh), coach-regen row-shape extraction-safe.
**Round 2 (needs-changes → converge-after-fold):** all 5 R1 fixes re-verified SOUND against code.
**NEW-1 (P1, the core catch both R1 + I missed):** G5 must ALSO gate on `effectiveExp` —
`effectiveLevel(exp,phase)` WIDENS with phase (beginner→intermediate@3), changing the split TEMPLATE +
slot COUNT with zero user edit; without it a beginner 2→3 pins full-body names into Push/Pull/Legs
frames. Folded: store/compare the COMPUTED `effective_exp`. NEW-2 compare mapped planGoal (not raw).
NEW-3 pin the extract-before-plan_start ordering. Trend 3→1 P1s + narrow tuple-extension fold →
CONVERGED, no split (reviewer concurred).

## Converged design (implemented)
`last_phase_profile = {plan_goal, equipment, days_per_week, effective_exp}` written by
generateAndSchedule (flag-gated). `autoGenerateNextPhaseIfNeeded(repeatContent)` → `_buildRepeatPins`
(reads configBox + getWeek(1/2) before the plan_start overwrite) → PURE `repeatPinsFrom`
(`@visibleForTesting`): G5 all-4-match gate + A/B extraction (union keys, empty-guard, gap→empty
entry) → `pinnedExercisesByDay` → generateAndSchedule → generate(). Facade forwards `repeatContent`.
Kill-switch `enable_adherence_gate` (ship-dark OFF) gates the extraction, the gate, AND the config
write → OFF is byte-identical.

## Verdict: converged
`flutter analyze` clean (3 files); 10/10 behavioral (`repeat_content_scheduling_test.dart` — 8 pure
`repeatPinsFrom` [match/effectiveExp-NEW-1/planGoal/equipment/days mismatch, absent, empty, gap-index,
blank-name] + 2 Hive [pins→wk1/wk2 rows, last_phase_profile flag-gated]). SoT `repeat_content_scheduling`.
Accepted limitations (documented): mid-phase regen / coach-regen leave a stale baseline → next advance
biases to FRESH (safe); the rare all-pool-contraindicated empty-day is a pre-existing cascade limit
(fresh gen hits it too), not repeat-specific. B-pass runs on the implemented diff before the `--no-ff`
merge (§4.3 / platform).

## Post-B-pass (staging 2c1916685e89) — 2 P1 + 1 P2, all fixed in-batch
The fresh context-blind B-pass (`docs/reviews/workout-adherence-8a2int-bpass.md`) caught a **real P1
cross-account bug** + a **real coverage gap**. All fixed:
- **P1 (cross-account isolation):** `last_phase_profile` was written to the DEVICE-shared `configBox` — a
  2nd account on the same device would read a stale baseline and misjudge the G5 gate. Fixed: routed
  through `MigratedKey` (user-scoped `userBox`, like the sibling `plan_start_date`) + registered in
  `UserConfigMigrator.userScopedKeys`.
- **P1 (untested production path):** no test called the FACADE
  `autoGenerateNextPhaseIfNeeded(repeatContent:true)` — the facade forward, the pre-`plan_start`-overwrite
  ordering, `_buildRepeatPins`, and `effectiveLevel` were uncovered. Fixed: added an e2e test (expired prior
  phase → advance via `WorkoutScheduleService.instance` with `recompose`→`build_muscle` mapping → asserts
  the new phase pins the prior A/B selection, phase 3).
- **P2:** deleted a tautological pure "mapped goal" test; the mapping is now proven by the e2e test.
Final: `flutter analyze` clean; **10/10** behavioral (7 pure `repeatPinsFrom` + 3 Hive incl. the e2e
facade path). **bpass: accepted.**
