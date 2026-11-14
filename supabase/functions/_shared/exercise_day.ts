// supabase/functions/_shared/exercise_day.ts
//
// Day attribution for `workout_log_exercises` (wle) summary rows (L1b plan B3).
//
// A wle row's DAY is carried only by `workout_log_id` = UUID v5 of
// `workout_<IST date>` (uuid_v5.ts). `completed_at` is the WRITE time: an old
// log edited today carries today's `completed_at` and an old id, and a log the
// coach moved forward keeps an earlier `completed_at` than its day. So no
// `completed_at` range selects a day window correctly; readers select by id
// (`windowLogIds`) and attribute by `resolveDay`.
//
// `_shared/ist_date.ts` is deliberately not edited (its bundle is imported by
// many functions); the helpers here only compose it.

import { istDateStr, IST_OFFSET_MS } from "./ist_date.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/** First date the day map covers (earlier than any real log). */
export const DAY_MAP_START = "2020-01-01";
/** The map reaches this far past today: a coach reschedule moves logs forward. */
export const DAY_MAP_FUTURE_DAYS = 400;

/** `workout_log_id` an installed APK writes when it has no date: v5('workout_'). */
export const MISSING_DATE_BUCKET_ID_PROMISE = workoutLogIdForDate("");

/** `n` IST dates 'YYYY-MM-DD', ascending, the last one being IST today of `now`. */
export function istDatesEnding(n: number, now: Date = new Date()): string[] {
  if (!Number.isInteger(n) || n < 1) {
    throw new Error(`istDatesEnding: n must be a positive integer, got ${n}`);
  }
  const todayMs = Date.parse(`${istDateStr(now)}T00:00:00Z`);
  const out: string[] = [];
  for (let i = n - 1; i >= 0; i--) {
    out.push(istDateStr(new Date(todayMs - i * ONE_DAY_MS)));
  }
  return out;
}

/** The IST date after `date` ('YYYY-MM-DD'). */
export function nextIstDate(date: string): string {
  return istDateStr(new Date(Date.parse(`${date}T00:00:00Z`) + ONE_DAY_MS));
}

/**
 * Half-open instant window `[first date 00:00+05:30, day after last date 00:00+05:30)`
 * for a list of consecutive IST dates; both ends are UTC ISO strings.
 */
export function istDateWindow(dates: string[]): { start: string; end: string } {
  if (dates.length === 0) throw new Error("istDateWindow: empty date list");
  const first = dates[0];
  const last = dates[dates.length - 1];
  return {
    start: new Date(Date.parse(`${first}T00:00:00Z`) - IST_OFFSET_MS).toISOString(),
    end: new Date(Date.parse(`${nextIstDate(last)}T00:00:00Z`) - IST_OFFSET_MS).toISOString(),
  };
}

const dayMapCache = new Map<string, Promise<Map<string, string>>>();

/**
 * workout_log_id -> IST date for every date in [DAY_MAP_START, today + 400 days]
 * (~2,870 entries). Cached per process per `today`.
 */
export function buildDayMap(now: Date = new Date()): Promise<Map<string, string>> {
  const today = istDateStr(now);
  let cached = dayMapCache.get(today);
  if (!cached) {
    cached = (async () => {
      const startMs = Date.parse(`${DAY_MAP_START}T00:00:00Z`);
      const endMs = Date.parse(`${today}T00:00:00Z`) + DAY_MAP_FUTURE_DAYS * ONE_DAY_MS;
      const dates: string[] = [];
      for (let ms = startMs; ms <= endMs; ms += ONE_DAY_MS) {
        dates.push(istDateStr(new Date(ms)));
      }
      const ids = await Promise.all(dates.map((d) => workoutLogIdForDate(d)));
      const m = new Map<string, string>();
      ids.forEach((id, i) => m.set(id, dates[i]));
      return m;
    })();
    dayMapCache.clear(); // one live entry: yesterday's map is garbage after midnight
    dayMapCache.set(today, cached);
  }
  return cached;
}

/**
 * The `workout_log_id` values that select `dates` plus the missing-date bucket
 * (its rows are attributed by IST(completed_at) and window-filtered in memory).
 */
export async function windowLogIds(dates: string[]): Promise<string[]> {
  const ids = await Promise.all(dates.map((d) => workoutLogIdForDate(d)));
  ids.push(await MISSING_DATE_BUCKET_ID_PROMISE);
  return ids;
}

/** Splits `ids` into chunks of at most `size` (default 100, the PostgREST URL-safe size). */
export function chunkIds<T>(ids: T[], size = 100): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < ids.length; i += size) out.push(ids.slice(i, i + size));
  return out;
}

export interface DayBearingRow {
  workout_log_id?: string | null;
  completed_at?: string | null;
}

/**
 * The IST date a summary row belongs to: the date whose v5 id equals
 * `workout_log_id`; fallback IST(`completed_at`) for an unresolved id (the
 * missing-date bucket, a pre-2020 or far-future id); null when neither exists.
 */
export function resolveDay(row: DayBearingRow, dayMap: Map<string, string>): string | null {
  const viaId = row.workout_log_id ? dayMap.get(row.workout_log_id) : undefined;
  if (viaId) return viaId;
  if (row.completed_at) {
    const t = Date.parse(row.completed_at);
    if (!Number.isNaN(t)) return istDateStr(new Date(t));
  }
  return null;
}

/** True when `row` resolves to a day inside `dates` (inclusive list membership). */
export function inWindow(row: DayBearingRow, dayMap: Map<string, string>, dates: string[]): boolean {
  const d = resolveDay(row, dayMap);
  return d !== null && dates.includes(d);
}
