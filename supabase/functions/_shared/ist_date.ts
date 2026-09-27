// supabase/functions/_shared/ist_date.ts
// IST (UTC+5:30) date helpers shared across Edge Functions.
// Mirrors lib/core/utils/ist_date.dart on the Flutter client so both sides
// agree on what "today" means.

export const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

/// Returns a new Date object shifted to IST (UTC+5:30).
export function istNow(d: Date = new Date()): Date {
  return new Date(d.getTime() + IST_OFFSET_MS);
}

/// Returns 'YYYY-MM-DD' in IST.
export function istDateStr(d: Date = new Date()): string {
  const ist = istNow(d);
  return ist.toISOString().substring(0, 10);
}

/// Returns day-of-week in IST (Sun=0 .. Sat=6).
/// Mirrors JavaScript's getDay() but computed in IST, not the server's local TZ.
export function istDayOfWeek(d: Date = new Date()): number {
  return istNow(d).getUTCDay();
}

/// Returns IST midnight (00:00:00 IST) for the given date as a
/// timestamptz-comparable ISO string carrying the +05:30 offset.
/// Use this for cloud rate-limit / cap queries like
/// `.gte("created_at", istDayStartIso())` so the "today" window
/// aligns with the user's IST day instead of UTC midnight (a 5h30m
/// drift that gives Indian users a stale rate-limit reset at
/// 05:30 IST every morning).
///
/// audit-2026-05-11 H-4 / H-10 — ai-proxy + ai-media-proxy vision
/// caps + free-tier message count were filtering against UTC
/// midnight; switched to this helper.
export function istDayStartIso(d: Date = new Date()): string {
  return `${istDateStr(d)}T00:00:00+05:30`;
}

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/** Yesterday's IST day as an [yStart, tStart) instant window, plus its IST date label. */
export function istYesterdayWindow(
  now: Date = new Date(),
): { yStart: string; tStart: string; label: string } {
  const tStartMs = Date.parse(istDayStartIso(now));
  const yStartMs = tStartMs - ONE_DAY_MS;
  return {
    yStart: new Date(yStartMs).toISOString(),
    tStart: new Date(tStartMs).toISOString(),
    label: istDateStr(new Date(yStartMs)),
  };
}

/// Returns the IST midnight instant of the MONDAY that starts the IST week
/// containing `d`, as a timestamptz-comparable ISO string carrying the
/// +05:30 offset (same shape as istDayStartIso, one level up).
///
/// day-swapper-sync-load spec §5.3 — the day-swap allowance window is a
/// Monday-Sunday IST week, and this file had no Monday helper before this.
/// Sun=0 in istDayOfWeek's convention, so the offset back to the most recent
/// Monday is (dow + 6) % 7: Mon(1)->0, Tue(2)->1, ..., Sat(6)->5, Sun(0)->6.
export function istWeekStartIso(d: Date = new Date()): string {
  const dow = istDayOfWeek(d);
  const daysSinceMonday = (dow + 6) % 7;
  const mondayIst = new Date(istNow(d).getTime() - daysSinceMonday * ONE_DAY_MS);
  const mondayDateStr = mondayIst.toISOString().substring(0, 10);
  return `${mondayDateStr}T00:00:00+05:30`;
}
