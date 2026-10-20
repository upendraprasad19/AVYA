// OI-341 Piece B1: unit tests of the stacking module (docs/plans/oi341-piece-b-door.md 2.2, 3b).
// `recordPaidSubscription` runs against the REAL supabase-js client over the fetch-level fake
// (postgrest_fake_fetch.ts) for the request shape, and against stub clients for the answer shapes.
// The SQL behaviour of the function itself is proven in test/sql (not here).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  isStackingEnabled,
  isValidPaymentId,
  plainEndDate,
  recordPaidSubscription,
  STACKING_ENABLE_ENV,
} from "./subscription_stacking.ts";
import { FAKE_ORIGIN, FakeServer, jsonResponse } from "./postgrest_fake_fetch.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const PAY = "pay_NEW0000000001";

const ARGS = { userId: USER, plan: "yearly", paymentId: PAY, orderId: "order_X1", signature: "sig_1" };

// ── isStackingEnabled ───────────────────────────────────────────────────────

Deno.test("isStackingEnabled: exactly the string 'true' is ON; every other value is OFF", () => {
  const at = (v: string | undefined) => isStackingEnabled((n) => (n === STACKING_ENABLE_ENV ? v : undefined));
  assertEquals(at("true"), true);
  for (const v of [undefined, "false", "TRUE", "True", " true", "true ", "true\n", "\ttrue", "", "1", "yes"]) {
    assertEquals(at(v), false, JSON.stringify(v));
  }
});

Deno.test("isStackingEnabled: reads the secret NAME it exports, and the live env by default", () => {
  assertEquals(STACKING_ENABLE_ENV, "ENABLE_SUBSCRIPTION_STACKING");
  assertEquals(isStackingEnabled((n) => (n === "ENABLE_SUBSCRIPTION_STACKING" ? "true" : "true-but-wrong-name")), true);
  assertEquals(isStackingEnabled((n) => (n === "OTHER_NAME" ? "true" : undefined)), false);
  const before = Deno.env.get(STACKING_ENABLE_ENV);
  try {
    Deno.env.set(STACKING_ENABLE_ENV, "true");
    assertEquals(isStackingEnabled(), true);
    Deno.env.set(STACKING_ENABLE_ENV, "TRUE");
    assertEquals(isStackingEnabled(), false);
    Deno.env.delete(STACKING_ENABLE_ENV);
    assertEquals(isStackingEnabled(), false);
  } finally {
    if (before === undefined) Deno.env.delete(STACKING_ENABLE_ENV);
    else Deno.env.set(STACKING_ENABLE_ENV, before);
  }
});

// ── plainEndDate ────────────────────────────────────────────────────────────

Deno.test("plainEndDate: equals the old inline setDate arithmetic for 30 and 365 and does not mutate its input", () => {
  const now = new Date("2026-10-17T10:00:00.000Z");
  const before = now.getTime();
  for (const days of [30, 365]) {
    const old = new Date(now);
    old.setDate(old.getDate() + days);
    assertEquals(plainEndDate(now, days).toISOString(), old.toISOString());
  }
  assertEquals(now.getTime(), before);
});

