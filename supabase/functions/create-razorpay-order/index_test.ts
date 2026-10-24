// OI-341 Piece B2a: handler-level tests of the purchase door
// (docs/plans/oi341-piece-b2-door.md 2.2, section 3). The REAL supabase-js client
// runs on the fetch-level fake (../_shared/postgrest_fake_fetch.ts); the Razorpay
// Orders API is faked. The door-SHUT golden recording drives the UNMODIFIED
// origin/main module (../_shared/fixtures/create_razorpay_order_origin_main.ts.txt)
// through each scenario. It pins the response status and body, the Razorpay order
// request and the guard read's table and filters, NOT the guard read's URL (the
// read changes from order + limit 1 + maybeSingle to one unlimited read), and not
// the read-error case (a deliberate change with its own tests below).
// Sanitizers are off: createClient() starts an auth refresh timer.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeServer, jsonResponse, type RecordedRequest, type Row } from "../_shared/postgrest_fake_fetch.ts";
import { istDateStr } from "../_shared/ist_date.ts";
import {
  captureConsole,
  type Handler,
  iso,
  loadOriginMainHandler,
  MODULE_ENV,
  stripInstants,
  TOKEN,
  USER,
  withSwitch,
  withTrialPurchaseSwitch,
} from "../_shared/payment_writer_harness.ts";

const newHandler = (await import("./index.ts")).handler as Handler;
const retryMinutes = (await import("./index.ts")).retryMinutes as (retryAfterSeconds: number) => string;
const originHandler = await loadOriginMainHandler("create_razorpay_order_origin_main.ts.txt");

function t(name: string, fn: () => Promise<void>) {
  Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });
}

