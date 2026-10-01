// Batch 10 (W3.1 explainability) — the deload-decision "why" string.
//
// PURE + total: given the deload eval's already-computed decision booleans + the
// ACTUAL lift outcome (`liftedAny`), returns one non-shaming Navy one-liner that
// MATCHES the wave character the phase-arc strip will show (working iff a row was
// actually lifted). Precedence is STRUCTURAL-before-EVIDENCE, and each evidence
// branch is gated on its had-data flag so a no-data keep never reads as "fatigue".
//
// ⚠ A DECISION BOOLEAN IS NOT AN EXPLANATION. Every branch here reads a flag the
// evaluator computed to decide, and a flag can be safely false for several
// different reasons. `notBackstop` is the one that bit: false means "cannot
// confirm a recent real deload", which covers THREE worlds — never taken,
// overdue (>=2 phases), and a future/corrupt marker — and the overdue wording
// is a falsehood for the never-taken user. Before adding a branch, ask what
// ELSE makes its flag false, and COUNT — this comment itself said "two" while
// the branch 35 lines below said "three", which round 3 caught.
//
// Consumed by `deload_evaluator.dart` (writer → `deload_reason_phase_<N>`) and
// rendered by the phase-arc strip via `WorkoutScheduleReadService.currentDeloadReason`.

/// One-line explanation of a week-4 deload decision. [shouldLift] is the eval's
/// decision; [liftedAny] is whether `_liftWeekFour` actually rewrote a row (a
/// `shouldLift` with nothing eligible to lift leaves the week a `deload`, so the
/// copy must reflect the OUTCOME, not the intent).
///
/// [hasDeloadOnRecord] is `last_actual_deload_phase != null`. It exists ONLY to
/// split the backstop branch: a decision boolean that is safely false in several
/// distinct situations cannot also serve as an explanation of which one.
String deloadDecisionReason({
  required bool shouldLift,
  required bool liftedAny,
  required bool notDeloadPhase,
  required bool notBackstop,
  required bool hasDeloadOnRecord,
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
    // `notBackstop` collapses THREE worlds: no deload has ever been recorded,
    // one is overdue (>=2 phases ago), and a future/corrupt marker. That is the
    // right polarity for the DECISION (all three mean "cannot confirm a recent
    // real deload" — keep) and wrong for the EXPLANATION: the marker is
    // LOCAL-ONLY and written by nothing but this evaluator, so a user's FIRST
    // ever week-4 eval reads null and would have been told they are "two blocks
    // in" during block ONE. Found by plan-review round 2 at the flip commit,
    // which is the first moment any of this copy reaches a user.
    return hasDeloadOnRecord
        ? "Recovery week — you're two blocks in. Time to bank the gains."
        : "Recovery week — no recovery block on record yet. Bank this one; it sets your baseline.";
  }
  if (!readinessGood && readinessHadData) {
    return 'Recovery week held — your recent check-ins flagged fatigue. Rest up.';
  }
  if (!e1rmNoFatigue && e1rmHasEvidence) {
    return 'Recovery week held — your key lifts dipped. Bank the rest, come back stronger.';
  }
  return 'Recovery week — not enough recent data to lift it yet. Log a few sessions.';
}
