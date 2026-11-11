import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { pickStreakMessage } from "./message.ts";

Deno.test("pickStreakMessage: day 7 milestone", () => {
  const r = pickStreakMessage({ streakDays: 7, streakWeeks: 1, weight: null, targetWeight: null });
  assertEquals(r.title, "1 week strong!");
  assertEquals(r.message, "You've hit 7 days straight — that's the hardest week done. Don't stop now!");
});

Deno.test("pickStreakMessage: day 14 milestone", () => {
  const r = pickStreakMessage({ streakDays: 14, streakWeeks: 2, weight: null, targetWeight: null });
  assertEquals(r.title, "2 weeks! You're building a habit.");
  assertEquals(r.message, "14 days of consistency. Most people quit by now — you didn't. Keep going!");
});

Deno.test("pickStreakMessage: day 30 milestone", () => {
  const r = pickStreakMessage({ streakDays: 30, streakWeeks: 4, weight: null, targetWeight: null });
  assertEquals(r.title, "30-day warrior!");
});

Deno.test("pickStreakMessage: day 50 milestone", () => {
  const r = pickStreakMessage({ streakDays: 50, streakWeeks: 7, weight: null, targetWeight: null });
  assertEquals(r.title, "50 days. Legendary.");
});

Deno.test("pickStreakMessage: day 100 milestone", () => {
  const r = pickStreakMessage({ streakDays: 100, streakWeeks: 14, weight: null, targetWeight: null });
  assertEquals(r.title, "100-DAY STREAK!");
});

Deno.test("pickStreakMessage: every-10-day milestone (e.g. 60) uses the templated title/message", () => {
  const r = pickStreakMessage({ streakDays: 60, streakWeeks: 8, weight: null, targetWeight: null });
  assertEquals(r.title, "60-day milestone!");
  assertEquals(r.message, "60 days of showing up. That's elite. Don't let today be the one you miss.");
});

Deno.test("pickStreakMessage: near goal weight (within 2kg) takes priority over the standard nudge", () => {
  const r = pickStreakMessage({ streakDays: 12, streakWeeks: 1, weight: 70, targetWeight: 71 });
  assertEquals(r.title, "Almost at your goal weight!");
});

Deno.test("pickStreakMessage: standard nudge rotates through 4 variants by streakDays % 4, title fixed", () => {
  const seen = new Set<string>();
  for (const days of [12, 13, 22, 23]) {
    const r = pickStreakMessage({ streakDays: days, streakWeeks: 2, weight: null, targetWeight: null });
    assertEquals(r.title, "Don't break your streak!");
    seen.add(r.message);
  }
  assertEquals(seen.size, 4);
});

Deno.test("streak-guardian no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from streak-guardian/index.ts");
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Coach workout parity 2 (OI-492): the 8 pm partial-day line, behavioural.
// ════════════════════════════════════════════════════════════════════════════
// deno-lint-ignore-file no-explicit-any
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { loadPartialDays } from "../_shared/partial_day_loader.ts";
import type { PartialDayInfo } from "../_shared/partial_day_count.ts";
import { handler, realDeps } from "./index.ts";
import { selectStreakMessage } from "./message.ts";

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

const pdInfo = (over: Partial<PartialDayInfo> = {}): PartialDayInfo => ({
  planned: 3,
  logged: 2,
  left: 1,
  workoutName: "Push Day",
  ...over,
});

// One input per message family of pickStreakMessage (11 families).
const FAMILIES: Array<{ name: string; input: { streakDays: number; streakWeeks: number; weight: number | null; targetWeight: number | null } }> = [
  { name: "day 7", input: { streakDays: 7, streakWeeks: 1, weight: null, targetWeight: null } },
  { name: "day 14", input: { streakDays: 14, streakWeeks: 2, weight: null, targetWeight: null } },
  { name: "day 30", input: { streakDays: 30, streakWeeks: 4, weight: null, targetWeight: null } },
  { name: "day 50", input: { streakDays: 50, streakWeeks: 7, weight: null, targetWeight: null } },
  { name: "day 100", input: { streakDays: 100, streakWeeks: 14, weight: null, targetWeight: null } },
  { name: "every-10 milestone", input: { streakDays: 60, streakWeeks: 8, weight: null, targetWeight: null } },
  { name: "near goal weight", input: { streakDays: 12, streakWeeks: 1, weight: 70, targetWeight: 71 } },
  { name: "standard 0", input: { streakDays: 12, streakWeeks: 2, weight: null, targetWeight: null } },
  { name: "standard 1", input: { streakDays: 13, streakWeeks: 2, weight: null, targetWeight: null } },
  { name: "standard 2", input: { streakDays: 22, streakWeeks: 2, weight: null, targetWeight: null } },
  { name: "standard 3", input: { streakDays: 23, streakWeeks: 2, weight: null, targetWeight: null } },
];

