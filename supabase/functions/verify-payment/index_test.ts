// OI-341 Piece A: handler-level tests of `verify-payment` stacking. The REAL
// supabase-js client runs on a fetch-level fake (../_shared/postgrest_fake_fetch.ts);
// the switch-OFF golden recording drives the UNMODIFIED origin/main module
// (../_shared/fixtures/verify_payment_origin_main.ts.txt) through the same scenario.
// Sanitizers are off for these tests: createClient() starts an auth refresh timer.
import { assert, assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  captureConsole,
  type Handler,
  alertInserts,
  helperReads,
  isMismatchRead,
  mismatchAlerts,
  mismatchReads,
  referralTrialRow,
  withoutMismatchRead,
  importWithEnv,
  iso,
  loadOriginMainHandler,
  normalizeRequests,
  OTHER_USER,
  PAY,
  paymentServer,
  recordPaidCalls,
  type Scenario,
  stripInstants,
  subscriptionInserts,
  trialRow,
  USER,
  verifyRequest,
  withSwitch,
  YEARLY_PAISE,
} from "../_shared/payment_writer_harness.ts";

const newHandler = (await importWithEnv(() => import("./index.ts"))).handler as Handler;
const originHandler = await loadOriginMainHandler("verify_payment_origin_main.ts.txt");

function t(name: string, fn: () => Promise<void>) {
  Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });
}

async function run(handler: Handler, sc: Scenario, switchValue: string | undefined, paymentId = PAY) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const before = Date.now();
    const { result: res, errors, all } = await withSwitch(switchValue, () => captureConsole(() => handler(verifyRequest(paymentId))));
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

t("ON: calls rpc/record_paid_subscription exactly once with the exact args; NO insert POST and NO helper GET", async () => {
  const r = await run(newHandler, withRpc({ rows: [] }), "true");
  assertEquals(r.res.status, 200);
  const calls = recordPaidCalls(r.server);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].body, {
    p_user_id: USER,
    p_plan: "monthly",
    p_payment_id: PAY,
    p_order_id: "order_TEST0001",
    p_signature: "verified_via_api:" + PAY.substring(0, 12),
  });
  assertEquals(subscriptionInserts(r.server).length, 0, "the function inserts; the writer must not");
  assertEquals(helperReads(r.server).length, 0);
  assertEquals(r.server.tables.subscriptions.length, 0);
});

t("ON, YEARLY payment: p_plan is 'yearly' (the plan is derived, never hard-coded)", async () => {
  const r = await run(newHandler, withRpc({ rows: [], amount: YEARLY_PAISE }), "true");
  assertEquals(r.res.status, 200);
  assertEquals((recordPaidCalls(r.server)[0].body as Record<string, unknown>).p_plan, "yearly");
});

for (const inserted of [true, false]) {
  t(`ON, out_inserted=${inserted}: the response end_date is the rpc's out_end_date as an ISO string (not the local now+days)`, async () => {
    const r = await run(newHandler, withRpc({ rows: [] }, { out_inserted: inserted }), "true");
    assertEquals(r.res.status, 200);
    assertEquals(r.body.verified, true);
    assertEquals(r.body.end_date, RPC_END_ISO);
    assertEquals(r.body.source, "razorpay_api");
    assert(r.all.some((l) => l.includes(`[verify-payment] stacking=on payment_id=${PAY} inserted=${inserted}`)));
  });
}

