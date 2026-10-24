// supabase/functions/_shared/payment_writer_harness.ts
//
// Test helper (NOT a test): loads the `verify-payment` / `razorpay-webhook`
// handlers - the CURRENT modules and, for the golden recording, the UNMODIFIED
// origin/main copies kept under `fixtures/` - against the fetch-level fake
// (OI-341 Piece A, plan 2.3). Both modules read their environment at MODULE
// load, so the variables are set around the dynamic import and removed again
// afterwards (the process-wide env leak class of
// `reference_deno_test_env_leak_daily_snapshot_2026_10_11`).

import { FAKE_ORIGIN, FakeServer, jsonResponse, type RecordedRequest, type Row } from "./postgrest_fake_fetch.ts";

import { toFileUrl } from "https://deno.land/std@0.224.0/path/mod.ts";

export type Handler = (req: Request) => Promise<Response>;

export const MODULE_ENV: Record<string, string> = {
  SUPABASE_URL: FAKE_ORIGIN,
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test",
  RAZORPAY_KEY_ID: "rzp_test_harness",
  RAZORPAY_KEY_SECRET: "whsec_harness",
};

export const USER = "11111111-1111-4111-8111-111111111111";
export const OTHER_USER = "22222222-2222-4222-8222-222222222222";
export const TOKEN = "user-jwt-1";
export const SWITCH = "ENABLE_SUBSCRIPTION_STACKING";
export const DAY_MS = 86_400_000;
/** One event time per process: the signature (an HMAC of the body) must be identical across the golden run and the run under test. */
export const EVENT_CREATED_AT = Math.floor(Date.now() / 1000);