/** The door reads its env per request, so MODULE_ENV is set around each call (and restored). */
async function withModuleEnv<T>(fn: () => Promise<T>): Promise<T> {
  const saved = new Map<string, string | undefined>();
  for (const [k, v] of Object.entries(MODULE_ENV)) {
    saved.set(k, Deno.env.get(k));
    Deno.env.set(k, v);
  }
  try {
    return await fn();
  } finally {
    for (const [k, v] of saved) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

async function withEnvVar<T>(name: string, value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const before = Deno.env.get(name);
  if (value === undefined) Deno.env.delete(name);
  else Deno.env.set(name, value);
  try {
    return await fn();
  } finally {
    if (before === undefined) Deno.env.delete(name);
    else Deno.env.set(name, before);
  }
}

const paid = (endInDays: number, over: Row = {}): Row => ({
  id: "paid-1",
  user_id: USER,
  plan: "monthly",
  status: "active",
  end_date: iso(endInDays),
  razorpay_payment_id: "pay_OLD0000000001",
  ...over,
});
const trial = (endInDays: number, over: Row = {}): Row => ({
  id: "trial-1",
  user_id: USER,
  plan: "referral_trial",
  status: "active",
  end_date: iso(endInDays),
  razorpay_payment_id: null,
  ...over,
});

interface DoorScenario {
  rows?: Row[];
  promoRows?: Row[];
  body?: Record<string, unknown>;
  guardError?: boolean;
  noAuth?: boolean;
  /** The order counter's answer (payment-hardening U3): a count (1 = under the limit, the default), -1, or an RPC error. */
  quota?: number | "error" | "null";
  /** The promo_codes read answers 500. */
  promoError?: boolean;
}

/** `guards` sets DISABLE_ORDER_ABUSE_GUARDS (unset = the U3 guards ON). */
type Switches = { stack?: string; door?: string; guards?: string };
// The RPC's name is built, not spelled: census tests scan _test.ts files for the literal.
const CONSUME_QUOTA_RPC = "consume_" + "quota";
const GUARDS_SWITCH = "DISABLE_ORDER_ABUSE_GUARDS";
const OPEN: Switches = { stack: "true", door: "true" };
const SHUT: Switches = {};

async function run(handler: Handler, sc: DoorScenario, sw: Switches) {
  const server = new FakeServer({
    tables: { subscriptions: sc.rows ?? [], promo_codes: sc.promoRows ?? [] },
    users: { [TOKEN]: { id: USER } },
    // Any RPC not routed is the order counter: `quota` (default 1, under the limit).
    fallbackRpc: () => (sc.quota === "null" ? null : typeof sc.quota === "number" ? sc.quota : 1),
    razorpay: (req) => {
      if (req.method === "POST" && req.path === "/v1/orders") {
        return jsonResponse(200, { id: "order_FAKE0001", amount: req.body.amount, currency: req.body.currency });
      }
      return jsonResponse(404, { error: { description: "unrouted" } });
    },
    intercept: (req) =>
      sc.guardError && req.method === "GET" && req.path === "/rest/v1/subscriptions"
        ? jsonResponse(500, { code: "XX000", message: "guard read failed" })
        : sc.quota === "error" && req.path === `/rest/v1/rpc/${CONSUME_QUOTA_RPC}`
        ? jsonResponse(500, { code: "XX000", message: "counter unavailable" })
        : sc.promoError && req.method === "GET" && req.path === "/rest/v1/promo_codes"
        ? jsonResponse(500, { code: "XX000", message: "promo read failed" })
        : undefined,
  });
  server.install();
  try {
    const req = new Request("https://fn.test/create-razorpay-order", {
      method: "POST",
      headers: { ...(sc.noAuth ? {} : { Authorization: `Bearer ${TOKEN}` }), "Content-Type": "application/json" },
      body: JSON.stringify(sc.body ?? { plan: "monthly" }),
    });
    const res = await withModuleEnv(() =>
      withEnvVar(GUARDS_SWITCH, sw.guards, () =>
        withSwitch(sw.stack, () => withTrialPurchaseSwitch(sw.door, () => handler(req)))
      )
    );
    const body = JSON.parse(await res.text()) as Record<string, unknown>;
    return { res, body, server };
  } finally {
    server.restore();
  }
}

function orderCalls(server: FakeServer): RecordedRequest[] {
  return server.requests.filter((r) => r.host === "https://api.razorpay.com" && r.path === "/v1/orders");
}

/** The order request body with the time-based receipt suffix removed. */
function orderBody(server: FakeServer): Record<string, any> | null {
  const c = orderCalls(server);
  if (c.length === 0) return null;
  const b = structuredClone(c[0].body) as Record<string, any>;
  b.receipt = String(b.receipt).replace(/_\d+$/, "_<ms>");
  return b;
}

/** The guard read's table and FILTERS (not its select/order/limit): user, status, end_date operator. */
function guardFilters(server: FakeServer): unknown[] {
  return server.to("/rest/v1/subscriptions", "GET").map((r) =>
    stripInstants({
      path: r.path,
      filters: r.query.filter(([k]) => !["select", "order", "limit"].includes(k)),
    })
  );
}

// ── door SHUT: the golden recording against origin/main ─────────────────────

const SHUT_STATES: Array<[string, Switches]> = [
  ["both unset", {}],
  ["door on, stacking OFF", { door: "true" }],
  ["stacking on, door OFF", { stack: "true" }],
  ["door ' true'", { stack: "true", door: " true" }],
  ["door 'TRUE'", { stack: "true", door: "TRUE" }],
  ["stacking 'TRUE'", { stack: "TRUE", door: "true" }],
];

const GOLDEN_SCENARIOS: Array<[string, () => DoorScenario]> = [
  ["no row (order created)", () => ({ rows: [] })],
  ["referral trial row (409)", () => ({ rows: [trial(4)] })],
  ["paid row (409)", () => ({ rows: [paid(20)] })],
  ["paid + later trial (409, latest row)", () => ({ rows: [paid(20), trial(25, { id: "t2" })] })],
  ["expired paid only (order created)", () => ({ rows: [paid(-1)] })],
  ["another user's paid row (order created)", () => ({ rows: [paid(20, { user_id: "33333333-3333-4333-8333-333333333333" })] })],
  ["yearly with a promo", () => ({
    rows: [],
    body: { plan: "yearly", promo_code: "half50" },
    promoRows: [{ code: "HALF50", discount_pct: 50, is_active: true, valid_until: "2099-01-01T00:00:00Z", max_uses: null, used_count: 0 }],
  })],
  ["invalid plan (400)", () => ({ rows: [], body: { plan: "weekly" } })],
  ["no auth (401)", () => ({ rows: [], noAuth: true })],
];

for (const [stateLabel, sw] of SHUT_STATES) {
  t(`door SHUT (${stateLabel}): identical to origin/main for every scenario, and no stacks_after anywhere`, async () => {
    for (const [label, make] of GOLDEN_SCENARIOS) {
      const golden = await run(originHandler, make(), SHUT);
      const now = await run(newHandler, make(), sw);
      assertEquals(now.res.status, golden.res.status, label);
      assertEquals(stripInstants(now.body), stripInstants(golden.body), label);
      assertEquals(orderBody(now.server), orderBody(golden.server), label);
      assertEquals(guardFilters(now.server), guardFilters(golden.server), label);
      assert(!("stacks_after" in now.body), `${label}: the shut response has no stacks_after key`);
      assert(!("stacks_after" in (orderBody(now.server)?.notes ?? {})), `${label}: no stacks_after note`);
    }
  });
}

t("door SHUT golden sanity: the scenarios really cover 200, 409, 400 and 401", async () => {
  const seen = new Set<number>();
  for (const [, make] of GOLDEN_SCENARIOS) seen.add((await run(newHandler, make(), SHUT)).res.status);
  assertEquals([...seen].sort(), [200, 400, 401, 409]);
});

t("door SHUT: a trial row answers today's 409 already_pro with the trial's plan and end", async () => {
  const row = trial(4);
  const r = await run(newHandler, { rows: [row] }, SHUT);
  assertEquals(r.res.status, 409);
  assertEquals(r.body, {
    error: "You're already a PRO member.",
    error_code: "already_pro",
    current_plan: "referral_trial",
    current_expires_at: row.end_date,
  });
  assertEquals(orderCalls(r.server).length, 0);
});

// ── the guard read error: fail CLOSED, in both switch states ────────────────

for (const [label, sw] of [["shut", SHUT], ["open", OPEN]] as const) {
  t(`guard read ERROR (door ${label}): 500 subscription_check_unavailable, NO Razorpay order`, async () => {
    const r = await run(newHandler, { rows: [], guardError: true }, sw);
    assertEquals(r.res.status, 500);
    assertEquals(r.body.error, "Could not verify your subscription. Please try again.");
    assertEquals(r.body.error_code, "subscription_check_unavailable");
    assert(/^[0-9a-f]{8}$/.test(String(r.body.request_id)));
    assertEquals(orderCalls(r.server).length, 0);
  });
}

t("guard read ERROR: origin/main created the order (the fail-open hole this batch closes)", async () => {
  const r = await run(originHandler, { rows: [], guardError: true }, SHUT);
  assertEquals(r.res.status, 200);
  assertEquals(orderCalls(r.server).length, 1);
});

// ── door OPEN ───────────────────────────────────────────────────────────────

t("door OPEN + a referral trial: 200, stacks_after = the trial end in the response AND the order notes", async () => {
  const row = trial(4);
  const r = await run(newHandler, { rows: [row] }, OPEN);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.order_id, "order_FAKE0001");
  assertEquals(r.body.stacks_after, row.end_date);
  assertEquals(orderBody(r.server)!.notes.stacks_after, row.end_date);
  assertEquals(orderBody(r.server)!.notes.user_id, USER);
});

t("door OPEN + no row: 200 with stacks_after null, and no stacks_after note", async () => {
  const r = await run(newHandler, { rows: [] }, OPEN);
  assertEquals(r.res.status, 200);
  assert("stacks_after" in r.body);
  assertEquals(r.body.stacks_after, null);
  assert(!("stacks_after" in orderBody(r.server)!.notes));
});

t("door OPEN + a paid row alone: 409 already_pro, no order", async () => {
  const row = paid(20);
  const r = await run(newHandler, { rows: [row] }, OPEN);
  assertEquals(r.res.status, 409);
  assertEquals(r.body.current_plan, "monthly");
  assertEquals(r.body.current_expires_at, row.end_date);
  assertEquals(orderCalls(r.server).length, 0);
});

t("door OPEN + paid and trial rows: 409 (one paid row is enough)", async () => {
  const r = await run(newHandler, { rows: [trial(4), paid(20)] }, OPEN);
  assertEquals(r.res.status, 409);
  assertEquals(orderCalls(r.server).length, 0);
});

t("door OPEN + a trial ending LATER than the paid row: 409 reports the PAID row, not the trial", async () => {
  const p = paid(20, { plan: "yearly" });
  const r = await run(newHandler, { rows: [p, trial(40)] }, OPEN);
  assertEquals(r.res.status, 409);
  assertEquals(r.body.current_plan, "yearly");
  assertEquals(r.body.current_expires_at, p.end_date);
});

t("door OPEN + two paid rows: 409 reports the LATEST-ending paid row", async () => {
  const later = paid(50, { id: "p2", plan: "yearly" });
  const r = await run(newHandler, { rows: [paid(20), later] }, OPEN);
  assertEquals(r.res.status, 409);
  assertEquals(r.body.current_expires_at, later.end_date);
});

t("door OPEN + two trial rows: stacks_after is the LATER end (max, not min)", async () => {
  const later = trial(6, { id: "t2" });
  const r = await run(newHandler, { rows: [later, trial(2)] }, OPEN);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.stacks_after, later.end_date);
  const r2 = await run(newHandler, { rows: [trial(2), later] }, OPEN);
  assertEquals(r2.body.stacks_after, later.end_date, "order of rows does not matter");
});

