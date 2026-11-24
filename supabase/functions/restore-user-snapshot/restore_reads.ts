// supabase/functions/restore-user-snapshot/restore_reads.ts
//
// OI-348 B10 (diagnose a0d5f7): the bundle assembly of restore-user-snapshot, moved out of
// index.ts (whose module scope reads env and starts a server, so it cannot be imported by a test)
// and run with a small, bounded concurrency instead of one read after another.
//
// ── WHY ──
//   The function used to issue ~33 requests strictly in series (each 150-650 ms on a slow
//   backend): 4.8 to 97.5 s live (2026-11-22/23). `runLimited` runs at most `limit` reads at once
//   (env RESTORE_READ_CONCURRENCY, default 3, clamped 1..8, read per request; `1` = the old serial
//   order, the rollback lever without a redeploy). Live max_connections is 60, so the default is
//   conservative.
//
// ── WHAT DOES NOT CHANGE ──
//   • READS is the ONE source of the bundle's key ORDER and key SET: an ordered array of
//     [name, kind, read] tuples in the exact order the serial code used. `tables` is built by
//     INPUT index, so the bundle is byte-identical whatever order the reads finish in (pinned
//     against a golden recorded from the e28cdab8 serial code, testdata/restore_bundle.golden.json).
//   • Every read is scoped to vUid exactly as before (same chains, verbatim). vUid is validated in
//     index.ts BEFORE assembleTables is called; the paged readers re-validate it.
//   • Fail-closed: the first rejected read makes assembleTables reject (nothing new starts; the
//     reads already in flight settle first), and index.ts answers the same 500.
//   • The three user_progress reads stay three (freezes projection parity, H-1).
//
// ── KINDS ──
//   "query": a PostgREST builder; assembleTables wraps it as q(name, builder) (destructures
//            {data, error}, throws `query_failed:<name>:<msg>` on an error). The label IS the
//            tuple name, so no body repeats it and a label cannot drift.
//   "paged": readPaged / readCoachNewest, which already return plain arrays and throw their own
//            errors; NOT wrapped (wrapping a plain array would yield undefined).
//
// ── TIMINGS ──
//   One log line per request, names and numbers only, written in a `finally` so a failed or slow
//   restore (the case worth diagnosing) still logs it:
//   `restore_timings request_id=<id> auth_ms=<n> reads_ms=<n> limit=<n> ok=<bool> <name>_ms=<n> ...`
//   (a read that did not finish successfully is omitted).

import { type DbLike, type PageBudget, readCoachNewest, readPaged } from "./paged_reads.ts";

export type ReadKind = "paged" | "query";
export type ReadFn = (db: DbLike, vUid: string, budget: PageBudget) => PromiseLike<unknown>;

/** The default and the bounds of RESTORE_READ_CONCURRENCY. */
export const DEFAULT_READ_CONCURRENCY = 3;
export const MAX_READ_CONCURRENCY = 8;

