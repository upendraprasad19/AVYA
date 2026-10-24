// OI-341 Piece B1: tests of `reportPaymentRecordFailure` (docs/plans/oi341-piece-b-door.md 2.3, 3b).
// The REAL supabase-js client runs over the fetch-level fake; the `alerts` table is answered by the
// harness's `alertsIntercept` (the fake's evaluator does not model `->>` JSON paths or `gte`), so the
// dedup query is asserted as the exact RECORDED query string.
import { assert, assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  checkStackingMismatch,
  type MismatchCheck,
  PAYMENT_ALERT_SOURCE,
  type PaymentRecordFailure,
  reportPaymentRecordFailure,
  reportStackingMismatch,
  STACKING_MISMATCH_SOURCE,
} from "./payment_alert.ts";
import { FAKE_ORIGIN, FakeServer } from "./postgrest_fake_fetch.ts";
import { alertInserts, type AlertsBehavior, alertsIntercept, captureConsole } from "./payment_writer_harness.ts";

const FAILURE: PaymentRecordFailure = {
  fn: "verify-payment",
  requestId: "abcd1234",
  paymentId: "pay_NEW0000000001",
  userId: "11111111-1111-4111-8111-111111111111",
  plan: "monthly",
  amountPaise: 34900,
  code: "55P03",
};

