// supabase/functions/pr-detection/window.ts
//
// The pure window arithmetic of pr-detection (L1b plan T9, R5T-1/R10T-1).
// `index.ts` calls `Deno.serve` at import, so anything testable lives here.
//
// The cron is `proactive_pr_detection`, `0 * * * *` since migration 141
// (supabase/migrations/141_disk_io_audit_cleanup_batch.sql; registry row
// docs/operations/CRON_REGISTRY.md). The window is TICK-ALIGNED: a tick at T
// reads `completed_at` in [floor(T) - period, floor(T)), so consecutive ticks
// read adjacent, disjoint windows — each row present at its tick is read by
// exactly one tick, and a few minutes of cron start drift neither drops nor
// repeats a row. (`completed_at` is the device's write time; a row pushed
// after its tick passed is read by none — the old 20-minute window lost those
// too, plus every row 20-60 minutes old.) There is NO overlap to absorb:
// `shouldSendProactive` only blocks the same type on the same IST date and
// other senders overwrite its single slot between ticks, so an overlapping
// window would push a PR twice.
//
// `PR_PERIOD_MINUTES` MUST equal the live cron period; the test parses the
// cron writer out of the migrations and the registry cell and asserts it.

export const PR_PERIOD_MINUTES = 60;

const MS_PER_MINUTE = 60_000;

/** Floors `now` to the start of its period (epoch-aligned; 60 min = the hour). */
export function floorToPeriod(
  now: Date,
  periodMinutes: number = PR_PERIOD_MINUTES,
): Date {
  const p = periodMinutes * MS_PER_MINUTE;
  return new Date(Math.floor(now.getTime() / p) * p);
}

/** `[since, until)` ISO instants for the tick running at `now`. */
export function prWindow(
  now: Date,
  periodMinutes: number = PR_PERIOD_MINUTES,
): { since: string; until: string } {
  const until = floorToPeriod(now, periodMinutes);
  const since = new Date(until.getTime() - periodMinutes * MS_PER_MINUTE);
  return { since: since.toISOString(), until: until.toISOString() };
}
