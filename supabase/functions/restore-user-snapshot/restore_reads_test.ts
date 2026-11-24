// Behavioural tests for restore-user-snapshot/restore_reads.ts (OI-348 B10, diagnose a0d5f7).
//
// Parity is checked against a GOLDEN, not against the new code itself:
// testdata/restore_bundle.golden.json was recorded ONCE by running the e28cdab8 serial assembly
// (the body of that commit's index.ts, verbatim, in a throwaway harness) against the same fake DB
// (fake_restore_db.ts). The new assembly must produce the same bundle, byte for byte, at limit 1
// and limit 3, and issue the same request chains (an order-independent multiset per table; the
// `gt("expires_at", now)` argument is a placeholder). The golden proves only what the fake can see:
// no embeds resolved, no RLS.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/restore-user-snapshot/

import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { canonicalCalls, makeFakeDb, ME, restoreDataset, type Row } from "./fake_restore_db.ts";
import { createPageBudget, PAGED_READ_NAMES, TOTAL_PAGE_BUDGET } from "./paged_reads.ts";
import {
  assembleTables,
  DEFAULT_READ_CONCURRENCY,
  parseReadConcurrency,
  READS,
  runLimited,
  timingLogLine,
} from "./restore_reads.ts";

const golden = JSON.parse(
  await Deno.readTextFile(new URL("./testdata/restore_bundle.golden.json", import.meta.url)),
) as { tables: Record<string, unknown>; calls: Record<string, string[]> };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Latencies that make reads finish OUT of input order (later tables faster).
function skewedLatency(): Record<string, number> {
  const tables = [
    "user_profile", "users", "user_progress", "user_preferences", "workout_templates",
    ...PAGED_READ_NAMES, "streaks", "user_saved_meals", "ai_coach_interactions", "coach_memory",
    "notifications_inbox", "saved_diet_plans", "rank_promotions", "referral_codes",
    "referral_redemptions",
  ];
  return Object.fromEntries(tables.map((t, i) => [t, ((tables.length - i) * 7) % 23]));
}

async function assemble(limit: number, o: { latency?: Record<string, number>; failTable?: string } = {}) {
  const db = makeFakeDb(restoreDataset(), o);
  const lines: string[] = [];
  const out = await assembleTables(db, ME, createPageBudget(), limit, {
    authMs: 12.4,
    requestId: "req1",
    log: (l) => lines.push(l),
  });
  return { ...out, db, lines };
}

// ── parity with the e28cdab8 serial code ─────────────────────────────────────────────────────

for (const limit of [1, 3]) {
  Deno.test(`limit=${limit}: the bundle equals the golden recorded from the serial code, byte for byte`, async () => {
    const { tables } = await assemble(limit, { latency: skewedLatency() });
    assertEquals(JSON.stringify(tables), JSON.stringify(golden.tables));
  });

  Deno.test(`limit=${limit}: every request chain equals the golden's (per table, order-independent)`, async () => {
    const { db } = await assemble(limit, { latency: skewedLatency() });
    assertEquals(canonicalCalls(db.calls), golden.calls);
  });
}

Deno.test("READS: 29 unique names, in the golden's key order", () => {
  const names = READS.map(([n]) => n);
  assertEquals(names.length, 29);
  assertEquals(new Set(names).size, 29);
  assertEquals(names, Object.keys(golden.tables));
});

Deno.test("READS kinds: every paged name is a paged read, and only those", () => {
  const paged = READS.filter(([, k]) => k === "paged").map(([n]) => n);
  assertEquals(paged.sort(), [...PAGED_READ_NAMES, "ai_coach_interactions"].sort());
});

// ── runLimited ─────────────────────────────────────────────────────────────────────────────

