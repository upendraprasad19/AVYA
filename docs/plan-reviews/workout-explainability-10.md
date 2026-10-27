---
branch: workout-explainability-10
scope: Batch 10 · W3.1 explainability — deload "why" (arc strip) + adherence "why" (non-shaming copy)
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-explainability-10-bpass.md
---

# Plan-review record — Batch 10 (W3.1 explainability)

Plan: `docs/plans/batch10-explainability.md` (full ground-truth + ×2 review detail). §4.12 TWO
context-blind rounds (2 parallel lenses on the original plan → 1 Round-2 on the hardened plan).
**Converged.** ACCOUNT tier (`deload_evaluator.dart` + new `core/utils/deload_reason.dart` +
`workout_schedule_read_service.dart` → account; render/sheet files → feature; NO `plan_engine/**`).
NOT a `fix:` (additive explainability) → no diagnose-doc. No migration. Ship-dark — rides the parent
flags (`enable_triggered_deload`+`enable_readiness`+`enable_phase_arc` for the deload "why";
`enable_adherence_gate` for the sheet copy). Purely additive → byte-identical when the parents are OFF.

## Ground-truth verified (against code, file:line — both Round-1 reviewers, ALL confirmed correct)
- Deload decision `deload_evaluator.dart:123-124` (`shouldLift = notBackstop && notDeloadPhase &&
  readiness.good && e1rm.noFatigue`); clauses :111-121; firmKeep :137-140; phase source :66-76
  (`getWeek(4)→r['phase']`) + flag :81; marker/flag keys :41-42; eval gate :53-54; `_liftWeekFour`
  early-return-leaves-'deload' ~:205.
- Render `phase_arc_strip.dart` + `phaseArcProvider` (`train_provider.dart:715-722`, currentWeek :720),
  gate `enable_phase_arc` :717; mounted `train/screen.dart:312`.
- Adherence sheet `advance_choice_sheet.dart` const/no-params :42-43, body :60-65, non-shaming
  contract :3-4; `AppConstants.phaseUnlockCompletionRate == 0.8` (`app_constants.dart:128`).
- Eval-timing `day_rollover_service._doRolloverWithRef:181` (awaited before provider invalidation).

## ×2 review (context-blind) — converged
**Round-1 (2 parallel lenses — deload/inertness + adherence/drift):** both `needs-changes`, GT 100%
correct. Findings folded (plan §6): A-P1 reader phase-source unpinned → **shared phase helper**
(writer==reader); A-P2 precedence → **structural-before-evidence** + had-data gating; A-P2 blast-radius
→ **account**; A-P2 reversibility → `currentDeloadReason` gated on `triggeredDeloadEnabled`. **B-P1×4
(rate hoist / signature-break / provider-shape) ALL DISSOLVED** by the R2-P2 finding: the raw-% copy
VIOLATES the codified non-shaming brand soul → the adherence "why" is redesigned to a **non-shaming
COPY-ONLY** trigger lead-in (no %, no rate threading) → zero test breaks.

**Round-2 (on the hardened plan):** verified the shared-phase-helper writer==reader (a phase advance
moves `plan_start_date` → currentWeek resets → the week-4 render gate shuts → no stale leak),
eval-timing (rollover awaited before render), adherence copy-only (breaks 0 tests), account tier.
Two P2 folds (plan §8): **R2-1** stamp the reason from the ACTUAL outcome (`liftedAny` threaded out of
`_liftWeekFour`) so a `shouldLift`-but-nothing-lifted case shows a matching (not contradictory)
subtext; **R2-2** the copy test is a real `find.textContaining` widget assertion. No forbidden 5th
round. Correction: the `deload_reason_phase_*` key needs no migrator registration (mirrors the
existing un-registered deload keys).

## Converged design (to implement)
- **`lib/core/utils/deload_reason.dart`** pure `deloadDecisionReason({shouldLift, liftedAny, clauses…})`
  — structural-before-evidence, had-data-gated, + a positive `shouldLift && !liftedAny` reason.
- **`deload_evaluator.dart`** — `_liftWeekFour` returns `bool liftedAny`; stamp `deload_reason_phase_<P>`
  (shared phase helper, per-user workoutBox) on lift/firm-keep/transient.
- **`workout_schedule_read_service.dart`** — `currentDeloadReason()` (same phase helper; null unless
  `triggeredDeloadEnabled`); **`phaseArcProvider`** exposes it; **`PhaseArcStrip`** renders a
  `textDim bodySm` line only when `currentWeek==4` && reason non-null.
- **`advance_choice_sheet.dart`** — non-shaming copy-only lead-in (no %, sheet signature UNCHANGED);
  routed through the Wardroom soul + psychology-pass-fitness lens.
- SoT `deload_decision_reason`; behavioral `deload_reason_test.dart` (pure truth-table) + a round-trip
  in `deload_eval_behavioral_test.dart` + a widget assertion in `advance_choice_test.dart`.

## Verdict: converged
Self-initiated ≥account B-pass runs on the implemented diff BEFORE the `--no-ff` merge (§4.3);
`bpass:`/`bpass_review:` filled on acceptance.