// The bundle, in the serial code's exact order. Comments carried over from index.ts.
export const READS: ReadonlyArray<readonly [string, ReadKind, ReadFn]> = [
  // ── Step A — profile + lightweight ──
  ["user_profile", "query", (db, vUid) =>
    db.from("user_profile").select("*").eq("user_id", vUid).limit(1)],
  ["users", "query", (db, vUid) =>
    db.from("users").select("full_name, email").eq("id", vUid).maybeSingle()],
  ["user_progress", "query", (db, vUid) =>
    db.from("user_progress").select("*").eq("user_id", vUid).limit(1)],
  ["user_preferences", "query", (db, vUid) =>
    db.from("user_preferences").select("*").eq("user_id", vUid).limit(1)],
  // OI-252 (stable ID rework): NO `is_active` filter -- the client needs BOTH live rows (to
  // restore) AND deleted rows (to remove any local copy + clean their schedules). Live-first
  // (nullsFirst) so a `.limit(500)` clip loses stale delete evidence before a live template.
  ["workout_templates", "query", (db, vUid) =>
    db.from("workout_templates")
      .select("*, template_exercises(*)")
      .eq("user_id", vUid)
      .order("deleted_at", { ascending: true, nullsFirst: true })
      .limit(500)],
  // workout_plan = the plan_json snapshot on user_progress (parser reads rows.first['plan_json']).
  ["workout_plan", "query", (db, vUid) =>
    db.from("user_progress").select("plan_json").eq("user_id", vUid).limit(1)],
  ["user_custom_exercises", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "user_custom_exercises", budget)],
  ["user_custom_foods", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "user_custom_foods", budget)],
  // ── Step B — bulk history (paged; see paged_reads.ts) ──
  ["workout_logs", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "workout_logs", budget)],
  ["workout_log_exercises", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "workout_log_exercises", budget)],
  ["workout_log_sets", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "workout_log_sets", budget)],
  ["workout_schedule_completions", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "workout_schedule_completions", budget)],
  ["weight_logs", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "weight_logs", budget)],
  ["daily_steps", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "daily_steps", budget)],
  ["nutrition_logs", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "nutrition_logs", budget)],
  ["body_measurements", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "body_measurements", budget)],
  ["water_logs", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "water_logs", budget)],
  ["sleep_logs", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "sleep_logs", budget)],
  ["streaks", "query", (db, vUid) =>
    db.from("streaks").select("*").eq("user_id", vUid)
      .order("week_start", { ascending: false }).limit(52)],
  // OI-252: `deleted_at` is in the embed so the client can tell a deleted template's schedule day
  // apart from a merely-missing embed. The embed is owner-scoped inside readPaged (Hermes C13).
  ["scheduled_workouts", "paged", (db, vUid, budget) =>
    readPaged(db, vUid, "scheduled_workouts", budget)],
  ["user_saved_meals", "query", (db, vUid) =>
    db.from("user_saved_meals").select("*").eq("user_id", vUid).limit(500)],
  // The NEWEST 1000 coach interactions, ascending (bundle shape unchanged).
  ["ai_coach_interactions", "paged", (db, vUid) => readCoachNewest(db, vUid)],
  // 10-column projection ONLY (H-12) — never SELECT * (keeps server-only risk scores / private
  // fields off the wire). Mirrors sync_coach.dart.
  ["coach_memory", "query", (db, vUid) =>
    db.from("coach_memory")
      .select(
        "committed_at, committed_to_lt_cdr, induction_completed_at, why_now, definition_of_winning, known_injuries, typical_wake_time, preferred_workout_time, body_part_priorities, coach_notes",
      )
      .eq("user_id", vUid)
      .maybeSingle()],
  // ── Step C — restore-completeness surfaces ──
  ["freezes", "query", (db, vUid) =>
    db.from("user_progress")
      .select(
        "streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill, streak_freezes_first_pro_grant_done, streak_progress_version",
      )
      .eq("user_id", vUid)
      .maybeSingle()],
  ["notifications_inbox", "query", (db, vUid) =>
    db.from("notifications_inbox").select("*").eq("user_id", vUid)
      .order("created_at", { ascending: false }).limit(200)],
  ["saved_diet_plan", "query", (db, vUid) =>
    db.from("saved_diet_plans").select("plan_json").eq("user_id", vUid).maybeSingle()],
  ["rank_promotions", "query", (db, vUid) =>
    db.from("rank_promotions").select("*").eq("user_id", vUid)
      .order("achieved_at", { ascending: false }).limit(20)],
  ["referral_codes", "query", (db, vUid) =>
    db.from("referral_codes").select("code, expires_at, created_at").eq("user_id", vUid)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false }).limit(1).maybeSingle()],
  // Dual-FK self-scope (H-8). vUid is UUID-validated in index.ts → .or() interpolation is safe.
  ["referral_redemptions", "query", (db, vUid) =>
    db.from("referral_redemptions")
      .select("code, referrer_id, referee_id, days_granted_each, created_at")
      .or(`referrer_id.eq.${vUid},referee_id.eq.${vUid}`)
      .order("created_at", { ascending: false }).limit(50)],
];

/**
 * RESTORE_READ_CONCURRENCY -> the number of reads in flight. PURE.
 * Absent / empty / blank -> DEFAULT (checked before parsing: `Number(undefined)` is NaN).
 * Otherwise `Number(raw.trim())` (never parseInt: "3abc" must not read as 3): not an integer
 * (NaN, "3abc", "2.5", "Infinity") -> 1 (serial, the safe side); then clamped to 1..MAX.
 */
export function parseReadConcurrency(raw: string | null | undefined): number {
  if (raw === null || raw === undefined || raw.trim() === "") return DEFAULT_READ_CONCURRENCY;
  const n = Number(raw.trim());
  if (!Number.isInteger(n)) return 1;
  return Math.min(MAX_READ_CONCURRENCY, Math.max(1, n));
}