t("door OPEN + an expired paid row and an active trial: the order is created (expired rows never count)", async () => {
  const row = trial(4);
  const r = await run(newHandler, { rows: [paid(-1), row] }, OPEN);
  assertEquals(r.res.status, 200);
  assertEquals(r.body.stacks_after, row.end_date);
});

t("door OPEN: the order body is otherwise today's (amount, currency, capture, notes)", async () => {
  const r = await run(newHandler, { rows: [trial(4)] }, OPEN);
  const golden = await run(originHandler, { rows: [] }, SHUT);
  const a = orderBody(r.server)!;
  const g = orderBody(golden.server)!;
  delete a.notes.stacks_after;
  assertEquals(a, g);
});

// ── the switches are read per request ───────────────────────────────────────

t("one import, the env toggled between requests: the answer follows the switch each time", async () => {
  const sc = () => ({ rows: [trial(4)] });
  assertEquals((await run(newHandler, sc(), SHUT)).res.status, 409);
  assertEquals((await run(newHandler, sc(), OPEN)).res.status, 200);
  assertEquals((await run(newHandler, sc(), { stack: "true" })).res.status, 409);
  assertEquals((await run(newHandler, sc(), OPEN)).res.status, 200);
});

// ── import side effects ─────────────────────────────────────────────────────

