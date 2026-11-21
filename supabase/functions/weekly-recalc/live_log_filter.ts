// OI-246 follow-up (round-2 review finding P2, 2026-09-29). Extracted pure
// so it is independently testable without a live Supabase call -- mirrors
// workout-window-closing/deleted_template_filter.ts's shape for the same
// reason: the main handler is not unit-tested at the Deno level, so this is
// the only piece of the delete-filter logic a `deno test` can exercise.
//
// Why this exists: migrations 150/151 mutate `exercise_id` on the delete
// transition (suffix it, to free the natural key for a re-log — see
// docs/diagnoses/2026-09-28-exlog-tombstone-resurrection-e1c8b4.md). Before
// this filter, weekly-recalc's `calculateExperienceLevel` grouped rows by
// `exercise_id ?? exercise_name` with no `deleted_at` check at all, so a
// deleted-and-tombstoned row fragmented into its own bogus single-entry
// "exercise" (inflating the variety score) instead of being excluded, or —
// pre-150/151 — at least merging correctly into its real exercise's bucket
// (an existing minor inaccuracy, but not a fragmentation bug).

/** The shape this module reads off a `workout_log_exercises` row. */
export interface LiveLogRef {
  deleted_at: string | null;
}

/**
 * Keeps only rows that are NOT soft-deleted (migration 150's `deleted_at`).
 * A deleted exercise log must never reach the variety/weight-progression
 * scoring — it is neither "the user did this exercise" nor a valid grouping
 * key once its `exercise_id` may carry a delete-transition suffix.
 */
export function excludeDeletedLogs<T extends LiveLogRef>(
  rows: readonly T[],
): T[] {
  return rows.filter((r) => r.deleted_at == null);
}

// ── L1b (plan B1/B3) ─────────────────────────────────────────────────────────
import { inWindow, resolveDay } from "../_shared/exercise_day.ts";
import { liveSummaryRows, type SummaryRow } from "../_shared/live_exercise_rows.ts";

/**
 * One live summary row per (user, workout_log_id, exercise_id), kept only when
 * its RESOLVED workout day is in `dates`, with `date` = that day. The progression
 * and variety scores therefore see each exercise-day once (a superseded row
 * would double-count it) and an edited-old / rescheduled-forward log lands on
 * its own day, not on its write time.
 */
export function liveLogsForWindow<T extends SummaryRow>(
  rows: readonly T[],
  dayMap: Map<string, string>,
  dates: string[],
): Array<T & { date: string }> {
  return liveSummaryRows([...rows], dayMap)
    .filter((r) => inWindow(r, dayMap, dates))
    .map((r) => ({ ...r, date: resolveDay(r, dayMap) as string }));
}
