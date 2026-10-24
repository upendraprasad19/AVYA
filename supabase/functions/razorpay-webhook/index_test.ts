// OI-341 Piece A: handler-level tests of `razorpay-webhook` stacking, on the
// same fetch-level fake as verify-payment/index_test.ts. The switch-OFF golden
// recording drives the UNMODIFIED origin/main module
// (../_shared/fixtures/razorpay_webhook_origin_main.ts.txt) through each scenario.
// Sanitizers are off: createClient() starts an auth refresh timer.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authorizedWebhookRequest,
  captureConsole,
  EVENT_CREATED_AT,
  type Handler,
  alertInserts,
  helperReads,
  isMismatchRead,
  mismatchAlerts,
  mismatchReads,
  referralTrialRow,
  withoutMismatchRead,
  importWithEnv,
  loadOriginMainHandler,
  normalizeRequests,
  PAY,
  paymentServer,
  recordPaidCalls,
  type Scenario,
  stripInstants,
  subscriptionInserts,
  trialRow,
  USER,
  webhookRequest,
  withSwitch,
  YEARLY_PAISE,
} from "../_shared/payment_writer_harness.ts";

const newHandler = (await importWithEnv(() => import("./index.ts"))).handler as Handler;
const originHandler = await loadOriginMainHandler("razorpay_webhook_origin_main.ts.txt");

function t(name: string, fn: () => Promise<void>) {
  Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });
}

async function run(handler: Handler, sc: Scenario, switchValue: string | undefined) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const req = await webhookRequest(sc);
    const before = Date.now();
    const { result: res, errors, all } = await withSwitch(switchValue, () => captureConsole(() => handler(req)));
    const after = Date.now();
    const text = await res.text();
    let body: Record<string, unknown> = {};
    try { body = JSON.parse(text); } catch { /* leave empty */ }
    return { res, body, text, server, promoIncrements, errors, all, before, after };
  } finally {
    server.restore();
  }
}

/** `base + days` in local time, the same calendar arithmetic the writers always used. */
function plusDays(isoStr: string, days: number): string {
  const d = new Date(isoStr);
  d.setDate(d.getDate() + days); // local time, like the module (a UTC-ms oracle breaks across a DST change)
  return d.toISOString();
}

const promoScenario = (rows: Scenario["rows"]): Scenario => ({
  rows,
  amount: 17450, // 34900 * 50%
  notes: { promo_code: "HALF50" },
  promoRows: [{ code: "HALF50", discount_pct: 50, is_active: true, valid_until: "2099-01-01T00:00:00Z", max_uses: null, used_count: 0 }],
});

// ── stacking ON (OI-341 Piece B1): one rpc call, no insert, no helper read ──

const RPC_END = "2026-12-01T10:00:00.123456+00:00";
const RPC_END_ISO = new Date(RPC_END).toISOString();
const rpcRow = (over: Record<string, unknown> = {}) => ({
  out_end_date: RPC_END,
  out_start_date: "2026-11-01T10:00:00.654321+00:00",
  out_inserted: true,
  ...over,
});
const withRpc = (sc: Scenario, over: Record<string, unknown> = {}): Scenario => ({ ...sc, recordPaid: { rows: [rpcRow(over)] } });

t("ON: calls rpc/record_paid_subscription exactly once with the exact args (order id + the REAL signature); NO insert POST, NO helper GET", async () => {
  const sc = withRpc({ rows: [] });
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 200);
  const realSignature = (await webhookRequest(sc)).headers.get("x-razorpay-signature");
  assert(realSignature && /^[0-9a-f]{64}$/.test(realSignature));
  const calls = recordPaidCalls(r.server);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].body, {
    p_user_id: USER,
    p_plan: "monthly",
    p_payment_id: PAY,
    p_order_id: "order_TEST0001",
    p_signature: realSignature,
  });
  assertEquals(subscriptionInserts(r.server).length, 0, "the function inserts; the writer must not");
  assertEquals(helperReads(r.server).length, 0);
  assertEquals(r.server.tables.subscriptions.length, 0);
});

t("ON, a captured payment entity with NO order_id: the rpc body still carries p_order_id = null (an omitted key would 404 the function)", async () => {
  const r = await run(newHandler, withRpc({ omitOrderId: true }), "true");
  assertEquals(r.res.status, 200);
  const body = recordPaidCalls(r.server)[0].body as Record<string, unknown>;
  assert("p_order_id" in body, `p_order_id dropped: ${JSON.stringify(body)}`);
  assertEquals(body.p_order_id, null);
});

t("ON, YEARLY payment: p_plan is 'yearly' (the plan is derived, never hard-coded)", async () => {
  const r = await run(newHandler, withRpc({ rows: [], amount: YEARLY_PAISE }), "true");
  assertEquals(r.res.status, 200);
  assertEquals((recordPaidCalls(r.server)[0].body as Record<string, unknown>).p_plan, "yearly");
  assertEquals(r.body.plan, "yearly");
});

for (const inserted of [true, false]) {
  t(`ON, out_inserted=${inserted}: expires_at is the rpc's out_end_date as an ISO string (not the local now+days)`, async () => {
    const r = await run(newHandler, withRpc({ rows: [] }, { out_inserted: inserted }), "true");
    assertEquals(r.res.status, 200);
    assertEquals(r.body.status, "success");
    assertEquals(r.body.expires_at, RPC_END_ISO);
    assert(r.all.some((l) => l.includes(`[razorpay-webhook] stacking=on payment_id=${PAY} inserted=${inserted}`)));
  });
}

t("ON: an out_end_date with a +05:30 offset maps to the right instant", async () => {
  const r = await run(newHandler, withRpc({ rows: [] }, { out_end_date: "2026-12-01T15:30:00.5+05:30" }), "true");
  assertEquals(r.body.expires_at, "2026-12-01T10:00:00.500Z");
});

t("ON, out_inserted=false: the promo is NOT redeemed; out_inserted=true: redeemed exactly once", async () => {
  const no = await run(newHandler, withRpc(promoScenario([]), { out_inserted: false }), "true");
  assertEquals(no.res.status, 200);
  assertEquals(no.promoIncrements.length, 0);
  assertEquals(no.server.to("/rest/v1/promo_code_uses", "POST").length, 0);
  const yes = await run(newHandler, withRpc(promoScenario([]), { out_inserted: true }), "true");
  assertEquals(yes.res.status, 200);
  assertEquals(yes.promoIncrements, ["HALF50"]);
  assertEquals(yes.server.to("/rest/v1/promo_code_uses", "POST").length, 1);
});