t("importing create-razorpay-order/index.ts reads none of its own env, does no fetch and binds no server", async () => {
  const modulePath = new URL("./index.ts", import.meta.url).href;
  // Every trap is VERIFIED to be installed (a non-assignable property must fail the test, not pass it silently).
  // supabase-js (esm.sh's node shim) reads NODE_OPTIONS when IT loads; that library read is allowed. Any other name
  // (the door's RAZORPAY_*, SUPABASE_*, ENABLE_* reads) at import is a failure. std@0.177's serve() listens through
  // Deno.listen, so both Deno.listen and Deno.serve are trapped.
  const script = `
    const trips = [];
    const origGet = Deno.env.get;
    const envTrap = (n) => { if (n === "NODE_OPTIONS") return origGet.call(Deno.env, n); trips.push("env:" + n); throw new Error("env read at import"); };
    Deno.env.get = envTrap;
    const fetchTrap = (...a) => { trips.push("fetch"); throw new Error("fetch at import"); };
    globalThis.fetch = fetchTrap;
    const listenTrap = (...a) => { trips.push("listen"); throw new Error("listen at import"); };
    Deno.listen = listenTrap;
    const serveTrap = (...a) => { trips.push("serve"); throw new Error("serve at import"); };
    Deno.serve = serveTrap;
    const installed = Deno.env.get === envTrap && globalThis.fetch === fetchTrap && Deno.listen === listenTrap && Deno.serve === serveTrap;
    let mod = null;
    try { mod = await import(${JSON.stringify(modulePath)}); } catch (e) { trips.push("import threw: " + (e && e.message)); }
    Deno.env.get = origGet;
    if (!installed) console.log("TRAPS NOT INSTALLED");
    else console.log(trips.length === 0 && mod && typeof mod.handler === "function" ? "clean" : "TRIPPED " + trips.join(","));
  `;
  const out = await new Deno.Command(Deno.execPath(), {
    args: ["eval", "--no-check", "--no-prompt", "--node-modules-dir=none", script],
    stdout: "piped",
    stderr: "piped",
    signal: AbortSignal.timeout(30_000),
  }).output();
  const text = new TextDecoder().decode(out.stdout).trim();
  assertEquals(text, "clean", new TextDecoder().decode(out.stderr));
});

