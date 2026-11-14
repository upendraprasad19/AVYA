import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { excludeDeletedLogs } from "./live_log_filter.ts";

// OI-246 follow-up (round-2 review finding P2, 2026-09-29).

Deno.test("excludeDeletedLogs: drops a row with a non-null deleted_at", () => {
  const rows = [
    { id: "live-1", deleted_at: null },
    { id: "dead-1", deleted_at: "2026-09-29T00:00:00Z" },
  ];
  const kept = excludeDeletedLogs(rows);
  assertEquals(kept.map((r) => r.id), ["live-1"]);
});

Deno.test("excludeDeletedLogs: keeps every row when none are deleted", () => {
  const rows = [
    { id: "a", deleted_at: null },
    { id: "b", deleted_at: null },
  ];
  assertEquals(excludeDeletedLogs(rows).length, 2);
});

Deno.test("excludeDeletedLogs: drops every row when all are deleted", () => {
  const rows = [
    { id: "a", deleted_at: "2026-09-29T00:00:00Z" },
    { id: "b", deleted_at: "2026-09-28T00:00:00Z" },
  ];
  assertEquals(excludeDeletedLogs(rows), []);
});

Deno.test("excludeDeletedLogs: empty input yields empty output", () => {
  assertEquals(excludeDeletedLogs([]), []);
});

// Wiring — the fetch must select deleted_at, and the fetched rows must be
// routed through excludeDeletedLogs before building allLogs. A source-grep
// check because the main handler makes a live Supabase call and is not
// otherwise unit-tested at the Deno level (same scope note as
// workout-window-closing/index_test.ts).
Deno.test("weekly-recalc: selects deleted_at and filters through excludeDeletedLogs before building allLogs", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("deleted_at: string | null")) {
    throw new Error("expected the workout_log_exercises fetch to select+type deleted_at");
  }
  if (!src.includes('completed_at, deleted_at"')) {
    throw new Error("expected the workout_log_exercises select column list to include deleted_at");
  }
  if (!src.includes("excludeDeletedLogs(rawLogs)")) {
    throw new Error("expected rawLogs to be routed through excludeDeletedLogs(rawLogs) before building allLogs");
  }
  const filterIdx = src.indexOf("excludeDeletedLogs(rawLogs)");
  const allLogsIdx = src.indexOf("const allLogs: WorkoutLog[] =");
  if (filterIdx === -1 || allLogsIdx === -1 || filterIdx > allLogsIdx) {
    throw new Error("expected excludeDeletedLogs to run BEFORE allLogs is built, not after");
  }
});

// ── L1b behavioural: liveLogsForWindow ───────────────────────────────────────
import { liveLogsForWindow } from "./live_log_filter.ts";
import { buildDayMap, istDatesEnding } from "../_shared/exercise_day.ts";
import { workoutLogIdForDate } from "../_shared/uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z");
const mkLog = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "bench",
  set_number: 3,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  ...over,
});

Deno.test("liveLogsForWindow: the progression input has ONE row per (user, day, exercise)", async () => {
  const m = await buildDayMap(NOW);
  const dates = istDatesEnding(28, NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-10-06", { id: 1, set_number: 3 }),
    await mkLog("2026-10-06", { id: 2, set_number: 4 }),
  ], m, dates);
  assertEquals(out.length, 1);
  assertEquals(out[0].set_number, 4);
  assertEquals(out[0].date, "2026-10-06");
});

Deno.test("liveLogsForWindow: an edited old log (old id, recent completed_at) is outside the 28-day window; date = resolved day", async () => {
  const m = await buildDayMap(NOW);
  const dates = istDatesEnding(28, NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-06-01", { completed_at: "2026-10-06T05:00:00Z" }),
    await mkLog("2026-10-01", { completed_at: "2026-10-06T05:00:00Z" }),
  ], m, dates);
  assertEquals(out.map((r) => r.date), ["2026-10-01"]);
});

Deno.test("liveLogsForWindow: two users on the same day/exercise both survive", async () => {
  const m = await buildDayMap(NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-10-06", { user_id: "u1" }),
    await mkLog("2026-10-06", { user_id: "u2" }),
  ], m, istDatesEnding(28, NOW));
  assertEquals(out.length, 2);
});

