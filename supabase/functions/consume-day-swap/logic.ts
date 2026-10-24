// supabase/functions/consume-day-swap/logic.ts
//
// Pure logic for the consume-day-swap Edge Function: request validation,
// tier -> limit resolution, and the consume_quota() RPC result -> response
// mapping. No Deno.serve, no Supabase client, no env reads — every branch is
// unit-testable without booting a server (spec 2026-09-26-day-swapper-design.md
// §5.3, §9's "Deno" test-layer list).

import { istWeekStartIso } from "../_shared/ist_date.ts";

export const DAY_SWAP_QUOTA_KEY = "day_swap";
export const FREE_DAY_SWAP_LIMIT = 1;
export const PRO_DAY_SWAP_LIMIT = 3;
export const MAX_WEEKS_AHEAD = 8;

const WEEK_START_FORMAT = /^\d{4}-\d{2}-\d{2}$/;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export type ValidationError =
  | "missing_week_start"
  | "invalid_week_start_format"
  | "invalid_calendar_date"
  | "week_start_not_monday"
  | "week_start_in_past"
  | "week_start_too_far_ahead";

export type ValidationResult =
  | { ok: true; weekStart: string }
  | { ok: false; error: ValidationError };

/**
 * Calendar day-of-week for a 'YYYY-MM-DD' string, Sun=0..Sat=6, evaluated as
 * a proleptic-Gregorian WALL DATE — not tied to any timezone instant.
 * Whether '2026-09-28' is a Monday does not depend on where in the world you
 * ask; anchoring to T00:00:00Z is just a stable way to ask the question.
 */
function dateStrDayOfWeek(dateStr: string): number {
  return new Date(`${dateStr}T00:00:00Z`).getUTCDay();
}

/** Whole-day difference b - a for two 'YYYY-MM-DD' strings (can be negative). */
function daysBetween(aDateStr: string, bDateStr: string): number {
  const a = Date.parse(`${aDateStr}T00:00:00Z`);
  const b = Date.parse(`${bDateStr}T00:00:00Z`);
  return Math.round((b - a) / ONE_DAY_MS);
}

/**
 * Validates `week_start` against spec §5.3: must be an IST Monday, not
 * before the current IST Monday, and at most MAX_WEEKS_AHEAD weeks ahead.
 * `now` is injectable for tests; defaults to the real current instant.
 */
export function validateWeekStart(
  weekStart: unknown,
  now: Date = new Date(),
): ValidationResult {
  if (typeof weekStart !== "string" || weekStart.length === 0) {
    return { ok: false, error: "missing_week_start" };
  }
  if (!WEEK_START_FORMAT.test(weekStart)) {
    return { ok: false, error: "invalid_week_start_format" };
  }
  const parsedMs = Date.parse(`${weekStart}T00:00:00Z`);
  if (Number.isNaN(parsedMs)) {
    return { ok: false, error: "invalid_calendar_date" };
  }
  // Date.parse silently ROLLS OVER an out-of-range day-of-month (e.g.
  // '2026-02-30' -> '2026-03-02') instead of failing, so round-trip the
  // parsed instant back through toISOString and require an exact match.
  const roundTrip = new Date(parsedMs).toISOString().substring(0, 10);
  if (roundTrip !== weekStart) {
    return { ok: false, error: "invalid_calendar_date" };
  }
  if (dateStrDayOfWeek(weekStart) !== 1) {
    return { ok: false, error: "week_start_not_monday" };
  }
  const currentMonday = istWeekStartIso(now).substring(0, 10);
  const diff = daysBetween(currentMonday, weekStart);
  if (diff < 0) {
    return { ok: false, error: "week_start_in_past" };
  }
  if (diff > MAX_WEEKS_AHEAD * 7) {
    return { ok: false, error: "week_start_too_far_ahead" };
  }
  return { ok: true, weekStart };
}

/** The IST-midnight instant string consume_quota() uses as p_window_start. */
export function windowStartIso(weekStart: string): string {
  return `${weekStart}T00:00:00+05:30`;
}

/** Tier -> per-week swap limit (spec §5.3: free 1, PRO 3). */
export function limitForTier(isPro: boolean): number {
  return isPro ? PRO_DAY_SWAP_LIMIT : FREE_DAY_SWAP_LIMIT;
}

export interface ConsumeQuotaOutcome {
  allowed: boolean;
  used: number;
  limit: number;
}

/**
 * Maps consume_quota()'s raw return (>=1 = new used count when allowed, or
 * exactly -1 when exhausted — migration 128_usage_counters.sql:69-118 never
 * returns 0 or NULL) to the response body contract (brief_common.md
 * "Decided cross-task contracts"): `-1` -> `{allowed:false, used:limit,
 * limit}`, otherwise `{allowed:true, used:<rpcResult>, limit}`.
 */
export function mapQuotaResult(
  rpcResult: number,
  limit: number,
): ConsumeQuotaOutcome {
  if (rpcResult === -1) {
    return { allowed: false, used: limit, limit };
  }
  return { allowed: true, used: rpcResult, limit };
}
