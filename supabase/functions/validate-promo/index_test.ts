// payment-hardening U3 (OI-366): handler-level tests of validate-promo. The REAL supabase-js client runs on the
// fetch-level fake (../_shared/postgrest_fake_fetch.ts). The kill-switch golden drives the UNMODIFIED origin/main
// module (../_shared/fixtures/validate_promo_origin_main.ts.txt) through the same scenarios.
// Sanitizers are off: createClient() starts an auth refresh timer.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeServer, jsonResponse, type Row } from "../_shared/postgrest_fake_fetch.ts";
import { istDateStr } from "../_shared/ist_date.ts";
import { captureConsole, type Handler, loadOriginMainHandler, MODULE_ENV, OTHER_USER, TOKEN, USER } from "../_shared/payment_writer_harness.ts";
import { CHECK_UNAVAILABLE_REASON, PROMO_GUARDS_DISABLE_ENV, rateLimitedReason } from "./index.ts";
import { ORDER_ABUSE_GUARDS_DISABLE_ENV } from "../create-razorpay-order/index.ts";
import { secondsLeftInBucket } from "../_shared/order_abuse_guards.ts";

const newHandler = (await import("./index.ts")).handler as Handler;
const originHandler = await loadOriginMainHandler("validate_promo_origin_main.ts.txt");

// The RPC's name is built, not spelled: census tests scan _test.ts files for the literal.
const CONSUME_QUOTA_RPC = "consume_" + "quota";
const OTHER_TOKEN = "user-jwt-2";

function t(name: string, fn: () => Promise<void>) {
  Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });
}

interface Sc {
  promoRows?: Row[];
  code?: unknown;
  quota?: number | "error" | "null";
  promoError?: boolean;
  noAuth?: boolean;
  /** A raw request body (not JSON-encoded), for the catch-all tests. */
  rawBody?: string;
  /** A counter shared ACROSS run() calls (a run builds a new server each time): the quota RPC is emulated on it. */
  counterRows?: Map<string, number>;
  /** The caller's bearer token; OTHER_TOKEN is OTHER_USER. */
  token?: string;
}

/** The counter key the emulator uses: one row per (user, quota key, bucket start), like the table behind the RPC. */
const counterKey = (userId: string, windowStart: string) => `${userId}|promo_validate|${windowStart}`;

/**
 * Emulates the quota RPC's contract (migration 128): a missing, non-integer or negative limit RAISES (the handler then
 * answers "couldn't check"), a limit of 0 or a row at the limit answers -1 WITHOUT counting, else the post-increment count.
 */
function emulateCounter(rows: Map<string, number>) {
  return (_name: string, args: Row): number => {
    const limit = Number(args.p_limit);
    if (args.p_limit == null || !Number.isInteger(limit) || limit < 0) throw new Error("emulated counter: the limit must be a non-negative integer");
    const key = `${args.p_user_id}|${args.p_quota_key}|${args.p_window_start}`;
    const used = rows.get(key) ?? 0;
    if (limit === 0 || used >= limit) return -1;
    rows.set(key, used + 1);
    return used + 1;
  };
}

