// OI-341 Piece B1: tests of `reportPaymentRecordFailure` (docs/plans/oi341-piece-b-door.md 2.3, 3b).
// The REAL supabase-js client runs over the fetch-level fake; the `alerts` table is answered by the
// harness's `alertsIntercept` (the fake's evaluator does not model `->>` JSON paths or `gte`), so the
// dedup query is asserted as the exact RECORDED query string.
import { assert, assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { PAYMENT_ALERT_SOURCE, type PaymentRecordFailure, reportPaymentRecordFailure } from "./payment_alert.ts";
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
