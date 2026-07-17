// ⑧ Batch 8 (W2.5 adherence gate) — UNIT 1 (D1): the phase-completion-rate
// primitive, extracted so BOTH the Train phase-unlock card and the (8-B) advance
// seam compute adherence from ONE rule — no writer/reader drift.
//
// Pure + total: given a per-day {isRest, isDone} sequence for the phase, the rate
// = completed non-rest days / total non-rest days (0.0 when there are no workout
// days). This is a verbatim lift of `phase_unlock_card._computePhaseCompletionRate`
// so the card's displayed % + `canGraduate` (>= AppConstants.phaseUnlockCompletionRate)
// are byte-identical after the refactor.

/// Fraction of the phase's NON-REST scheduled days that are done.
///
/// [days] is the phase's day sequence (rest days included — they're skipped).
/// `isRest` follows the Train rule (a day is non-rest iff its `type` is `workout`
/// or `custom_template`); `isDone` is `status == 'completed'`. Returns `0.0` when
/// there are zero non-rest days (never divides by zero).
double phaseCompletionRate(Iterable<({bool isRest, bool isDone})> days) {
  var total = 0;
  var done = 0;
  for (final d in days) {
    if (d.isRest) continue;
    total++;
    if (d.isDone) done++;
  }
  if (total == 0) return 0.0;
  return done / total;
}