// ── rpc failure: fail the call (Razorpay retries), page, never guess ────────

t("ON + rpc DATABASE error: 500, NO insert, no promo, reconcile line with ids and code (no message), one alert row", async () => {
  const sc: Scenario = {
    ...promoScenario([trialRow(3)]),
    recordPaid: { status: 400, body: { code: "55P03", message: "could not obtain lock on advisory key", details: null, hint: null } },
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 500);
  assertEquals(r.body.error, "Failed to create subscription record");
  assertEquals(recordPaidCalls(r.server).length, 1);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0);
  assertEquals(r.server.to("/rest/v1/promo_code_uses", "POST").length, 0);
  const line = r.errors.find((e) => e.startsWith("[razorpay-webhook] stacking read failed"));
  assert(line, `reconcile log missing: ${r.errors.join(" | ")}`);
  const rid = /request_id=([0-9a-f]{8})/.exec(line)?.[1];
  assert(rid, "request_id in the line");
  assert(line.includes(`payment_id=${PAY}`));
  assert(line.includes(`user_id=${USER}`));
  assert(line.includes("code=55P03"));
  assert(line.includes("plan=monthly"));
  assert(line.includes("amount_paise=17450"));
  assert(!line.includes("advisory key"), "the error MESSAGE must never be logged");
  const alerts = alertInserts(r.server);
  assertEquals(alerts.length, 1);
  const row = alerts[0].body as Record<string, any>;
  assertEquals(row.source, "payment_record_failed");
  assertEquals(row.severity, "critical");
  assertEquals(row.context_json.fn, "razorpay-webhook");
  assertEquals(row.context_json.request_id, rid);
  assertEquals(row.context_json.payment_id, PAY);
  assertEquals(row.context_json.user_id, USER);
  assertEquals(row.context_json.code, "55P03");
  assert(!JSON.stringify(row).includes("advisory key"));
});

t("ON + rpc transport failure (fetch throws): 500, NO insert, line code read_error, alert row written", async () => {
  const sc: Scenario = {
    rows: [trialRow(3)],
    intercept: (req) => (req.path === "/rest/v1/rpc/record_paid_subscription" ? "throw" : undefined),
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 500);
  assertEquals(subscriptionInserts(r.server).length, 0);
  const line = r.errors.find((e) => e.startsWith("[razorpay-webhook] stacking read failed"));
  assert(line, "reconcile log missing");
  assert(line.includes("code=read_error"), line);
  assertEquals(alertInserts(r.server).length, 1);
});

t("ON + rpc failure + the alert INSERT fails: the response is still the same 500", async () => {
  const mk = (alerts: Scenario["alerts"]): Scenario => ({
    rows: [],
    recordPaid: { status: 400, body: { code: "55P03", message: "x" } },
    alerts,
  });
  const good = await run(newHandler, mk({}), "true");
  const bad = await run(newHandler, mk({ insert: "error" }), "true");
  assertEquals(bad.res.status, 500);
  assertEquals(alertInserts(bad.server).length, 1, "the insert was attempted");
  assertEquals(bad.res.status, good.res.status);
  assertEquals(bad.body, good.body);
  assertEquals(bad.body.error, "Failed to create subscription record");
  assert(bad.errors.some((e) => e.startsWith("[razorpay-webhook] stacking read failed")));
});

for (const [label, body] of [["scalar 1 (the harness fallbackRpc answer)", 1], ["empty array", []]] as const) {
  t(`ON + malformed rpc answer (${label}): 500 and an alert with code bad_rpc_response`, async () => {
    const r = await run(newHandler, { rows: [], recordPaid: { body } }, "true");
    assertEquals(r.res.status, 500);
    assertEquals(r.body.error, "Failed to create subscription record");
    assertEquals(subscriptionInserts(r.server).length, 0);
    assertEquals(r.promoIncrements.length, 0);
    const line = r.errors.find((e) => e.startsWith("[razorpay-webhook] stacking read failed"));
    assert(line && line.includes("code=bad_rpc_response"), String(line));
    const alerts = alertInserts(r.server);
    assertEquals(alerts.length, 1);
    assertEquals((alerts[0].body as Record<string, any>).context_json.code, "bad_rpc_response");
  });
}

t("ON with NO rpc route at all (the fallback answers 1): the call fails, it does not read as success", async () => {
  const r = await run(newHandler, { rows: [] }, "true");
  assertEquals(r.res.status, 500);
  assertEquals(alertInserts(r.server).length, 1);
});

// ── switch OFF: byte-identical to origin/main, and the helper adds nothing ──

for (const sw of [undefined, "false", "", "TRUE", " true", "1"]) {
  t(`OFF (switch ${JSON.stringify(sw)}) + active trial: golden recording against origin/main is identical, no helper read, today's value`, async () => {
    const sc = () => ({ rows: [trialRow(3)] });
    const golden = await run(originHandler, sc(), undefined);
    const now = await run(newHandler, sc(), sw);
    assertEquals(golden.res.status, 200);
    assertEquals(now.res.status, golden.res.status);
    // Piece B2a plan 2.5: the ONE deliberate addition is the mismatch alarm's read after the OFF insert.
    assertEquals(mismatchReads(now.server).length, 1, "exactly one added request: the alarm read");
    assertEquals(normalizeRequests(withoutMismatchRead(now.server.requests)), normalizeRequests(golden.server.requests));
    assertEquals(stripInstants(now.body), stripInstants(golden.body));
    assertEquals(helperReads(now.server).length, 0);
    const row = subscriptionInserts(now.server)[0].body as Record<string, string>;
    assertEquals(row.end_date, plusDays(row.start_date, 30), "OFF stores exactly start + 30, ignoring the trial");
    assertEquals(now.body.expires_at, row.end_date);
  });
}

t("OFF golden: yearly, with a promo, and with no row are identical to origin/main too", async () => {
  for (const make of [
    () => ({ rows: [trialRow(3)], amount: YEARLY_PAISE }) as Scenario,
    () => promoScenario([trialRow(3)]),
    () => ({ rows: [] }) as Scenario,
  ]) {
    const golden = await run(originHandler, make(), undefined);
    const now = await run(newHandler, make(), undefined);
    assertEquals(now.res.status, golden.res.status);
    // Piece B2a plan 2.5: the ONE deliberate addition is the mismatch alarm's read after the OFF insert.
    assertEquals(mismatchReads(now.server).length, 1, "exactly one added request: the alarm read");
    assertEquals(normalizeRequests(withoutMismatchRead(now.server.requests)), normalizeRequests(golden.server.requests));
    assertEquals(stripInstants(now.body), stripInstants(golden.body));
    assertEquals(now.promoIncrements, golden.promoIncrements);
  }
});