/** Sets MODULE_ENV around `importer`, then restores every variable. */
export async function importWithEnv<T>(importer: () => Promise<T>): Promise<T> {
  const saved = new Map<string, string | undefined>();
  for (const [k, v] of Object.entries(MODULE_ENV)) {
    saved.set(k, Deno.env.get(k));
    Deno.env.set(k, v);
  }
  try {
    return await importer();
  } finally {
    for (const [k, v] of saved) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

/**
 * The unmodified origin/main handler: its only change is the wrapper, from
 * `serve(async (req) => {...});` to an exported const, so importing it binds no port.
 */
export async function loadOriginMainHandler(fixtureFile: string): Promise<Handler> {
  const text = await Deno.readTextFile(new URL(`./fixtures/${fixtureFile}`, import.meta.url));
  const head = "\nserve(async (req: Request) => {";
  if (text.split(head).length !== 2) throw new Error(`${fixtureFile}: expected exactly one serve( wrapper`);
  const transformed = text.replace(head, "\nexport const handler = (async (req: Request) => {");
  const dir = await Deno.makeTempDir({ prefix: "origin_main_writer_" });
  const file = `${dir}/index.ts`;
  await Deno.writeTextFile(file, transformed);
  try {
    const mod = await importWithEnv(() => import(toFileUrl(file).href));
    return mod.handler as Handler;
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

/** Runs `fn` with the stacking switch set (or deleted), and always undoes it. */
export async function withSwitch<T>(value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const before = Deno.env.get(SWITCH);
  if (value === undefined) Deno.env.delete(SWITCH);
  else Deno.env.set(SWITCH, value);
  try {
    return await fn();
  } finally {
    if (before === undefined) Deno.env.delete(SWITCH);
    else Deno.env.set(SWITCH, before);
  }
}

export const TRIAL_SWITCH = "ENABLE_TRIAL_PURCHASE";

/** Runs `fn` with the purchase-door switch set (or deleted), and always undoes it (Piece B2a). */
export async function withTrialPurchaseSwitch<T>(value: string | undefined, fn: () => Promise<T>): Promise<T> {
  const before = Deno.env.get(TRIAL_SWITCH);
  if (value === undefined) Deno.env.delete(TRIAL_SWITCH);
  else Deno.env.set(TRIAL_SWITCH, value);
  try {
    return await fn();
  } finally {
    if (before === undefined) Deno.env.delete(TRIAL_SWITCH);
    else Deno.env.set(TRIAL_SWITCH, before);
  }
}

/** Records console.error / warn / log / info / debug lines while `fn` runs (a leak through any of them must be visible). */
export async function captureConsole<T>(fn: () => Promise<T>): Promise<{ result: T; errors: string[]; all: string[] }> {
  const errors: string[] = [];
  const all: string[] = [];
  const orig = { error: console.error, warn: console.warn, log: console.log, info: console.info, debug: console.debug };
  const fmt = (args: unknown[]) =>
    args.map((a) => (typeof a === "string" ? a : a instanceof Error ? a.message : JSON.stringify(a))).join(" ");
  console.error = (...a: unknown[]) => { const s = fmt(a); errors.push(s); all.push(s); };
  console.warn = (...a: unknown[]) => { all.push(fmt(a)); };
  console.log = (...a: unknown[]) => { all.push(fmt(a)); };
  console.info = (...a: unknown[]) => { all.push(fmt(a)); };
  console.debug = (...a: unknown[]) => { all.push(fmt(a)); };
  try {
    const result = await fn();
    return { result, errors, all };
  } finally {
    console.error = orig.error;
    console.warn = orig.warn;
    console.log = orig.log;
    console.info = orig.info;
    console.debug = orig.debug;
  }
}

const ISO_RE = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00)/g;

/** Deep-replaces every ISO instant with `<ts>` so two runs of one scenario compare equal. */
export function stripInstants<T>(v: T): T {
  return JSON.parse(JSON.stringify(v).replace(ISO_RE, "<ts>"));
}

export function normalizeRequests(reqs: RecordedRequest[]): unknown[] {
  return reqs.map((r) => stripInstants({ method: r.method, host: r.host, path: r.path, query: r.query, body: r.body }));
}

export function iso(daysFromNow: number, from: Date = new Date()): string {
  return new Date(from.getTime() + daysFromNow * DAY_MS).toISOString();
}

/** An active trial/grant row (NULL payment id), ending `endInDays` from now. */
export function trialRow(endInDays: number, over: Row = {}): Row {
  return {
    id: "trial-1",
    user_id: USER,
    plan: "monthly",
    status: "active",
    start_date: iso(endInDays - 7),
    end_date: iso(endInDays),
    razorpay_payment_id: null,
    ...over,
  };
}

export const MONTHLY_PAISE = 34900;
export const YEARLY_PAISE = 299900;
export const PAY = "pay_NEW0000000001";

export interface Scenario {
  rows?: Row[];
  promoRows?: Row[];
  amount?: number;
  paymentId?: string;
  intercept?: FakeServer["intercept"];
  beforeInsert?: FakeServer["beforeInsert"];
  /** Override the webhook event time (epoch seconds) to build a stale or future-stamped delivery. */
  eventCreatedAt?: number;
  /** Extra Razorpay notes (e.g. promo_code). */
  notes?: Record<string, string>;
  /**
   * Routes `rpc/record_paid_subscription` (OI-341 Piece B1). `rows` is answered as PostgREST answers a
   * `RETURNS TABLE` function: a JSON array. `body` overrides it (e.g. a scalar `1`, or an error object with a
   * non-2xx `status`). Unrouted, the RPC falls through to `fallbackRpc` (answers 1) like any other RPC.
   */
  recordPaid?: { status?: number; rows?: Row[]; body?: unknown };
  /** The captured payment entity carries NO order_id key (Razorpay omits it for a payment made without an order). */
  omitOrderId?: boolean;
  /** How the `alerts` table answers the payment alert's dedup read and insert. Default: empty read, accepted insert. */
  alerts?: AlertsBehavior;
}

export type AlertsBehavior = {
  dedup?: "none" | "existing" | "error" | "hang";
  insert?: "ok" | "error" | "hang";
};

/** An Intercept answering `/rest/v1/alerts` per `b`; undefined for every other request. */
export function alertsIntercept(b: AlertsBehavior = {}): NonNullable<FakeServer["intercept"]> {
  return (req) => {
    if (req.path !== "/rest/v1/alerts") return undefined;
    if (req.method === "GET") {
      switch (b.dedup ?? "none") {
        case "none":
          return jsonResponse(200, []);
        case "existing":
          return jsonResponse(200, [{ id: "alert-prior" }]);
        case "error":
          return jsonResponse(500, { code: "XX000", message: "alerts read failed" });
        case "hang":
          return new Promise<Response>(() => {});
      }
    }
    if (req.method === "POST") {
      switch (b.insert ?? "ok") {
        case "ok":
          return undefined; // the fake table accepts it and the row lands in server.tables.alerts
        case "error":
          return jsonResponse(500, { code: "XX000", message: "alerts insert failed" });
        case "hang":
          return new Promise<Response>(() => {});
      }
    }
    return undefined;
  };
}

/** A FakeServer wired for either writer: auth, quota, Razorpay payment, promo RPC. */
export function paymentServer(s: Scenario = {}): { server: FakeServer; promoIncrements: string[] } {
  const promoIncrements: string[] = [];
  const paymentId = s.paymentId ?? PAY;
  const server = new FakeServer({
    tables: {
      subscriptions: s.rows ?? [],
      promo_codes: s.promoRows ?? [],
      promo_code_uses: [],
    },
    users: { [TOKEN]: { id: USER } },
    // Any RPC not named here is the handlers' per-user rate-limit counter: 1 = under the limit.
    fallbackRpc: () => 1,
    rpcs: {
      increment_promo_used_count: (args) => {
        promoIncrements.push(String(args.p_code));
        return null;
      },
      ...(s.recordPaid
        ? {
          record_paid_subscription: () =>
            jsonResponse(s.recordPaid!.status ?? 200, s.recordPaid!.body ?? s.recordPaid!.rows ?? []),
        }
        : {}),
    },
    razorpay: (req) => {
      if (req.method === "GET" && req.path === `/v1/payments/${paymentId}`) {
        return jsonResponse(200, {
          id: paymentId,
          status: "captured",
          captured: true,
          amount: s.amount ?? MONTHLY_PAISE,
          currency: "INR",
          ...(s.omitOrderId ? {} : { order_id: "order_TEST0001" }),
          notes: { user_id: USER, ...(s.notes ?? {}) },
        });
      }
      return jsonResponse(404, { error: { description: `unrouted razorpay ${req.method} ${req.path}` } });
    },
    intercept: (req) => s.intercept?.(req) ?? alertsIntercept(s.alerts)(req),
    beforeInsert: s.beforeInsert,
  });
  return { server, promoIncrements };
}

export function verifyRequest(paymentId: string = PAY): Request {
  return new Request("https://fn.test/verify-payment", {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ payment_id: paymentId }),
  });
}

async function hmacHex(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return [...sig].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function webhookRequest(s: Scenario = {}): Promise<Request> {
  return signedWebhookRequest(s, "payment.captured");
}

/**
 * A signed `payment.authorized` delivery (entity status `authorized`, `captured: false`): the webhook then calls
 * Razorpay's capture, which `paymentServer` does not route, so a test answers it through `intercept`
 * (payment-hardening U0 / U2).
 */
export function authorizedWebhookRequest(s: Scenario = {}): Promise<Request> {
  return signedWebhookRequest(s, "payment.authorized");
}

async function signedWebhookRequest(s: Scenario, event: "payment.captured" | "payment.authorized"): Promise<Request> {
  const authorized = event === "payment.authorized";
  const body = JSON.stringify({
    event,
    created_at: s.eventCreatedAt ?? EVENT_CREATED_AT,
    payload: {
      payment: {
        entity: {
          id: s.paymentId ?? PAY,
          ...(s.omitOrderId ? {} : { order_id: "order_TEST0001" }),
          amount: s.amount ?? MONTHLY_PAISE,
          currency: "INR",
          ...(authorized ? { status: "authorized" } : {}),
          captured: !authorized,
          notes: { user_id: USER, ...(s.notes ?? {}) },
        },
      },
    },
  });
  return new Request("https://fn.test/razorpay-webhook", {
    method: "POST",
    headers: {
      "x-razorpay-signature": await hmacHex(body, MODULE_ENV.RAZORPAY_KEY_SECRET),
      "Content-Type": "application/json",
    },
    body,
  });
}

/** Calls of `rpc/record_paid_subscription`. */
export function recordPaidCalls(server: FakeServer): RecordedRequest[] {
  return server.to("/rest/v1/rpc/record_paid_subscription", "POST");
}

/** Insert requests (POST) made to `alerts`. */
export function alertInserts(server: FakeServer): RecordedRequest[] {
  return server.to("/rest/v1/alerts", "POST");
}

/** Insert requests (POST) made to `subscriptions`. */
export function subscriptionInserts(server: FakeServer): RecordedRequest[] {
  return server.to("/rest/v1/subscriptions", "POST");
}

/** The OFF-branch switch-mismatch alarm's read (Piece B2a plan 2.5): `subscriptions` filtered on `plan=eq.referral_trial`. */
export function isMismatchRead(r: RecordedRequest): boolean {
  return r.method === "GET" && r.path === "/rest/v1/subscriptions" &&
    r.query.some(([k, v]) => k === "plan" && v === "eq.referral_trial");
}

export function mismatchReads(server: FakeServer): RecordedRequest[] {
  return server.requests.filter(isMismatchRead);
}

/** Alerts rows of the switch-mismatch source. */
export function mismatchAlerts(server: FakeServer): RecordedRequest[] {
  return alertInserts(server).filter((r) => (r.body as Record<string, unknown>)?.source === "stacking_switch_mismatch");
}

/**
 * The stacking module's own read (Piece A): a `subscriptions` GET filtered on `end_date=gt.`, other than the
 * mismatch alarm's read.
 */
export function helperReads(server: FakeServer): RecordedRequest[] {
  return server.to("/rest/v1/subscriptions", "GET").filter((r) =>
    !isMismatchRead(r) && r.query.some(([k, v]) => k === "end_date" && v.startsWith("gt."))
  );
}

/** The recorded requests with the mismatch alarm's read removed: the OFF golden comparison (plan 2.5, amended goldens). */
export function withoutMismatchRead(reqs: RecordedRequest[]): RecordedRequest[] {
  return reqs.filter((r) => !isMismatchRead(r));
}

/** An active `referral_trial` grant row (NULL payment id), ending `endInDays` from now. */
export function referralTrialRow(endInDays: number, over: Row = {}): Row {
  return trialRow(endInDays, { id: "rtrial-1", plan: "referral_trial", ...over });
}