t("door: the guard-failure log carries the error code and the response's request_id", async () => {
  const orig = console.error;
  const lines: string[] = [];
  console.error = (...a: unknown[]) => { lines.push(a.map(String).join(" ")); };
  try {
    const r = await run(newHandler, { rows: [], guardError: true }, SHUT);
    const line = lines.find((l) => l.includes("subscription guard read failed"));
    assert(line, lines.join(" | "));
    assert(line.includes("code=XX000"), line);
    assert(line.includes(`request_id=${r.body.request_id}`), line);
    assert(!line.includes("guard read failed\"") && !line.includes("message"), "never the message text");
  } finally {
    console.error = orig;
  }
});

t("door OPEN + an active row of an UNKNOWN plan (neither paid nor referral_trial): 409, it counts as paid", async () => {
  const row = paid(20, { plan: "lifetime" });
  const r = await run(newHandler, { rows: [row, trial(4)] }, OPEN);
  assertEquals(r.res.status, 409);
  assertEquals(r.body.current_plan, "lifetime");
  assertEquals(orderCalls(r.server).length, 0);
});

t("instants are compared as instants, not strings: mixed +05:30 / Z end dates pick the truly latest row", async () => {
  // Lexically "...T15:00:00+05:30" > "...T10:00:00.000Z", but 15:00+05:30 is 09:30Z, the EARLIER instant.
  const d = istDateStr(new Date(Date.now() + 5 * 86_400_000)); // any day 4-6 days out; both instants below are on it
  const lateZ = trial(0, { id: "tz", end_date: `${d}T10:00:00.000Z` });
  const earlyOffset = trial(0, { id: "to", end_date: `${d}T15:00:00+05:30` });
  const open = await run(newHandler, { rows: [earlyOffset, lateZ] }, OPEN);
  assertEquals(open.body.stacks_after, lateZ.end_date, "stacks_after = the latest instant");
  const p1 = paid(0, { id: "p1", end_date: `${d}T10:00:00.000Z` });
  const p2 = paid(0, { id: "p2", plan: "yearly", end_date: `${d}T15:00:00+05:30` });
  const shut = await run(newHandler, { rows: [p2, p1] }, SHUT);
  assertEquals(shut.res.status, 409);
  assertEquals(shut.body.current_expires_at, p1.end_date, "the 409 body reports the latest instant");
});

