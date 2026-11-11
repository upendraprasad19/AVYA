// supabase/functions/_shared/distinct_dates.ts
//
// ONE rule for "how many completed workout DAYS": the number of distinct
// `workout_logs.date` values, mirroring the client's
// `WorkoutReadService.completedWorkoutDayCount`
// (lib/core/services/workout_read_service.dart). `workout_logs` holds one row
// per completed day, plus a handful of dates that carry two rows (17 at the
// 2026-11-10 survey), so a ROW count over-counts those days.
//
// Used by evaluate-rank-promotions, weekly-recalc, getPromotionStatus and the
// i-see-you-callout Saturday gate, so the rule exists once (coach workout
// parity 2, OI-492).

/** `YYYY-MM-DD`, nothing else (no timestamp, no padding-free month). */
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Size of the Set of `date` strings that are non-empty after trim and match
 * `YYYY-MM-DD`. NULL, empty and malformed dates are ignored: these are
 * display-only counters, and a NULL-date row is a data defect, not a day.
 */
export function countDistinctDates(
  rows: ReadonlyArray<{ date?: string | null }>,
): number {
  const seen = new Set<string>();
  for (const r of rows) {
    const d = r?.date;
    if (typeof d !== "string") continue;
    const t = d.trim();
    if (t.length === 0 || !ISO_DATE.test(t)) continue;
    seen.add(t);
  }
  return seen.size;
}
