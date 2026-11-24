// OI-519 U4: delete-account's Google Play leg. A fake fetch records every RevenueCat call and answers per URL.
// Run: deno test --allow-read supabase/functions/delete-account/revenuecat_leg_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { cancelAndDeletePlayCustomer, cancelPlayRows, deletePlayCustomer, type PlayDeleteDeps, type PlayTxn } from "./revenuecat_leg.ts";

const UID = "11111111-2222-4333-8444-555555555555";
const BASE = `https://api.revenuecat.com/v1/subscribers/${UID}`;

/** A bare id (or null) is an ACTIVE row; `{ txn, expired }` spells the state out. */
type Row = string | null | PlayTxn;

function run(
  txns: Row[] | { error: string },
  answer: (method: string, url: string) => number | "throw" | "hang",
  secret: string | null = "sk_test",
) {
  const calls: string[] = [];
  const alerts: Array<Record<string, unknown>> = [];
  const auth: string[] = [];
  const fetchFn = ((url: string, init: RequestInit) => {
    calls.push(`${init.method} ${url}`);
    auth.push(String((init.headers as Record<string, string>).Authorization));
    const a = answer(init.method!, url);
    if (a === "throw") return Promise.reject(new TypeError("network"));
    if (a === "hang") {
      return new Promise((_, rej) => init.signal!.addEventListener("abort", () => rej(new DOMException("t", "AbortError"))));
    }
    return Promise.resolve(new Response(a === 204 ? null : "{}", { status: a }));
  }) as unknown as typeof fetch;
  const deps: PlayDeleteDeps = {
    secret,
    readPlayTxns: () =>
      Promise.resolve(
        Array.isArray(txns)
          ? { txns: txns.map((t) => (t !== null && typeof t === "object" ? t : { txn: t, expired: false })) }
          : txns,
      ),
    fetchFn,
    timeoutMs: 20,
    alert: (summary, context) => {
      alerts.push({ summary, ...context });
      return Promise.resolve();
    },
  };
  return cancelAndDeletePlayCustomer(UID, deps).then((r) => ({ r, calls, alerts, auth }));
}

Deno.test("one Play row: cancel by its store transaction id, THEN delete the customer; no alert", async () => {
  const { r, calls, alerts, auth } = await run(["GPA.1"], () => 200);
  assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.1/cancel`, `DELETE ${BASE}`]);
  assertEquals(r, { status: "done:1", customerDeleted: true });
  assertEquals(alerts, []);
  assertEquals(auth, ["Bearer sk_test", "Bearer sk_test"]);
});

Deno.test("a failed cancel skips the customer delete and alerts with the user and the code", async () => {
  for (const a of [500, 400, "throw", "hang"] as const) {
    const { r, calls, alerts } = await run(["GPA.1"], (m) => (m === "POST" ? a : 200));
    assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.1/cancel`], String(a));
    assertEquals(r.customerDeleted, false);
    const code = a === "throw" ? "network" : a === "hang" ? "timeout" : String(a);
    assertEquals(r.status, `cancel_failed:GPA.1:${code}`);
    assertEquals(alerts.length, 1);
    assertEquals(alerts[0].user_id, UID);
    assertEquals(alerts[0].status, r.status);
  }
});

Deno.test("two rows, one cancel fails: both are tried, the delete is skipped for the whole customer", async () => {
  const { r, calls, alerts } = await run(["A", "B"], (_m, url) => (url.includes("/B/") ? 503 : 200));
  assertEquals(calls, [`POST ${BASE}/subscriptions/A/cancel`, `POST ${BASE}/subscriptions/B/cancel`]);
  assertEquals(r.status, "cancel_failed:B:503");
  assertEquals(alerts.length, 1);
  assertEquals(alerts[0].cancelled, 1);
});