// ── idempotency: a row that already exists never reaches the rpc ────────────

t("replay (a row for this payment exists): the H-19 early return - NO rpc call, no insert, no promo", async () => {
  const done = trialRow(33, { id: "done", razorpay_payment_id: PAY });
  const r = await run(newHandler, withRpc(promoScenario([done, trialRow(3)])), "true");
  assertEquals(r.res.status, 200);
  assertEquals(r.body.alreadyProcessed, true);
  assertEquals(recordPaidCalls(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0);
});

t("sibling-writer interleave: the other writer's row appears between the H-19 check and the second pre-SELECT - the skip branch runs, NO rpc call, no insert, no promo", async () => {
  let paymentReads = 0;
  const sc: Scenario = {
    ...withRpc(promoScenario([trialRow(3)])),
    intercept: (req) => {
      if (req.method === "GET" && req.path === "/rest/v1/subscriptions" && req.query.some(([k]) => k === "razorpay_payment_id")) {
        paymentReads++;
        if (paymentReads === 2) sc.rows!.push(trialRow(33, { id: "verify-row", razorpay_payment_id: PAY }));
      }
      return undefined;
    },
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(paymentReads, 2, "the scenario reached the second pre-SELECT");
  assertEquals(r.res.status, 200);
  assertEquals(recordPaidCalls(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0, "the creator owns the promo; the skip branch must not redeem");
  assert(r.all.some((l) => l.includes("Idempotent webhook: payment") && l.includes("skipping insert")));
});

t("plain 23505 race (switch OFF): no promo redemption", async () => {
  const sc: Scenario = {
    ...promoScenario([]),
    beforeInsert: (table, _row, srv) => {
      if (table === "subscriptions" && !srv.tables.subscriptions.some((x) => x.razorpay_payment_id === PAY)) {
        srv.tables.subscriptions.push(trialRow(33, { id: "verify-row", razorpay_payment_id: PAY }));
      }
    },
  };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 200);
  assertEquals(r.promoIncrements.length, 0);
});

// ── payment-id format check (validation, not switch-gated; same shape as verify-payment) ──

for (const sw of [undefined, "true"]) {
  t(`a signed payload with a malformed payment id is rejected with 400 before any request (switch ${sw ?? "absent"})`, async () => {
    for (const bad of ["pay_X?y=1", "pay_X/capture", "pay_X#1", "../x", "pay_" + "a".repeat(65), "pay_a,b", "xpay_abc", "pay_"]) {
      const r = await run(newHandler, { rows: [trialRow(3)], paymentId: bad }, sw);
      assertEquals(r.res.status, 400, bad);
      assertEquals(r.body.error, "Invalid payment id", bad);
      assertEquals(r.server.requests.length, 0, `${bad}: no Supabase and no Razorpay request`);
      assert(r.errors.some((e) => e.startsWith("[razorpay-webhook] rejecting a payment id")), bad);
    }
  });
}

t("a conforming payment id still records the payment (control for the 400 cases)", async () => {
  const id = "pay_ABCDEFGHIJ0123";
  const r = await run(newHandler, { rows: [], paymentId: id }, undefined);
  assertEquals(r.res.status, 200);
  assertEquals(subscriptionInserts(r.server).length, 1);
});

t("a malformed payment id on a STALE delivery is rejected as an invalid id, before the replay log can interpolate it", async () => {
  const bad = "pay_X?y=1";
  const r = await run(newHandler, { rows: [], paymentId: bad, eventCreatedAt: EVENT_CREATED_AT - 1000 }, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(r.body.error, "Invalid payment id", "not 'Webhook too old': the id check runs before the replay block");
  assert(!r.all.join("\n").includes(bad), "the raw malformed id must never reach a log line");
  assertEquals(r.server.requests.length, 0);
});

t("a conforming id on a stale delivery still hits the replay window (control)", async () => {
  // 25 h: past the payment.captured window (24 h + 10 min, Piece B2a plan 2.6).
  const r = await run(newHandler, { rows: [], eventCreatedAt: nowSec() - 25 * 3600 }, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(r.body.error, "Webhook too old");
});

// ── OI-341 Piece B2a: replay window per event (plan 2.6) ────────────────────

function nowSec(): number {
  return Math.floor(Date.now() / 1000);
}

/** A webhook request for `event` stamped `ageSec` seconds in the past (negative = future). */
async function eventRequest(sc: Scenario, event: string, ageSec: number): Promise<Request> {
  const base = await webhookRequest({ ...sc, eventCreatedAt: nowSec() - ageSec });
  const body = JSON.parse(await base.text());
  body.event = event;
  if (event === "payment.authorized") body.payload.payment.entity.captured = true; // no capture call: the window is under test
  const raw = JSON.stringify(body);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("whsec_harness"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  return new Request("https://fn.test/razorpay-webhook", {
    method: "POST",
    headers: { "x-razorpay-signature": sig, "Content-Type": "application/json" },
    body: raw,
  });
}

async function runEvent(sc: Scenario, event: string, ageSec: number, sw: string | undefined = undefined) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const req = await eventRequest(sc, event, ageSec);
    const { result: res, all } = await withSwitch(sw, () => captureConsole(() => newHandler(req)));
    const body = JSON.parse(await res.text());
    return { res, body, server, promoIncrements, all };
  } finally {
    server.restore();
  }
}

const done = () => trialRow(33, { id: "done", razorpay_payment_id: PAY });

t("replay window: payment.captured aged 6 min with the row present is an idempotent 200 (was 400 under the 300 s rule)", async () => {
  const r = await runEvent({ rows: [done()] }, "payment.captured", 6 * 60);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.alreadyProcessed, true);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("replay window: payment.captured aged 6 min with NO row records the row", async () => {
  const r = await runEvent({ rows: [] }, "payment.captured", 6 * 60);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.status, "success");
  assertEquals(subscriptionInserts(r.server).length, 1);
});

t("replay window: a stale idempotent payment.captured does not redeem the promo again", async () => {
  const r = await runEvent({ ...promoScenario([done()]) }, "payment.captured", 6 * 3600);
  assertEquals(r.res.status, 200);
  assertEquals(r.promoIncrements.length, 0);
});

t("replay window: payment.captured boundaries - 24 h 5 min accepted, 24 h 15 min and 25 h rejected", async () => {
  const ok = await runEvent({ rows: [done()] }, "payment.captured", 24 * 3600 + 5 * 60);
  assertEquals(ok.res.status, 200, "24 h 5 min is inside 24 h + 10 min");
  for (const age of [24 * 3600 + 15 * 60, 25 * 3600]) {
    const r = await runEvent({ rows: [done()] }, "payment.captured", age);
    assertEquals(r.res.status, 400, `age ${age}`);
    assertEquals(r.body.error, "Webhook too old");
  }
});

t("replay window: payment.authorized keeps 300 s (6 min is rejected; 2 min is accepted)", async () => {
  const stale = await runEvent({ rows: [done()] }, "payment.authorized", 6 * 60);
  assertEquals(stale.res.status, 400);
  assertEquals(stale.body.error, "Webhook too old");
  const fresh = await runEvent({ rows: [done()] }, "payment.authorized", 2 * 60);
  assertEquals(fresh.res.status, 200);
});

t("replay window: a future stamp of -3 min is rejected for BOTH events", async () => {
  for (const ev of ["payment.captured", "payment.authorized"]) {
    const r = await runEvent({ rows: [done()] }, ev, -3 * 60);
    assertEquals(r.res.status, 400, ev);
    assertEquals(r.body.error, "Webhook too old", ev);
  }
});

// ── OI-341 Piece B2a: switch log line (plan 2.3) ────────────────────────────

t("switch log line: OFF prints stacking_switch=off once, ON prints stacking_switch=on once, a replay prints none", async () => {
  const count = (all: string[], v: string) => all.filter((l) => l === `[razorpay-webhook] stacking_switch=${v} payment_id=${PAY}`).length;
  const off = await run(newHandler, { rows: [] }, undefined);
  assertEquals(count(off.all, "off"), 1);
  assertEquals(count(off.all, "on"), 0);
  const on = await run(newHandler, withRpc({ rows: [] }), "true");
  assertEquals(count(on.all, "on"), 1);
  assertEquals(count(on.all, "off"), 0);
  const replay = await run(newHandler, { rows: [done()] }, undefined);
  assertEquals(replay.all.filter((l) => l.includes("stacking_switch=")).length, 0);
  // The SECOND skip path: the sibling writer's row appears between the H-19 check and the second pre-SELECT.
  let paymentReads = 0;
  const sc: Scenario = {
    rows: [],
    intercept: (req) => {
      if (req.method === "GET" && req.path === "/rest/v1/subscriptions" && req.query.some(([k]) => k === "razorpay_payment_id")) {
        paymentReads++;
        if (paymentReads === 2) sc.rows!.push(trialRow(33, { id: "verify-row", razorpay_payment_id: PAY }));
      }
      return undefined;
    },
  };
  const second = await run(newHandler, sc, undefined);
  assertEquals(paymentReads, 2, "the scenario reached the second pre-SELECT");
  assertEquals(second.all.filter((l) => l.includes("stacking_switch=")).length, 0);
});

// ── OI-341 Piece B2a: the alert round trips are bounded at 1 s here (plan 2.4) ──

t("ON + rpc failure + a HUNG alerts table: the 500 is released within about 2.2 s (two 1 s round trips)", async () => {
  const r = await run(newHandler, { rows: [], recordPaid: { status: 400, body: { code: "55P03", message: "x" } }, alerts: { dedup: "hang", insert: "hang" } }, "true");
  assertEquals(r.res.status, 500);
  const ms = r.after - r.before;
  assert(ms >= 1900, `two bounded round trips, took ${ms} ms`);
  assert(ms < 4500, `must be bounded near 2 s (the 3 s default would take 6 s), took ${ms} ms`);
});

// ── OI-341 Piece B2a: the switch-mismatch alarm (plan 2.5) ──────────────────

const hangMismatch: Scenario["intercept"] = (req) => (isMismatchRead(req) ? new Promise<Response>(() => {}) : undefined);
const errorMismatch: Scenario["intercept"] = (req) =>
  isMismatchRead(req) ? new Response(JSON.stringify({ code: "XX000", message: "boom" }), { status: 500, headers: { "Content-Type": "application/json" } }) : undefined;

t("alarm: OFF + an active referral trial outliving the new row: same 200 body and row as origin/main, plus one critical stacking_switch_mismatch alert and log", async () => {
  const trial = referralTrialRow(5);
  const sc = () => ({ rows: [{ ...trial }] }) as Scenario;
  const golden = await run(originHandler, sc(), undefined);
  const now = await run(newHandler, sc(), undefined);
  assertEquals(now.res.status, 200);
  assertEquals(stripInstants(now.body), stripInstants(golden.body));
  assertEquals(
    stripInstants(subscriptionInserts(now.server).map((r) => r.body)),
    stripInstants(subscriptionInserts(golden.server).map((r) => r.body)),
    "the row is exactly what OFF wrote before B2a",
  );
  const alerts = mismatchAlerts(now.server);
  assertEquals(alerts.length, 1);
  const row = alerts[0].body as Record<string, any>;
  assertEquals(row.severity, "critical");
  assertEquals(row.context_json.fn, "razorpay-webhook");
  assertEquals(row.context_json.payment_id, PAY);
  assertEquals(row.context_json.user_id, USER);
  assertEquals(row.context_json.trial_end, trial.end_date);
  assertEquals(row.context_json.row_end, (subscriptionInserts(now.server)[0].body as Record<string, string>).end_date);
  assertEquals(row.context_json.plan, "monthly");
  assert(String(row.summary).startsWith("razorpay-webhook: paid row recorded without stacking over an active trial"));
  assert(now.errors.some((e) => e === `[razorpay-webhook] stacking_switch_mismatch payment_id=${PAY} user_id=${USER}`));
  // The dedup query is keyed on THIS source, not payment_record_failed.
  const dedup = now.server.to("/rest/v1/alerts", "GET");
  assertEquals(dedup.length, 1);
  assert(dedup[0].query.some(([k, v]) => k === "source" && v === "eq.stacking_switch_mismatch"));
});

t("alarm: OFF + a referral trial that already ENDED, a non-trial grant row, or no row: the read runs, no alert", async () => {
  for (const rows of [[referralTrialRow(-1)], [trialRow(5)], []]) {
    const r = await run(newHandler, { rows }, undefined);
    assertEquals(r.res.status, 200);
    assertEquals(mismatchReads(r.server).length, 1);
    assertEquals(mismatchAlerts(r.server).length, 0, JSON.stringify(rows));
  }
});

t("alarm: the read is scoped to this user, active rows, referral_trial, end_date > the new row's start, limit 1", async () => {
  const r = await run(newHandler, { rows: [] }, undefined);
  const q = mismatchReads(r.server)[0].query;
  const get = (k: string) => q.filter(([key]) => key === k).map(([, v]) => v);
  assertEquals(get("user_id"), [`eq.${USER}`]);
  assertEquals(get("status"), ["eq.active"]);
  assertEquals(get("plan"), ["eq.referral_trial"]);
  assertEquals(get("limit"), ["1"]);
  const start = (subscriptionInserts(r.server)[0].body as Record<string, string>).start_date;
  assertEquals(get("end_date"), [`gt.${start}`]);
});

t("alarm: another user's active referral trial does not fire it", async () => {
  const r = await run(newHandler, { rows: [referralTrialRow(5, { user_id: "33333333-3333-4333-8333-333333333333" })] }, undefined);
  assertEquals(mismatchAlerts(r.server).length, 0);
});

for (const [label, intercept] of [["an ERROR", errorMismatch], ["a HANG", hangMismatch]] as const) {
  t(`alarm: the check read returning ${label}: the same 200, the promo still redeemed, no alert`, async () => {
    const r = await run(newHandler, { ...promoScenario([referralTrialRow(5)]), intercept }, undefined);
    assertEquals(r.res.status, 200);
    assertEquals(r.body.status, "success");
    assertEquals(r.promoIncrements, ["HALF50"]);
    assertEquals(mismatchAlerts(r.server).length, 0);
    assert(r.errors.some((e) => e.startsWith("[razorpay-webhook] stacking mismatch check unavailable")));
    assert(r.after - r.before < 3500, `bounded at 1 s (a 5 s bound would fail), took ${r.after - r.before} ms`);
  });
}

t("alarm: a hit + a HUNG alerts table: the same 200 within about 2.2 s", async () => {
  const r = await run(newHandler, { rows: [referralTrialRow(5)], alerts: { dedup: "hang", insert: "hang" } }, undefined);
  assertEquals(r.res.status, 200);
  const ms = r.after - r.before;
  assert(ms >= 1900 && ms < 4500, `two 1 s round trips, took ${ms} ms`);
});

t("alarm: never on the ON path (no check request, even with a referral trial row)", async () => {
  const r = await run(newHandler, withRpc({ rows: [referralTrialRow(5)] }), "true");
  assertEquals(r.res.status, 200);
  assertEquals(mismatchReads(r.server).length, 0);
});

t("alarm: never on the skip paths (H-19 replay, second pre-SELECT)", async () => {
  const replay = await run(newHandler, { rows: [done(), referralTrialRow(5)] }, undefined);
  assertEquals(mismatchReads(replay.server).length, 0);
  let paymentReads = 0;
  const sc: Scenario = {
    rows: [referralTrialRow(5)],
    intercept: (req) => {
      if (req.method === "GET" && req.path === "/rest/v1/subscriptions" && req.query.some(([k]) => k === "razorpay_payment_id")) {
        paymentReads++;
        if (paymentReads === 2) sc.rows!.push(trialRow(33, { id: "verify-row", razorpay_payment_id: PAY }));
      }
      return undefined;
    },
  };
  const second = await run(newHandler, sc, undefined);
  assertEquals(paymentReads, 2);
  assertEquals(mismatchReads(second.server).length, 0);
});

t("alarm: never on the 23505 race arm (the sibling writer won the insert and owns the check)", async () => {
  const sc: Scenario = {
    rows: [referralTrialRow(5)],
    beforeInsert: (table, _row, srv) => {
      if (table === "subscriptions" && !srv.tables.subscriptions.some((x) => x.razorpay_payment_id === PAY)) {
        srv.tables.subscriptions.push(trialRow(33, { id: "verify-row", razorpay_payment_id: PAY }));
      }
    },
  };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 200);
  assertEquals(mismatchReads(r.server).length, 0);
});

t("alarm: never after a failed (non-23505) insert - that is the existing 500", async () => {
  const sc: Scenario = {
    rows: [referralTrialRow(5)],
    intercept: (req) =>
      req.method === "POST" && req.path === "/rest/v1/subscriptions"
        ? new Response(JSON.stringify({ code: "23502", message: "null" }), { status: 400, headers: { "Content-Type": "application/json" } })
        : undefined,
  };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 500);
  assertEquals(mismatchReads(r.server).length, 0);
});

// ── OI-341 Piece B2a: a captured payment no row can record is paged (hermes seat 4 F4) ──

t("no-match: a promo payment whose code was DELETED mid-checkout: the same 400, no row, and one critical payment_record_failed alert (amount_no_match)", async () => {
  const sc: Scenario = { rows: [], amount: 17450, notes: { promo_code: "HALF50" }, promoRows: [] };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(r.body, { error: "amount_does_not_match_any_plan" });
  assertEquals(subscriptionInserts(r.server).length, 0);
  const alerts = alertInserts(r.server);
  assertEquals(alerts.length, 1);
  const row = alerts[0].body as Record<string, any>;
  assertEquals(row.source, "payment_record_failed");
  assertEquals(row.severity, "critical");
  assertEquals(row.context_json.code, "amount_no_match");
  assertEquals(row.context_json.payment_id, PAY);
  assertEquals(row.context_json.user_id, USER);
  assertEquals(row.context_json.amount_paise, 17450);
  assertEquals(row.context_json.plan, "unknown");
});

t("no-match: a full-price-shaped amount that matches no plan (no promo) is paged too, and a hung alerts table releases the 400 within about 2 s", async () => {
  const r = await run(newHandler, { rows: [], amount: 12345, alerts: { dedup: "hang", insert: "hang" } }, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(alertInserts(r.server).length, 1);
  const ms = r.after - r.before;
  assert(ms >= 1900 && ms < 4500, `two 1 s round trips, took ${ms} ms`);
});

t("cross-check: the promo's discount changed between the two reads: the same 400 amount_mismatch and one alert (amount_cross_check)", async () => {
  let promoReads = 0;
  const sc: Scenario = {
    ...promoScenario([]),
    intercept: (req) => {
      if (req.method === "GET" && req.path === "/rest/v1/promo_codes") {
        promoReads++;
        if (promoReads === 2) {
          return new Response(JSON.stringify({ discount_pct: 40, is_active: true, valid_until: "2099-01-01T00:00:00Z", max_uses: null, used_count: 0 }), { status: 200, headers: { "Content-Type": "application/json" } });
        }
      }
      return undefined;
    },
  };
  const r = await run(newHandler, sc, undefined);
  assertEquals(promoReads, 2);
  assertEquals(r.res.status, 400);
  assertEquals(r.body, { error: "amount_mismatch" });
  const alerts = alertInserts(r.server);
  assertEquals(alerts.length, 1);
  assertEquals((alerts[0].body as Record<string, any>).context_json.code, "amount_cross_check");
  assertEquals((alerts[0].body as Record<string, any>).context_json.plan, "monthly");
});

t("no-match control: a matching promo payment records the row and writes no alert", async () => {
  const r = await run(newHandler, promoScenario([]), undefined);
  assertEquals(r.res.status, 200);
  assertEquals(alertInserts(r.server).length, 0);
});

// ── payment-hardening U0 (OI-360): a log line carries a code, a type or a bounded value, never a whole object ──
// Each leak test first runs the scenario through the frozen origin/main handler and requires the secret to be
// VISIBLE there (captureConsole prints objects through JSON.stringify), then requires it absent here.

const SECRET = "SIGf3b1c2d4e5a6978812345678abcdef00112233";
const pgError = (status: number, code: string) =>
  new Response(JSON.stringify({ code, message: "insert or update violates a constraint", details: `Key (razorpay_signature)=(${SECRET})`, hint: SECRET }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const anyLine = (all: string[], needle: string) => all.some((l) => l.includes(needle));

async function runAuthorized(handler: Handler, sc: Scenario) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const req = await authorizedWebhookRequest(sc);
    const { result: res, errors, all } = await withSwitch(undefined, () => captureConsole(() => handler(req)));
    const text = await res.text();
    return { res, text, server, promoIncrements, errors, all };
  } finally {
    server.restore();
  }
}

t("U0 log: a non-23505 insert failure logs the reconcile fields and the code, never the error's details (control: origin logged them)", async () => {
  const sc: Scenario = {
    rows: [],
    intercept: (req) => (req.method === "POST" && req.path === "/rest/v1/subscriptions" ? pgError(409, "23503") : undefined),
  };
  const before = await run(originHandler, sc, undefined);
  assert(anyLine(before.all, SECRET), "positive control: the origin handler must show the secret");
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 500);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(
    r.errors.includes(`[razorpay-webhook] subscription insert failed (non-23505) payment_id=${PAY} user_id=${USER} plan=monthly amount_paise=34900 code=23503`),
    r.errors.join("\n"),
  );
});

t("U0 log: missing user_id logs the SHAPE of the notes, never a value (control: origin logged the notes)", async () => {
  const sc: Scenario = { rows: [], notes: { user_id: "", card_token: SECRET } };
  const before = await run(originHandler, sc, undefined);
  assert(anyLine(before.all, SECRET), "positive control");
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 400);
  assert(!anyLine(r.all, SECRET) && !anyLine(r.all, "card_token"), r.all.join("\n"));
  assert(r.errors.includes("[razorpay-webhook] Missing user_id in payment notes: keys=[user_id] other=1"), r.errors.join("\n"));
});