t("ON: an out_end_date with a +05:30 offset maps to the right instant", async () => {
  const r = await run(newHandler, withRpc({ rows: [] }, { out_end_date: "2026-12-01T15:30:00.5+05:30" }), "true");
  assertEquals(r.body.end_date, "2026-12-01T10:00:00.500Z");
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

// ── rpc failure: fail the call, page, never guess ───────────────────────────

t("ON + rpc DATABASE error: 500, NO insert, no promo, reconcile line with ids and code (no message), one alert row", async () => {
  const sc: Scenario = {
    ...promoScenario([trialRow(3)]),
    recordPaid: { status: 400, body: { code: "55P03", message: "could not obtain lock on advisory key", details: null, hint: null } },
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 500);
  assertEquals(r.body.verified, false);
  assertEquals(r.body.error, "Could not record subscription; please retry");
  assertMatch(String(r.body.request_id), /^[0-9a-f]{8}$/);
  assertEquals(recordPaidCalls(r.server).length, 1);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0);
  assertEquals(r.server.to("/rest/v1/promo_code_uses", "POST").length, 0);
  const line = r.errors.find((e) => e.startsWith("[verify-payment] stacking read failed"));
  assert(line, `reconcile log missing: ${r.errors.join(" | ")}`);
  assert(line.includes(`request_id=${r.body.request_id}`));
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
  assertEquals(row.context_json.fn, "verify-payment");
  assertEquals(row.context_json.request_id, r.body.request_id);
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
  const line = r.errors.find((e) => e.startsWith("[verify-payment] stacking read failed"));
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
  assertEquals({ ...bad.body, request_id: "x" }, { ...good.body, request_id: "x" });
  assert(bad.errors.some((e) => e.startsWith("[verify-payment] stacking read failed")));
});

for (const [label, body] of [["scalar 1 (the harness fallbackRpc answer)", 1], ["empty array", []]] as const) {
  t(`ON + malformed rpc answer (${label}): 500 and an alert with code bad_rpc_response`, async () => {
    const r = await run(newHandler, { rows: [], recordPaid: { body } }, "true");
    assertEquals(r.res.status, 500);
    assertEquals(r.body.verified, false);
    assertEquals(subscriptionInserts(r.server).length, 0);
    assertEquals(r.promoIncrements.length, 0);
    const line = r.errors.find((e) => e.startsWith("[verify-payment] stacking read failed"));
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
    assertEquals(now.body.end_date, row.end_date);
  });
}

t("OFF golden: yearly, and with a promo, are identical to origin/main too", async () => {
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

t("replay (an ACTIVE row for this payment): early return, NO rpc call, no insert, the canonical end", async () => {
  const done = trialRow(33, { id: "done", razorpay_payment_id: PAY });
  const r = await run(newHandler, withRpc({ rows: [done, trialRow(3)] }), "true");
  assertEquals(r.body.source, "existing");
  assertEquals(r.body.end_date, done.end_date);
  assertEquals(recordPaidCalls(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("replay (the row for this payment exists but is not 'active'): pre-SELECT arm, NO rpc call, no insert, canonical end, no promo", async () => {
  const done = trialRow(33, { id: "done", razorpay_payment_id: PAY, status: "cancelled" });
  const r = await run(newHandler, withRpc(promoScenario([done, trialRow(3)])), "true");
  assertEquals(r.res.status, 200);
  assertEquals(r.body.end_date, done.end_date);
  assertEquals(recordPaidCalls(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0, "a replay never redeems the promo");
});

t("plain 23505 race (switch OFF): reports the canonical row and does not redeem", async () => {
  const winner = trialRow(33, { id: "webhook-row", razorpay_payment_id: PAY });
  const sc: Scenario = {
    ...promoScenario([]),
    beforeInsert: (table, _row, srv) => {
      if (table === "subscriptions" && !srv.tables.subscriptions.some((x) => x.razorpay_payment_id === PAY)) {
        srv.tables.subscriptions.push(winner);
      }
    },
  };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 200);
  assertEquals(r.promoIncrements.length, 0);
  assertEquals(r.body.end_date, winner.end_date);
});

// ── payment-id format check (validation, not switch-gated) ──────────────────

for (const sw of [undefined, "true"]) {
  t(`invalid payment ids are rejected with 400 BEFORE any Razorpay call (switch ${sw ?? "absent"})`, async () => {
    for (const bad of ["pay_X?y=1", "pay_X/capture", "pay_X#1", "../x", "pay_" + "a".repeat(65), "pay_a,b", "xpay_abc", "pay_"]) {
      const r = await run(newHandler, { rows: [] }, sw, bad);
      assertEquals(r.res.status, 400, bad);
      assertEquals(r.body.error, "Invalid payment_id", bad);
      assertEquals(r.server.requests.filter((q) => q.host === "https://api.razorpay.com").length, 0, `${bad}: no Razorpay call`);
      assertEquals(r.server.to("/rest/v1/subscriptions").length, 0, `${bad}: no subscriptions access`);
    }
  });
}

t("an empty payment id keeps its existing 'Missing payment_id' answer; a conforming id passes", async () => {
  const empty = await run(newHandler, { rows: [] }, undefined, "");
  assertEquals(empty.res.status, 400);
  assertEquals(empty.body.error, "Missing payment_id");
  const id = "pay_ABCDEFGHIJ0123";
  const ok = await run(newHandler, { rows: [], paymentId: id }, undefined, id);
  assertEquals(ok.res.status, 200);
  assertEquals(ok.body.verified, true);
});

// ── OI-341 Piece B2a: switch log line (plan 2.3) ────────────────────────────

t("switch log line: OFF prints stacking_switch=off once, ON prints stacking_switch=on once, an existing row prints none", async () => {
  const count = (all: string[], v: string) => all.filter((l) => l === `[verify-payment] stacking_switch=${v} payment_id=${PAY}`).length;
  const off = await run(newHandler, { rows: [] }, undefined);
  assertEquals(count(off.all, "off"), 1);
  assertEquals(count(off.all, "on"), 0);
  const on = await run(newHandler, withRpc({ rows: [] }), "true");
  assertEquals(count(on.all, "on"), 1);
  assertEquals(count(on.all, "off"), 0);
  const cancelled = trialRow(33, { id: "done", razorpay_payment_id: PAY, status: "cancelled" });
  const existing = await run(newHandler, { rows: [cancelled] }, undefined);
  assertEquals(existing.all.filter((l) => l.includes("stacking_switch=")).length, 0);
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
  assertEquals(row.context_json.fn, "verify-payment");
  assertEquals(row.context_json.plan, "monthly");
  assertEquals(row.context_json.payment_id, PAY);
  assertEquals(row.context_json.user_id, USER);
  assertEquals(row.context_json.trial_end, trial.end_date);
  assertEquals(row.context_json.row_end, (subscriptionInserts(now.server)[0].body as Record<string, string>).end_date);
  assert(String(row.summary).startsWith("verify-payment: paid row recorded without stacking over an active trial"));
  assert(now.errors.some((e) => e === `[verify-payment] stacking_switch_mismatch payment_id=${PAY} user_id=${USER}`));
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

for (const [label, intercept] of [["an ERROR", errorMismatch], ["a HANG", hangMismatch]] as const) {
  t(`alarm: the check read returning ${label}: the same 200, the promo still redeemed, no alert`, async () => {
    const r = await run(newHandler, { ...promoScenario([referralTrialRow(5)]), intercept }, undefined);
    assertEquals(r.res.status, 200);
    assertEquals(r.body.verified, true);
    assertEquals(r.promoIncrements, ["HALF50"]);
    assertEquals(mismatchAlerts(r.server).length, 0);
    assert(r.errors.some((e) => e.startsWith("[verify-payment] stacking mismatch check unavailable")));
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

t("alarm: never when the payment's row already exists (active early return, or the pre-SELECT arm)", async () => {
  const active = await run(newHandler, { rows: [trialRow(33, { id: "done", razorpay_payment_id: PAY }), referralTrialRow(5)] }, undefined);
  assertEquals(mismatchReads(active.server).length, 0);
  const cancelled = await run(newHandler, { rows: [trialRow(33, { id: "done", razorpay_payment_id: PAY, status: "cancelled" }), referralTrialRow(5)] }, undefined);
  assertEquals(mismatchReads(cancelled.server).length, 0);
});

t("alarm: never on the 23505 race arm (weInsertedTheRow false: the webhook won the insert and owns the check)", async () => {
  const sc: Scenario = {
    rows: [referralTrialRow(5)],
    beforeInsert: (table, _row, srv) => {
      if (table === "subscriptions" && !srv.tables.subscriptions.some((x) => x.razorpay_payment_id === PAY)) {
        srv.tables.subscriptions.push(trialRow(33, { id: "webhook-row", razorpay_payment_id: PAY }));
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

t("ON + rpc failure: verify-payment keeps the DEFAULT 3 s alert bound (only the webhook passes 1000)", async () => {
  const r = await run(newHandler, { rows: [], recordPaid: { status: 400, body: { code: "55P03", message: "x" } }, alerts: { dedup: "hang" } }, "true");
  assertEquals(r.res.status, 500);
  const ms = r.after - r.before;
  assert(ms >= 2900 && ms < 5500, `one hung 3 s dedup read, took ${ms} ms`);
});

// ── OI-341 Piece B2a: a captured payment no row can record is paged (hermes seat 4 F4) ──

t("no-match: a promo payment whose code was DELETED mid-checkout: the same 400, no row, and one critical payment_record_failed alert (amount_no_match)", async () => {
  const sc: Scenario = { rows: [], amount: 17450, notes: { promo_code: "HALF50" }, promoRows: [] };
  const r = await run(newHandler, sc, undefined);
  assertEquals(r.res.status, 400);
  assertEquals(r.body, { verified: false, error: "Payment amount does not match any known plan price" });
  assertEquals(subscriptionInserts(r.server).length, 0);
  const alerts = alertInserts(r.server);
  assertEquals(alerts.length, 1);
  const row = alerts[0].body as Record<string, any>;
  assertEquals(row.source, "payment_record_failed");
  assertEquals(row.context_json.fn, "verify-payment");
  assertEquals(row.context_json.code, "amount_no_match");
  assertEquals(row.context_json.payment_id, PAY);
  assertEquals(row.context_json.amount_paise, 17450);
});

t("no-match control: a matching promo payment records the row and writes no alert", async () => {
  const r = await run(newHandler, promoScenario([]), undefined);
  assertEquals(r.res.status, 200);
  assertEquals(alertInserts(r.server).length, 0);
});

// ── payment-hardening U1 (OI-350 / OI-359): ownership before any side effect ──
// The harness's Razorpay route always answers a CAPTURED payment, so these tests answer the GET (and the
// capture) through `intercept`, which runs first; every request, the intercepted ones included, is recorded.

/** Answers GET /v1/payments/PAY with `entity`, and the capture POST with the same entity, captured. */
function razorpayEntity(entity: Record<string, unknown>): Scenario["intercept"] {
  return (req) => {
    if (req.host !== "https://api.razorpay.com") return undefined;
    if (req.method === "GET" && req.path === `/v1/payments/${PAY}`) {
      return new Response(JSON.stringify(entity), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (req.method === "POST" && req.path === `/v1/payments/${PAY}/capture`) {
      const captured = { ...entity, status: "captured", captured: true };
      return new Response(JSON.stringify(captured), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    return undefined;
  };
}

function entity(status: string, notes: unknown): Record<string, unknown> {
  return { id: PAY, status, captured: status === "captured", amount: 34900, currency: "INR", order_id: "order_TEST0001", notes };
}

const captures = (r: { server: { to: (p: string, m?: string) => unknown[] } }) => r.server.to("/v1/payments/", "POST");

t("U1: ANOTHER user's AUTHORIZED payment: 403, and no capture request is sent", async () => {
  const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity("authorized", { user_id: OTHER_USER })) }, undefined);
  assertEquals(r.res.status, 403);
  assertEquals(r.body, { verified: false, error: "Payment does not belong to this user" });
  assertEquals(captures(r).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("U1: ANOTHER user's CREATED payment: 403, and its status is not echoed", async () => {
  const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity("created", { user_id: OTHER_USER })) }, undefined);
  assertEquals(r.res.status, 403);
  assert(!r.text.includes("Payment status is"), r.text);
  assert(!r.text.includes("created"), r.text);
  assertEquals(captures(r).length, 0);
});

for (const [label, notes] of [["no user_id key", { plan: "monthly" }], ["Razorpay's empty-notes array", []]] as const) {
  t(`U1: an AUTHORIZED payment with ${label}: 400, and no capture request is sent`, async () => {
    const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity("authorized", notes)) }, undefined);
    assertEquals(r.res.status, 400);
    assertEquals(r.body, { verified: false, error: "Missing user_id in payment notes" });
    assertEquals(captures(r).length, 0);
  });
}

t("U1 control: the caller's OWN authorized payment is still captured once and recorded (200)", async () => {
  const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity("authorized", { user_id: USER })) }, undefined);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.verified, true);
  const posts = captures(r) as Array<{ path: string; body: Record<string, unknown> }>;
  assertEquals(posts.length, 1);
  assertEquals(posts[0].path, `/v1/payments/${PAY}/capture`);
  assertEquals(posts[0].body, { amount: 34900, currency: "INR" });
  assertEquals(subscriptionInserts(r.server).length, 1);
});

// The 403 is a STRICT compare: a notes.user_id of another TYPE that a loose `!=` would equate with the caller
// (an array holding the id coerces to the same string) must still be refused, before any capture.
for (const [label, userId] of [["an array holding the caller's id", [USER]], ["a number", 123], ["an object", { id: USER }]] as const) {
  t(`U1: an AUTHORIZED payment whose notes.user_id is ${label}: 403, and no capture request is sent`, async () => {
    const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity("authorized", { user_id: userId })) }, undefined);
    assertEquals(r.res.status, 403);
    assertEquals(r.body, { verified: false, error: "Payment does not belong to this user" });
    assertEquals(captures(r).length, 0);
  });
}

// Mirror of the foreign-payment refusals: the caller's OWN payment that is neither captured nor authorized
// still gets today's 200 status echo (the client polls on it), with no capture request.
for (const status of ["created", "failed"]) {
  t(`U1 control: the caller's OWN ${status.toUpperCase()} payment: 200 with its status echoed, no capture`, async () => {
    const r = await run(newHandler, { rows: [], intercept: razorpayEntity(entity(status, { user_id: USER })) }, undefined);
    assertEquals(r.res.status, 200);
    assertEquals(r.body, { verified: false, error: `Payment status is '${status}', not 'captured'` });
    assertEquals(captures(r).length, 0);
    assertEquals(subscriptionInserts(r.server).length, 0);
  });
}

// ── payment-hardening U0 (OI-360): a log line carries a code, a type or a bounded value, never a whole object ──
// captureConsole prints an object through JSON.stringify, so a whole-object log of a PostgREST error SHOWS its
// `details`. Each leak test therefore runs the same scenario through the frozen origin/main handler first and
// requires the secret to be VISIBLE there (the positive control), then requires it absent from the new handler.

const SECRET = "SIGf3b1c2d4e5a6978812345678abcdef00112233";
const FORGED = "monthly\n[verify-payment] FORGED-LINE " + "Z".repeat(300);
const pgError = (status: number, code: string) =>
  new Response(JSON.stringify({ code, message: "insert or update violates a constraint", details: `Key (razorpay_signature)=(${SECRET})`, hint: SECRET }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const anyLine = (all: string[], needle: string) => all.some((l) => l.includes(needle));

async function runRequest(handler: Handler, sc: Scenario, req: Request) {
  const { server, promoIncrements } = paymentServer(sc);
  server.install();
  try {
    const { result: res, all } = await withSwitch(undefined, () => captureConsole(() => handler(req)));
    return { res, all, server, promoIncrements };
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
  const line = r.errors.find((l) => l.startsWith("[verify-payment] subscription insert failed (non-23505)"));
  assert(line, r.errors.join("\n"));
  assertMatch(line!, new RegExp(`request_id=[0-9a-f]{8} payment_id=${PAY} user_id=${USER} plan=monthly amount_paise=34900 code=23503$`));
});

t("U0 log: a refused capture logs status and Razorpay's code/reason, never the description (control: origin logged the body)", async () => {
  const intercept: Scenario["intercept"] = (req) => {
    if (req.host !== "https://api.razorpay.com") return undefined;
    if (req.method === "GET") return new Response(JSON.stringify(entity("authorized", { user_id: USER })), { status: 200 });
    return new Response(JSON.stringify({ error: { code: "BAD_REQUEST_ERROR", description: `card ${SECRET}`, reason: "capture_failed", field: "amount" } }), { status: 400 });
  };
  const before = await run(originHandler, { rows: [], intercept }, undefined);
  assert(anyLine(before.all, SECRET), "positive control");
  const r = await run(newHandler, { rows: [], intercept }, undefined);
  assertEquals(r.res.status, 502);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(anyLine(r.errors, `capture failed for ${PAY}: status=400 code="BAD_REQUEST_ERROR" reason="capture_failed"`), r.errors.join("\n"));
});

t("U0 log: the client's raw `plan` is bounded and quoted: no forged line, no unbounded text (control: origin printed it raw)", async () => {
  const req = () => new Request("https://fn.test/verify-payment", {
    method: "POST",
    headers: { Authorization: "Bearer user-jwt-1", "Content-Type": "application/json" },
    body: JSON.stringify({ payment_id: PAY, plan: FORGED }),
  });
  const before = await runRequest(originHandler, { rows: [] }, req());
  assert(anyLine(before.all, "\n[verify-payment] FORGED-LINE"), "positive control");
  const r = await runRequest(newHandler, { rows: [] }, req());
  assertEquals(r.res.status, 200);
  assert(!anyLine(r.all, "\n[verify-payment] FORGED-LINE"), r.all.join("\n"));
  assert(!anyLine(r.all, "Z".repeat(50)), "the value is bounded");
  assert(anyLine(r.all, `Plan mismatch: client claimed ${JSON.stringify(FORGED.slice(0, 40))}`), r.all.join("\n"));
});

t("U0 log: a failed idempotency pre-SELECT logs its code, never its message (control: origin logged the message)", async () => {
  const intercept: Scenario["intercept"] = (req) => {
    if (req.method !== "GET" || req.path !== "/rest/v1/subscriptions") return undefined;
    const q = new Map(req.query);
    if (q.get("select") === "id,end_date" && !q.has("status")) {
      return new Response(JSON.stringify({ code: "XX000", message: `read failed ${SECRET}` }), { status: 500 });
    }
    return undefined;
  };
  const before = await run(originHandler, { rows: [], intercept }, undefined);
  assert(anyLine(before.all, SECRET), "positive control");
  const r = await run(newHandler, { rows: [], intercept }, undefined);
  assertEquals(r.res.status, 200);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(anyLine(r.all, "[verify-payment] idempotency pre-SELECT failed (continuing to insert): code=XX000"), r.all.join("\n"));
});

// R-6: redeemPromo now checks the RETURNED errors (supabase-js does not throw them). Log only: the response,
// the row and the request sequence are those of a redemption that succeeded.
for (const [label, path, expectLine] of [
  ["increment_promo_used_count", "/rest/v1/rpc/increment_promo_used_count", "[verify-payment] promo redemption: increment_promo_used_count failed code=P0001"],
  ["promo_code_uses insert", "/rest/v1/promo_code_uses", "[verify-payment] promo redemption: promo_code_uses insert failed code=P0001"],
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

// B-pass of commit 2: the two remaining sites that logged client text or a database message.
const FORGED_PROMO = "HALF50\n[verify-payment] FORGED-LINE " + "Z".repeat(300);
// Built, not spelled: a census test requires every file naming the counter RPC to be a known caller.
const COUNTER_RPC = "consume_" + "quota";

t("U0 log: an unmatched amount logs the checkout's promo code bounded and quoted (control: origin printed it raw)", async () => {
  const sc = (): Scenario => ({ rows: [], amount: 12345, notes: { promo_code: FORGED_PROMO } });
  const before = await run(originHandler, sc(), undefined);
  assert(anyLine(before.all, "\n[verify-payment] FORGED-LINE"), "positive control");
  const r = await run(newHandler, sc(), undefined);
  assertEquals(r.res.status, before.res.status);
  assert(!anyLine(r.all, "\n[verify-payment] FORGED-LINE") && !anyLine(r.all, "Z".repeat(50)), r.all.join("\n"));
  assert(
    anyLine(r.errors, `Amount mismatch: 12345 paise does not match any plan (promo: ${JSON.stringify(FORGED_PROMO.slice(0, 40))})`),
    r.errors.join("\n"),
  );
});

t("U0 log: a failed rate-limit counter logs its code, never its message (control: origin logged the message)", async () => {
  const sc = (): Scenario => ({
    rows: [],
    intercept: (req) =>
      req.method === "POST" && req.path === `/rest/v1/rpc/${COUNTER_RPC}`
        ? new Response(JSON.stringify({ code: "XX000", message: `counter unavailable ${SECRET}`, details: SECRET }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        })
        : undefined,
  });
  const before = await run(originHandler, sc(), undefined);
  assert(anyLine(before.all, SECRET), "positive control: the origin handler logged the message");
  const r = await run(newHandler, sc(), undefined);
  assertEquals(r.res.status, 429);
  assertEquals(r.res.status, before.res.status);
  assert(!anyLine(r.all, SECRET), r.all.join("\n"));
  assert(anyLine(r.errors, `[verify-payment] ${COUNTER_RPC} FAILED for user=${USER} (fail-closed): code=XX000`), r.errors.join("\n"));
});

// B-pass beee28f0d9f2 finding 6: a counter answer that is neither -1 nor a count fails CLOSED like an error.
for (const [label, value] of [["null", null], ["0", 0], ["a fraction", 1.5]] as const) {
  t(`the rate-limit counter answers ${label} -> 429 and a code-only line (control: origin went on)`, async () => {
    const sc = (): Scenario => ({
      rows: [],
      intercept: (req) =>
        req.method === "POST" && req.path === `/rest/v1/rpc/${COUNTER_RPC}`
          ? new Response(JSON.stringify(value), { status: 200, headers: { "Content-Type": "application/json" } })
          : undefined,
    });
    const before = await run(originHandler, sc(), undefined);
    assert(before.res.status !== 429, `positive control: origin answered ${before.res.status}`);
    const r = await run(newHandler, sc(), undefined);
    assertEquals(r.res.status, 429);
    assert(anyLine(r.errors, `[verify-payment] ${COUNTER_RPC} FAILED for user=${USER} (fail-closed): code=bad_result`), r.errors.join("\n"));
  });
}