Deno.test("an EXPIRED row whose cancel answers 410 Gone has ended: no alert, customer deleted", async () => {
  for (const a of [410] as const) {
    const { r, calls, alerts } = await run([{ txn: "GPA.9", expired: true }], (m) => (m === "POST" ? a : 200));
    assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.9/cancel`, `DELETE ${BASE}`], String(a));
    assertEquals(r, { status: `done:1;ended:GPA.9:${a}`, customerDeleted: true });
    assertEquals(alerts, []);
  }
});

Deno.test("an EXPIRED row may still bill: auth, rate-limit, 5xx, timeout and network failures stay failures", async () => {
  for (const a of [400, 401, 403, 404, 408, 422, 429, 500, 503, "throw", "hang"] as const) {
    const { r, calls, alerts } = await run([{ txn: "GPA.9", expired: true }], (m) => (m === "POST" ? a : 200));
    assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.9/cancel`], String(a));
    assertEquals(r.customerDeleted, false);
    assertEquals(r.status.startsWith("cancel_failed:GPA.9:"), true, String(a));
    assertEquals(alerts.length, 1);
  }
});

Deno.test("an EXPIRED row is still cancelled (paused or on hold can bill); a good cancel is a plain done", async () => {
  const { r, calls } = await run([{ txn: "GPA.9", expired: true }], () => 200);
  assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.9/cancel`, `DELETE ${BASE}`]);
  assertEquals(r.status, "done:1");
});

Deno.test("an ended expired row next to a failed active row: alerted, delete skipped, both named", async () => {
  const { r, alerts } = await run(
    [{ txn: "OLD", expired: true }, { txn: "NEW", expired: false }],
    // Both cancels answer 410: only the EXPIRED row may read it as "ended".
    (m) => (m === "POST" ? 410 : 200),
  );
  assertEquals(r.status, "cancel_failed:NEW:410");
  assertEquals(r.customerDeleted, false);
  assertEquals(alerts[0].cancelled, 0);
  assertEquals(alerts[0].ended, "OLD:410");
});

Deno.test("a row with no transaction id cannot be cancelled: no delete, alerted", async () => {
  const { r, calls } = await run([null], () => 200);
  assertEquals(calls, []);
  assertEquals(r.status, "cancel_failed:no_txn");
});

Deno.test("no Play row: the customer is still deleted (the SDK may have made one); 404 is nothing to erase", async () => {
  const a = await run([], () => 200);
  assertEquals(a.calls, [`DELETE ${BASE}`]);
  assertEquals(a.r, { status: "done:0", customerDeleted: true });
  const b = await run([], () => 404);
  assertEquals(b.r, { status: "done:0", customerDeleted: false });
  assertEquals(b.alerts, []);
});

Deno.test("a failed customer delete after good cancels is alerted", async () => {
  const { r, alerts } = await run(["GPA.1"], (m) => (m === "DELETE" ? 500 : 200));
  assertEquals(r.status, "customer_delete_failed:500");
  assertEquals(alerts.length, 1);
});

Deno.test("no secret: no call; a Play row is alerted, no row is quiet", async () => {
  const a = await run(["GPA.1"], () => 200, null);
  assertEquals(a.calls, []);
  assertEquals(a.r.status, "no_secret");
  assertEquals(a.alerts.length, 1);
  const b = await run([], () => 200, "");
  assertEquals(b.calls, []);
  assertEquals(b.r.status, "no_play_sub");
  assertEquals(b.alerts, []);
});

Deno.test("an unreadable Play lookup: no call, alerted", async () => {
  const { r, calls, alerts } = await run({ error: "57014" }, () => 200);
  assertEquals(calls, []);
  assertEquals(r.status, "lookup_failed");
  assertEquals(alerts[0].code, "57014");
});

Deno.test("a Play lookup that THROWS is a lookup failure, never an exception out of the leg", async () => {
  const alerts: unknown[] = [];
  const deps: PlayDeleteDeps = {
    secret: "sk",
    readPlayTxns: () => Promise.reject(new Error("socket hang up")),
    fetchFn: (() => Promise.reject(new Error("no call expected"))) as unknown as typeof fetch,
    alert: (_s, c) => {
      alerts.push(c);
      return Promise.resolve();
    },
  };
  const r = await cancelAndDeletePlayCustomer(UID, deps);
  assertEquals(r, { status: "lookup_failed", customerDeleted: false });
  assertEquals((alerts[0] as Record<string, unknown>).code, "exception");
});

Deno.test("an alert that throws never fails the erasure leg", async () => {
  const deps: PlayDeleteDeps = {
    secret: "sk",
    readPlayTxns: () => Promise.resolve({ error: "x" }),
    alert: () => Promise.reject(new Error("db down")),
  };
  assertEquals((await cancelAndDeletePlayCustomer(UID, deps)).status, "lookup_failed");
});

Deno.test("index.ts: the leg runs after the Razorpay leg, reads non-refunded Play rows, alerts critical", async () => {
  const src = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\s+/g, " ");
  const razor = src.indexOf("razorpayStatus = `cancel_failed:");
  const leg = src.indexOf("const play = await cancelPlayRows(userId, playDeps);");
  const authDel = src.indexOf("admin.auth.admin.deleteUser(userId)");
  const authFail = src.indexOf('return jsonError(500, "auth_delete_failed", requestId);');
  const custDel = src.indexOf("if (play.deleteCustomer) { try { const customer = await deletePlayCustomer(userId, playDeps);");
  // cancels before the auth delete; the customer DELETE only after it succeeded (never before: a cancel's webhook
  // would re-create the customer while the users row exists).
  assertEquals(razor > 0 && leg > razor && authDel > leg && authFail > authDel && custDel > authFail, true);
  assertEquals(src.includes("cancelAndDeletePlayCustomer"), false, "the function never runs both steps together");
  assertEquals(
    src.includes(
      '.select("store_original_transaction_id, status") .eq("user_id", userId) .eq("store", "play") .neq("status", "cancelled")',
    ),
    true,
  );
  assertEquals(src.includes('expired: r.status === "expired",'), true);
  assertEquals(src.includes('severity: "critical",'), true);
  assertEquals(src.includes('secret: Deno.env.get("REVENUECAT_SECRET_KEY") ?? null,'), true);
});