// ── payment-hardening U3 (OI-366): the order limit and the strict promo rule ──

const counterCalls = (server: FakeServer) => server.to(`/rest/v1/rpc/${CONSUME_QUOTA_RPC}`, "POST");
const promo = (over: Row = {}): Row => ({ code: "HALF50", discount_pct: 50, is_active: true, valid_until: "2099-01-01", max_uses: null, used_count: 0, ...over });
const withPromo = (row: Row | null, extra: DoorScenario = {}): DoorScenario => ({
  rows: [],
  body: { plan: "yearly", promo_code: "half50" },
  promoRows: row ? [row] : [],
  ...extra,
});

t("U3: one counter call per attempt with the key, a 1-hour UTC bucket and the limit, before any other read", async () => {
  const r = await run(newHandler, { rows: [] }, SHUT);
  assertEquals(r.res.status, 200);
  const calls = counterCalls(r.server);
  assertEquals(calls.length, 1);
  const args = calls[0].body as Record<string, unknown>;
  assertEquals(args.p_user_id, USER);
  assertEquals(args.p_quota_key, "create_order");
  assertEquals(args.p_limit, 30);
  const start = Date.parse(String(args.p_window_start));
  assertEquals(start % 3_600_000, 0, "a whole UTC hour");
  assert(Date.now() - start < 3_600_000);
  const firstRead = r.server.requests.findIndex((q) => q.path === "/rest/v1/subscriptions");
  const counterAt = r.server.requests.findIndex((q) => q.path === `/rest/v1/rpc/${CONSUME_QUOTA_RPC}`);
  assert(counterAt >= 0 && counterAt < firstRead, "the counter runs before the guard read");
});

t("U3: over the limit (-1) -> 429 rate_limited with Retry-After, and NO Razorpay order", async () => {
  const r = await run(newHandler, { rows: [], quota: -1 }, SHUT);
  assertEquals(r.res.status, 429);
  assertEquals(r.body.error_code, "rate_limited");
  const after = Number(r.res.headers.get("Retry-After"));
  // Exactly the rest of the current UTC hour (B-pass beee28f0d9f2 finding 3), within the test's own run time.
  const rest = Math.ceil((3_600_000 - (Date.now() % 3_600_000)) / 1000);
  assert(after >= rest && after <= rest + 5, `Retry-After ${after}, the rest of the hour ${rest}`);
  assertEquals(r.body.retry_after_seconds, after);
  assertEquals(r.body.error, `Too many payment attempts. Try again in ${retryMinutes(after)}.`);
  assertEquals(orderCalls(r.server).length, 0);
});

t("U3: the counter RPC fails -> 429 rate_limit_unavailable (fail closed), NO order", async () => {
  const r = await run(newHandler, { rows: [], quota: "error" }, SHUT);
  assertEquals(r.res.status, 429);
  assertEquals(r.body.error_code, "rate_limit_unavailable");
  assert(typeof r.body.request_id === "string");
  assertEquals(orderCalls(r.server).length, 0);
});

t("U3: an EXPIRED code (yesterday, IST) -> 400 promo_invalid, NO order", async () => {
  const yesterday = istDateStr(new Date(Date.now() - 86_400_000));
  const r = await run(newHandler, withPromo(promo({ valid_until: yesterday })), SHUT);
  assertEquals(r.res.status, 400);
  assertEquals(r.body, { error: "This promo code can no longer be used. Reopen the upgrade screen to pay without it.", error_code: "promo_invalid" });
  assertEquals(orderCalls(r.server).length, 0);
});

for (const [label, row] of [
  ["exhausted", promo({ max_uses: 3, used_count: 3 })],
  ["inactive", promo({ is_active: false })],
  ["inactive (null)", promo({ is_active: null })],
  ["unknown", null],
] as const) {
  t(`U3: a ${label} code -> 400 promo_invalid, NO order (it used to give a silent full-price order)`, async () => {
    const r = await run(newHandler, withPromo(row), SHUT);
    assertEquals(r.res.status, 400);
    assertEquals(r.body.error_code, "promo_invalid");
    assertEquals(orderCalls(r.server).length, 0);
  });
}

