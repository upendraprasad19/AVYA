// redeem-referral — behavioural tests for the paid-referee guard (migration 159, unit S2).
//
// WHAT THIS PROVES. handleRedeemReferral is driven with a FAKE supabase client that records every call, so each test
// reads the real response status and body AND what the function asked of the database:
//   * a referee who has ever PAID gets a clean 400 (step 5b) and the RPC is never called;
//   * the check sits AFTER the idempotency step (an already-redeemed paid user still reads "Code already applied");
//   * a read ERROR on `subscriptions` falls through to the RPC (its refusal is the authoritative check);
//   * the RPC's own `referee_has_paid_plan` refusal maps to the SAME 400 (not the generic 500);
//   * every unchanged outcome stays unchanged: success, the 23505 race, any other RPC error (500).
// Importing index.ts must not bind a server: that is the `import.meta.main` guard (a leaked listener would fail the
// Deno resource sanitizer at the end of the run).
//
// The fake is hand-built, not a mock of supabase-js: it implements exactly the chains this function uses, and a chain
// the function does not use throws, so a changed query shape reddens a test instead of silently returning data.

import { assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleRedeemReferral } from "./index.ts";

const REFEREE_ID = "11111111-1111-1111-1111-111111111111";
const REFERRER_ID = "22222222-2222-2222-2222-222222222222";
const PAID_MESSAGE = "Referral codes are for new recruits who haven't subscribed yet.";

interface Opts {
  user?: { id: string; created_at: string } | null;
  codeRow?: { user_id: string; expires_at: string } | null;
  alreadyRedeemed?: boolean;
  /** rows the subscriptions read returns; `"error"` makes the read return an error, `"throw"` makes it reject. */
  paid?: Array<Record<string, unknown>> | "error" | "throw";
  rpcError?: { code?: string; message?: string } | null;
}

interface Call {
  table?: string;
  rpc?: string;
  args?: unknown;
  ops: Array<[string, unknown[]]>;
}

function fakeClient(opts: Opts) {
  const calls: Call[] = [];
  const nowIso = new Date().toISOString();
  const user = opts.user === undefined ? { id: REFEREE_ID, created_at: nowIso } : opts.user;
  const codeRow = opts.codeRow === undefined
    ? { user_id: REFERRER_ID, expires_at: new Date(Date.now() + 86_400_000).toISOString() }
    : opts.codeRow;

  function builder(table: string) {
    const call: Call = { table, ops: [] };
    calls.push(call);
    const record = (name: string) => (...args: unknown[]) => {
      call.ops.push([name, args]);
      return b;
    };
    const resolve = (): { data: unknown; error: unknown } => {
      if (table === "referral_codes") return { data: codeRow, error: codeRow ? null : { message: "not found" } };
      if (table === "referral_redemptions") return { data: opts.alreadyRedeemed ? { id: "r1" } : null, error: null };
      if (table === "subscriptions") {
        if (opts.paid === "throw") throw new Error("connection reset");
        if (opts.paid === "error") return { data: null, error: { message: "read failed" } };
        return { data: opts.paid ?? [], error: null };
      }
      throw new Error(`unexpected table ${table}`);
    };
    const b: Record<string, unknown> = {
      select: record("select"),
      eq: record("eq"),
      in: record("in"),
      not: record("not"),
      limit: record("limit"),
      single: () => Promise.resolve(resolve()),
      maybeSingle: () => Promise.resolve(resolve()),
      then: (ok: (v: unknown) => unknown, bad?: (e: unknown) => unknown) =>
        new Promise((res) => res(resolve())).then(ok, bad),
    };
    return b;
  }

  const client = {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve(user ? { data: { user }, error: null } : { data: { user: null }, error: { message: "bad jwt" } }),
    },
    from: (table: string) => builder(table),
    rpc: (name: string, args: unknown) => {
      calls.push({ rpc: name, args, ops: [] });
      return Promise.resolve({ error: opts.rpcError ?? null });
    },
  };
  // deno-lint-ignore no-explicit-any
  return { client: client as any, calls };
}

async function redeem(opts: Opts) {
  const { client, calls } = fakeClient(opts);
  const res = await handleRedeemReferral({ code: "avya-abcd1234" }, client, "token");
  const body = await res.json() as Record<string, unknown>;
  const rpcCalls = calls.filter((c) => c.rpc);
  const subsReads = calls.filter((c) => c.table === "subscriptions");
  return { status: res.status, body, rpcCalls, subsReads, calls };
}

Deno.test("a referee who has ever paid gets the clean 400 and the RPC is never called", async () => {
  const r = await redeem({ paid: [{ id: "s1" }] });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, PAID_MESSAGE);
  assertEquals(typeof r.body.request_id, "string");
  assertEquals(r.rpcCalls.length, 0, "the RPC must not run for a paid referee");
});