t("U0 log: a malformed user_id logs its type and length, never the value (control: origin logged it)", async () => {
  const bad = `not-a-uuid ${SECRET}`;
  const sc: Scenario = { rows: [], notes: { user_id: bad } };
  const before = await run(originHandler, sc, undefined);
  assert(anyLine(before.all, SECRET), "positive control");
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 400);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(r.errors.includes(`[razorpay-webhook] Invalid user_id format in payment notes: type=string length=${bad.length}`), r.errors.join("\n"));
});

t("U0 log: a refused capture of an authorized payment logs status and Razorpay's code/reason only (control: origin logged the body)", async () => {
  const sc: Scenario = {
    rows: [],
    // The recovery GET (U2) must see the payment still authorized, so the refusal stands and is logged.
    intercept: (req) =>
      req.host !== "https://api.razorpay.com"
        ? undefined
        : req.method === "POST" && req.path === `/v1/payments/${PAY}/capture`
        ? new Response(JSON.stringify({ error: { code: "BAD_REQUEST_ERROR", description: `card ${SECRET}`, reason: "capture_failed" } }), { status: 400 })
        : req.method === "GET"
        ? new Response(JSON.stringify({ id: PAY, amount: 34900, captured: false, status: "authorized" }), { status: 200 })
        : undefined,
  };
  const before = await runAuthorized(originHandler, sc);
  assert(anyLine(before.all, SECRET), "positive control");
  const r = await runAuthorized(newHandler, sc);
  assertEquals(r.res.status, 502);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(anyLine(r.errors, `capture failed for ${PAY}: status=400 code="BAD_REQUEST_ERROR" reason="capture_failed"`), r.errors.join("\n"));
});