/**
 * Runs LAZY thunks with at most `limit` in flight; resolves with the results in INPUT order.
 * A thunk is only called when its slot is free (a supabase builder fetches when awaited, so no
 * request is built early). On the first rejection nothing new starts; it rejects with that first
 * error once every read already in flight has settled (they run to completion: no deadline).
 */
export function runLimited<T>(
  thunks: ReadonlyArray<() => PromiseLike<T>>,
  limit: number,
): Promise<T[]> {
  const cap = Math.max(1, Math.floor(limit));
  return new Promise<T[]>((resolve, reject) => {
    const n = thunks.length;
    const results = new Array<T>(n);
    let next = 0;
    let inFlight = 0;
    let finished = 0;
    let failure: { error: unknown } | null = null;
    if (n === 0) {
      resolve(results);
      return;
    }
    const settle = () => {
      if (failure) {
        if (inFlight === 0) reject(failure.error);
        return;
      }
      if (finished === n) {
        resolve(results);
        return;
      }
      launch();
    };
    const launch = () => {
      while (!failure && inFlight < cap && next < n) {
        const i = next++;
        inFlight++;
        let p: PromiseLike<T>;
        try {
          p = thunks[i]();
        } catch (e) {
          p = Promise.reject(e);
        }
        Promise.resolve(p).then(
          (v) => {
            results[i] = v;
          },
          (e) => {
            failure ??= { error: e };
          },
        ).finally(() => {
          inFlight--;
          finished++;
          settle();
        });
      }
    };
    launch();
  });
}

/** Throws `query_failed:<label>:<msg>` on a PostgREST error (an empty maybeSingle is null data,
 * not an error). Moved verbatim from index.ts. */
export async function q<T>(
  label: string,
  builder: PromiseLike<{ data: T; error: unknown }>,
): Promise<T> {
  const { data, error } = await builder;
  if (error) {
    const msg = (error as { message?: string })?.message ?? String(error);
    throw new Error(`query_failed:${label}:${msg}`);
  }
  return data;
}

/** The per-request timing line. PURE. Names and numbers only, never a value. */
export function timingLogLine(o: {
  requestId: string;
  authMs: number;
  readsMs: number;
  limit: number;
  ok: boolean;
  timings: Record<string, number>;
}): string {
  const parts = READS.map(([name]) => name)
    .filter((name) => Object.hasOwn(o.timings, name))
    .map((name) => `${name}_ms=${o.timings[name]}`);
  return [
    `restore_timings request_id=${o.requestId}`,
    `auth_ms=${Math.round(o.authMs)}`,
    `reads_ms=${Math.round(o.readsMs)}`,
    `limit=${o.limit}`,
    `ok=${o.ok}`,
    ...parts,
  ].join(" ");
}

/**
 * Assembles the whole bundle for an ALREADY-VALIDATED vUid. Rejects on the first failed read
 * (fail-closed; index.ts maps it to the 500). Logs the timing line in a `finally`.
 */
export async function assembleTables(
  db: DbLike,
  vUid: string,
  budget: PageBudget,
  limit: number,
  opts: {
    authMs: number;
    requestId: string;
    clock?: () => number;
    log?: (line: string) => void;
  },
): Promise<{ tables: Record<string, unknown>; timings: Record<string, number> }> {
  const clock = opts.clock ?? (() => performance.now());
  const log = opts.log ?? ((line: string) => console.log(line));
  const timings: Record<string, number> = {};
  const started = clock();
  let ok = false;
  const run = async (name: string, kind: ReadKind, f: ReadFn): Promise<unknown> => {
    const t = clock();
    const value = kind === "query"
      ? await q(name, f(db, vUid, budget) as PromiseLike<{ data: unknown; error: unknown }>)
      : await f(db, vUid, budget);
    timings[name] = Math.round(clock() - t);
    return value;
  };
  try {
    const values = await runLimited(
      READS.map(([name, kind, f]) => () => run(name, kind, f)),
      limit,
    );
    const tables: Record<string, unknown> = {};
    READS.forEach(([name], i) => {
      tables[name] = values[i];
    });
    ok = true;
    return { tables, timings };
  } finally {
    log(timingLogLine({
      requestId: opts.requestId,
      authMs: opts.authMs,
      readsMs: clock() - started,
      limit,
      ok,
      timings,
    }));
  }
}
