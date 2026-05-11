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
