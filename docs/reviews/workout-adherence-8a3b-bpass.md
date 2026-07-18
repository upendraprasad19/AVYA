---
review: B-pass (context-blind, adversarial)
branch: workout-adherence-8a3b
scope: ⑧ Batch 8 · UNIT 3-b (W2.5) — graduation repeat-vs-advance choice sheet (ship-dark)
blast_radius: account
verdict: accepted
---

# B-pass — ⑧ UNIT 3-b (graduation choice sheet)

Self-initiated ≥account B-pass (§4.3) on the implemented, staged diff BEFORE the `--no-ff` merge. A
context-blind adversarial reviewer verified every claim against the actual code and ran `flutter analyze`
(the 4 lib files 100% clean).

## Verdict: accepted — no P0, no P1.

## Classes verified CLEAN (reviewer read the code)
- **_onPro restructure** — (a) flag SHORT-CIRCUITED so `currentPhaseCompletionRate()` is never eagerly
  evaluated when OFF; (b) abort-if-changed sound in BOTH the normal case (no false abort: `live==currentPhase
  < nextPhase`) AND the concurrent-advance case (no phase skip: `live>=nextPhase` → `/train`, `return`);
  `context.go` is `mounted`-guarded; (c) `setState(_isGenerating=true)` moved AFTER the sheet, the abort
  returns BEFORE it so the `finally` never leaves a stuck spinner; (d) the shared locals feed IDENTICAL
  goal/equipment/daysPerWeek/experienceLevel to BOTH `buildRepeatPinsForAdvance` and `generateAndSchedule`
  (no G5 value drift); (e) pins built BEFORE `generateAndSchedule` overwrites plan_start; (f) nudge gated on
  `pins != null`.
- **Inertness (flag OFF) — byte-identical:** `offerChoice=false` → no sheet/abort, no rate call, `pins=null`
  → `generateAndSchedule(pinnedExercisesByDay: null)` == today, no nudge; the moved `setState` fires in the
  same synchronous frame → observably identical.
- **E1/E2/E3:** `buildRepeatPinsForAdvance` is a pure delegate to `_buildRepeatPins`; `markPhaseRepeatNudgePending`
  holds the cross-account belt inside (3-a2's refactored call is logically identical); `autoGenerateNextPhaseIfNeeded`
  still returns `repeated: pins != null`; the sheet maps primary→repeat / ghost→advance, dismiss→null→advance.
- **Regressions:** no other `_buildRepeatPins` caller; both test files pass; null-safety clean; copy non-shaming
  (no %/"you missed", two forward options) + Wardroom-compliant (WardButton primary/ghost, AppColors/AppTypography
  all verified to exist).

## P2 notes — BOTH fixed in-batch
- **P2-1 (test lint) — FIXED.** `advance_choice_test.dart`'s local helper `_openThen` tripped
  `no_leading_underscores_for_local_identifiers` (info-level; would have passed `--no-fatal-infos`). Renamed to
  `openThen`. (The abort-if-changed source-anchored regex's `{0,120}` gap was widened to `{0,300}` to span the
  P2-2 invalidations added between the guard and `context.go`.)
- **P2-2 (abort path lacked provider invalidation) — FIXED.** The abort path (`live >= nextPhase` → `/train`)
  now invalidates `currentPlanProvider` + `todayWorkoutProvider` before routing, so /train doesn't briefly show
  the pre-advance plan when a concurrent advance won the race. Ship-dark + near-nil window, but a strict
  improvement for when the flag flips ON.