Deno.test("selectStreakMessage: exact string of plan 4.3 for left 1 and 2+", () => {
  const input = { streakDays: 9, streakWeeks: 2, weight: null, targetWeight: null };
  assertEquals(
    selectStreakMessage({ ...input, partialDay: pdInfo({ left: 1 }) }).message,
    "1 exercise left in Push Day. Finish and tap Complete to keep your 9-day streak.",
  );
  assertEquals(
    selectStreakMessage({ ...input, partialDay: pdInfo({ left: 2, workoutName: "Leg Day" }) }).message,
    "2 exercises left in Leg Day. Finish and tap Complete to keep your 9-day streak.",
  );
});

Deno.test("selectStreakMessage: the title equals pickStreakMessage's for ALL 11 families; the partial line is the same shape for each (M22)", () => {
  assertEquals(FAMILIES.length, 11);
  for (const f of FAMILIES) {
    const picked = pickStreakMessage(f.input);
    const sel = selectStreakMessage({ ...f.input, partialDay: pdInfo({ left: 2 }) });
    assertEquals(sel.title, picked.title, f.name);
    assertEquals(
      sel.message,
      `2 exercises left in Push Day. Finish and tap Complete to keep your ${f.input.streakDays}-day streak.`,
      f.name,
    );
  }
});

Deno.test("selectStreakMessage: partialDay null / undefined / left == 0 return today's bytes for all 11 families", () => {
  for (const f of FAMILIES) {
    const picked = pickStreakMessage(f.input);
    assertEquals(selectStreakMessage({ ...f.input, partialDay: null }), picked, f.name);
    assertEquals(selectStreakMessage({ ...f.input }), picked, f.name);
    assertEquals(selectStreakMessage({ ...f.input, partialDay: pdInfo({ left: 0 }) }), picked, f.name);
  }
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
  user_progress: [
    { id: 1, user_id: "u1", current_streak_weeks: 2, current_streak_days: 9 },
    { id: 2, user_id: "u2", current_streak_weeks: 2, current_streak_days: 12 },
    { id: 3, user_id: "u3", current_streak_weeks: 3, current_streak_days: 20 },
  ],
  workout_logs: [] as any[],
  user_preferences: [
    // u3 switched streak alerts off
    { id: 1, user_id: "u3", notification_preferences: { streak_alerts: { enabled: false } } },
  ],
  user_daily_snapshots: [] as any[],
  coach_memory: [] as any[],
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

Deno.test("handler: the loader's partial user gets the partial line with the family title; the null user keeps today's message (M22 second form)", async () => {
  const fake = makeFake(tables());
  const { deps, sent } = mkDeps(fake, async () => new Map([["u1", pdInfo({ left: 1 })]]));
  const { status } = await run(deps);
  assertEquals(status, 200);
  const a = byUser(sent, "u1");
  assertEquals(a.title, pickStreakMessage({ streakDays: 9, streakWeeks: 2, weight: null, targetWeight: null }).title);
  assertEquals(a.message, "1 exercise left in Push Day. Finish and tap Complete to keep your 9-day streak.");
  assertEquals(a.screen, "/train");
  const b = byUser(sent, "u2");
  assertEquals(
    b.message,
    pickStreakMessage({ streakDays: 12, streakWeeks: 2, weight: null, targetWeight: null }).message,
  );
  assertEquals(byUser(sent, "u3"), undefined, "u3 switched streak alerts off");
});

Deno.test("handler: the loader receives ONLY users that pass the preference gate", async () => {
  const fake = makeFake(tables());
  const { deps, loaderCalls } = mkDeps(fake);
  await run(deps);
  assertEquals(loaderCalls.length, 1);
  assertEquals([...loaderCalls[0]].sort(), ["u1", "u2"]);
});

Deno.test("handler: prefsDegraded -> the loader is called with [] and nothing is sent", async () => {
  const fake = makeFake(tables(), (q) => q.table === "user_preferences");
  const { deps, loaderCalls, sent } = mkDeps(fake);
  await run(deps);
  assertEquals(loaderCalls, [[]]);
  assertEquals(sent.length, 0);
});

Deno.test("handler: a loadPartialDays that THROWS still sends today's family message for every eligible user (M49)", async () => {
  const fake = makeFake(tables());
  const { deps, sent } = mkDeps(fake, async () => {
    throw new Error("loader blew up");
  });
  const { status } = await run(deps);
  assertEquals(status, 200);
  assertEquals(sent.length, 2);
  assertEquals(
    byUser(sent, "u1").message,
    pickStreakMessage({ streakDays: 9, streakWeeks: 2, weight: null, targetWeight: null }).message,
  );
});
