// Generator Unit 3D-a (OI-175 / FOB-4): the server's hold-week signal.
//
// A free user who keeps training Phase I takes "hold weeks" (H1, H2, ...). The app writes each hold day as a
// `schedule_<date>` row with `week: 4 + n`, and the push sends it to `scheduled_workouts.week_number`
// (lib/core/services/sync/sync_workout.dart, `'week_number': entry['week']`). The cloud has no `is_hold` column, so a
// row with `week_number > 4` in a Phase-I user's schedule is the only server-side mark of a hold. Phases 2-12 write
// their own weeks 1-4 (measured live 2026-11-16), and the phase filter below keeps any future numbering out.
//
// Two texts read it: the Sunday Brief push (`weekly-recap-ready`) and the weekly report prompt (`weekly-report`).
// Both said "Week 4" to a holder every week (FOB-4), because `user_progress.current_week` is the clamped program
// week. Every read here FAILS CLOSED: a missing progress row, a phase other than exactly 1 or a failed read gives
// no hold, and the texts keep today's wording.

import { fetchAllByIds } from "./paged_fetch.ts";
import { istDateStr, istWeekStartIso } from "./ist_date.ts";

const ONE_DAY_MS = 86_400_000;

/** The hold number a set of `week_number` values implies: max(week - 4) over integers above 4, else null. */
export function holdOrdinalFromWeekNumbers(weeks: readonly unknown[]): number | null {
  let best: number | null = null;
  for (const w of weeks) {
    if (typeof w !== "number" || !Number.isInteger(w) || w <= 4) continue;
    const n = w - 4;
    if (best === null || n > best) best = n;
  }
  return best;
}

/**
 * The IST Monday and Sunday (YYYY-MM-DD) of the IST week containing [now]. `scheduled_date` is a date column holding
 * IST dates, so the bounds are IST dates too, never UTC.
 */
export function istWeekBounds(now: Date): { monday: string; sunday: string } {
  const mondayStart = Date.parse(istWeekStartIso(now)); // the instant of IST Monday 00:00
  return { monday: istDateStr(new Date(mondayStart)), sunday: istDateStr(new Date(mondayStart + 6 * ONE_DAY_MS)) };
}

/**
 * The users whose progress row says Phase I. Fails closed: only a row that is present, has a string `user_id` and
 * has `current_phase` exactly 1 counts (a null or missing phase is NOT read as 1 here, unlike the prompt's `?? 1`).
 */
export function phaseOneUserIds(rows: readonly Record<string, unknown>[]): string[] {
  const out: string[] = [];
  for (const row of rows) {
    if (row == null) continue;
    const id = row.user_id;
    if (typeof id !== "string" || id.length === 0) continue;
    if (row.current_phase !== 1) continue;
    out.push(id);
  }
  return out;
}

/** The Sunday Brief push text. A holder gets the hold's name; everyone else today's text, unchanged. */
export function recapMessage(firstName: string, week: number, holdOrdinal: number | null): string {
  if (holdOrdinal != null) return `${firstName} — Hold H${holdOrdinal} debrief ready. Stand to.`;
  return `${firstName} — Week ${week} debrief ready. Stand to.`;
}

/** The weekly report's week line. A holder gets the hold, with no Peak / Deload claim; everyone else today's line. */
export function reportWeekLine(week: number, holdOrdinal: number | null): string {
  if (holdOrdinal != null) {
    return `Current week: hold week H${holdOrdinal} (the user chose to keep training Phase I; a repeat of a Phase I week)`;
  }
  return `Current week: ${week}`;
}

export interface HoldOrdinals {
  /** user id -> hold number, only for users with a hold row in the window. */
  map: Map<string, number>;
  /** true when the read failed (the map is then empty and the texts keep today's wording). */
  failed: boolean;
}

/**
 * Reads `scheduled_workouts (user_id, week_number)` for [userIds] with `scheduled_date` in [fromDate, toDate]
 * (inclusive IST date strings) and `week_number > 4`, paged and chunked through `fetchAllByIds`. NEVER throws: a page
 * error, a throwing query builder or a malformed answer gives `{ map: empty, failed: true }`.
 */
export async function fetchHoldOrdinals(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userIds: readonly string[],
  fromDate: string,
  toDate: string,
): Promise<HoldOrdinals> {
  const map = new Map<string, number>();
  if (userIds.length === 0) return { map, failed: false };
  try {
    const rows = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("scheduled_workouts")
          .select("id, user_id, week_number")
          .in("user_id", chunk)
          .gte("scheduled_date", fromDate)
          .lte("scheduled_date", toDate)
          .gt("week_number", 4),
      [...userIds],
      { orderBy: "id", label: "hold_week" },
    );
    const weeksByUser = new Map<string, unknown[]>();
    for (const row of rows) {
      const id = row?.user_id;
      if (typeof id !== "string") continue;
      const list = weeksByUser.get(id) ?? [];
      list.push(row.week_number);
      weeksByUser.set(id, list);
    }
    for (const [id, weeks] of weeksByUser) {
      const n = holdOrdinalFromWeekNumbers(weeks);
      if (n != null) map.set(id, n);
    }
    return { map, failed: false };
  } catch (err) {
    // Never the error object: a PostgREST error can echo row values. The name is enough to find it.
    console.error(`[hold_week] read failed: ${err instanceof Error ? err.name : typeof err}`);
    return { map: new Map(), failed: true };
  }
}