// PRESENCE-ONLY: index.ts calls serve() at import. The window is exactly 28 IST dates and the
// wle read selects by workout_log_id, not completed_at (the write time).
Deno.test("weekly-recalc: 28-date window, wle selected by workout_log_id ids", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("istDatesEnding(28)")) throw new Error("expected a 28-date IST window");
  if (!src.includes('.in("workout_log_id", chunk)')) throw new Error("expected the wle read to select by id list");
  if (src.includes('"completed_at",\n        fourWeeksAgoStr')) throw new Error("wle must not be selected by completed_at");
});

// ════════════════════════════════════════════════════════════════════════════
// Coach workout parity 2 (OI-492): the total_workouts_done floor counts
// COMPLETED days only, behavioural through handler(req, fakeDeps).
// ════════════════════════════════════════════════════════════════════════════
// deno-lint-ignore-file no-explicit-any
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { handler, realDeps } from "./index.ts";
import { nextIstDate } from "../_shared/exercise_day.ts";
import { istDateStr } from "../_shared/ist_date.ts";
// The day before an IST date, read back in IST (same shape as nextIstDate).
const prevIstDate = (date: string) => istDateStr(new Date(Date.parse(`${date}T00:00:00Z`) - 86_400_000));

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

Deno.test("S0 default path: OPTIONS -> 200, GET -> 405, POST without a bearer -> 401, no request goes out", async () => {
  await withFetchStub(async (urls) => {
    const opt = await handler(new Request("https://example.test/fn", { method: "OPTIONS" }));
    assertEquals(opt.status, 200);
    const get = await handler(new Request("https://example.test/fn", { method: "GET" }));
    assertEquals(get.status, 405);
    const { out } = await quiet(() =>
      handler(new Request("https://example.test/fn", { method: "POST" }))
    );
    assertEquals(out.status, 401);
    assertNoStrayRequests(urls);
  });
});

// ── behavioural ─────────────────────────────────────────────────────────────

// Every fixture date is built from istDatesEnding(28) at TEST time (never a literal).
const WINDOW = istDatesEnding(28);
const wleRow = async (id: number, userId: string, date: string) => ({
  id,
  user_id: userId,
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "bench",
  exercise_name: "Bench Press",
  set_number: 3,
  is_pr: false,
  weight_kg: 60,
  reps: 8,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
});

async function recalc(
  workoutLogs: any[],
  wle: any[],
  existing: Record<string, number>,
) {
  const fake = makeFake({
    workout_log_exercises: wle,
    scheduled_workouts: [] as any[],
    workout_logs: workoutLogs,
    user_progress: Object.entries(existing).map(([user_id, total_workouts_done], i) => ({
      id: i + 1,
      user_id,
      total_workouts_done,
    })),
  });
  const res = await withFetchStub((urls) =>
    withCronSecret(async () => {
      const { out } = await quiet(() =>
        handler(authedPost(), { createClient: (() => fake.sb) as any })
      );
      const body = await out.json();
      assertNoStrayRequests(urls);
      return { status: out.status, body };
    })
  );
  const written = new Map<string, number>();
  for (const w of fake.writes) {
    if (w.table === "user_progress" && w.op === "upsert") {
      written.set(w.payload.user_id, w.payload.total_workouts_done);
    }
  }
  return { ...res, written };
}

Deno.test("handler: a wle-only user (exercise rows, NO workout_logs row, existing 0) gets 0 WRITTEN, not 1 (M25)", async () => {
  const { status, body, written } = await recalc([], [await wleRow(1, "wle-only", WINDOW[26])], {
    "wle-only": 0,
  });
  assertEquals(status, 200);
  // precondition: the user IS in the recalculation (otherwise 0 proves nothing)
  assert(body.total_logs >= 1, "the wle row must reach allLogs");
  assertEquals(body.total_users, 1);
  assertEquals(written.get("wle-only"), 0);
});