for (const [label, until] of [["'YYYY-MM-DD'", () => "2099-01-01"], ["a timestamp string", () => "2099-01-01T00:00:00Z"], ["today (IST)", () => istDateStr()]] as const) {
  t(`U3: a usable code with valid_until ${label} -> the discounted order`, async () => {
    const r = await run(newHandler, withPromo(promo({ valid_until: until() })), SHUT);
    assertEquals(r.res.status, 200);
    assertEquals(r.body.promo_applied, true);
    assertEquals(orderBody(r.server)!.amount, 149950);
  });
}

t("U3: the promo READ fails -> 500 promo_check_unavailable, NO order (an outage is never 'a dead code')", async () => {
  const r = await run(newHandler, withPromo(promo(), { promoError: true }), SHUT);
  assertEquals(r.res.status, 500);
  assertEquals(r.body.error_code, "promo_check_unavailable");
  assert(typeof r.body.request_id === "string");
  assertEquals(orderCalls(r.server).length, 0);
});

t("U3 switch exactly \"true\": no counter, and origin/main's tolerant promo answers (status, body, order body)", async () => {
  const yesterday = istDateStr(new Date(Date.now() - 86_400_000));
  const scenarios: Array<[string, () => DoorScenario]> = [
    ["expired code (honoured)", () => withPromo(promo({ valid_until: yesterday }))],
    ["exhausted code (honoured)", () => withPromo(promo({ max_uses: 1, used_count: 1 }))],
    ["inactive code (full price)", () => withPromo(promo({ is_active: false }))],
    ["unknown code (full price)", () => withPromo(null)],
    ["over the limit (ignored)", () => ({ rows: [], quota: -1 })],
    ["counter down (ignored)", () => ({ rows: [], quota: "error" as const })],
  ];
  for (const [label, make] of scenarios) {
    const golden = await run(originHandler, make(), SHUT);
    const now = await run(newHandler, make(), { guards: "true" });
    assertEquals(now.res.status, golden.res.status, label);
    assertEquals(stripInstants(now.body), stripInstants(golden.body), label);
    assertEquals(orderBody(now.server), orderBody(golden.server), label);
    assertEquals(counterCalls(now.server).length, 0, label);
  }
});

t("U3: any switch value other than exactly \"true\" keeps the guards ON", async () => {
  for (const v of ["TRUE", " true", "1", "false", ""]) {
    const r = await run(newHandler, { rows: [], quota: -1 }, { guards: v });
    assertEquals(r.res.status, 429, `switch=${JSON.stringify(v)}`);
  }
});

// ── payment-hardening U0 (OI-360): a refused Razorpay order is logged by status and code/reason only ──
// A Razorpay error body can echo the order's notes (the user id, the promo code). The scenario runs through the
// frozen origin/main handler first, which must SHOW the secret (positive control), then through this handler.
const LOG_SECRET = "SIGf3b1c2d4e5a6978812345678abcdef00112233";

async function refusedOrder(handler: Handler) {
  const server = new FakeServer({
    tables: { subscriptions: [], promo_codes: [] },
    users: { [TOKEN]: { id: USER } },
    // Any counter call (the order limit, from U3 on) is under the limit.
    fallbackRpc: () => 1,
    razorpay: () => jsonResponse(404, { error: { description: "unrouted" } }),
    intercept: (req) =>
      req.host === "https://api.razorpay.com" && req.method === "POST" && req.path === "/v1/orders"
        ? jsonResponse(400, {
          error: { code: "BAD_REQUEST_ERROR", description: `notes ${LOG_SECRET}`, reason: "input_validation_failed", metadata: { user_id: USER } },
        })
        : undefined,
  });
  server.install();
  try {
    const req = new Request("https://fn.test/create-razorpay-order", {
      method: "POST",
      headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ plan: "monthly" }),
    });
    const { result: res, errors, all } = await captureConsole(() =>
      withModuleEnv(() => withSwitch(undefined, () => withTrialPurchaseSwitch(undefined, () => handler(req))))
    );
    return { res, errors, all, server };
  } finally {
    server.restore();
  }
}

