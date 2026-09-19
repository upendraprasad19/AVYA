---
branch: workout-adherence-8a3b
scope: ⑧ Batch 8 · UNIT 3-b (W2.5) — graduation repeat-vs-advance choice sheet (the LAST UNIT 3 piece; ship-dark)
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-8a3b-bpass.md
---

# Plan-review record — ⑧ UNIT 3-b (graduation choice sheet)

Plan: `scratchpad/batch8_unit3b_plan.md` (full ×2 + Round-2 detail). §4.12 THREE context-blind review rounds
(2 parallel lenses on the original plan → 1 Round-2 on the hardened plan). **Converged — implemented.**
ACCOUNT tier (train graduation screen + read-service public method + shared nudge writer; no plan_engine/
payment/RLS/migration). NOT a `fix:` (new ship-dark capability) → no diagnose-doc. No migration. **INERT while
`enable_adherence_gate` OFF** (offerChoice false → no sheet → verbatim `_onPro`).

## Ground-truth verified (against code, file:line)
- `_onPro` (`graduation_screen.dart:563-681`): `_isGenerating` re-tap guard; reads profile/progress;
  `nextPhase = currentPhase+1`; `ref.read(workoutScheduleReadServiceProvider).generateAndSchedule(...)`
  DIRECTLY (`:589`, not the facade/autoGenerate); `updateProgress` (`:610`); invalidations (`:622-629`).
- `generateAndSchedule` accepts `pinnedExercisesByDay` (`workout_schedule_read_service.dart:113`→`:131`);
  `_buildRepeatPins` (`:514`); `currentPhaseCompletionRate()` (`:687`, ~90 Hive reads); `AppConstants.
  phaseUnlockCompletionRate=0.8` (`:128`); flag `enable_adherence_gate` (`plan_engine_flags.dart:199`); the
  3-a2 nudge write (`pro_phase_advance.dart:121-123`); readiness-sheet pattern (`readiness_sheet.dart:44-54`);
  `WardButtonVariant{primary,ghost}`.

## ×3 review (context-blind) — converged
**Review #1 (correctness):** GT accurate. **[P1]** `_onPro` inlines its defaults — the pin-build + generate
MUST use the SAME shared locals with graduation's OWN defaults (`general_fitness`/`basic_gym`/`4`/`beginner`),
NOT the other surfaces' (`intermediate`/`bodyweight`), else the G5 gate validates one frame-shape while a
different one generates (value-drift). Folded.
**Review #2 (UI/tests):** **[P1]** the plan's G2 "re-read + RECOMPUTE nextPhase" causes a phase-SKIP under a
concurrent splash advance → redesigned to **abort-if-changed** (`live >= nextPhase` → `/train`, never
recompute). **[P1]** graduation "repeat" would DROP the Home nudge → shared `markPhaseRepeatNudgePending()`
(cross-account gated) called on `pins != null`. **[P2]** extract testable seams (`showAdvanceChoiceSheet` +
pure `shouldOfferAdvanceChoice`); `_isGenerating` AFTER the sheet; dismiss→advance keyed on `choice==repeat`;
mirror `readiness_sheet`. Folded.
**Round-2 (on the hardened plan):** verified abort-if-changed sound in all cases + the shared nudge-writer
behavior-preserving. **[P1]** the seam eagerly evaluated `currentPhaseCompletionRate()` on flag-OFF (Dart
eager args) → NOT byte-identical → FIX: callsite short-circuit `adherenceGateEnabled && shouldOfferAdvanceChoice(...)`
(drop `flagOn`; the outer `&&` skips the arg eval, mirroring `pro_phase_advance.dart:86-88`). **[P2]**
`ref.invalidate(phaseRepeatNudgeProvider)` after the write for same-session surfacing. Both folded → converged,
no split (reviewer: "coherent + small; implement, no Round-3").

## Converged design (implemented)
- **E1** public `buildRepeatPinsForAdvance` (read service) delegates to `_buildRepeatPins` (visibility only).
- **E2** shared `markPhaseRepeatNudgePending()` (pro_phase_advance) — cross-account belt inside; refactored
  3-a2's inline write to call it; graduation's repeat branch calls it. `autoGenerateNextPhaseIfNeeded` keeps
  `repeated: pins != null` (the predicate graduation reuses).
- **E3** `advance_choice_sheet.dart`: `enum AdvanceChoice{repeat,advance}`; pure `shouldOfferAdvanceChoice(
  completionRate<threshold)`; `showAdvanceChoiceSheet` (readiness pattern; non-shaming Navy copy).
- **G1 `_onPro`**: shared locals (graduation defaults); `nextPhase` captured once; `offerChoice =
  adherenceGateEnabled && shouldOfferAdvanceChoice(rate, threshold)` (short-circuit → OFF never runs the loop);
  if offerChoice → `await showAdvanceChoiceSheet ?? advance`; `!mounted` return; abort-if-changed
  (`live >= nextPhase` → `/train`); `setState(_isGenerating=true)`; pins on `choice==repeat`; generate(pins);
  updateProgress; on `pins != null` → `markPhaseRepeatNudgePending()` + `invalidate(phaseRepeatNudgeProvider)`.
  Flag OFF → byte-identical.

## Verdict: converged
`flutter analyze` clean on all 4 touched lib files (No issues found). **14 behavioral** — `advance_choice_test.dart`
(pure gate truth-table + sheet widget: both options + repeat/advance/dismiss→null + graduation source-anchored:
flag-short-circuit, abort-if-changed, pins-on-repeat, nudge-on-pins) + `phase_repeat_nudge_test.dart` (extended:
shared-writer owner-gate pin follows the refactor + a behavioral markPhaseRepeatNudgePending case). Self-B-pass
runs on the implemented diff before the `--no-ff` merge (§4.3); see `bpass_review`. Merge gated on 3-a2 CI green
(confirmed success).
