// supabase/functions/i-see-you-callout/streak_gate.ts
//
// The Saturday "first in-streak Saturday" gate. The callout text promises "two
// weeks of consistent work", i.e. distinct DAYS, but the gate used to count
// `workout_logs` ROWS in the last 672 hours: a user with 7 days and two rows
// each passed. It is now >= 14 DISTINCT IST dates among the last 28 IST dates,
// the same rule (countDistinctDates) the rank job, weekly-recalc and
// getPromotionStatus use (coach workout parity 2, OI-492).

import { countDistinctDates } from "../_shared/distinct_dates.ts";
import { istDatesEnding } from "../_shared/exercise_day.ts";
import { fetchPagesBounded } from "../_shared/paged_fetch_bounded.ts";

/** Distinct completed days needed in the 28-IST-date window. */
export const DEEP_STREAK_MIN_DAYS = 14;

/** Pure: true when `rows` hold at least 14 distinct completed IST dates. */
export function hasDeepStreak(rows: ReadonlyArray<{ date?: string | null }>): boolean {
  return countDistinctDates(rows) >= DEEP_STREAK_MIN_DAYS;
}

/**
 * Reads the user's completed days inside the 28 IST dates ending today and
 * applies {@link hasDeepStreak}. A page error or a truncated read THROWS, so a
 * cut can never under-count into a silently skipped callout.
 */
export async function readDeepStreak(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  now: Date = new Date(),
): Promise<boolean> {
  const window = istDatesEnding(28, now);
  const res = await fetchPagesBounded<{ date: string | null }>(
    (withCount) =>
      supabase
        .from("workout_logs")
        .select("id, date", withCount ? { count: "exact" } : undefined)
        .eq("user_id", userId)
        .gte("date", window[0])
        .lte("date", window[27]),
    {
      orderBy: [{ column: "date", ascending: false }, { column: "id" }],
      maxPages: 20,
      label: "i-see-you-callout deep-streak",
    },
  );
  if (res.truncated) throw new Error("workout_logs read truncated");
  return hasDeepStreak(res.rows);
}
