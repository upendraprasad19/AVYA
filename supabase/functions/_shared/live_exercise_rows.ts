// supabase/functions/_shared/live_exercise_rows.ts
//
// `liveSummaryRows` — the ONE read-side rule for `workout_log_exercises` (wle)
// summary rows (L1b plan B1, SoT concept `wle_live_summary_read_contract`).
//
// `set_number` on wle is the set COUNT and part of the unique key, so an edit
// that changes the count leaves the old-count row live next to the new one
// (OI-307). After migration 155's `single_live` trigger there is one live row
// per (user, workout_log_id, exercise_id); this helper keeps the readers
// correct for rows written by older builds and for the window before the
// cleanup, and dedupes BEFORE any `is_pr` filter or cap.
//
// Winner = highest `set_number`, then highest `id` (the last push in 44/44 live
// groups, L1a-1 V11). The winner's OWN `is_pr` is used (last write wins).
// Known limit of any server rule: three rows A→B→A resolve to "highest count".

import { istDateStr } from "./ist_date.ts";

export interface SummaryRow {
  id?: string | number | null;
  user_id?: string | null;
  workout_log_id?: string | null;
  exercise_id?: string | null;
  set_number?: number | null;
  is_pr?: boolean | null;
  completed_at?: string | null;
  deleted_at?: string | null;
  // deno-lint-ignore no-explicit-any
  [k: string]: any;
}

function cmpId(a: SummaryRow["id"], b: SummaryRow["id"]): number {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  const sa = String(a);
  const sb = String(b);
  const na = Number(sa);
  const nb = Number(sb);
  if (!Number.isNaN(na) && !Number.isNaN(nb)) return na - nb;
  return sa < sb ? -1 : sa > sb ? 1 : 0;
}

function keyOf(r: SummaryRow, dayMap: Map<string, string> | undefined): string {
  const user = r.user_id ?? "";
  // Case-insensitive: the coach tools match exercise names with ilike, and the
  // same lift logged as "Bench Press" / "bench press" is one exercise-day.
  const ex = (r.exercise_id ?? "").toLowerCase();
  const resolved = r.workout_log_id && dayMap ? dayMap.get(r.workout_log_id) : undefined;
  if (resolved || !dayMap) {
    // Resolved id (or no map supplied: key on the id as stored).
    return `${user}|${r.workout_log_id ?? ""}|${ex}`;
  }
  // Unresolved id (missing-date bucket etc.): never collapse across days.
  let day = "";
  if (r.completed_at) {
    const t = Date.parse(r.completed_at);
    if (!Number.isNaN(t)) day = istDateStr(new Date(t));
  }
  return `${user}|~${day}|${ex}`;
}

/**
 * Drops tombstoned rows and keeps one winner per
 * (user_id, workout_log_id, exercise_id). Pass the day map from
 * `buildDayMap()` so rows whose id does not resolve are keyed by
 * (user, IST(completed_at) date, exercise) instead.
 */
export function liveSummaryRows<T extends SummaryRow>(
  rows: T[],
  dayMap?: Map<string, string>,
): T[] {
  const best = new Map<string, T>();
  for (const r of rows) {
    if (r.deleted_at) continue;
    const k = keyOf(r, dayMap);
    const cur = best.get(k);
    if (!cur) {
      best.set(k, r);
      continue;
    }
    const a = r.set_number ?? 0;
    const b = cur.set_number ?? 0;
    if (a > b || (a === b && cmpId(r.id, cur.id) > 0)) best.set(k, r);
  }
  return [...best.values()];
}
