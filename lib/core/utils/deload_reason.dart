// Batch 10 (W3.1 explainability) — the deload-decision "why" string.
//
// PURE + total: given the deload eval's already-computed decision booleans + the
// ACTUAL lift outcome (`liftedAny`), returns one non-shaming Navy one-liner that
// MATCHES the wave character the phase-arc strip will show (working iff a row was
// actually lifted). Precedence is STRUCTURAL-before-EVIDENCE, and each evidence
// branch is gated on its had-data flag so a no-data keep never reads as "fatigue".
//
// Consumed by `deload_evaluator.dart` (writer → `deload_reason_phase_<N>`) and
// rendered by the phase-arc strip via `WorkoutScheduleReadService.currentDeloadReason`.

/// One-line explanation of a week-4 deload decision. [shouldLift] is the eval's
/// decision; [liftedAny] is whether `_liftWeekFour` actually rewrote a row (a
/// `shouldLift` with nothing eligible to lift leaves the week a `deload`, so the
/// copy must reflect the OUTCOME, not the intent).
String deloadDecisionReason({
  required bool shouldLift,
  required bool liftedAny,
  required bool notDeloadPhase,
  required bool notBackstop,
  required bool readinessGood,
  required bool readinessHadData,
  required bool e1rmNoFatigue,
  required bool e1rmHasEvidence,
}) {
  if (shouldLift) {
    return liftedAny
        ? "Working week — you've recovered. Full volume restored for this block."
        : "Recovery week logged — you're recovered and ready for the next block.";
  }
  // KEEP — structural causes first (deterministic), then evidence (had-data-gated).
  if (!notDeloadPhase) {
    return 'Scheduled recovery week — trust the taper. Muscles grow during rest.';
  }
  if (!notBackstop) {
    return "Recovery week — you're two blocks in. Time to bank the gains.";
  }
  if (!readinessGood && readinessHadData) {
    return 'Recovery week held — your recent check-ins flagged fatigue. Rest up.';
  }
  if (!e1rmNoFatigue && e1rmHasEvidence) {
    return 'Recovery week held — your key lifts dipped. Bank the rest, come back stronger.';
  }
  return 'Recovery week — not enough recent data to lift it yet. Log a few sessions.';
}
