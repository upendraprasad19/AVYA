// supabase/functions/_shared/recent_prs.ts
//
// The ONE rule for "a PR worth announcing" shared by the recency readers
// `pr-detection` and `i-see-you-callout` (L1b plan B1/B3):
//
//  * dedupe to ONE live summary row per (user, workout_log_id, exercise_id)
//    BEFORE the `is_pr` filter, so a stale PR on a superseded row is never
//    announced (the winner's OWN `is_pr` decides);
//  * the row's RESOLVED workout day (the date whose UUID v5 is its
//    `workout_log_id`) must be IST yesterday or today. This drops an old log
//    edited today (fresh `completed_at`, old id — today that re-announces an
//    old PR) and a forward-moved row (its day is later), while a workout
//    logged today for yesterday (the coach's past-date log) is still
//    announced.
// Newest `completed_at` first. The caller supplies the `completed_at`
// recency window in its own query.

import { resolveDay } from "./exercise_day.ts";
import { istDateStr } from "./ist_date.ts";
import { liveSummaryRows, type SummaryRow } from "./live_exercise_rows.ts";

export function recentLivePrs<T extends SummaryRow>(
  rows: readonly T[],
  dayMap: Map<string, string>,
  now: Date = new Date(),
): T[] {
  const today = istDateStr(now);
  const yesterday = istDateStr(new Date(now.getTime() - 86_400_000));
  return liveSummaryRows([...rows], dayMap)
    .filter((r) => r.is_pr === true)
    .filter((r) => {
      const d = resolveDay(r, dayMap);
      return d === today || d === yesterday;
    })
    .sort((a, b) => String(b.completed_at ?? "").localeCompare(String(a.completed_at ?? "")));
}
