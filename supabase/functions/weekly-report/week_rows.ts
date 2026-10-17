// supabase/functions/weekly-report/week_rows.ts
//
// Pure shaping of the report's exercise rows (L1b plan B1/B3). index.ts calls
// `serve()` at module scope, so this lives here to be unit-testable.

import { inWindow, resolveDay } from "../_shared/exercise_day.ts";
import { liveSummaryRows, type SummaryRow } from "../_shared/live_exercise_rows.ts";

export interface WeekWorkoutRow {
  date: string; // RESOLVED workout day (IST), not the write time
  exercise_name: unknown;
  sets_completed: number; // set_number = completed-set COUNT
  reps_completed: unknown; // CUMULATIVE reps across all sets
  weight_kg: unknown;
  duration_seconds: unknown;
  is_pr: unknown;
  rpe: number | null;
}

/**
 * One live summary row per (user, workout_log_id, exercise_id), in-window by
 * RESOLVED day, sorted chronologically by (day, completed_at) — pages and id
 * chunks arrive in arbitrary order — shaped for the report.
 */
export function weekWorkoutRows(
  raw: readonly SummaryRow[],
  dayMap: Map<string, string>,
  dates: string[],
): WeekWorkoutRow[] {
  return liveSummaryRows([...raw], dayMap)
    .filter((r) => inWindow(r, dayMap, dates))
    .map((r) => ({ r, day: resolveDay(r, dayMap) as string }))
    .sort((a, b) =>
      a.day !== b.day
        ? (a.day < b.day ? -1 : 1)
        : String(a.r.completed_at ?? "").localeCompare(String(b.r.completed_at ?? ""))
    )
    .map(({ r, day }) => ({
      date: day,
      exercise_name: r.exercise_name,
      sets_completed: (r.set_number as number) ?? 1,
      reps_completed: r.reps,
      weight_kg: r.weight_kg,
      duration_seconds: r.duration_seconds,
      is_pr: r.is_pr,
      rpe: null,
    }));
}
