// OI-341 Piece A: handler-level tests of `verify-payment` stacking. The REAL
// supabase-js client runs on a fetch-level fake (../_shared/postgrest_fake_fetch.ts);
// the switch-OFF golden recording drives the UNMODIFIED origin/main module
// (../_shared/fixtures/verify_payment_origin_main.ts.txt) through the same scenario.
// Sanitizers are off for these tests: createClient() starts an auth refresh timer.
import { assert, assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  captureConsole,
  type Handler,
  helperReads,
  importWithEnv,
  iso,
  loadOriginMainHandler,
  normalizeRequests,
  PAY,
  paymentServer,
  type Scenario,
  stripInstants,
  subscriptionInserts,
  trialRow,
  USER,
  OTHER_USER,
  verifyRequest,
  withSwitch,
  YEARLY_PAISE,
} from "../_shared/payment_writer_harness.ts";
import { jsonResponse } from "../_shared/postgrest_fake_fetch.ts";

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

// ── stacking ON ─────────────────────────────────────────────────────────────

t("ON + active trial: end_date = trialEnd + 30, start_date = payment time, response reports the stored end", async () => {
  const trial = trialRow(3);
  const r = await run(newHandler, { rows: [trial] }, "true");
  assertEquals(r.res.status, 200);
  const inserts = subscriptionInserts(r.server);
  assertEquals(inserts.length, 1);
  const row = inserts[0].body as Record<string, string>;
  assertEquals(row.end_date, plusDays(trial.end_date as string, 30));
  assert(Date.parse(row.start_date) >= r.before && Date.parse(row.start_date) <= r.after, "start_date is the payment time");
  assertEquals(row.plan, "monthly");
  assertEquals(r.body.end_date, row.end_date);
  assertEquals(r.body.verified, true);
  assertEquals(helperReads(r.server).length, 1);
});

t("ON + active trial, YEARLY payment: end_date = trialEnd + 365", async () => {
  const trial = trialRow(3);
  const r = await run(newHandler, { rows: [trial], amount: YEARLY_PAISE }, "true");
  const row = subscriptionInserts(r.server)[0].body as Record<string, string>;
  assertEquals(row.plan, "yearly");
  assertEquals(row.end_date, plusDays(trial.end_date as string, 365));
  assertEquals(r.body.end_date, row.end_date);
});

t("ON + no active row: today's values (start + 30)", async () => {
  const r = await run(newHandler, { rows: [] }, "true");
  const row = subscriptionInserts(r.server)[0].body as Record<string, string>;
  assertEquals(row.end_date, plusDays(row.start_date, 30));
  assertEquals(r.body.end_date, row.end_date);
});

t("ON: distractors are ignored (another user's PRO, a cancelled row, an expired row); the latest ACTIVE of several wins", async () => {
  const keep = trialRow(5, { id: "keep", razorpay_payment_id: "pay_OLD0000000001" });
  const rows = [
    trialRow(300, { id: "other-user", user_id: OTHER_USER }),
    trialRow(200, { id: "cancelled", status: "cancelled" }),
    trialRow(-2, { id: "expired" }),
    trialRow(2, { id: "earlier" }),
    keep,
  ];
  const r = await run(newHandler, { rows }, "true");
  const row = subscriptionInserts(r.server)[0].body as Record<string, string>;
  assertEquals(row.end_date, plusDays(keep.end_date as string, 30));
});

t("ON: the promo is redeemed exactly once on a first insert", async () => {
  const trial = trialRow(3);
  const r = await run(newHandler, promoScenario([trial]), "true");
  assertEquals(r.res.status, 200);
  assertEquals(r.promoIncrements, ["HALF50"]);
  assertEquals(r.server.to("/rest/v1/promo_code_uses", "POST").length, 1);
  assertEquals((subscriptionInserts(r.server)[0].body as Record<string, string>).end_date, plusDays(trial.end_date as string, 30));
});

// ── read failure: fail the call, never guess ────────────────────────────────

const isHelperRead = (q: Array<[string, string]>) => q.some(([k, v]) => k === "end_date" && v.startsWith("gt."));

t("ON + helper read DATABASE error: 500, NO insert, no promo, the reconcile log line carries the ids and the code", async () => {
  const sc: Scenario = {
    ...promoScenario([trialRow(3)]),
    intercept: (req) =>
      req.method === "GET" && req.path === "/rest/v1/subscriptions" && isHelperRead(req.query)
        ? jsonResponse(500, { code: "57014", message: "canceling statement due to statement timeout" })
        : undefined,
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 500);
  assertEquals(r.body.verified, false);
  assertMatch(String(r.body.request_id), /^[0-9a-f]{8}$/);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0);
  assertEquals(r.server.to("/rest/v1/promo_code_uses", "POST").length, 0);
  const line = r.errors.find((e) => e.startsWith("[verify-payment] stacking read failed"));
  assert(line, `reconcile log missing: ${r.errors.join(" | ")}`);
  assert(line.includes(`request_id=${r.body.request_id}`));
  assert(line.includes(`payment_id=${PAY}`));
  assert(line.includes(`user_id=${USER}`));
  assert(line.includes("code=57014"));
  assert(line.includes("plan=monthly"), "the reconcile line carries the plan");
  assert(line.includes("amount_paise=17450"), "the reconcile line carries the amount paid");
  assert(!line.includes("canceling statement"), "the error MESSAGE must never be logged");
});

