// supabase/functions/weekly-recalc/completed_days.ts
//
// Pure helpers for the `total_workouts_done` floor (coach workout parity 2,
// OI-492). The floor must come from COMPLETED days only: `workout_logs` is the
// cloud mirror of the client's `wlog_<date>` key, which only `markCompleted`
// writes, so a partial coach day (exercise rows, no `workout_logs` row) can
// never lift the lifetime counter.

import { countDistinctDates } from "../_shared/distinct_dates.ts";

/** Per user: the number of DISTINCT completed IST dates among `rows`. */
export function completedDayCounts(
  rows: ReadonlyArray<{ user_id: string; date?: string | null }>,
): Map<string, number> {
  const byUser = new Map<string, Array<{ date?: string | null }>>();
  for (const r of rows) {
    const list = byUser.get(r.user_id);
    if (list) list.push(r);
    else byUser.set(r.user_id, [r]);
  }
  const out = new Map<string, number>();
  for (const [userId, list] of byUser) out.set(userId, countDistinctDates(list));
  return out;
}

/**
 * `total_workouts_done` is a LIFETIME monotonic counter (diagnose 3a7b9f): the
 * 28-day recompute may raise it, never lower it.
 */
export function mergeMonotonicTotal(
  recomputed: number,
  existing: number | null | undefined,
): number {
  return Math.max(recomputed, existing ?? 0);
}
