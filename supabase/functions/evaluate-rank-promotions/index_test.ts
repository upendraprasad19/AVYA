// evaluate-rank-promotions: the nightly rank job counts DISTINCT completed days
// (coach workout parity 2, OI-492). Behavioural, through the exported
// handler(req, fakeDeps); importing index.ts starts no server (serve() sits
// under import.meta.main).
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { handler, realDeps } from "./index.ts";

// ── handler-local test kit (coach workout parity 2) ─────────────────────────
// A table-backed fake client with write RECORDING, per-table failure injection
// and count support; a `globalThis.fetch` stub that records URLs; a CRON_SECRET
// request builder. Env timing: static imports are hoisted, so Deno.env.set
// only works for CALL-time reads (CRON_SECRET, DISABLE_*). We do NOT set
// SUPABASE_URL or the service key (process-wide; another file's dummy URL could
// make telemetry send a real HTTPS insert), and we stub fetch instead.

const TEST_CRON_SECRET = "test-cron-secret-12345678901234567890";

interface FakeQuery {
  table: string;
  select: string;
  filters: Array<[string, string, unknown]>;
}
interface FakeWrite {
  table: string;
  op: "insert" | "upsert" | "update";
  payload: any;
  filters: Array<[string, string, unknown]>;
}

function makeFake(
  tables: Record<string, any[]>,
  failWhen: (q: FakeQuery) => boolean = () => false,
) {
  const queries: FakeQuery[] = [];
  const writes: FakeWrite[] = [];
  const client = {
    from(table: string) {
      const q: FakeQuery = { table, select: "", filters: [] };
      let wantCount = false;
      let head = false;
      let write: FakeWrite | null = null;
      let rangeFrom = 0;
      let rangeTo = Number.MAX_SAFE_INTEGER;
      let limitN: number | null = null;
      const orders: Array<[string, boolean]> = [];
      const b: any = {};
      b.select = (c?: string, o?: { count?: string; head?: boolean }) => {
        q.select = c ?? "";
        wantCount = o?.count === "exact";
        head = o?.head === true;
        return b;
      };
      for (const op of ["eq", "neq", "in", "is", "gte", "lte", "not"]) {
        b[op] = (col: string, ...rest: unknown[]) => {
          q.filters.push([op, col, op === "not" ? rest : rest[0]]);
          return b;
        };
      }
      for (const op of ["insert", "upsert", "update"] as const) {
        b[op] = (payload: unknown) => {
          write = { table, op, payload, filters: q.filters };
          writes.push(write);
          return b;
        };
      }
      b.order = (c: string, o?: { ascending?: boolean }) => {
        orders.push([c, o?.ascending ?? true]);
        return b;
      };
      b.range = (f: number, t: number) => {
        rangeFrom = f;
        rangeTo = t;
        return b;
      };
      b.limit = (n: number) => {
        limitN = n;
        return b;
      };
      const run = () => {
        if (failWhen(q)) return { data: null, error: { message: "injected failure" }, count: null };
        if (write) return { data: null, error: null };
        let rows = (tables[table] ?? []).filter((r) =>
          q.filters.every(([op, col, val]) => {
            const v = r[col];
            switch (op) {
              case "eq": return v === val;
              case "neq": return v !== val;
              case "in": return (val as unknown[]).includes(v);
              case "is": return val === null ? v === null || v === undefined : v === val;
              case "gte": return v !== null && v !== undefined && String(v) >= String(val);
              case "lte": return v !== null && v !== undefined && String(v) <= String(val);
              case "not": {
                const [nop, nval] = val as [string, string];
                if (nop !== "in") return true;
                const set = String(nval).replace(/^\(|\)$/g, "").split(",");
                return !set.includes(String(v));
              }
              default: return true;
            }
          })
        );
        for (const [c, asc] of [...orders].reverse()) {
          rows = [...rows].sort((a, z) => (a[c] < z[c] ? -1 : a[c] > z[c] ? 1 : 0) * (asc ? 1 : -1));
        }
        const total = rows.length;
        let end = Math.min(rangeTo + 1, rangeFrom + 1000);
        if (limitN !== null) end = Math.min(end, rangeFrom + limitN);
        return { data: head ? null : rows.slice(rangeFrom, end), error: null, count: wantCount ? total : null };
      };
      b.maybeSingle = () => {
        const r: any = run();
        return Promise.resolve({ data: r.data?.[0] ?? null, error: r.error });
      };
      b.single = b.maybeSingle;
      b.then = (resolve: (r: unknown) => void, reject?: (e: unknown) => void) => {
        queries.push(q);
        return Promise.resolve(run()).then(resolve, reject);
      };
      return b;
    },
  };
  return { sb: client, queries, writes };
}