Deno.test("runLimited never has more than `limit` in flight, and returns INPUT order", async () => {
  for (const limit of [1, 2, 3, 8]) {
    let inFlight = 0;
    let max = 0;
    const thunks = Array.from({ length: 12 }, (_, i) => async () => {
      inFlight++;
      max = Math.max(max, inFlight);
      await sleep((12 - i) % 5);
      inFlight--;
      return i;
    });
    const out = await runLimited(thunks, limit);
    assertEquals(out, Array.from({ length: 12 }, (_, i) => i));
    assert(max <= limit, `limit ${limit}: ${max} in flight`);
    if (limit > 1) assert(max > 1, `limit ${limit}: never ran in parallel`);
  }
});

Deno.test("runLimited: a thunk is not called before its slot is free (lazy)", async () => {
  const called: number[] = [];
  const gates: (() => void)[] = [];
  const thunks = Array.from({ length: 6 }, (_, i) => () => {
    called.push(i);
    return new Promise<number>((r) => gates.push(() => r(i)));
  });
  const p = runLimited(thunks, 2);
  await sleep(1);
  assertEquals(called, [0, 1]);
  gates[0]();
  await sleep(1);
  assertEquals(called, [0, 1, 2]);
  while (gates.length < 6 || called.length < 6) {
    gates.forEach((g) => g());
    await sleep(1);
  }
  gates.forEach((g) => g());
  assertEquals(await p, [0, 1, 2, 3, 4, 5]);
});

Deno.test("runLimited: the first error rejects only after the in-flight reads settle, and starts nothing new", async () => {
  const called: number[] = [];
  let slowDone = false;
  const thunks = [
    () => { called.push(0); return sleep(1).then(() => { throw new Error("first"); }); },
    () => { called.push(1); return sleep(30).then(() => { slowDone = true; return 1; }); },
    () => { called.push(2); return Promise.reject(new Error("second")); },
    () => { called.push(3); return Promise.resolve(3); },
  ];
  await assertRejects(() => runLimited(thunks, 2), Error, "first");
  assert(slowDone, "rejected before the in-flight read settled");
  assertEquals(called, [0, 1], "a read started after the first failure");
});

Deno.test("runLimited: a thunk that throws synchronously is a rejection; empty input resolves []", async () => {
  await assertRejects(() => runLimited([() => { throw new Error("sync"); }], 3), Error, "sync");
  assertEquals(await runLimited([], 3), []);
});

// ── the assembly ───────────────────────────────────────────────────────────────────────────

Deno.test("assembleTables keeps the fake DB's in-flight requests at or under the limit", async () => {
  for (const limit of [1, 3]) {
    const { db } = await assemble(limit, { latency: skewedLatency() });
    assert(db.stats.maxInFlight <= limit, `limit ${limit}: ${db.stats.maxInFlight}`);
  }
  const { db } = await assemble(3, { latency: skewedLatency() });
  assert(db.stats.maxInFlight > 1, "limit 3 never overlapped two requests");
});

Deno.test("assembleTables builds no request before its slot: at most `limit` builders exist early", async () => {
  const db = makeFakeDb(restoreDataset(), { latency: Object.fromEntries(
    Object.keys(golden.calls).map((t) => [t, 40]),
  ) });
  const p = assembleTables(db, ME, createPageBudget(), 2, { authMs: 0, requestId: "r", log: () => {} });
  await sleep(5);
  assert(db.stats.fromCalls <= 2, `${db.stats.fromCalls} builders created with 2 slots`);
  await p;
});

Deno.test("one failed read rejects the whole assembly (index.ts maps it to the 500)", async () => {
  for (const failTable of ["users", "weight_logs", "referral_redemptions"]) {
    const db = makeFakeDb(restoreDataset(), { failTable });
    const lines: string[] = [];
    const e = await assertRejects(() =>
      assembleTables(db, ME, createPageBudget(), 3, { authMs: 1, requestId: "r", log: (l) => lines.push(l) })
    );
    assertStringIncludes(String(e), failTable === "weight_logs" ? "failed" : `query_failed:${failTable}`);
    assertEquals(lines.length, 1, "the timing line is written even on a failure");
    assertStringIncludes(lines[0], "ok=false");
  }
});

