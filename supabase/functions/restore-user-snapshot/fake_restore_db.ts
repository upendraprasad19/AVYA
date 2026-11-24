// A fake PostgREST client for restore_reads_test.ts (OI-348 B10, diagnose a0d5f7) and for the
// one-off golden recording of the e28cdab8 serial assembly (see testdata/restore_bundle.golden.json).
// Test-only: no function imports it, so the deploy payload (emit_payload.js follows imports) never
// carries it.
//
// It supports the chains the restore uses: select / eq / gt / gte / or / order / limit / range /
// maybeSingle, and resolves like a supabase-js builder (a thenable that "fetches" when `then` is
// first called). Every table answers after its own latency, so reads finish out of order. It
// records, per resolved request, the table and the exact call chain; it counts requests in flight
// (max) and how many builders were created (`from` calls).
//
// What it cannot see (stated in the diagnose-doc): embeds are not resolved (the select string is
// recorded, the stored row is returned as is), and row-level security does not exist here.

export type Row = Record<string, unknown>;

export interface RecordedCall {
  table: string;
  chain: unknown[][];
}

export interface FakeDbOptions {
  /** Milliseconds before each request of this table resolves (default 0). */
  latency?: Record<string, number>;
  /** A request to this table resolves with `{data: null, error}`. */
  failTable?: string;
  /** The server row cap (PostgREST `db-max-rows`), default 1000. */
  serverCap?: number;
}

function cmp(a: unknown, b: unknown): number {
  if (a === b) return 0;
  if (a === null || a === undefined) return -1;
  if (b === null || b === undefined) return 1;
  return (a as string | number) < (b as string | number) ? -1 : 1;
}

export function makeFakeDb(data: Record<string, Row[]>, o: FakeDbOptions = {}) {
  const calls: RecordedCall[] = [];
  const stats = { inFlight: 0, maxInFlight: 0, fromCalls: 0, thenCalls: 0 };
  const cap = o.serverCap ?? 1000;

  function builder(table: string) {
    stats.fromCalls++;
    const chain: unknown[][] = [];
    const eqs: [string, unknown][] = [];
    const gts: [string, unknown][] = [];
    const gtes: [string, unknown][] = [];
    const ors: string[] = [];
    const orders: [string, { ascending?: boolean; nullsFirst?: boolean }][] = [];
    let limitN: number | undefined;
    let range: [number, number] | undefined;
    let single = false;
    let started: Promise<{ data: unknown; error: unknown }> | undefined;

    const run = async () => {
      stats.inFlight++;
      stats.maxInFlight = Math.max(stats.maxInFlight, stats.inFlight);
      try {
        const ms = o.latency?.[table] ?? 0;
        await new Promise((r) => setTimeout(r, ms));
        calls.push({ table, chain: chain.map((c) => [...c]) });
        if (o.failTable === table) return { data: null, error: { message: `boom on ${table}` } };
        let rows = (data[table] ?? []).filter((r) =>
          eqs.every(([c, v]) => r[c] === v) &&
          gts.every(([c, v]) => cmp(r[c], v) > 0) &&
          gtes.every(([c, v]) => cmp(r[c], v) >= 0) &&
          ors.every((expr) =>
            expr.split(",").some((part) => {
              const [c, op, ...rest] = part.split(".");
              return op === "eq" && r[c] === rest.join(".");
            })
          )
        );
        if (orders.length) {
          rows = [...rows].sort((a, b) => {
            for (const [c, opt] of orders) {
              const av = a[c], bv = b[c];
              const an = av === null || av === undefined, bn = bv === null || bv === undefined;
              if (an !== bn) return an === (opt.nullsFirst ?? !(opt.ascending ?? true)) ? -1 : 1;
              const d = cmp(av, bv) * ((opt.ascending ?? true) ? 1 : -1);
              if (d !== 0) return d;
            }
            return 0;
          });
        }
        if (range) rows = rows.slice(range[0], Math.min(range[1] + 1, range[0] + cap));
        else rows = rows.slice(0, Math.min(limitN ?? cap, cap));
        if (limitN !== undefined) rows = rows.slice(0, limitN);
        if (single) return { data: rows.length ? rows[0] : null, error: null };
        return { data: rows, error: null };
      } finally {
        stats.inFlight--;
      }
    };

    // deno-lint-ignore no-explicit-any
    const b: any = {
      select(s: string) { chain.push(["select", s]); return b; },
      eq(c: string, v: unknown) { chain.push(["eq", c, v]); eqs.push([c, v]); return b; },
      gt(c: string, v: unknown) { chain.push(["gt", c, v]); gts.push([c, v]); return b; },
      gte(c: string, v: unknown) { chain.push(["gte", c, v]); gtes.push([c, v]); return b; },
      or(s: string) { chain.push(["or", s]); ors.push(s); return b; },
      order(c: string, opt: { ascending?: boolean; nullsFirst?: boolean } = {}) {
        chain.push(["order", c, opt]);
        orders.push([c, opt]);
        return b;
      },
      limit(n: number) { chain.push(["limit", n]); limitN = n; return b; },
      range(a: number, z: number) { chain.push(["range", a, z]); range = [a, z]; return b; },
      maybeSingle() { chain.push(["maybeSingle"]); single = true; return b; },
      then(res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) {
        stats.thenCalls++;
        started ??= run();
        return started.then(res, rej);
      },
    };
    return b;
  }

  return { from: (t: string) => builder(t), calls, stats };
}

