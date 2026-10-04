---
branch: workout-adherence-d1
scope: Batch 8 UNIT 1 (D1) — extract the phase-completion-rate primitive (W2.5 adherence signal); byte-identical + inert reader
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-d1-bpass.md
---

# Plan-review record — Batch 8 UNIT 1 (D1: adherence-signal extraction)

The smallest converged piece of the §4.12-split Batch 8 (W2.5 adherence-gated advance). Both Batch-8
review rounds verified D1 clean while the material fixes stayed in the pin-capability path (UNIT 2) —
so D1 ships first.

## ×2 review (both rounds covered D1)
- **Round-1 (Batch 8, 2 context-blind reviewers):** split Batch 8 → 8-A (content path) / 8-B (surfaces);
  identified the adherence signal (`_computePhaseCompletionRate`, trapped in the card) as a drift-prone
  extraction to hoist.
- **Round-2 (8-A, 2 context-blind reviewers):** **BOTH verified D1 byte-identical** (the card rule =
  `type ∈ {workout,custom_template}` non-rest, `status=='completed'` done, span `1..plan.weeks.length`,
  `total==0→0.0`; the pure-helper move is order-independent identical accumulation). The material fixes
  (MF-1 per-day empty, MF-2 SplitResolver-frame intensity, MF-3 in-ExerciseSelector) all live in the
  UNIT-2 pin path, NOT D1 → D1 is the smallest converged piece per §4.12.

## Reviewer-B hardening (folded)
1. Helper → `lib/core/utils/phase_completion.dart` (NOT train_provider — a `core→feature` import for the
   read-service would risk a circular import + drag Riverpod into core). ✓
2. `currentPhaseCompletionRate()` mirrors the card's DYNAMIC totalWeeks — **`phase<=1?4:scan`, phase from
   `UserRepository.getProgress().current_phase`** (the same source as the card). The B-pass P2 caught an
   initial *bare-scan* shortcut that would drift on a mid-phase Edit-Profile regen (which leaves a
   `current_phase==1` plan with week-5/6 rows via `generateAndScheduleFromDate` keeping `plan_start`);
   fixed at root to mirror the card exactly + pinned by a phase-1-cap test AND a phase≥2/>4-week case. ✓
3. Parity test builds day data via the REAL `getWeek`→`getScheduleForDate` path (inherits the
   completed→planned cross-date demotion `:467-471`), NOT hand-assembled → no circular test. ✓
4. Set-equality-not-order is a UNIT-2 concern (SequencingEngine); N/A to D1.

## Ground truth (Opus-read)
- Card loop `phase_unlock_card.dart:95-111`; `isRest = type != 'workout' && != 'custom_template'`
  (`train_provider.dart:602`); `isDone = status=='completed'` (`:638`); dynamic totalWeeks (`:582-592`).
- `getWeek` → `getScheduleForDate` (`:454-478`) applies the completed→planned demotion when
  `completed_at` date < the requested date.
- `AppConstants.phaseUnlockCompletionRate = 0.8` (`:128`) consumes the card's returned rate → unchanged
  by the byte-identical adapter.

## The change (account-tier, byte-identical, NO flag)
- NEW `lib/core/utils/phase_completion.dart` — pure `phaseCompletionRate(Iterable<({isRest,isDone})>)`.
- `phase_unlock_card._computePhaseCompletionRate` → thin adapter feeding the helper the same weeks/days
  (import added to `screen.dart`, the part-of owner).
- `WorkoutScheduleReadService.currentPhaseCompletionRate()` — INERT (no production caller in D1; 8-B
  wires it); reconstructs `{isRest,isDone}` from `getWeek` rows through the real demotion path.

## Verification
- `flutter analyze` clean on all touched files.
- `test/contracts/phase_adherence_rate_test.dart` — 9 GREEN: pure-primitive (rest-excluded, zero→0.0);
  currentPhaseCompletionRate over the real getWeek path across rest/workout/custom_template, paused
  (non-rest not-done), the cross-date demotion, zero-workout, a phase≥2/6-week dynamic-span case, AND
  the phase-1-cap case (a phase-1 plan with week-5/6 rows → totalWeeks stays 4, pinning the B-pass P2 fix).
- SoT `phase_adherence_rate` with a behavioral_test_path. No migration, no flag.

## Verdict: converged. B-pass: accepted (see bpass_review).