t("U0 log: notes.plan is bounded and quoted: no forged line, no unbounded text (control: origin printed it raw)", async () => {
  const forged = "yearly\n[razorpay-webhook] FORGED-LINE " + "Z".repeat(300);
  // A fresh scenario per run: the fake server inserts into the scenario's own `rows` array.
  const sc = (): Scenario => ({ rows: [], notes: { plan: forged } });
  const before = await run(originHandler, sc(), undefined);
  assert(anyLine(before.all, "\n[razorpay-webhook] FORGED-LINE"), "positive control");
  const r = await run(newHandler, sc(), undefined);
  assertEquals(r.res.status, 200);
  assert(!anyLine(r.all, "\n[razorpay-webhook] FORGED-LINE") && !anyLine(r.all, "Z".repeat(50)), r.all.join("\n"));
  assert(anyLine(r.all, `client claimed ${JSON.stringify(forged.slice(0, 40))}`), r.all.join("\n"));
});

// B-pass of commit 2: notes.promo_code is checkout-supplied and logged BEFORE any database match.
const FORGED_PROMO = "HALF50\n[razorpay-webhook] FORGED-LINE " + "Z".repeat(300);
for (const [label, amount, expectLine] of [
  ["the full-price cross-check (code not found)", 34900, `Promo code ${JSON.stringify(FORGED_PROMO.slice(0, 40))} not found`],
  ["an amount that matches no plan", 12345, `[razorpay-webhook] amount 12345 paise does not match any plan (promo: ${JSON.stringify(FORGED_PROMO.slice(0, 40))})`],
] as const) {
  t(`U0 log: ${label} logs notes.promo_code bounded and quoted (control: origin printed it raw)`, async () => {
    const sc = (): Scenario => ({ rows: [], amount, notes: { promo_code: FORGED_PROMO } });
    const before = await run(originHandler, sc(), undefined);
    assert(anyLine(before.all, "\n[razorpay-webhook] FORGED-LINE"), "positive control");
    const r = await run(newHandler, sc(), undefined);
    assertEquals(r.res.status, before.res.status);
    assert(!anyLine(r.all, "\n[razorpay-webhook] FORGED-LINE") && !anyLine(r.all, "Z".repeat(50)), r.all.join("\n"));
    assert(anyLine(r.all, expectLine), r.all.join("\n"));
  });
}