Deno.test("step 1 (cancelPlayRows) never DELETEs the customer; it says whether step 2 may", async () => {
  const calls: string[] = [];
  const deps: PlayDeleteDeps = {
    secret: "sk",
    readPlayTxns: () => Promise.resolve({ txns: [{ txn: "GPA.1", expired: false }] }),
    fetchFn: ((url: string, init: RequestInit) => {
      calls.push(`${init.method} ${url}`);
      return Promise.resolve(new Response("{}", { status: 200 }));
    }) as unknown as typeof fetch,
    alert: () => Promise.resolve(),
  };
  const c = await cancelPlayRows(UID, deps);
  assertEquals(c, { status: "cancelled:1", deleteCustomer: true });
  assertEquals(calls, [`POST ${BASE}/subscriptions/GPA.1/cancel`]);
  const d = await deletePlayCustomer(UID, deps);
  assertEquals(d, { status: "customer_deleted:200", customerDeleted: true });
  assertEquals(calls.at(-1), `DELETE ${BASE}`);
});

Deno.test("step 1 with a failed cancel: deleteCustomer false (the handle is kept for the hand cancel)", async () => {
  const deps: PlayDeleteDeps = {
    secret: "sk",
    readPlayTxns: () => Promise.resolve({ txns: [{ txn: "GPA.1", expired: false }] }),
    fetchFn: (() => Promise.resolve(new Response("{}", { status: 500 }))) as unknown as typeof fetch,
    alert: () => Promise.resolve(),
  };
  assertEquals((await cancelPlayRows(UID, deps)).deleteCustomer, false);
});
