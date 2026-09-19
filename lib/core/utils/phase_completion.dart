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

/// Whether a `schedule_*` row's `type` counts as a training day.
///
/// ⚠️ **This is a DIFFERENT, WIDER rule than `phaseCompletionRate`'s `isRest`
/// above, and the difference is deliberate.** That one is inclusion-shaped
/// (`workout` | `custom_template`) and accurately describes its two callers
/// (`WorkoutScheduleReadService.currentPhaseCompletionRate`, `phase_unlock_card`).
/// This one is EXCLUSION-shaped, because the weekly-streak reckoning must also
/// count two shapes that inclusion list drops:
///
///  - `type: 'logged'` — written by `WorkoutWriteService.markCompleted`'s
///    no-prior-schedule branch (AI-coach-only logging) and by the restore
///    synthesize path in `sync/sync_workout.dart`, whose own comment states a
///    logged row "counts as a workout day in the streak walk".
///  - a legacy row carrying no `type` at all — `null` is counted here, matching
///    `WorkoutScheduleReadService.holdWeekSessionProgress`, which coerces via
///    `(row['type'] ?? '').toString()` and so also counts it. The two must agree:
///    they are the non-hold and hold day-sources for the SAME ratio.
///
/// An inclusion list would have to enumerate all of those and would silently
/// drop any future `type`. `'off'` is never written anywhere in `lib/` today; it
/// is excluded defensively because `holdWeekSessionProgress` excludes it, and
/// these two predicates must not drift.
///
/// The repo-wide split between the two shapes (5 call sites still use the
/// inclusion form, so they treat a `logged` day as REST) is pre-existing and
/// tracked on the open-issues board — deliberately NOT changed here.
bool isTrainingDayType(Object? type) => type != 'rest' && type != 'off';