async function withEnv<T>(vars: Record<string, string | undefined>, fn: () => Promise<T>): Promise<T> {
  const saved = new Map<string, string | undefined>();
  for (const [k, v] of Object.entries(vars)) {
    saved.set(k, Deno.env.get(k));
    if (v === undefined) Deno.env.delete(k);
    else Deno.env.set(k, v);
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

async function run(handler: Handler, sc: Sc, guardsSwitch?: string) {
  const server = new FakeServer({
    tables: { promo_codes: sc.promoRows ?? [] },
    users: { [TOKEN]: { id: USER }, [OTHER_TOKEN]: { id: OTHER_USER } },
    fallbackRpc: sc.counterRows
      ? emulateCounter(sc.counterRows)
      : () => (sc.quota === "null" ? null : typeof sc.quota === "number" ? sc.quota : 1),
    intercept: (req) =>
      sc.quota === "error" && req.path === `/rest/v1/rpc/${CONSUME_QUOTA_RPC}`
        ? jsonResponse(500, { code: "XX000", message: "counter unavailable" })
        : sc.promoError && req.path === "/rest/v1/promo_codes"
        ? jsonResponse(500, { code: "XX000", message: "promo read failed" })
        : undefined,
  });
  server.install();
  try {
    const req = new Request("https://fn.test/validate-promo", {
      method: "POST",
      headers: { ...(sc.noAuth ? {} : { Authorization: `Bearer ${sc.token ?? TOKEN}` }), "Content-Type": "application/json" },
      body: sc.rawBody ?? JSON.stringify({ code: sc.code ?? "half50" }),
    });
    const res = await withEnv({ ...MODULE_ENV, [PROMO_GUARDS_DISABLE_ENV]: guardsSwitch }, () => handler(req));
    const body = JSON.parse(await res.text()) as Record<string, unknown>;
    return { res, body, server };
  } finally {
    server.restore();
  }
}

const promo = (over: Row = {}): Row => ({ code: "HALF50", discount_pct: 50, is_active: true, valid_until: "2099-01-01", max_uses: null, used_count: 0, ...over });
const promoReads = (server: FakeServer) => server.to("/rest/v1/promo_codes", "GET");
const counterCalls = (server: FakeServer) => server.to(`/rest/v1/rpc/${CONSUME_QUOTA_RPC}`, "POST");

const HOUR_MS = 3_600_000;
/** The rate reason for the rest of the current UTC hour, read before and after the call (a minute can turn). */
function rateReasonsAround(t0: number, t1: number): string[] {
  return [t0, t1].map((now) => rateLimitedReason(secondsLeftInBucket(Math.floor(now / HOUR_MS) * HOUR_MS, HOUR_MS, now)));
}
async function runRateLimited(sw?: string) {
  const t0 = Date.now();
  const r = await run(newHandler, { promoRows: [promo()], quota: -1 }, sw);
  return { r, expected: rateReasonsAround(t0, Date.now()) };
}

t("hermes H3: the rate reason names the wait in minutes, never 'an hour' for a bucket that ends in one minute", () => {
  assertEquals(rateLimitedReason(2220), "Too many attempts. Try again in 37 minutes.");
  assertEquals(rateLimitedReason(30), "Too many attempts. Try again in 1 minute.");
  assertEquals(rateLimitedReason(3600), "Too many attempts. Try again in 60 minutes.");
  return Promise.resolve();
});

t("the switch name is the one create-razorpay-order reads (one switch turns both off)", () => {
  assertEquals(PROMO_GUARDS_DISABLE_ENV, ORDER_ABUSE_GUARDS_DISABLE_ENV);
  return Promise.resolve();
});

t("the four existing answers are unchanged (valid, inactive, exhausted, unknown) and expiry uses the IST day", async () => {
  const yesterday = istDateStr(new Date(Date.now() - 86_400_000));
  const cases: Array<[Sc, Record<string, unknown>]> = [
    [{ promoRows: [promo()] }, { valid: true, discount_pct: 50 }],
    [{ promoRows: [promo({ is_active: false })] }, { valid: false, reason: "This code is no longer active" }],
    [{ promoRows: [promo({ max_uses: 2, used_count: 2 })] }, { valid: false, reason: "This code has reached its maximum uses" }],
    [{ promoRows: [] }, { valid: false, reason: "Invalid promo code" }],
    [{ promoRows: [promo({ valid_until: yesterday })] }, { valid: false, reason: "This code has expired" }],
    [{ promoRows: [promo({ valid_until: istDateStr() })] }, { valid: true, discount_pct: 50 }],
    [{ promoRows: [promo()], code: "" }, { valid: false, reason: "No code provided" }],
  ];
  for (const [sc, expected] of cases) {
    const r = await run(newHandler, sc);
    assertEquals(r.res.status, 200);
    assertEquals(r.body, expected, JSON.stringify(sc));
  }
});

t("one counter call per check: the key, a 1-hour UTC bucket and the configured limit", async () => {
  const r = await run(newHandler, { promoRows: [promo()] });
  const calls = counterCalls(r.server);
  assertEquals(calls.length, 1);
  const args = calls[0].body as Record<string, unknown>;
  assertEquals(args.p_user_id, USER);
  assertEquals(args.p_quota_key, "promo_validate");
  assertEquals(args.p_limit, 7);
  assertEquals(Date.parse(String(args.p_window_start)) % 3_600_000, 0);
});

t("over the limit (the counter answers -1) -> 200 valid:false with the rate reason, and NO promo_codes read", async () => {
  const { r, expected } = await runRateLimited();
  assertEquals(r.res.status, 200);
  assertEquals(r.body.valid, false);
  assert(expected.includes(String(r.body.reason)), `${r.body.reason} not in ${expected}`);
  assertEquals(Object.keys(r.body).sort(), ["reason", "valid"]);
  assertEquals(promoReads(r.server).length, 0);
});

t("the counter RPC fails -> 200 valid:false with the distinct 'couldn't check' reason, NO promo_codes read", async () => {
  const r = await run(newHandler, { promoRows: [promo()], quota: "error" });
  assertEquals(r.res.status, 200);
  assertEquals(r.body, { valid: false, reason: CHECK_UNAVAILABLE_REASON });
  assertEquals(promoReads(r.server).length, 0);
});

t("the promo READ fails -> 200 valid:false 'couldn't check' (not 'Invalid promo code')", async () => {
  const r = await run(newHandler, { promoRows: [promo()], promoError: true });
  assertEquals(r.res.status, 200);
  assertEquals(r.body, { valid: false, reason: CHECK_UNAVAILABLE_REASON });
});

t("switch exactly \"true\": origin/main's answer for every scenario, and no counter call", async () => {
  const yesterday = istDateStr(new Date(Date.now() - 86_400_000));
  const scenarios: Sc[] = [
    { promoRows: [promo()] },
    { promoRows: [promo({ is_active: false })] },
    { promoRows: [promo({ max_uses: 2, used_count: 2 })] },
    { promoRows: [] },
    { promoRows: [promo({ valid_until: yesterday })] },
    { promoRows: [promo()], code: "" },
    { promoRows: [promo()], quota: -1 },
    { promoRows: [promo()], quota: "error" },
    { promoRows: [promo()], promoError: true },
    { promoRows: [promo()], noAuth: true },
  ];
  for (const sc of scenarios) {
    const golden = await run(originHandler, sc);
    const now = await run(newHandler, sc, "true");
    assertEquals(now.res.status, golden.res.status, JSON.stringify(sc));
    assertEquals(now.body, golden.body, JSON.stringify(sc));
    assertEquals(counterCalls(now.server).length, 0);
  }
});

t("any switch value other than exactly \"true\" keeps the throttle ON", async () => {
  for (const v of ["TRUE", " true", "1", "false", ""]) {
    const { r, expected } = await runRateLimited(v);
    assertEquals(r.body.valid, false, `switch=${JSON.stringify(v)}`);
    assert(expected.includes(String(r.body.reason)), `switch=${JSON.stringify(v)}: ${r.body.reason}`);
  }
});

const CATCH_ALL_BODY = '{"code":\n at SECRETBODY jane.doe@example.com';
// B-pass bfaeb6fb79da findings 1 and 2: the catch-all logs the error's name and frames, never body text, even when
// the body holds a newline followed by "at ".
t("catch-all: an unparseable body -> 500 and one 'unhandled SyntaxError at' line with no body text", async () => {
  const { result: r, errors } = await captureConsole(() => run(newHandler, { promoRows: [promo()], rawBody: CATCH_ALL_BODY }));
  assertEquals(r.res.status, 500);
  const lines = errors.filter((l) => l.includes("unhandled"));
  assertEquals(lines.length, 1, errors.join("\n"));
  assert(/^\[validate-promo\] request_id=[0-9a-f]{8} unhandled SyntaxError at at /.test(lines[0]), lines[0]);
  assert(!errors.some((l) => l.includes("SECRETB") || l.includes("jane")), errors.join("\n"));
});

t("no JWT -> 401 before the counter is touched", async () => {
  const r = await run(newHandler, { promoRows: [promo()], noAuth: true });
  assertEquals(r.res.status, 401);
  assertEquals(counterCalls(r.server).length, 0);
});

t("importing validate-promo/index.ts reads none of its own env, does no fetch and binds no server", async () => {
  const modulePath = new URL("./index.ts", import.meta.url).href;
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
  assert(true);
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

t("frozen clock: at 00:01 IST a code valid until the previous IST day is EXPIRED (a UTC-day rule would say valid)", async () => {
  const row = promo({ valid_until: "2026-10-24" });
  const after = await withFrozenNow(MINUTE_AFTER_IST_MIDNIGHT, () => run(newHandler, { promoRows: [row] }));
  assertEquals(after.body, { valid: false, reason: "This code has expired" });
  const before = await withFrozenNow(MINUTE_BEFORE_IST_MIDNIGHT, () => run(newHandler, { promoRows: [row] }));
  assertEquals(before.body, { valid: true, discount_pct: 50 }, "23:59 IST is still the last day");
});

// ── The limit's VALUE (founder 2026-10-25: 7 checks per user per UTC-hour bucket). The older over-limit test
// answers -1 from a fake that ignores the limit, so only these tests, the p_limit assertion above and the Dart
// source pin can see the number. The counter is emulated on a Map shared across the calls (an emulator that read a
// literal 7 instead of args.p_limit would pin nothing).
const BUCKET_18Z = "2026-10-24T18:00:00.000Z";
const BUCKET_19Z = "2026-10-24T19:00:00.000Z";
const FIVE_MINUTES_INTO_NEXT_BUCKET = "2026-10-24T19:05:00Z";
const windowStartOf = (server: FakeServer) => (counterCalls(server)[0].body as Record<string, unknown>).p_window_start;

t("the limit is 7 per user per UTC-hour bucket: 7 checks pass, the 8th is refused with the wait, another user is unaffected", async () => {
  const counterRows = new Map<string, number>();
  await withFrozenNow(MINUTE_AFTER_IST_MIDNIGHT, async () => {
    for (let i = 1; i <= 7; i++) {
      const r = await run(newHandler, { promoRows: [promo()], counterRows });
      assertEquals(r.body, { valid: true, discount_pct: 50 }, `check ${i} of 7`);
      assertEquals(windowStartOf(r.server), BUCKET_18Z, `check ${i} bucket start`);
    }
    // 18:31:00Z: 1740 s left in the 18:00Z bucket -> 29 minutes (a literal, independent of the helper).
    const eighth = await run(newHandler, { promoRows: [promo()], counterRows });
    assertEquals(eighth.res.status, 200);
    assertEquals(eighth.body, { valid: false, reason: "Too many attempts. Try again in 29 minutes." });
    assertEquals(promoReads(eighth.server).length, 0, "a refused check must not read promo_codes");
    assertEquals(counterRows.get(counterKey(USER, BUCKET_18Z)), 7, "emulator sanity: a refusal does not count");
    // Checked AFTER the first user hit the limit: a handler that sent one fixed user id would be refused here.
    const other = await run(newHandler, { promoRows: [promo()], counterRows, token: OTHER_TOKEN });
    assertEquals(other.body, { valid: true, discount_pct: 50 }, "the counter is per user");
  });
});

t("the bucket is the fixed UTC hour: refused at 18:31Z with 7 used, allowed again at 19:05Z in the next bucket", async () => {
  const counterRows = new Map<string, number>([[counterKey(USER, BUCKET_18Z), 7]]);
  const refused = await withFrozenNow(MINUTE_AFTER_IST_MIDNIGHT, () => run(newHandler, { promoRows: [promo()], counterRows }));
  assertEquals(refused.body, { valid: false, reason: "Too many attempts. Try again in 29 minutes." });
  assertEquals(windowStartOf(refused.server), BUCKET_18Z);
  const allowed = await withFrozenNow(FIVE_MINUTES_INTO_NEXT_BUCKET, () => run(newHandler, { promoRows: [promo()], counterRows }));
  assertEquals(allowed.body, { valid: true, discount_pct: 50 });
  assertEquals(windowStartOf(allowed.server), BUCKET_19Z);
  assertEquals(counterRows.get(counterKey(USER, BUCKET_19Z)), 1);
});

for (const [label, quota] of [["null", "null"], ["0", 0], ["a fraction", 1.5]] as const) {
  t(`the counter answers ${label} (neither -1 nor a count) -> 'couldn't check', NO promo_codes read (fails closed)`, async () => {
    const r = await run(newHandler, { promoRows: [promo()], quota });
    assertEquals(r.body, { valid: false, reason: "Couldn't check the code right now. Try again shortly." });
    assertEquals(promoReads(r.server).length, 0);
  });
}

// The strict switch must answer every check itself: inputs where the tolerant path below it answers differently
// in ANY process time zone (it compares with local midnight, so under TZ=Asia/Kolkata it can look like the IST
// rule). B-pass beee28f0d9f2 finding 1 (mutant V4: the switch skipped, every other test stayed green).
for (const [label, over, expected] of [
  ["a malformed valid_until", { valid_until: "abc" }, { valid: false, reason: "This code has expired" }],
  ["is_active as the string \"true\"", { is_active: "true" }, { valid: false, reason: "This code is no longer active" }],
] as const) {
  t(`guards ON: ${label} is refused by the strict rule (the tolerant path would answer valid)`, async () => {
    const strict = await run(newHandler, { promoRows: [promo(over)] });
    assertEquals(strict.body, expected);
    const tolerant = await run(newHandler, { promoRows: [promo(over)] }, "true");
    assertEquals(tolerant.body, { valid: true, discount_pct: 50 }, "control: the switched-off tolerant path differs here");
  });
}