async function report(b: AlertsBehavior, f: PaymentRecordFailure = FAILURE) {
  const server = new FakeServer({ intercept: alertsIntercept(b) });
  server.install();
  const db = createClient(FAKE_ORIGIN, "service-role", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  try {
    const started = Date.now();
    const { errors } = await captureConsole(() => reportPaymentRecordFailure(db, f));
    const elapsed = Date.now() - started;
    const inserts = alertInserts(server);
    return {
      server,
      errors,
      elapsed,
      inserts,
      row: (inserts[0]?.body ?? null) as Record<string, unknown> | null,
      reads: server.to("/rest/v1/alerts", "GET"),
    };
  } finally {
    server.restore();
  }
}

Deno.test("the alert row: non-empty summary, source, ids + code in context_json, no message text", async () => {
  const r = await report({});
  assertEquals(r.inserts.length, 1);
  const row = r.row!;
  assertEquals(typeof row.summary, "string");
  assert((row.summary as string).length > 0, "summary is NOT NULL in the table: it must be non-empty");
  assert((row.summary as string).includes("verify-payment") && (row.summary as string).includes("55P03"));
  assertEquals(row.source, "payment_record_failed");
  assertEquals(PAYMENT_ALERT_SOURCE, "payment_record_failed");
  assertEquals(row.context_json, {
    fn: "verify-payment",
    request_id: "abcd1234",
    payment_id: "pay_NEW0000000001",
    user_id: "11111111-1111-4111-8111-111111111111",
    plan: "monthly",
    amount_paise: 34900,
    code: "55P03",
  });
  assertEquals(typeof row.suggested_action, "string");
  assert(!JSON.stringify(row).toLowerCase().includes("message"), "no error message text anywhere in the row");
});

Deno.test("severity: the first failure (dedup read returns []) is critical", async () => {
  const r = await report({ dedup: "none" });
  assertEquals(r.row!.severity, "critical");
});

Deno.test("severity: a prior unresolved row for the same payment makes the next one warn", async () => {
  const r = await report({ dedup: "existing" });
  assertEquals(r.row!.severity, "warn");
  assertEquals(r.inserts.length, 1, "a warn row is still written");
});

Deno.test("severity: a failed dedup read falls back to critical", async () => {
  const r = await report({ dedup: "error" });
  assertEquals(r.row!.severity, "critical");
});

Deno.test("severity: a dedup read that never answers is critical within about 3.5 s", async () => {
  const r = await report({ dedup: "hang" });
  assertEquals(r.row!.severity, "critical");
  assert(r.elapsed >= 2900, `the bound is 3 s, took ${r.elapsed} ms`);
  assert(r.elapsed < 3500, `must be bounded near 3 s, took ${r.elapsed} ms`);
});

Deno.test("an insert that never answers is bounded too, and does not throw", async () => {
  const r = await report({ insert: "hang" });
  assertEquals(r.inserts.length, 1);
  assert(r.elapsed < 3500, `took ${r.elapsed} ms`);
  assert(r.errors.some((e) => e.includes("alerts insert failed")));
});

Deno.test("an insert error does not throw and is logged without the payload", async () => {
  const r = await report({ insert: "error" });
  assertEquals(r.inserts.length, 1);
  assert(r.errors.some((e) => e.includes("alerts insert failed") && e.includes(FAILURE.paymentId)));
  assert(!r.errors.join("\n").includes("XX000"), "the error body is not echoed");
});

Deno.test("a thrown client does not escape", async () => {
  const exploding = { from: () => { throw new Error("sync boom"); } };
  const { errors } = await captureConsole(() => reportPaymentRecordFailure(exploding, FAILURE));
  assert(errors.some((e) => e.includes("threw")));
});

Deno.test("the dedup query: this source, this payment_id (JSON path), UNRESOLVED only, 24 h window, limit 1", async () => {
  const before = Date.now();
  const r = await report({});
  const after = Date.now();
  assertEquals(r.reads.length, 1);
  const q = r.reads[0].query;
  const get = (k: string) => q.filter(([key]) => key === k).map(([, v]) => v);
  assertEquals(get("select"), ["id"]);
  assertEquals(get("source"), ["eq.payment_record_failed"]);
  assertEquals(get("context_json->>payment_id"), ["eq.pay_NEW0000000001"]);
  assertEquals(get("resolved_at"), ["is.null"], "an earlier RESOLVED alert must not suppress a new page");
  assertEquals(get("limit"), ["1"]);
  const gte = get("detected_at");
  assertEquals(gte.length, 1);
  assert(gte[0].startsWith("gte."));
  const since = Date.parse(gte[0].slice(4));
  assert(since >= before - 24 * 3600 * 1000 && since <= after - 24 * 3600 * 1000, "window starts 24 h ago");
});

Deno.test("a different payment id is a different dedup key", async () => {
  const r = await report({}, { ...FAILURE, paymentId: "pay_OTHER00000002" });
  assertNotEquals(r.reads[0].query.find(([k]) => k === "context_json->>payment_id")![1], "eq.pay_NEW0000000001");
});

Deno.test("importing payment_alert.ts performs no Deno.env read and no fetch", async () => {
  const modulePath = new URL("./payment_alert.ts", import.meta.url).href;
  // Run with NO permissions (a Deno.env read would throw NotCapable) and with env.get / fetch stubbed to throw.
  const script = `
    const trips = [];
    const origGet = Deno.env.get;
    try { Deno.env.get = (n) => { trips.push("env:" + n); throw new Error("env read at import"); }; } catch (_) { /* not assignable */ }
    globalThis.fetch = (...a) => { trips.push("fetch"); throw new Error("fetch at import"); };
    await import(${JSON.stringify(modulePath)});
    Deno.env.get = origGet;
    console.log(trips.length === 0 ? "clean" : "TRIPPED " + trips.join(","));
  `;
  const out = await new Deno.Command(Deno.execPath(), {
    args: ["eval", "--no-check", "--no-prompt", "--node-modules-dir=none", script],
    stdout: "piped",
    stderr: "piped",
  }).output();
  const text = new TextDecoder().decode(out.stdout).trim();
  assertEquals(text, "clean", new TextDecoder().decode(out.stderr));
});

// ── OI-341 Piece B2a (docs/plans/oi341-piece-b2-door.md 2.4, 2.5) ──────────

function client() {
  return createClient(FAKE_ORIGIN, "service-role", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

Deno.test("timeoutMs: a hung dedup read with timeoutMs 1000 is bounded near 1 s (the webhook's setting)", async () => {
  const server = new FakeServer({ intercept: alertsIntercept({ dedup: "hang" }) });
  server.install();
  try {
    const started = Date.now();
    await captureConsole(() => reportPaymentRecordFailure(client(), FAILURE, { timeoutMs: 1000 }));
    const ms = Date.now() - started;
    assert(ms >= 900 && ms < 2500, `took ${ms} ms`);
    assertEquals((alertInserts(server)[0].body as Record<string, unknown>).severity, "critical");
  } finally {
    server.restore();
  }
});

const MISMATCH = {
  fn: "razorpay-webhook" as const,
  paymentId: "pay_NEW0000000001",
  userId: "11111111-1111-4111-8111-111111111111",
  plan: "monthly",
  rowEnd: "2026-11-20T10:00:00.000Z",
  trialEnd: "2026-10-25T10:00:00.000Z",
};

Deno.test("reportStackingMismatch: its OWN source in BOTH the dedup query and the insert, neutral wording", async () => {
  const server = new FakeServer({ intercept: alertsIntercept({}) });
  server.install();
  try {
    await captureConsole(() => reportStackingMismatch(client(), MISMATCH));
    const reads = server.to("/rest/v1/alerts", "GET");
    assertEquals(reads.length, 1);
    assert(reads[0].query.some(([k, v]) => k === "source" && v === `eq.${STACKING_MISMATCH_SOURCE}`));
    assert(reads[0].query.some(([k, v]) => k === "context_json->>payment_id" && v === "eq.pay_NEW0000000001"));
    const row = alertInserts(server)[0].body as Record<string, any>;
    assertEquals(STACKING_MISMATCH_SOURCE, "stacking_switch_mismatch");
    assertEquals(row.source, "stacking_switch_mismatch");
    assertEquals(row.severity, "critical");
    assertEquals(row.context_json, {
      fn: "razorpay-webhook",
      payment_id: "pay_NEW0000000001",
      user_id: "11111111-1111-4111-8111-111111111111",
      plan: "monthly",
      row_end: "2026-11-20T10:00:00.000Z",
      trial_end: "2026-10-25T10:00:00.000Z",
    });
    assert(String(row.summary).includes("row ends 2026-11-20T10:00:00.000Z, trial ends 2026-10-25T10:00:00.000Z"));
    assert(String(row.suggested_action).includes("WAS written"));
    assert(String(row.suggested_action).includes("mid-checkout"), "both causes are named");
  } finally {
    server.restore();
  }
});

Deno.test("reportStackingMismatch: a prior unresolved mismatch row for the payment makes the next one warn", async () => {
  const server = new FakeServer({ intercept: alertsIntercept({ dedup: "existing" }) });
  server.install();
  try {
    await captureConsole(() => reportStackingMismatch(client(), MISMATCH));
    assertEquals((alertInserts(server)[0].body as Record<string, unknown>).severity, "warn");
  } finally {
    server.restore();
  }
});

Deno.test("reportPaymentRecordFailure still dedups on payment_record_failed (the source is not shared)", async () => {
  const r = await report({});
  assert(r.reads[0].query.some(([k, v]) => k === "source" && v === "eq.payment_record_failed"));
});

const CHECK: MismatchCheck = {
  fn: "verify-payment",
  paymentId: "pay_NEW0000000001",
  userId: "11111111-1111-4111-8111-111111111111",
  plan: "monthly",
  rowStart: "2026-10-21T10:00:00.000Z",
  rowEnd: "2026-11-20T10:00:00.000Z",
};

Deno.test("checkStackingMismatch: a THROWING client is caught and logged; it never throws", async () => {
  const exploding = { from: () => { throw new Error("sync boom"); } };
  const { errors } = await captureConsole(() => checkStackingMismatch(exploding, CHECK));
  assert(errors.some((e) => e.startsWith("[verify-payment] stacking mismatch check threw payment_id=pay_NEW0000000001")));
  assert(!errors.join("\n").includes("sync boom"), "the error message is not logged");
});

Deno.test("checkStackingMismatch: a HUNG read is released near 1 s with no alert", async () => {
  const server = new FakeServer({
    intercept: (req) => (req.path === "/rest/v1/subscriptions" ? new Promise<Response>(() => {}) : undefined),
  });
  server.install();
  try {
    const started = Date.now();
    const { errors } = await captureConsole(() => checkStackingMismatch(client(), CHECK));
    const ms = Date.now() - started;
    assert(ms >= 900 && ms < 2500, `took ${ms} ms`);
    assertEquals(alertInserts(server).length, 0);
    assert(errors.some((e) => e.includes("stacking mismatch check unavailable")));
  } finally {
    server.restore();
  }
});

Deno.test("checkStackingMismatch: a hit pages with 1 s round trips (a hung alerts table adds about 2 s, not 6)", async () => {
  const trial = { id: "t", user_id: CHECK.userId, plan: "referral_trial", status: "active", end_date: "2026-10-25T10:00:00.000Z" };
  const server = new FakeServer({ tables: { subscriptions: [trial] }, intercept: alertsIntercept({ dedup: "hang", insert: "hang" }) });
  server.install();
  try {
    const started = Date.now();
    await captureConsole(() => checkStackingMismatch(client(), CHECK));
    const ms = Date.now() - started;
    assert(ms >= 1900 && ms < 4500, `took ${ms} ms`);
    assertEquals(alertInserts(server).length, 1);
  } finally {
    server.restore();
  }
});

// Every timer a bounded round trip starts must be CLEARED once it answers (B-pass seat A mutant 1: `clearTimeout`
// dropped from `bounded`'s finally leaves a live timer per round trip). Deno's op sanitizer did not flag the leak
// in practice, so the test spies on setTimeout / clearTimeout directly. A stub client, not supabase-js, because
// createClient() starts its own refresh timer.
function stubDb(answer: { data: unknown; error: unknown }) {
  const builder: Record<string, unknown> = {};
  for (const m of ["select", "eq", "gt", "is", "gte", "limit", "insert"]) builder[m] = () => builder;
  builder.then = (resolve: (v: unknown) => unknown) => Promise.resolve(answer).then(resolve);
  return { from: () => builder };
}

async function timersLeftBy(fn: () => Promise<unknown>): Promise<{ started: number; left: number }> {
  const live = new Set<number>();
  let started = 0;
  const origSet = globalThis.setTimeout;
  const origClear = globalThis.clearTimeout;
  // deno-lint-ignore no-explicit-any
  (globalThis as any).setTimeout = (cb: () => void, ms?: number) => {
    const id = origSet(() => { live.delete(id as unknown as number); cb(); }, ms) as unknown as number;
    live.add(id);
    started++;
    return id;
  };
  // deno-lint-ignore no-explicit-any
  (globalThis as any).clearTimeout = (id?: number) => { if (id !== undefined) live.delete(id); origClear(id); };
  try {
    await fn();
  } finally {
    globalThis.setTimeout = origSet;
    globalThis.clearTimeout = origClear;
  }
  const left = live.size;
  for (const id of live) origClear(id);
  return { started, left };
}

Deno.test("checkStackingMismatch (no hit) clears its timer", async () => {
  const r = await timersLeftBy(() => captureConsole(() => checkStackingMismatch(stubDb({ data: [], error: null }), CHECK)));
  assertEquals(r.started, 1);
  assertEquals(r.left, 0);
});

Deno.test("checkStackingMismatch (a hit, paged) clears all three timers", async () => {
  const r = await timersLeftBy(() =>
    captureConsole(() => checkStackingMismatch(stubDb({ data: [{ end_date: "2026-10-25T10:00:00.000Z" }], error: null }), CHECK))
  );
  assertEquals(r.started, 3, "the read, the dedup read and the insert");
  assertEquals(r.left, 0);
});

Deno.test("reportPaymentRecordFailure clears both timers", async () => {
  const r = await timersLeftBy(() => captureConsole(() => reportPaymentRecordFailure(stubDb({ data: [], error: null }), FAILURE, { timeoutMs: 1000 })));
  assertEquals(r.started, 2);
  assertEquals(r.left, 0);
});