/** Stubs globalThis.fetch (resolves an EMPTY 201) and records every URL. */
async function withFetchStub<T>(fn: (urls: string[]) => Promise<T>): Promise<T> {
  const orig = globalThis.fetch;
  const urls: string[] = [];
  globalThis.fetch = ((input: unknown) => {
    urls.push(typeof input === "string" ? input : input instanceof Request ? input.url : String(input));
    return Promise.resolve(new Response("[]", { status: 201 }));
  }) as typeof fetch;
  try {
    return await fn(urls);
  } finally {
    globalThis.fetch = orig;
  }
}

/** Nothing but the telemetry table path may go out; never a push. */
function assertNoStrayRequests(urls: string[]) {
  for (const u of urls) {
    if (!u.includes("/rest/v1/cron_call_log")) throw new Error(`unexpected outbound request: ${u}`);
    if (u.toLowerCase().includes("onesignal")) throw new Error(`push sent: ${u}`);
  }
}

async function withCronSecret<T>(fn: () => Promise<T>): Promise<T> {
  const prev = Deno.env.get("CRON_SECRET");
  Deno.env.set("CRON_SECRET", TEST_CRON_SECRET);
  try {
    return await fn();
  } finally {
    if (prev === undefined) Deno.env.delete("CRON_SECRET");
    else Deno.env.set("CRON_SECRET", prev);
  }
}

async function withEnv<T>(name: string, value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const prev = Deno.env.get(name);
  if (value === undefined) Deno.env.delete(name);
  else Deno.env.set(name, value);
  try {
    return await fn();
  } finally {
    if (prev === undefined) Deno.env.delete(name);
    else Deno.env.set(name, prev);
  }
}

const authedPost = () =>
  new Request("https://example.test/fn", {
    method: "POST",
    headers: { Authorization: `Bearer ${TEST_CRON_SECRET}` },
  });

/** Silences and captures console.log/warn/error for a block. */
async function quiet<T>(fn: () => Promise<T>): Promise<{ out: T; logs: string[]; errors: string[] }> {
  const logs: string[] = [];
  const errors: string[] = [];
  const o = { log: console.log, warn: console.warn, error: console.error };
  console.log = (...a: unknown[]) => void logs.push(a.join(" "));
  console.warn = () => {};
  console.error = (...a: unknown[]) => void errors.push(a.join(" "));
  try {
    return { out: await fn(), logs, errors };
  } finally {
    console.log = o.log;
    console.warn = o.warn;
    console.error = o.error;
  }
}
// ── end handler-local test kit ──────────────────────────────────────────────

// ── S0: the deps seam, default path ─────────────────────────────────────────

Deno.test("S0: realDeps().createClient is the imported original (M51)", () => {
  assert(realDeps().createClient === createClient);
});

Deno.test("S0 default path: OPTIONS -> 200, POST without a bearer -> 401, no request goes out", async () => {
  await withFetchStub(async (urls) => {
    const opt = await handler(new Request("https://example.test/fn", { method: "OPTIONS" }));
    assertEquals(opt.status, 200);
    const { out } = await quiet(() =>
      handler(new Request("https://example.test/fn", { method: "POST" }))
    );
    assertEquals(out.status, 401);
    assertNoStrayRequests(urls);
  });
});

// ── behavioural: distinct total, per-user failure isolation ────────────────

const THREE_WEEKS_AGO = new Date(Date.now() - 21 * 86_400_000).toISOString();

