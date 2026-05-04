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