for (const [label, path, expectLine] of [
  ["increment_promo_used_count", "/rest/v1/rpc/increment_promo_used_count", "[razorpay-webhook] promo redemption: increment_promo_used_count failed code=P0001"],
  ["promo_code_uses insert", "/rest/v1/promo_code_uses", "[razorpay-webhook] promo redemption: promo_code_uses insert failed code=P0001"],
] as const) {
  t(`U0 R-6: a failed ${label} answers as before and logs one labelled, code-only line`, async () => {
    const sc: Scenario = { ...promoScenario([]), intercept: (req) => (req.method === "POST" && req.path === path ? pgError(400, "P0001") : undefined) };
    const ok = await run(newHandler, promoScenario([]), undefined);
    const r = await run(newHandler, sc, undefined);
    assertEquals(r.res.status, ok.res.status);
    assertEquals(stripInstants(r.body), stripInstants(ok.body));
    assertEquals(subscriptionInserts(r.server).length, 1);
    assertEquals(r.server.to(path, "POST").length, 1);
    assertEquals(r.errors.filter((l) => l === expectLine).length, 1, r.errors.join("\n"));
    assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  });
}

// ── payment-hardening U2 (OI-351): a refused capture of an ALREADY-captured payment records the row ──
// Before U2 every replay of a payment.authorized event whose first delivery captured the payment and then
// failed to record the row met "already captured" and answered 502 until the replay window closed.