t("U0 log: a refused Razorpay order logs status and Razorpay's code/reason, never the body (control: origin logged the body)", async () => {
  const before = await refusedOrder(originHandler);
  assert(before.all.some((l) => l.includes(LOG_SECRET)), "positive control: the origin handler logged the body");
  const r = await refusedOrder(newHandler);
  assertEquals(r.res.status, before.res.status);
  assertEquals(orderCalls(r.server).length, 1);
  assert(!r.all.some((l) => l.includes(LOG_SECRET) || l.includes(USER)), r.all.join("\n"));
  assert(
    r.errors.some((l) => l.includes(`razorpay status=400 code="BAD_REQUEST_ERROR" reason="input_validation_failed"`)),
    r.errors.join("\n"),
  );
});

// ── Frozen clock (B-pass beee28f0d9f2 finding 1): the handler's promo rule must use the IST day of the REAL
// clock. At 2026-10-24T18:31Z it is 00:01 IST on the 25th while the UTC date is still the 24th, so a code valid
// until "2026-10-24" is expired by the IST rule and usable by a UTC rule, at whatever time the suite runs.
const MINUTE_AFTER_IST_MIDNIGHT = "2026-10-24T18:31:00Z";
const MINUTE_BEFORE_IST_MIDNIGHT = "2026-10-24T18:29:00Z";

async function withFrozenNow<T>(iso: string, fn: () => Promise<T>): Promise<T> {
  const RealDate = Date;
  const frozen = RealDate.parse(iso);
  class FrozenDate extends RealDate {
    constructor(...args: [] | [string | number | Date]) {
      if (args.length === 0) super(frozen);
      else super(args[0]);
    }
    static override now(): number {
      return frozen;
    }
  }
  globalThis.Date = FrozenDate as DateConstructor;
  try {
    return await fn();
  } finally {
    globalThis.Date = RealDate;
  }
}

t("U3 frozen clock: at 00:01 IST a code valid until the previous IST day gets NO order (a UTC-day rule would order)", async () => {
  const sc = () => withPromo(promo({ valid_until: "2026-10-24" }));
  const after = await withFrozenNow(MINUTE_AFTER_IST_MIDNIGHT, () => run(newHandler, sc(), SHUT));
  assertEquals(after.res.status, 400);
  assertEquals(after.body.error_code, "promo_invalid");
  assertEquals(orderCalls(after.server).length, 0);
  const before = await withFrozenNow(MINUTE_BEFORE_IST_MIDNIGHT, () => run(newHandler, sc(), SHUT));
  assertEquals(before.res.status, 200, "23:59 IST is still the last day");
  assertEquals(orderBody(before.server)!.amount, 149950);
});

for (const [label, quota] of [["null", "null"], ["0", 0], ["a fraction", 1.5]] as const) {
  t(`U3: the counter answers ${label} (neither -1 nor a count) -> 429 rate_limit_unavailable, NO order (fails closed)`, async () => {
    const r = await run(newHandler, { rows: [], quota }, SHUT);
    assertEquals(r.res.status, 429);
    assertEquals(r.body.error_code, "rate_limit_unavailable");
    assertEquals(orderCalls(r.server).length, 0);
  });
}

t("U3: the limit message names the real wait in minutes (the bucket is a fixed hour)", () => {
  assertEquals(retryMinutes(1), "1 minute");
  assertEquals(retryMinutes(60), "1 minute");
  assertEquals(retryMinutes(61), "2 minutes");
  assertEquals(retryMinutes(3600), "60 minutes");
  return Promise.resolve();
});