Deno.test("handler: a completed-day user writes the DISTINCT count of workout_logs dates (double-row date counts once)", async () => {
  const { written, body } = await recalc(
    [
      { id: 1, user_id: "u1", date: WINDOW[27] },
      { id: 2, user_id: "u1", date: WINDOW[27] },
      { id: 3, user_id: "u1", date: WINDOW[26] },
      { id: 4, user_id: "u1", date: WINDOW[20] },
    ],
    [await wleRow(1, "u1", WINDOW[27])],
    { u1: 0 },
  );
  assert(body.total_logs >= 1);
  assertEquals(written.get("u1"), 3);
});

Deno.test("handler: recomputed < existing keeps the lifetime counter (2 completed days, existing 10 -> 10 written) (M26)", async () => {
  const { written, body } = await recalc(
    [
      { id: 1, user_id: "u1", date: WINDOW[27] },
      { id: 2, user_id: "u1", date: WINDOW[26] },
    ],
    [await wleRow(1, "u1", WINDOW[27])],
    { u1: 10 },
  );
  assert(body.total_logs >= 1);
  assertEquals(written.get("u1"), 10);
});

Deno.test("handler: a workout_logs row 29 days old and a FUTURE-dated row are NOT counted (M53)", async () => {
  const dayBeforeWindow = prevIstDate(WINDOW[0]);
  const future = nextIstDate(WINDOW[27]);
  const { written, body } = await recalc(
    [
      { id: 1, user_id: "u1", date: WINDOW[27] }, // in window
      { id: 2, user_id: "u1", date: dayBeforeWindow }, // 29 days old
      { id: 3, user_id: "u1", date: future }, // future
    ],
    [await wleRow(1, "u1", WINDOW[27])], // precondition: u1 is in allUserIds with total_logs >= 1
    { u1: 0 },
  );
  assert(body.total_logs >= 1);
  assertEquals(body.total_users, 1);
  assertEquals(written.get("u1"), 1);
});

Deno.test("handler: a failed workout_logs read does NOT fail the tick: levels written, every stored total kept (B-pass S1-F1)", async () => {
  const fake = makeFake(
    {
      workout_log_exercises: [await wleRow(1, "u1", WINDOW[27]), await wleRow(2, "u2", WINDOW[26])],
      scheduled_workouts: [] as any[],
      // Three completed days for u1: a successful read would raise u1 to 3.
      workout_logs: [
        { id: 1, user_id: "u1", date: WINDOW[27] },
        { id: 2, user_id: "u1", date: WINDOW[26] },
        { id: 3, user_id: "u1", date: WINDOW[25] },
      ],
      user_progress: [
        { id: 1, user_id: "u1", total_workouts_done: 2 },
        { id: 2, user_id: "u2", total_workouts_done: 7 },
      ],
    },
    (q) => q.table === "workout_logs",
  );
  const { status, errs } = await withFetchStub(() =>
    withCronSecret(async () => {
      const { out, errors } = await quiet(() =>
        handler(authedPost(), { createClient: (() => fake.sb) as any })
      );
      return { status: out.status, errs: errors };
    })
  );
  assertEquals(status, 200);
  const upserts = fake.writes.filter((w: any) => w.table === "user_progress" && w.op === "upsert");
  const byUser = new Map(upserts.map((w: any) => [w.payload.user_id, w.payload]));
  assertEquals(byUser.size, 2, "both users still get their weekly write");
  // Kept as stored: neither lowered nor raised from a read that failed.
  assertEquals(byUser.get("u1").total_workouts_done, 2);
  assertEquals(byUser.get("u2").total_workouts_done, 7);
  assertEquals(typeof byUser.get("u1").detected_experience_level, "string", "the level is still written");
  assert(
    errs.some((e: string) => e.includes("completed-days read failed")),
    "the failure is logged",
  );
});

// PRESENCE-ONLY: the call site is a one-line wiring the behavioural handler test above
// already exercises; kept so a revert to the old Set fails loudly even if a fixture is missed.
Deno.test("weekly-recalc: the floor comes from completedDayCounts, not a Set of exercise-row dates (presence-only)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(src.includes("completedDayCounts("));
  assertEquals(src.includes("new Set(userLogs.map"), false);
});