// The old inline code, run in a subprocess under several TZ values (a month-end / DST regression check).
Deno.test("plainEndDate equals the old inline setDate code under several TZ values (DST and month-end bases)", async () => {
  const modulePath = new URL("./subscription_stacking.ts", import.meta.url).href;
  const script = `
    import { plainEndDate } from ${JSON.stringify(modulePath)};
    const bases = ["2026-01-31T10:00:00Z","2026-02-28T23:30:00Z","2026-03-08T06:30:00Z","2026-03-29T00:30:00Z",
      "2026-10-04T15:30:00Z","2026-10-31T20:00:00Z","2026-11-01T05:30:00Z","2028-02-29T12:00:00Z","2026-12-31T18:45:00Z"];
    let bad = 0;
    for (const b of bases) for (const days of [30, 365]) {
      const now = new Date(b);
      const old = new Date(now); old.setDate(old.getDate() + days);
      if (plainEndDate(now, days).toISOString() !== old.toISOString()) bad++;
    }
    console.log(bad === 0 ? "equivalent" : "DIFFERS " + bad);
  `;
  for (const tz of ["UTC", "Asia/Kolkata", "America/New_York", "Australia/Lord_Howe"]) {
    const out = await new Deno.Command(Deno.execPath(), {
      args: ["eval", "--no-check", script],
      env: { TZ: tz },
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(out.stdout).trim();
    assertEquals(text, "equivalent", `TZ=${tz}: ${new TextDecoder().decode(out.stderr)}`);
  }
});

// ── isValidPaymentId ────────────────────────────────────────────────────────

Deno.test("isValidPaymentId: real Razorpay ids pass; structural characters and bad shapes fail", () => {
  assert(isValidPaymentId("pay_NEW0000000001"));
  assert(isValidPaymentId("pay_" + "a".repeat(64)));
  for (const bad of ["", "pay_", "pay_" + "a".repeat(65), "pay_X?y=1", "pay_X/capture", "pay_X#1", "../x",
    "pay_a,b", "pay_a)", "pay_a(", "xpay_abc", "pay_abc ", "pay_ab\n", "manual_grant_123"]) {
    assertEquals(isValidPaymentId(bad), false, JSON.stringify(bad));
  }
  assertEquals(isValidPaymentId(undefined), false);
  assertEquals(isValidPaymentId(12), false);
});

// ── recordPaidSubscription ──────────────────────────────────────────────────

function realClient(server: FakeServer) {
  server.install();
  return createClient(FAKE_ORIGIN, "service-role", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

/** A stub whose rpc() answers `{data, error}` and remembers the call. */
function stub(answer: { data?: unknown; error?: unknown }) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  return {
    calls,
    db: {
      rpc: (fn: string, args: Record<string, unknown>) => {
        calls.push({ fn, args });
        return Promise.resolve({ data: answer.data ?? null, error: answer.error ?? null });
      },
    },
  };
}

const goodRow = {
  out_end_date: "2026-11-16T10:00:00.123456+00:00",
  out_start_date: "2026-10-17T10:00:00.654321+00:00",
  out_inserted: true,
};

Deno.test("recordPaidSubscription: calls rpc 'record_paid_subscription' once with exactly the five p_ args", async () => {
  const server = new FakeServer({ rpcs: { record_paid_subscription: () => [goodRow] } });
  const db = realClient(server);
  try {
    const r = await recordPaidSubscription(db, ARGS);
    assertEquals(r.ok, true);
    const calls = server.to("/rest/v1/rpc/", "POST");
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, "/rest/v1/rpc/record_paid_subscription");
    assertEquals(calls[0].body, {
      p_user_id: USER,
      p_plan: "yearly",
      p_payment_id: PAY,
      p_order_id: "order_X1",
      p_signature: "sig_1",
    });
    assertEquals(server.requests.length, 1, "no other request");
  } finally {
    server.restore();
  }
});

Deno.test("recordPaidSubscription: a null order id is passed as null (not dropped)", async () => {
  const s = stub({ data: [goodRow] });
  await recordPaidSubscription(s.db, { ...ARGS, orderId: null });
  assertEquals(s.calls[0].args.p_order_id, null);
  assert("p_order_id" in s.calls[0].args);
});

Deno.test("recordPaidSubscription: an UNDEFINED order id is sent as JSON null, so the request body still names all five args", async () => {
  const server = new FakeServer({ rpcs: { record_paid_subscription: () => [goodRow] } });
  const db = realClient(server);
  try {
    const r = await recordPaidSubscription(db, { ...ARGS, orderId: undefined });
    assert(r.ok);
    const body = server.to("/rest/v1/rpc/record_paid_subscription", "POST")[0].body as Record<string, unknown>;
    assert("p_order_id" in body, `p_order_id dropped from the body: ${JSON.stringify(body)}`);
    assertEquals(body.p_order_id, null);
  } finally {
    server.restore();
  }
});

Deno.test("recordPaidSubscription: ok row with a '+00:00' microsecond timestamp parses to the right instants", async () => {
  const server = new FakeServer({ rpcs: { record_paid_subscription: () => [goodRow] } });
  const db = realClient(server);
  try {
    const r = await recordPaidSubscription(db, ARGS);
    assert(r.ok);
    assertEquals(r.endDate.toISOString(), "2026-11-16T10:00:00.123Z");
    assertEquals(r.startDate.toISOString(), "2026-10-17T10:00:00.654Z");
    assertEquals(r.inserted, true);
  } finally {
    server.restore();
  }
});

Deno.test("recordPaidSubscription: a '+05:30' offset maps to the correct instant; inserted=false is carried", async () => {
  const s = stub({
    data: [{
      out_end_date: "2026-11-16T15:30:00.250000+05:30",
      out_start_date: "2026-10-17T15:30:00+05:30",
      out_inserted: false,
    }],
  });
  const r = await recordPaidSubscription(s.db, ARGS);
  assert(r.ok);
  assertEquals(r.endDate.toISOString(), "2026-11-16T10:00:00.250Z");
  assertEquals(r.startDate.toISOString(), "2026-10-17T10:00:00.000Z");
  assertEquals(r.inserted, false);
});

Deno.test("recordPaidSubscription: a database error with a code is ok:false with that code", async () => {
  const server = new FakeServer({
    rpcs: {
      record_paid_subscription: () => jsonResponse(400, { code: "55P03", message: "could not obtain lock", details: null, hint: null }),
    },
  });
  const db = realClient(server);
  try {
    assertEquals(await recordPaidSubscription(db, ARGS), { ok: false, code: "55P03" });
  } finally {
    server.restore();
  }
});

Deno.test("recordPaidSubscription: an error with an EMPTY code is read_error (|| not ??)", async () => {
  assertEquals(await recordPaidSubscription(stub({ error: { code: "", message: "TypeError: fetch failed" } }).db, ARGS), {
    ok: false,
    code: "read_error",
  });
  assertEquals(await recordPaidSubscription(stub({ error: { message: "no code at all" } }).db, ARGS), {
    ok: false,
    code: "read_error",
  });
  // The real client reports a transport failure with code "".
  const server = new FakeServer({ intercept: () => "throw" });
  const db = realClient(server);
  try {
    assertEquals(await recordPaidSubscription(db, ARGS), { ok: false, code: "read_error" });
  } finally {
    server.restore();
  }
});

Deno.test("recordPaidSubscription: a THROWN rejection is ok:false and never escapes", async () => {
  const rejecting = { rpc: () => Promise.reject(new TypeError("boom")) };
  assertEquals(await recordPaidSubscription(rejecting, ARGS), { ok: false, code: "TypeError" });
  const syncThrow = { rpc: () => { throw new Error("sync boom"); } };
  assertEquals(await recordPaidSubscription(syncThrow, ARGS), { ok: false, code: "Error" });
  const nameless = { rpc: () => Promise.reject(null) };
  assertEquals(await recordPaidSubscription(nameless, ARGS), { ok: false, code: "thrown" });
});

Deno.test("recordPaidSubscription: a malformed answer is ok:false 'bad_rpc_response' (never success)", async () => {
  const bad: Array<[string, unknown]> = [
    ["scalar 1 (the harness fallbackRpc answer)", 1],
    ["null data", null],
    ["object instead of array", goodRow],
    ["empty array", []],
    ["two rows", [goodRow, goodRow]],
    ["unparseable out_end_date", [{ ...goodRow, out_end_date: "not-a-date" }]],
    ["missing out_end_date", [{ out_start_date: goodRow.out_start_date, out_inserted: true }]],
    ["non-string out_end_date", [{ ...goodRow, out_end_date: 1792231200000 }]],
    ["unparseable out_start_date", [{ ...goodRow, out_start_date: "nope" }]],
    ["non-boolean out_inserted ('true')", [{ ...goodRow, out_inserted: "true" }]],
    ["non-boolean out_inserted (1)", [{ ...goodRow, out_inserted: 1 }]],
    ["missing out_inserted", [{ out_end_date: goodRow.out_end_date, out_start_date: goodRow.out_start_date }]],
  ];
  for (const [label, data] of bad) {
    const s = stub({ data });
    assertEquals(await recordPaidSubscription(s.db, ARGS), { ok: false, code: "bad_rpc_response" }, label);
  }
  // And through the real client: the unrouted-RPC fallback answer `1` must not read as success.
  const server = new FakeServer({ fallbackRpc: () => 1 });
  const db = realClient(server);
  try {
    assertEquals(await recordPaidSubscription(db, ARGS), { ok: false, code: "bad_rpc_response" });
  } finally {
    server.restore();
  }
});