Deno.test("the page budget still binds under concurrency: 13 tables over budget throw 'page budget exhausted'", async () => {
  // 13 tables x 10 pages (9,500 rows each at 1,000 a page, then the empty page) = 130 > 120.
  const data: Record<string, Row[]> = restoreDataset();
  for (const t of PAGED_READ_NAMES) {
    data[t] = Array.from({ length: 9500 }, (_, i) => ({
      user_id: ME, id: `${t}-${String(i).padStart(6, "0")}`, created_at: "2026-11-10T00:00:00Z",
      completed_at: "2026-11-10T00:00:00Z", date: "2026-11-10", scheduled_date: "2026-11-10",
    }));
  }
  for (const limit of [1, 3, 8]) {
    const db = makeFakeDb(data);
    const budget = createPageBudget();
    await assertRejects(
      () => assembleTables(db, ME, budget, limit, { authMs: 0, requestId: "r", log: () => {} }),
      Error,
      "page budget exhausted",
    );
    const pageRequests = db.calls.filter((c) => PAGED_READ_NAMES.includes(c.table)).length;
    assert(pageRequests <= TOTAL_PAGE_BUDGET, `${pageRequests} page requests at limit ${limit}`);
  }
});

Deno.test("under budget: 13 tables of 3,000 rows each pass at limit 3 (no starvation)", async () => {
  const data: Record<string, Row[]> = restoreDataset();
  for (const t of PAGED_READ_NAMES) {
    data[t] = Array.from({ length: 3000 }, (_, i) => ({
      user_id: ME, id: `${t}-${String(i).padStart(6, "0")}`, created_at: "2026-11-10T00:00:00Z",
      completed_at: "2026-11-10T00:00:00Z", date: "2026-11-10", scheduled_date: "2026-11-10",
    }));
  }
  const { tables } = await assembleTables(makeFakeDb(data), ME, createPageBudget(), 3, {
    authMs: 0, requestId: "r", log: () => {},
  });
  for (const t of PAGED_READ_NAMES) assertEquals((tables[t] as unknown[]).length, 3000, t);
});

// ── the timing line ────────────────────────────────────────────────────────────────────────

Deno.test("the timing line: names and numbers only, in READS order, finished reads only", async () => {
  const { lines } = await assemble(3);
  assertEquals(lines.length, 1);
  const line = lines[0];
  assert(line.startsWith("restore_timings request_id=req1 auth_ms=12 reads_ms="), line);
  assertStringIncludes(line, " limit=3 ok=true ");
  const names = [...line.matchAll(/ ([a-z_]+)_ms=\d+/g)].map((m) => m[1]).filter((n) => n !== "auth" && n !== "reads");
  assertEquals(names, READS.map(([n]) => n));
  assert(!line.includes(ME), "the line must not carry the user id");
  assert(!line.includes("P-a"), "the line must not carry a row value");
});

Deno.test("timingLogLine omits a read that did not finish", () => {
  const line = timingLogLine({
    requestId: "x", authMs: 1, readsMs: 2, limit: 1, ok: false, timings: { users: 5 },
  });
  assertEquals(line, "restore_timings request_id=x auth_ms=1 reads_ms=2 limit=1 ok=false users_ms=5");
});

// ── RESTORE_READ_CONCURRENCY ───────────────────────────────────────────────────────────────

Deno.test("parseReadConcurrency: the clamp table", () => {
  const table: [string | undefined | null, number][] = [
    [undefined, 3], [null, 3], ["", 3], ["  ", 3],
    ["abc", 1], ["3abc", 1], ["2.5", 1], ["Infinity", 1], ["NaN", 1],
    ["1e1", 8], ["0x10", 8], ["99", 8],
    ["0", 1], ["-1", 1],
    ["1", 1], ["2", 2], [" 4 ", 4], ["8", 8],
  ];
  for (const [raw, want] of table) assertEquals(parseReadConcurrency(raw), want, String(raw));
  assertEquals(DEFAULT_READ_CONCURRENCY, 3);
});
