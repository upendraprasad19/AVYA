// supabase/functions/_shared/wle_window_read.ts
//
// Day-window read of `workout_log_exercises` summary rows (L1b plan B3/B4).
// Selects by `workout_log_id IN (v5 of each window date + the missing-date
// bucket)` in chunks of <= 100 ids fetched concurrently, each chunk paged by
// `fetchPagesBounded` (order key `id`). The caller applies `liveSummaryRows`,
// then drops rows whose resolved day is outside the window (`inWindow`).

import { chunkIds, windowLogIds } from "./exercise_day.ts";
import { fetchPagesBounded } from "./paged_fetch_bounded.ts";

export interface WleWindowOptions {
  /** Per-chunk page budget. */
  maxPages: number;
  label: string;
}

/**
 * `makeQuery(ids, withCount)` returns a fresh builder for one id chunk with the
 * caller's select/filters applied (and `{count:"exact"}` when `withCount`).
 */
export async function fetchWleWindow<T>(
  makeQuery: (ids: string[], withCount: boolean) => unknown,
  dates: string[],
  opts: WleWindowOptions,
): Promise<{ rows: T[]; truncated: boolean }> {
  const ids = await windowLogIds(dates);
  const parts = await Promise.all(
    chunkIds(ids).map((chunk, i) =>
      fetchPagesBounded<T>((withCount) => makeQuery(chunk, withCount), {
        orderBy: [{ column: "id" }],
        maxPages: opts.maxPages,
        label: `${opts.label}#${i}`,
      })
    ),
  );
  return {
    rows: parts.flatMap((p) => p.rows),
    truncated: parts.some((p) => p.truncated),
  };
}