function tables(workoutLogs: any[]) {
  const ids = ["A", "B", "C"];
  return {
    users: ids.map((id) => ({ id, created_at: THREE_WEEKS_AGO })),
    // a live 8-day streak + 3 weeks since signup = SD1 (streak >= 7, weeks >= 1)
    user_progress: ids.map((id, i) => ({
      id: i + 1,
      user_id: id,
      current_streak_days: 8,
      deployments_complete: 0,
      longest_gap_days: 0,
      last_workout_date: null,
    })),
    rank_promotions: [] as any[],
    user_profile: ids.map((id, i) => ({ id: i + 1, user_id: id, current_rank_code: null })),
    workout_logs: workoutLogs,
    ai_coach_interactions: [] as any[],
  };
}

async function run(fake: ReturnType<typeof makeFake>) {
  return await withFetchStub((urls) =>
    withCronSecret(async () => {
      const { out, errors } = await quiet(() =>
        handler(authedPost(), { createClient: (() => fake.sb) as any })
      );
      const body = await out.json();
      assertNoStrayRequests(urls);
      return { status: out.status, body, errors };
    })
  );
}

const promotionUpserts = (fake: ReturnType<typeof makeFake>) =>
  fake.writes.filter((w) => w.table === "rank_promotions" && w.op === "upsert");
const upsertUser = (w: any) => w.payload[0].user_id;

Deno.test("rank job: double-row dates give the DISTINCT total in trigger_metadata.total_workouts (M24)", async () => {
  const fake = makeFake(tables([
    // user A: 5 rows on 3 distinct dates
    { id: 1, user_id: "A", date: "2026-10-01" },
    { id: 2, user_id: "A", date: "2026-10-01" },
    { id: 3, user_id: "A", date: "2026-10-02" },
    { id: 4, user_id: "A", date: "2026-10-02" },
    { id: 5, user_id: "A", date: "2026-10-03" },
  ]));
  const { status } = await run(fake);
  assertEquals(status, 200);
  const a = promotionUpserts(fake).find((w) => upsertUser(w) === "A")!;
  assert(a, "A is promoted");
  for (const row of a.payload) assertEquals(row.trigger_metadata.total_workouts, 3);
});

Deno.test("rank job: a NULL-date row is not a day", async () => {
  const fake = makeFake(tables([
    { id: 1, user_id: "A", date: null },
    { id: 2, user_id: "A", date: "2026-10-01" },
  ]));
  await run(fake);
  const a = promotionUpserts(fake).find((w) => upsertUser(w) === "A")!;
  assertEquals(a.payload[0].trigger_metadata.total_workouts, 1);
});

Deno.test("rank job: B's workout_logs read throws -> response 200, A and C ARE promoted, B is skipped with a console.error (M35)", async () => {
  const fake = makeFake(
    tables([{ id: 1, user_id: "A", date: "2026-10-01" }]),
    (q) => q.table === "workout_logs" && q.filters.some((f) => f[0] === "eq" && f[1] === "user_id" && f[2] === "B"),
  );
  const { status, body, errors } = await run(fake);
  assertEquals(status, 200);
  assertEquals(body.status, "success");
  const promoted = promotionUpserts(fake).map(upsertUser).sort();
  assertEquals(promoted, ["A", "C"]);
  assert(errors.some((e) => e.includes("user=B") && e.includes("totalWorkouts err")), errors.join("|"));
  assertEquals(body.evaluated, 2);
});

Deno.test("rank job: a read that reports truncated is a failure for that user; the others are promoted (M56a)", async () => {
  // 20 full pages of 1000 rows is the ceiling; 20,001 rows is cut.
  const rows: any[] = [];
  for (let i = 1; i <= 20_001; i++) rows.push({ id: i, user_id: "B", date: "2026-10-01" });
  const fake = makeFake(tables(rows));
  const { status, errors } = await run(fake);
  assertEquals(status, 200);
  assertEquals(promotionUpserts(fake).map(upsertUser).sort(), ["A", "C"]);
  assert(errors.some((e) => e.includes("user=B")), errors.join("|"));
});

Deno.test("rank job: no head-count of workout_logs rows remains (presence-only: guards the retired API shape)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes("head: true"), false);
});