const RECOVERY_SWITCH = "DISABLE_WEBHOOK_CAPTURE_RECOVERY";
const CAPTURE_PATH = `/v1/payments/${PAY}/capture`;
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const alreadyCaptured = () => json(400, { error: { code: "BAD_REQUEST_ERROR", description: "This payment has already been captured", reason: "payment_already_captured" } });
const capturedEntity = (over: Record<string, unknown> = {}) => ({ id: PAY, amount: 34900, currency: "INR", captured: true, status: "captured", notes: { user_id: USER }, ...over });

type CaptureAnswer = "refused" | "ok" | "throw";
type GetAnswer = Response | "throw" | "hang" | (() => Response);

function razorpayRoute(capture: CaptureAnswer, get: GetAnswer): Scenario["intercept"] {
  return (req) => {
    if (req.host !== "https://api.razorpay.com") return undefined;
    if (req.method === "POST" && req.path === CAPTURE_PATH) {
      if (capture === "throw") return "throw";
      return capture === "ok" ? json(200, capturedEntity()) : alreadyCaptured();
    }
    if (req.method === "GET" && req.path === `/v1/payments/${PAY}`) {
      if (get === "throw") return "throw";
      if (get === "hang") return new Promise<Response>(() => {});
      return typeof get === "function" ? get() : get.clone();
    }
    return undefined;
  };
}

async function withRecoverySwitch<T>(value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const before = Deno.env.get(RECOVERY_SWITCH);
  if (value === undefined) Deno.env.delete(RECOVERY_SWITCH);
  else Deno.env.set(RECOVERY_SWITCH, value);
  try {
    return await fn();
  } finally {
    if (before === undefined) Deno.env.delete(RECOVERY_SWITCH);
    else Deno.env.set(RECOVERY_SWITCH, before);
  }
}

async function runRecovery(handler: Handler, sc: Scenario, opts: { recovery?: string; stacking?: string } = {}) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const req = await authorizedWebhookRequest(sc);
    const before = Date.now();
    const { result: res, errors, all } = await withRecoverySwitch(opts.recovery, () =>
      withSwitch(opts.stacking, () => captureConsole(() => handler(req)))
    );
    const after = Date.now();
    const text = await res.text();
    let body: Record<string, unknown> = {};
    try { body = JSON.parse(text); } catch { /* leave empty */ }
    return { res, body, text, server, promoIncrements, errors, all, ms: after - before };
  } finally {
    server.restore();
  }
}

const gets = (server: { to: (p: string, m?: string) => unknown[] }) => server.to(`/v1/payments/${PAY}`, "GET").length;
const capturePosts = (server: { to: (p: string, m?: string) => unknown[] }) => server.to(CAPTURE_PATH, "POST").length;

t("U2 (1): authorized, capture refused, GET says captured for this amount -> the row is recorded, 200", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(200, capturedEntity())) });
  assertEquals(r.res.status, 200);
  assertEquals(subscriptionInserts(r.server).length, 1);
  assertEquals(gets(r.server), 1);
  assert(r.all.some((l) => l === `[razorpay-webhook] capture refused, payment already captured; continuing payment_id=${PAY}`), r.all.join("\n"));
});

t("U2 (2): capture refused, GET says still authorized -> 502 as today, no row", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(200, capturedEntity({ captured: false, status: "authorized" }))) });
  assertEquals(r.res.status, 502);
  assertEquals(r.body, { error: "Capture failed, will retry" });
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("U2 (3): capture refused, GET answers 500 -> 502, no row", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(500, { error: { code: "SERVER_ERROR" } })) });
  assertEquals(r.res.status, 502);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("U2 (4): the capture call THROWS, GET says captured -> recorded, 200", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("throw", json(200, capturedEntity())) });
  assertEquals(r.res.status, 200);
  assertEquals(subscriptionInserts(r.server).length, 1);
});

t("U2 (5): GET says captured but for ANOTHER amount -> 502, no row", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(200, capturedEntity({ amount: 34800 }))) });
  assertEquals(r.res.status, 502);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("U2 (6): happy path (capture OK) -> recorded, and no recovery GET is made", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("ok", "throw") });
  assertEquals(r.res.status, 200);
  assertEquals(gets(r.server), 0);
  assertEquals(subscriptionInserts(r.server).length, 1);
});

