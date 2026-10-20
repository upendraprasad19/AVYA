// OI-341 Piece A: handler-level tests of `razorpay-webhook` stacking, on the
// same fetch-level fake as verify-payment/index_test.ts. The switch-OFF golden
// recording drives the UNMODIFIED origin/main module
// (../_shared/fixtures/razorpay_webhook_origin_main.ts.txt) through each scenario.
// Sanitizers are off: createClient() starts an auth refresh timer.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  captureConsole,
  EVENT_CREATED_AT,
  type Handler,
  alertInserts,
  helperReads,
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
    assertEquals(normalizeRequests(now.server.requests), normalizeRequests(golden.server.requests));
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
    assertEquals(normalizeRequests(now.server.requests), normalizeRequests(golden.server.requests));
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
  const r = await run(newHandler, { rows: [], eventCreatedAt: EVENT_CREATED_AT - 1000 }, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(r.body.error, "Webhook too old");
});