t("ON + helper read THROWS (transport failure): 500, NO insert, log line with a non-empty code", async () => {
  const sc: Scenario = {
    rows: [trialRow(3)],
    intercept: (req) => (req.method === "GET" && req.path === "/rest/v1/subscriptions" && isHelperRead(req.query) ? "throw" : undefined),
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 500);
  assertEquals(r.body.verified, false);
  assertEquals(subscriptionInserts(r.server).length, 0);
  const line = r.errors.find((e) => e.startsWith("[verify-payment] stacking read failed"));
  assert(line, "reconcile log missing");
  assertMatch(line, /code=\S+/);
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
    assertEquals(normalizeRequests(now.server.requests), normalizeRequests(golden.server.requests));
    assertEquals(stripInstants(now.body), stripInstants(golden.body));
    assertEquals(now.promoIncrements, golden.promoIncrements);
  }
});

// ── idempotency: replays and races never read, never stack ──────────────────

t("replay (an ACTIVE row for this payment): early return, no helper read, no insert, the canonical end", async () => {
  const done = trialRow(33, { id: "done", razorpay_payment_id: PAY });
  const r = await run(newHandler, { rows: [done, trialRow(3)] }, "true");
  assertEquals(r.body.source, "existing");
  assertEquals(r.body.end_date, done.end_date);
  assertEquals(helperReads(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
});

t("replay (the row for this payment exists but is not 'active'): pre-SELECT arm, no helper read, no insert, canonical end", async () => {
  const done = trialRow(33, { id: "done", razorpay_payment_id: PAY, status: "cancelled" });
  const r = await run(newHandler, promoScenario([done, trialRow(3)]), "true");
  assertEquals(r.res.status, 200);
  assertEquals(r.body.end_date, done.end_date);
  assertEquals(helperReads(r.server).length, 0);
  assertEquals(subscriptionInserts(r.server).length, 0);
  assertEquals(r.promoIncrements.length, 0, "a replay never redeems the promo");
});

t("sibling-writer interleave: the other writer's row for the SAME payment appears just before the helper read - the helper ignores it, the 23505 arm reports the canonical row, no promo", async () => {
  const trial = trialRow(3);
  const canonicalEnd = plusDays(trial.end_date as string, 30);
  let planted = false;
  const sc: Scenario = {
    ...promoScenario([trial]),
    intercept: (req) => {
      if (!planted && req.method === "GET" && req.path === "/rest/v1/subscriptions" && isHelperRead(req.query)) {
        planted = true;
        sc.rows!.push(trialRow(33, { id: "webhook-row", razorpay_payment_id: PAY, end_date: canonicalEnd }));
      }
      return undefined;
    },
  };
  const { server, promoIncrements } = paymentServer(sc);
  // The scenario's rows array is the server's live table (paymentServer passes it through).
  assertEquals(server.tables.subscriptions, sc.rows);
  server.install();
  try {
    const { result: res } = await withSwitch("true", () => captureConsole(() => newHandler(verifyRequest())));
    const body = await res.json();
    assertEquals(res.status, 200);
    const attempted = subscriptionInserts(server)[0].body as Record<string, string>;
    assertEquals(attempted.end_date, canonicalEnd, "the sibling's row must not become the stacking base");
    assertEquals(body.end_date, canonicalEnd, "the response reports the canonical (sibling) row");
    assertEquals(promoIncrements.length, 0, "the creator owns the promo; this path must not redeem");
    assertEquals(server.tables.subscriptions.filter((r) => r.razorpay_payment_id === PAY).length, 1);
  } finally {
    server.restore();
  }
});

t("ON + 23505 race + the winner's row cannot be re-read: the response still reports the STACKED value, not start + 30", async () => {
  const trial = trialRow(3);
  const stacked = plusDays(trial.end_date as string, 30);
  const sc: Scenario = {
    rows: [trial],
    beforeInsert: (table, _row, srv) => {
      if (table === "subscriptions" && !srv.tables.subscriptions.some((x) => x.razorpay_payment_id === PAY)) {
        srv.tables.subscriptions.push(trialRow(33, { id: "webhook-row", razorpay_payment_id: PAY }));
      }
    },
    // The race re-read is the only subscriptions GET with select=end_date, a payment id filter and NO end_date filter.
    intercept: (req) =>
      req.method === "GET" && req.path === "/rest/v1/subscriptions" &&
        req.query.some(([k, v]) => k === "select" && v === "end_date") &&
        req.query.some(([k]) => k === "razorpay_payment_id") && !isHelperRead(req.query)
        ? jsonResponse(500, { code: "XX000", message: "boom" })
        : undefined,
  };
  const r = await run(newHandler, sc, "true");
  assertEquals(r.res.status, 200);
  assertEquals(r.body.end_date, stacked);
  assertEquals(r.promoIncrements.length, 0);
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