t("U2 (7): three replays after a recovery -> H-19 skips each: no capture, no GET, still one row", async () => {
  const sc: Scenario = { rows: [], notes: { promo_code: "HALF50" }, amount: 17450, promoRows: promoScenario([]).promoRows, intercept: razorpayRoute("refused", json(200, capturedEntity({ amount: 17450 }))) };
  const first = await runRecovery(newHandler, sc);
  assertEquals(first.res.status, 200);
  assertEquals(first.promoIncrements.length, 1);
  for (let i = 0; i < 3; i++) {
    const r = await runRecovery(newHandler, sc); // sc.rows now holds the recorded row
    assertEquals(r.res.status, 200);
    assertEquals(capturePosts(r.server), 0);
    assertEquals(gets(r.server), 0);
    assertEquals(r.promoIncrements.length, 0);
  }
  assertEquals(sc.rows!.length, 1);
});

t("U2 (8): recovery on the stacking-ON path -> exactly one record_paid_subscription call; promo only when inserted", async () => {
  for (const inserted of [true, false]) {
    const sc: Scenario = {
      ...promoScenario([]),
      recordPaid: { rows: [rpcRow({ out_inserted: inserted })] },
      intercept: razorpayRoute("refused", json(200, capturedEntity({ amount: 17450 }))),
    };
    const r = await runRecovery(newHandler, sc, { stacking: "true" });
    assertEquals(r.res.status, 200);
    assertEquals(recordPaidCalls(r.server).length, 1);
    assertEquals(r.promoIncrements.length, inserted ? 1 : 0);
  }
});

t("U2 (9): recovery then a 23505 race on the insert -> 200 and no promo redemption", async () => {
  const sc: Scenario = {
    ...promoScenario([]),
    intercept: (req) =>
      req.method === "POST" && req.path === "/rest/v1/subscriptions"
        ? json(409, { code: "23505", message: 'duplicate key value violates unique constraint "unique_razorpay_payment_id"' })
        : razorpayRoute("refused", json(200, capturedEntity({ amount: 17450 })))!(req),
  };
  const r = await runRecovery(newHandler, sc);
  assertEquals(r.res.status, 200);
  assertEquals(r.promoIncrements.length, 0);
});

t("U2 (10): switch exactly \"true\" -> a TRUE golden of origin/main: same status, body and request list", async () => {
  const sc = (): Scenario => ({ rows: [], intercept: razorpayRoute("refused", json(200, capturedEntity())) });
  const golden = await runRecovery(originHandler, sc(), { recovery: "true" });
  const r = await runRecovery(newHandler, sc(), { recovery: "true" });
  assertEquals(golden.res.status, 502);
  assertEquals(r.res.status, golden.res.status);
  assertEquals(r.text, golden.text);
  assertEquals(normalizeRequests(r.server.requests), normalizeRequests(golden.server.requests));
  assertEquals(gets(r.server), 0);
});

t("U2 (10b): any switch value other than exactly \"true\" leaves the recovery ON", async () => {
  for (const v of ["TRUE", " true", "1", "false", ""]) {
    const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(200, capturedEntity())) }, { recovery: v });
    assertEquals(r.res.status, 200, `switch=${JSON.stringify(v)}`);
  }
});

t("U2 (11): the recovery GET HANGS -> 502 within about 2 s", async () => {
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", "hang") });
  assertEquals(r.res.status, 502);
  assert(r.ms >= 1400 && r.ms < 2500, `bounded at 1.5 s, took ${r.ms} ms`);
});

t("U2 (11b): a GET whose BODY never arrives (headers sent) is bounded too -> 502 within about 2 s", async () => {
  const neverEnding = () => new Response(new ReadableStream({ start() {} }), { status: 200, headers: { "Content-Type": "application/json" } });
  const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", neverEnding) });
  assertEquals(r.res.status, 502);
  assert(r.ms >= 1400 && r.ms < 2500, `bounded at 1.5 s, took ${r.ms} ms`);
});

for (const [label, body] of [
  ["(12) the id differs", capturedEntity({ id: "pay_OTHER000000001" })],
  ["(13) captured:false with status captured", capturedEntity({ captured: false })],
  ["(14) captured:true with status authorized", capturedEntity({ status: "authorized" })],
  ["(15a) a null body", null],
  ["(15b) an array body", [capturedEntity()]],
  ["(15c) a string amount", capturedEntity({ amount: "34900" })],
] as const) {
  t(`U2 ${label}: the recovery refuses -> 502, no row`, async () => {
    const r = await runRecovery(newHandler, { rows: [], intercept: razorpayRoute("refused", json(200, body)) });
    assertEquals(r.res.status, 502);
    assertEquals(subscriptionInserts(r.server).length, 0);
  });
}

// ── U2 (16)/(17): the timeout's own cleanup (B-pass 6759fb19989f finding 6) ──
// Direct calls of rereadIsCaptured with fetch swapped here only: a hung GET must be ABORTED when the timeout
// wins (no socket left open in a warm isolate), and when the GET wins no 1.5 s timer may stay pending.
const reread = (await importWithEnv(() => import("./index.ts"))).rereadIsCaptured as (
  paymentId: string,
  expectedAmount: unknown,
  credentials: string,
  timeoutMs?: number,
) => Promise<boolean>;

async function withFetch<T>(fake: typeof fetch, fn: () => Promise<T>): Promise<T> {
  const real = globalThis.fetch;
  globalThis.fetch = fake;
  try {
    return await fn();
  } finally {
    globalThis.fetch = real;
  }
}

t("U2 (16): the timeout wins -> the hung GET's signal is ABORTED (live when the GET starts) and the answer is false", async () => {
  let signal: AbortSignal | null | undefined;
  let abortedAtCall: boolean | undefined;
  const hung = ((_url: unknown, init?: RequestInit) => {
    signal = init?.signal;
    abortedAtCall = init?.signal?.aborted;
    return new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
    });
  }) as typeof fetch;
  assertEquals(await withFetch(hung, () => reread(PAY, 34900, "x", 30)), false);
  assert(signal, "the GET must carry an abort signal");
  assertEquals(abortedAtCall, false, "the signal must be live when the GET starts (aborted only by the timeout)");
  assertEquals(signal.aborted, true);
});

for (const [label, answer, expected] of [
  ["captured for the amount -> true", () => json(200, capturedEntity()), true],
  ["a 500 -> false", () => json(500, { error: "x" }), false],
  ["captured:false -> false", () => json(200, capturedEntity({ captured: false })), false],
] as const) {
  Deno.test({
    name: `U2 (17): the GET wins, ${label}, and no timer is left pending (op sanitizer ON)`,
    sanitizeOps: true,
    sanitizeResources: true,
    fn: async () => {
      const quick = (() => Promise.resolve(answer())) as typeof fetch;
      assertEquals(await withFetch(quick, () => reread(PAY, 34900, "x", 60_000)), expected);
    },
  });
}