Deno.test("control: a referee with no paid row is redeemed (200, success, one RPC call with the declared arguments)", async () => {
  const r = await redeem({ paid: [] });
  assertEquals(r.status, 200);
  assertEquals(r.body.success, true);
  assertEquals(r.body.days_granted, 7);
  assertEquals(r.rpcCalls.length, 1);
  assertEquals(r.rpcCalls[0].rpc, "redeem_referral_atomic");
  assertEquals(r.rpcCalls[0].args, {
    p_code: "AVYA-ABCD1234",
    p_referrer_id: REFERRER_ID,
    p_referee_id: REFEREE_ID,
    p_days: 7,
  });
});

Deno.test("the paid read asks for exactly: this user, plans monthly/yearly, payment id present, one row", async () => {
  const r = await redeem({ paid: [] });
  assertEquals(r.subsReads.length, 1);
  assertEquals(r.subsReads[0].ops, [
    ["select", ["id"]],
    ["eq", ["user_id", REFEREE_ID]],
    ["in", ["plan", ["monthly", "yearly"]]],
    ["not", ["razorpay_payment_id", "is", null]],
    ["limit", [1]],
  ]);
});

Deno.test("an already-redeemed paid user still reads 'Code already applied' (the idempotency step runs first)", async () => {
  const r = await redeem({ alreadyRedeemed: true, paid: [{ id: "s1" }] });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, "Code already applied to your account.");
  assertEquals(r.subsReads.length, 0, "the paid read must not run once the idempotency step has answered");
  assertEquals(r.rpcCalls.length, 0);
});

Deno.test("a READ ERROR on subscriptions is LOGGED and falls through to the RPC (its refusal is the authoritative check)", async () => {
  const seen: string[] = [];
  const origWarn = console.warn;
  console.warn = (...a: unknown[]) => {
    seen.push(a.map(String).join(" "));
  };
  try {
    const r = await redeem({ paid: "error" });
    assertEquals(r.status, 200);
    assertEquals(r.rpcCalls.length, 1, "an unreadable paid check must not block a new recruit, and must not fake a refusal");
  } finally {
    console.warn = origWarn;
  }
  assertEquals(seen.length, 1, "a failing check must leave a trace in the server log, exactly once");
  assertStringIncludes(seen[0], "paid-check read failed: read failed");
});

Deno.test("a successful paid read logs nothing (the warning is only for a failing read)", async () => {
  const seen: string[] = [];
  const origWarn = console.warn;
  console.warn = (...a: unknown[]) => {
    seen.push(a.map(String).join(" "));
  };
  try {
    await redeem({ paid: [] });
    await redeem({ paid: [{ id: "s1" }] });
  } finally {
    console.warn = origWarn;
  }
  assertEquals(seen.length, 0);
});

Deno.test("a THROWN subscriptions read propagates out of handleRedeemReferral (handler's catch turns it into the generic 500) and the RPC never runs", async () => {
  const { client, calls } = fakeClient({ paid: "throw" });
  await assertRejects(() => handleRedeemReferral({ code: "AVYA-ABCD1234" }, client, "token"), Error, "connection reset");
  assertEquals(calls.filter((c) => c.rpc).length, 0);
});

Deno.test("the RPC's own referee_has_paid_plan refusal maps to the SAME clean 400, not the generic 500", async () => {
  const r = await redeem({ paid: [], rpcError: { code: "P0001", message: "referee_has_paid_plan" } });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, PAID_MESSAGE);
  assertEquals(r.rpcCalls.length, 1);
});

Deno.test("another RPC error stays a generic 500 and leaks no detail", async () => {
  const r = await redeem({ paid: [], rpcError: { code: "P0001", message: "some other raise" } });
  assertEquals(r.status, 500);
  assertEquals(r.body.error, "Internal server error");
});

Deno.test("the 23505 race stays 200 alreadyRedeemed with success:true", async () => {
  const r = await redeem({ paid: [], rpcError: { code: "23505", message: "duplicate key" } });
  assertEquals(r.status, 200);
  assertEquals(r.body.success, true);
  assertEquals(r.body.alreadyRedeemed, true);
});

Deno.test("an unauthenticated caller still gets the function's own 401 before any database read", async () => {
  const { client, calls } = fakeClient({ user: null });
  const res = await handleRedeemReferral({ code: "AVYA-ABCD1234" }, client, "bad");
  assertEquals(res.status, 401);
  assertStringIncludes(JSON.stringify(await res.json()), "Authentication required");
  assertEquals(calls.length, 0);
});

Deno.test("the earlier steps are unchanged: a malformed code is a 400 before the paid read", async () => {
  const { client, calls } = fakeClient({ paid: [{ id: "s1" }] });
  const res = await handleRedeemReferral({ code: "nope" }, client, "token");
  assertEquals(res.status, 400);
  assertStringIncludes(JSON.stringify(await res.json()), "Codes look like AVYA-XXXXXXXX.");
  assertEquals(calls.filter((c) => c.table === "subscriptions").length, 0);
});
