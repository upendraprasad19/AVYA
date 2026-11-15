// OI-246 follow-up (B-pass review A, round 3, 2026-09-29) — mirrors
// weekly-recalc/live_log_filter.ts's shape exactly, for the same reason: the
// main handler is not unit-tested at the Deno level, so this is the only
// piece of the delete-filter logic a `deno test` can exercise.
//
// Why this exists: migrations 150/151 mutate `exercise_id` on the delete
// transition (suffix it, to free the natural key for a re-log — see
// docs/diagnoses/2026-09-28-exlog-tombstone-resurrection-e1c8b4.md), but do
// NOT clear `is_pr` or touch `completed_at`. Before this filter,
// pr-detection's query (`is_pr=true AND completed_at >= <20min ago>`) had no
// `deleted_at` check at all — so a PR logged and then deleted within the
// same ~20-minute cron window still matched, and `composeMessage` (which has
// no `exercise_name` fallback, unlike i-see-you-callout's
// `pr.exercise_name ?? pr.exercise_id`) rendered the suffixed exercise_id
// verbatim into a real push notification, e.g. "new Bench Press
// ‹del:a1b2c3d4› 100kg PR" — an internal id fragment + non-ASCII delimiter
// leaking into user-facing copy. A genuinely NEW regression this batch's
// exercise_id-suffix design introduced, not a pre-existing gap (unlike the
// other readers tracked in OI-269).

/** The shape this module reads off a `workout_log_exercises` row. */
export interface LivePrRef {
  deleted_at: string | null;
}

/**
 * Keeps only rows that are NOT soft-deleted (migrations 150/151's
 * `deleted_at`). A deleted exercise log must never generate a PR
 * notification — the user explicitly removed it, and its `exercise_id` may
 * carry a delete-transition suffix unsafe to render verbatim.
 */
export function excludeDeletedPrs<T extends LivePrRef>(
  rows: readonly T[],
): T[] {
  return rows.filter((r) => r.deleted_at == null);
}

// ── L1b (plan B1/B3) ─────────────────────────────────────────────────────────
import { recentLivePrs } from "../_shared/recent_prs.ts";
import type { SummaryRow } from "../_shared/live_exercise_rows.ts";

/**
 * The PRs worth a push — the shared recency-reader rule, see
 * `_shared/recent_prs.ts` (dedupe BEFORE `is_pr`; resolved day = IST
 * yesterday/today). Newest `completed_at` first.
 */
export function celebratablePrs<T extends SummaryRow>(
  rows: readonly T[],
  dayMap: Map<string, string>,
  now: Date = new Date(),
): T[] {
  return recentLivePrs(rows, dayMap, now);
}

/**
 * The PRs to push at a tick: dedupe over `contextRows` (the window's rows PLUS
 * every other live row of the same (user, workout_log_id) keys, so a superseded
 * row and its winner are compared even when they were written in different
 * hours), then keep only winners whose OWN `completed_at` is in `[since, until)`.
 * A winner written in an earlier or later tick is announced by that tick, never
 * by this one, so one PR is never announced twice and a stale `is_pr` on an
 * old-count row never fires (reviewer finding, L1b B-pass).
 */
export function celebratablePrsInWindow<T extends SummaryRow>(
  contextRows: readonly T[],
  dayMap: Map<string, string>,
  now: Date,
  since: string,
  until: string,
): T[] {
  const lo = Date.parse(since);
  const hi = Date.parse(until);
  return recentLivePrs(contextRows, dayMap, now).filter((r) => {
    const t = Date.parse(String(r.completed_at ?? ""));
    return !Number.isNaN(t) && t >= lo && t < hi;
  });
}
