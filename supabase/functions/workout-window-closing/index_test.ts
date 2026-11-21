import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildWindowClosingMessage } from "./message.ts";
import {
  deletedTemplateIds,
  excludeDeletedTemplateRows,
} from "./deleted_template_filter.ts";

Deno.test("buildWindowClosingMessage: with a name and workout name", () => {
  assertEquals(
    buildWindowClosingMessage("Rahul", "Push Day"),
    "Rahul — haven't seen Push Day logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("buildWindowClosingMessage: null name omits greeting", () => {
  assertEquals(
    buildWindowClosingMessage(null, "your workout"),
    "haven't seen your workout logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("workout-window-closing no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from workout-window-closing/index.ts");
  }
});

// OI-252 (stable ID rework) -- deleted_template_filter.ts.

Deno.test("deletedTemplateIds: collects only rows with a non-null deleted_at", () => {
  const ids = deletedTemplateIds([
    { id: "live-1", deleted_at: null },
    { id: "dead-1", deleted_at: "2026-09-26T00:00:00Z" },
    { id: "dead-2", deleted_at: "2026-09-25T00:00:00Z" },
  ]);
  assertEquals([...ids].sort(), ["dead-1", "dead-2"]);
});

Deno.test("deletedTemplateIds: empty input yields an empty set", () => {
  assertEquals(deletedTemplateIds([]).size, 0);
});

Deno.test("excludeDeletedTemplateRows: drops a user whose scheduled template is deleted", () => {
  const byUser = new Map([
    ["user-a", { template_id: "dead-1" }],
    ["user-b", { template_id: "live-1" }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-b"]);
});

Deno.test("excludeDeletedTemplateRows: a null template_id is NEVER excluded", () => {
  // This is exactly the case a `!inner` embed join would have wrongly
  // dropped (round-2 plan review) -- a plain, non-template workout day
  // must survive the filter regardless of what is deleted.
  const byUser = new Map([
    ["user-a", { template_id: null }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-a"]);
});

Deno.test("excludeDeletedTemplateRows: an unrelated deleted id does not affect a live row", () => {
  const byUser = new Map([
    ["user-a", { template_id: "live-1" }],
  ]);
  const kept = excludeDeletedTemplateRows(byUser, new Set(["dead-1"]));
  assertEquals([...kept.keys()], ["user-a"]);
});

// ════════════════════════════════════════════════════════════════════════════
// Coach workout parity 2 (OI-492): the 9 pm partial-day line, behavioural.
// ════════════════════════════════════════════════════════════════════════════
// deno-lint-ignore-file no-explicit-any
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { istDateStr } from "../_shared/ist_date.ts";
import { workoutLogIdForDate } from "../_shared/uuid_v5.ts";
import { loadPartialDays } from "../_shared/partial_day_loader.ts";
import type { PartialDayInfo } from "../_shared/partial_day_count.ts";
import { handler, realDeps } from "./index.ts";
import { selectWindowClosingMessage, windowClosingScreen } from "./message.ts";

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

const TODAY = istDateStr();
const pdInfo = (over: Partial<PartialDayInfo> = {}): PartialDayInfo => ({
  planned: 3,
  logged: 2,
  left: 1,
  workoutName: "Push Day",
  ...over,
});

// ── pure message selection (exact strings of plan 4.2) ──────────────────────

Deno.test("selectWindowClosingMessage: singular, with a name and the PLAN-ROW name", () => {
  assertEquals(
    selectWindowClosingMessage(pdInfo({ left: 1 }), "Rahul", "Template Name"),
    "Rahul — 1 exercise left in Push Day. Finish up and tap Complete.",
  );
});

Deno.test("selectWindowClosingMessage: plural", () => {
  assertEquals(
    selectWindowClosingMessage(pdInfo({ left: 2 }), "Rahul", "Template Name"),
    "Rahul — 2 exercises left in Push Day. Finish up and tap Complete.",
  );
});

Deno.test("selectWindowClosingMessage: without a name the line starts with the count", () => {
  assertEquals(
    selectWindowClosingMessage(pdInfo({ left: 1, workoutName: "your workout" }), null, "T"),
    "1 exercise left in your workout. Finish up and tap Complete.",
  );
});

Deno.test("selectWindowClosingMessage: null and left == 0 return buildWindowClosingMessage bytes with the TEMPLATE name (M20)", () => {
  const today = buildWindowClosingMessage("Rahul", "Template Name");
  assertEquals(selectWindowClosingMessage(null, "Rahul", "Template Name"), today);
  assertEquals(selectWindowClosingMessage(pdInfo({ left: 0 }), "Rahul", "Template Name"), today);
});

Deno.test("windowClosingScreen: partial -> /train, otherwise /ai_coach (M46)", () => {
  assertEquals(windowClosingScreen(pdInfo()), "/train");
  assertEquals(windowClosingScreen(null), "/ai_coach");
  assertEquals(windowClosingScreen(pdInfo({ left: 0 })), "/ai_coach");
});

// ── S0: the deps seam, default path ─────────────────────────────────────────

Deno.test("S0: realDeps() members are the imported originals (M51)", () => {
  const d = realDeps();
  assert(d.createClient === createClient);
  assert(d.sendPushNotification === sendPushNotification);
  assert(d.loadPartialDays === loadPartialDays);
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

// ── end-to-end handler(req, fakeDeps) ───────────────────────────────────────

const tables = () => ({
  scheduled_workouts: [
    { id: 1, user_id: "u1", template_id: "t1", scheduled_date: TODAY, status: "planned" },
    { id: 2, user_id: "u2", template_id: "t1", scheduled_date: TODAY, status: "planned" },
  ],
  workout_logs: [] as any[],
  users: [{ id: "u1", full_name: "Asha Rao" }, { id: "u2", full_name: "Ben Lee" }],
  workout_templates: [{ id: "t1", name: "Template Push", deleted_at: null }],
  user_preferences: [] as any[],
  user_daily_snapshots: [] as any[],
  coach_memory: [] as any[],
  user_progress: [] as any[],
  workout_log_exercises: [] as any[],
});

function mkDeps(fake: ReturnType<typeof makeFake>, load?: (...a: any[]) => Promise<Map<string, PartialDayInfo>>) {
  const sent: any[] = [];
  const loaderCalls: string[][] = [];
  const deps = {
    createClient: (() => fake.sb) as any,
    loadPartialDays: (async (sb: any, ids: string[], today: string) => {
      loaderCalls.push(ids);
      return load ? await load(sb, ids, today) : new Map<string, PartialDayInfo>();
    }) as any,
    sendPushNotification: (async (p: any) => {
      sent.push(p);
      return true;
    }) as any,
  };
  return { deps, sent, loaderCalls };
}

async function run(deps: any) {
  return await withFetchStub((urls) =>
    withCronSecret(async () => {
      const { out } = await quiet(() => handler(authedPost(), deps));
      const body = await out.json();
      assertNoStrayRequests(urls);
      return { status: out.status, body };
    })
  );
}

const byUser = (sent: any[], id: string) => sent.find((p) => p.userId === id);

Deno.test("handler: the partial user gets the partial line + /train, the null user keeps today's line + /ai_coach (M46, M19, M22)", async () => {
  const fake = makeFake(tables());
  const { deps, sent, loaderCalls } = mkDeps(fake, async () => new Map([["u1", pdInfo({ left: 1 })]]));
  const { status, body } = await run(deps);
  assertEquals(status, 200);
  assertEquals(loaderCalls, [["u1", "u2"]]);
  assertEquals(sent.length, 2);
  const a = byUser(sent, "u1");
  assertEquals(a.title, "Workout window closing");
  assertEquals(a.message, "Asha — 1 exercise left in Push Day. Finish up and tap Complete.");
  assertEquals(a.screen, "/train");
  const b = byUser(sent, "u2");
  assertEquals(b.title, "Workout window closing");
  assertEquals(b.message, buildWindowClosingMessage("Ben", "Template Push"));
  assertEquals(b.screen, "/ai_coach");
  assertEquals(body.partial_sent, 1);
  assertEquals(body.partial_fallback, 1);
  assertEquals(body.notifications_sent, 2);
});

Deno.test("handler: a loader that returns an empty map (a failed read) still sends today's lines", async () => {
  const fake = makeFake(tables());
  const { deps, sent } = mkDeps(fake, async () => new Map());
  const { body } = await run(deps);
  assertEquals(sent.length, 2);
  for (const p of sent) assertEquals(p.screen, "/ai_coach");
  assertEquals(body.partial_sent, 0);
  assertEquals(body.partial_fallback, 2);
});

Deno.test("handler: a loadPartialDays that THROWS still sends today's lines and /ai_coach for every at-risk user (M49)", async () => {
  const fake = makeFake(tables());
  const { deps, sent } = mkDeps(fake, async () => {
    throw new Error("loader blew up");
  });
  const { status } = await run(deps);
  assertEquals(status, 200);
  assertEquals(sent.length, 2);
  assertEquals(byUser(sent, "u1").message, buildWindowClosingMessage("Asha", "Template Push"));
  for (const p of sent) assertEquals(p.screen, "/ai_coach");
});

// ── over the REAL loader (B3-F6, B4-F8) ─────────────────────────────────────

async function realLoaderTables() {
  const t = tables();
  const todayId = await workoutLogIdForDate(TODAY);
  t.user_progress = [{
    id: 1,
    user_id: "u1",
    today_row: {
      workout_name: "Push Day",
      type: "strength",
      status: "planned",
      exercises: [{ exercise_name: "Bench Press" }, { exercise_name: "Row" }, { exercise_name: "Fly" }],
    },
  }];
  t.workout_log_exercises = [{
    id: 1,
    user_id: "u1",
    workout_log_id: todayId,
    exercise_id: "Bench Press",
    exercise_name: "Bench Press",
    deleted_at: null,
  }];
  return t;
}

Deno.test("handler over the REAL loader, kill switch ON: today's bytes (message AND /ai_coach screen), no loader reads (B3-F6, M27)", async () => {
  const fake = makeFake(await realLoaderTables());
  const { sent } = await withEnv("DISABLE_PARTIAL_DAY_REMINDER", "true", async () => {
    const { deps, sent } = mkDeps(fake);
    deps.loadPartialDays = realDeps().loadPartialDays;
    await run(deps);
    return { sent };
  });
  const a = byUser(sent, "u1");
  assertEquals(a.message, buildWindowClosingMessage("Asha", "Template Push"));
  assertEquals(a.screen, "/ai_coach");
  assertEquals(a.title, "Workout window closing");
  assertEquals(
    fake.queries.filter((q) => q.table === "user_progress" || q.table === "workout_log_exercises").length,
    0,
    "the kill switch must not read",
  );
});

Deno.test("handler over the REAL loader, kill switch UNSET (mirror): the partial-day line and /train (B4-F8)", async () => {
  const fake = makeFake(await realLoaderTables());
  const { sent } = await withEnv("DISABLE_PARTIAL_DAY_REMINDER", undefined, async () => {
    const { deps, sent } = mkDeps(fake);
    deps.loadPartialDays = realDeps().loadPartialDays;
    await run(deps);
    return { sent };
  });
  const a = byUser(sent, "u1");
  assertEquals(a.message, "Asha — 2 exercises left in Push Day. Finish up and tap Complete.");
  assertEquals(a.screen, "/train");
  // u2 has no plan row -> today's line.
  assertEquals(byUser(sent, "u2").screen, "/ai_coach");
});