export const ME = "11111111-1111-4111-8111-111111111111";
export const OTHER = "22222222-2222-4222-8222-222222222222";

/** A deterministic dataset touching every table the restore reads, for ME and OTHER. */
export function restoreDataset(): Record<string, Row[]> {
  const out: Record<string, Row[]> = {};
  const add = (t: string, r: Row) => (out[t] ??= []).push(r);
  for (const [uid, tag] of [[ME, "a"], [OTHER, "b"]] as const) {
    add("user_profile", { user_id: uid, full_name: `P-${tag}`, units_system: "metric" });
    add("users", { id: uid, full_name: `U-${tag}`, email: `${tag}@x.test` });
    add("user_progress", {
      user_id: uid,
      current_phase: 2,
      plan_json: { weeks: 4, tag },
      streak_freezes_available: 1,
      streak_freezes_used_dates: [],
      streak_freezes_last_refill: "2026-11-16",
      streak_freezes_first_pro_grant_done: true,
      streak_progress_version: 3,
    });
    add("user_preferences", { user_id: uid, notification_preferences: { morning: true } });
    for (let i = 0; i < 3; i++) {
      add("workout_templates", {
        user_id: uid, id: `t-${tag}-${i}`, name: `T${i}`,
        deleted_at: i === 1 ? "2026-10-01T00:00:00Z" : null,
      });
    }
    add("streaks", { user_id: uid, id: `s-${tag}`, week_start: "2026-11-16" });
    add("streaks", { user_id: uid, id: `s2-${tag}`, week_start: "2026-11-09" });
    add("user_saved_meals", { user_id: uid, id: `m-${tag}`, name: "Dal" });
    add("coach_memory", { user_id: uid, coach_notes: `notes-${tag}`, why_now: "x" });
    add("notifications_inbox", { user_id: uid, id: `n-${tag}`, created_at: "2026-11-20T00:00:00Z" });
    add("saved_diet_plans", { user_id: uid, plan_json: { meals: 3, tag } });
    add("rank_promotions", { user_id: uid, rank_code: "SD1", achieved_at: "2026-11-01T00:00:00Z" });
    add("referral_codes", {
      user_id: uid, code: `C${tag}`, expires_at: "2099-01-01T00:00:00Z", created_at: "2026-11-01T00:00:00Z",
    });
    add("referral_codes", {
      user_id: uid, code: `OLD${tag}`, expires_at: "2020-01-01T00:00:00Z", created_at: "2019-11-01T00:00:00Z",
    });
    add("referral_redemptions", {
      code: `C${tag}`, referrer_id: uid, referee_id: tag === "a" ? OTHER : ME,
      days_granted_each: 7, created_at: "2026-11-02T00:00:00Z",
    });
    for (let i = 0; i < 4; i++) {
      const ts = `2026-11-${String(10 + i).padStart(2, "0")}T06:00:00Z`;
      for (const t of [
        "user_custom_exercises", "user_custom_foods", "workout_logs", "workout_log_exercises",
        "workout_log_sets", "workout_schedule_completions", "weight_logs", "daily_steps",
        "nutrition_logs", "body_measurements", "water_logs", "sleep_logs", "scheduled_workouts",
      ]) {
        add(t, {
          user_id: uid, id: `${t}-${tag}-${i}`, created_at: ts, completed_at: ts,
          date: ts.slice(0, 10), logged_at: ts, scheduled_date: ts.slice(0, 10),
          week_start: ts.slice(0, 10), measured_at: ts,
        });
      }
      add("ai_coach_interactions", { user_id: uid, id: `ci-${tag}-${i}`, created_at: ts });
    }
  }
  return out;
}

/** The recorded chains as a canonical, order-independent multiset per table (the `gt` timestamp
 * of the referral_codes read is replaced by a placeholder: it is "now"). */
export function canonicalCalls(calls: RecordedCall[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const c of calls) {
    const chain = c.chain.map((step) =>
      step[0] === "gt" && step[1] === "expires_at" ? ["gt", "expires_at", "<now>"] : step
    );
    (out[c.table] ??= []).push(JSON.stringify(chain));
  }
  for (const k of Object.keys(out)) out[k].sort();
  return Object.fromEntries(Object.entries(out).sort(([a], [b]) => (a < b ? -1 : 1)));
}
