// OI-519 U2: tests of _shared/revenuecat_mirror.ts (plan docs/plans/2026-11-23-revenuecat-play-billing-51.md, T-MAP).
// Customers are built from the doc-derived fixture _shared/testdata/revenuecat_customer_play_active_monthly.json; the
// fixture is replaced by a real license-tester response at live step L3 and this table is re-run then (plan section 18).
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fetchRevenueCatCustomer,
  isMirrorEnabled,
  mapCustomerToRows,
  type MirrorDb,
  mirrorRevenueCatCustomer,
  PLAY_RENEWAL_WINDOW_MS,
  type PlayRow,
  RevenueCatReadError,
  supabaseMirrorDb,
  UNKNOWN_PRODUCT_ALERT_SOURCE,
  type UpsertResult,
} from "./revenuecat_mirror.ts";

const FIXTURE = JSON.parse(
  await Deno.readTextFile(new URL("./testdata/revenuecat_customer_play_active_monthly.json", import.meta.url)),
);
const UID = "00000000-0000-4000-8000-000000000001";
const H = 3600 * 1000;
const D = 24 * H;
const T0 = Date.parse("2026-11-23T09:00:00Z"); // purchase P
const E = Date.parse("2026-12-23T09:00:00Z"); // expiry E

function customer(patch: Record<string, unknown> = {}, key = "avya_pro"): unknown {
  const c = structuredClone(FIXTURE);
  const entry = { ...c.subscriber.subscriptions.avya_pro, ...patch };
  c.subscriber.subscriptions = { [key]: entry };
  return c;
}
function one(c: unknown, now: number): PlayRow {
  const { rows, issues } = mapCustomerToRows(c, now);
  assertEquals(issues, []);
  assertEquals(rows.length, 1);
  return rows[0];
}
const isoOf = (ms: number) => new Date(ms).toISOString();

// ---------------------------------------------------------------------------------------------------------------- T-MAP
Deno.test("active monthly: renewing, end = E + 3 h, store_expires_at = E, start = P", () => {
  const r = one(customer(), T0 + D);
  assertEquals(r.status, "active");
  assertEquals(r.plan, "monthly");
  assertEquals(r.autoRenew, true);
  assertEquals(r.endIso, isoOf(E + PLAY_RENEWAL_WINDOW_MS));
  assertEquals(r.storeExpiresIso, isoOf(E));
  assertEquals(r.startIso, isoOf(T0));
  assertEquals(r.environment, "SANDBOX");
  assertEquals(r.productId, "avya_pro");
});

Deno.test("active yearly: plan from product_plan_identifier", () => {
  assertEquals(one(customer({ product_plan_identifier: "yearly" }), T0).plan, "yearly");
});

Deno.test("renewal window: at E + 1 h with no renewal posted the row stays active; at E + 4 h it is expired", () => {
  assertEquals(one(customer(), E + 1 * H).status, "active");
  assertEquals(one(customer(), E + 4 * H).status, "expired");
});

Deno.test("cancelled but not expired: active until E, auto_renew false, no window", () => {
  const c = customer({ unsubscribe_detected_at: "2026-11-30T10:00:00Z" });
  const r = one(c, E - H);
  assertEquals(r.status, "active");
  assertEquals(r.autoRenew, false);
  assertEquals(r.endIso, isoOf(E));
  assertEquals(one(c, E + 10 * 60 * 1000).status, "expired"); // the window never applies after an unsubscribe
});

Deno.test("billing issue in grace: end = max(E, G), active through G, no window", () => {
  const G = E + 3 * D;
  const c = customer({ billing_issues_detected_at: "2026-12-23T09:05:00Z", grace_period_expires_date: isoOf(G) });
  const r = one(c, E + D);
  assertEquals(r.status, "active");
  assertEquals(r.endIso, isoOf(G));
  assertEquals(r.autoRenew, false);
  assertEquals(one(c, G + 60_000).status, "expired");
});

Deno.test("grace date ignored when no billing issue is open", () => {
  const c = customer({ unsubscribe_detected_at: "2026-11-30T10:00:00Z", grace_period_expires_date: isoOf(E + 3 * D) });
  assertEquals(one(c, T0).endIso, isoOf(E));
});

Deno.test("expired: E in the past and not renewing", () => {
  const c = customer({ unsubscribe_detected_at: "2026-11-30T10:00:00Z" });
  assertEquals(one(c, E + D).status, "expired");
});

Deno.test("refund of the current period: cancelled, end = refunded_at (wins over every other rule)", () => {
  const refunded = "2026-11-25T12:00:00Z";
  const r = one(customer({ refunded_at: refunded }), T0 + 3 * D);
  assertEquals(r.status, "cancelled");
  assertEquals(r.endIso, isoOf(Date.parse(refunded)));
  // a later read of the same refunded chain stays cancelled
  assertEquals(one(customer({ refunded_at: refunded }), E + 10 * D).status, "cancelled");
});

Deno.test("refund of an OLD period followed by a new purchase does not cancel the new purchase", () => {
  const c = customer({ refunded_at: "2026-11-01T00:00:00Z" }); // before P = 2026-11-23
  assertEquals(one(c, T0 + D).status, "active");
});

Deno.test("paused (auto_resume_date set): not renewing, expired after E (no renewal window)", () => {
  const paused = customer({ auto_resume_date: "2027-01-23T09:00:00Z" });
  const r = one(paused, E + 30 * 60 * 1000);
  assertEquals(r.status, "expired");
  assertEquals(r.autoRenew, false);
});

Deno.test("PRODUCTION from is_sandbox false; store_transaction_id number -> string", () => {
  const r = one(customer({ is_sandbox: false, store_transaction_id: 12345 }), T0);
  assertEquals(r.environment, "PRODUCTION");
  assertEquals(r.originalTxn, "12345");
});

Deno.test("unknown plan id -> no row, issue unknown_plan", () => {
  const { rows, issues } = mapCustomerToRows(customer({ product_plan_identifier: "weekly" }), T0);
  assertEquals(rows, []);
  assertEquals(issues, [{ kind: "unknown_plan", productId: "avya_pro" }]);
});

Deno.test("unknown Play product -> no row, issue unknown_product; other stores ignored silently", () => {
  const { rows, issues } = mapCustomerToRows(customer({}, "other_sub"), T0);
  assertEquals(rows, []);
  assertEquals(issues, [{ kind: "unknown_product", productId: "other_sub" }]);
  const apple = mapCustomerToRows(customer({ store: "app_store" }), T0);
  assertEquals(apple, { rows: [], issues: [] });
});

Deno.test("bad entry (missing expires_date or is_sandbox) -> no row, issue bad_entry", () => {
  assertEquals(mapCustomerToRows(customer({ expires_date: null }), T0).issues[0].kind, "bad_entry");
  assertEquals(mapCustomerToRows(customer({ is_sandbox: "yes" }), T0).issues[0].kind, "bad_entry");
});

Deno.test("customer with no subscriptions -> nothing", () => {
  assertEquals(mapCustomerToRows({ subscriber: { subscriptions: {} } }, T0), { rows: [], issues: [] });
  assertEquals(mapCustomerToRows(null, T0), { rows: [], issues: [] });
});

// ---------------------------------------------------------------------------------------------------------- switch + IO
Deno.test("kill switch: only the exact string true", () => {
  assertEquals(isMirrorEnabled(() => "true"), true);
  for (const v of [undefined, "TRUE", " true", "1", ""]) assertEquals(isMirrorEnabled(() => v), false);
});

type Calls = { gets: string[]; upserts: { uid: string; row: PlayRow; readAt: string }[]; alerts: string[] };
function fakeDb(known: boolean, calls: Calls, result: UpsertResult = "written"): MirrorDb {
  return {
    userExists: (_uid) => Promise.resolve(known),
    upsertPlayRow: (uid, row, readAt) => {
      calls.upserts.push({ uid, row, readAt });
      return Promise.resolve(result);
    },
    alert: (source) => {
      calls.alerts.push(source);
      return Promise.resolve();
    },
  };
}
function fakeFetch(calls: Calls, responses: (Response | Error)[]): typeof fetch {
  let i = 0;
  return ((url: string | URL, init?: RequestInit) => {
    calls.gets.push(String(url));
    assertEquals((init?.headers as Record<string, string>).Authorization, "Bearer sk_test");
    const r = responses[Math.min(i++, responses.length - 1)];
    return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
  }) as typeof fetch;
}
const ok = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

Deno.test("mirror: refuses a non-UUID and an unknown user BEFORE any RevenueCat call", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const f = fakeFetch(calls, [ok(FIXTURE)]);
  assertEquals((await mirrorRevenueCatCustomer("not-a-uuid", { db: fakeDb(true, calls), secretKey: "sk_test", fetchFn: f })).outcome, "refused_uid");
  assertEquals((await mirrorRevenueCatCustomer(UID, { db: fakeDb(false, calls), secretKey: "sk_test", fetchFn: f })).outcome, "unknown_user");
  assertEquals(calls.gets, []);
});

Deno.test("mirror: a missing secret key THROWS no_secret after a critical alert, before any RevenueCat call (B-pass F2)", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const f = fakeFetch(calls, [ok(FIXTURE)]);
  const err = await assertRejects(() => mirrorRevenueCatCustomer(UID, { db: fakeDb(true, calls), secretKey: undefined, fetchFn: f }), RevenueCatReadError);
  assertEquals(err.code, "no_secret");
  assertEquals(calls.gets, []);
  assertEquals(calls.upserts, []);
  assertEquals(calls.alerts.length, 1);
});

Deno.test("mirror: an alert that REJECTS cannot replace the typed no_secret throw (B-pass round 2, F1)", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const db: MirrorDb = { ...fakeDb(true, calls), alert: () => Promise.reject(new Error("alerts down")) };
  const err = await assertRejects(() => mirrorRevenueCatCustomer(UID, { db, secretKey: undefined, fetchFn: fakeFetch(calls, [ok(FIXTURE)]) }), RevenueCatReadError);
  assertEquals(err.code, "no_secret");
});

Deno.test("mirror: read_at is stamped BEFORE the GET, the row is upserted, outcome mirrored", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  let clock = T0 + D;
  const f = ((url: string | URL, init?: RequestInit) => {
    calls.gets.push(String(url));
    clock += 5000; // the GET takes 5 s
    return fakeFetch(calls, [ok(FIXTURE)])(url, init);
  }) as typeof fetch;
  const out = await mirrorRevenueCatCustomer(UID, { db: fakeDb(true, calls), secretKey: "sk_test", fetchFn: f, nowMs: () => clock });
  assertEquals(out.outcome, "mirrored");
  assertEquals(calls.upserts.length, 1);
  assertEquals(calls.upserts[0].readAt, isoOf(T0 + D)); // before the 5 s GET
  assertEquals(calls.gets[0], `https://api.revenuecat.com/v1/subscribers/${UID}`);
});

Deno.test("mirror: stale_read is reported per row", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const out = await mirrorRevenueCatCustomer(UID, {
    db: fakeDb(true, calls, "stale_read"), secretKey: "sk_test", fetchFn: fakeFetch(calls, [ok(FIXTURE)]), nowMs: () => T0,
  });
  assert(out.outcome === "mirrored");
  assertEquals(out.rows[0].result, "stale_read");
});

Deno.test("mirror: sandbox_refused is reported per row (a SANDBOX read over a running PRODUCTION row)", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const out = await mirrorRevenueCatCustomer(UID, {
    db: fakeDb(true, calls, "sandbox_refused"), secretKey: "sk_test", fetchFn: fakeFetch(calls, [ok(FIXTURE)]), nowMs: () => T0,
  });
  assert(out.outcome === "mirrored");
  assertEquals(out.rows[0].result, "sandbox_refused");
});

Deno.test("mirror: an unknown plan raises the critical alert and writes nothing", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  await mirrorRevenueCatCustomer(UID, {
    db: fakeDb(true, calls), secretKey: "sk_test",
    fetchFn: fakeFetch(calls, [ok(customer({ product_plan_identifier: "weekly" }))]), nowMs: () => T0,
  });
  assertEquals(calls.upserts, []);
  assertEquals(calls.alerts, [UNKNOWN_PRODUCT_ALERT_SOURCE]);
});

Deno.test("fetch: 201 (customer created) is a success", async () => {
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const body = await fetchRevenueCatCustomer(UID, "sk_test", fakeFetch(calls, [ok(FIXTURE, 201)]));
  assertEquals((body as typeof FIXTURE).subscriber.original_app_user_id, FIXTURE.subscriber.original_app_user_id);
});

Deno.test("fetch: one retry on 5xx / 429 / network, none on another 4xx", async () => {
  for (const first of [ok({}, 503), ok({}, 429), new TypeError("net")]) {
    const calls: Calls = { gets: [], upserts: [], alerts: [] };
    await fetchRevenueCatCustomer(UID, "sk_test", fakeFetch(calls, [first, ok(FIXTURE)]));
    assertEquals(calls.gets.length, 2);
  }
  const calls: Calls = { gets: [], upserts: [], alerts: [] };
  const err = await assertRejects(() => fetchRevenueCatCustomer(UID, "sk_test", fakeFetch(calls, [ok({}, 401), ok(FIXTURE)])), RevenueCatReadError);
  assertEquals(err.code, "http_401");
  assertEquals(calls.gets.length, 1);
  const calls2: Calls = { gets: [], upserts: [], alerts: [] };
  const err2 = await assertRejects(() => fetchRevenueCatCustomer(UID, "sk_test", fakeFetch(calls2, [ok({}, 500), ok({}, 502)])), RevenueCatReadError);
  assertEquals(err2.code, "http_502");
  assertEquals(calls2.gets.length, 2);
});

Deno.test("fetch: a hung GET is aborted after the timeout and retried once", async () => {
  let n = 0;
  const hang = ((_u: string | URL, init?: RequestInit) => {
    n++;
    return new Promise<Response>((_res, rej) => init?.signal?.addEventListener("abort", () => rej(new DOMException("x", "AbortError"))));
  }) as typeof fetch;
  const err = await assertRejects(() => fetchRevenueCatCustomer(UID, "sk_test", hang, 20), RevenueCatReadError);
  assertEquals(err.code, "timeout");
  assertEquals(n, 2);
});

Deno.test("adapter: upsertPlayRow passes the three known answers through and throws on anything else", async () => {
  const row: PlayRow = mapCustomerToRows(FIXTURE, T0).rows[0];
  const db = (answer: unknown) =>
    supabaseMirrorDb({
      from: () => {
        throw new Error("no table read expected");
      },
      rpc: (_fn: string, _args: Record<string, unknown>) => Promise.resolve({ data: answer, error: null }),
    });
  for (const a of ["written", "stale_read", "sandbox_refused"]) {
    assertEquals(await db(a).upsertPlayRow(UID, row, new Date(T0).toISOString()), a);
  }
  await assertRejects(() => db("refused").upsertPlayRow(UID, row, new Date(T0).toISOString()), Error, "unknown value");
});

Deno.test("adapter: alert sends nothing when its dedup read fails, one insert when none is open, none when one is (B-pass round 2, F1)", async () => {
  const fakeClient = (read: { data: unknown; error: unknown }, inserts: unknown[]) => ({
    from: (_t: string) => {
      const chain = {
        select: () => chain, eq: () => chain, gte: () => chain,
        limit: () => Promise.resolve(read),
        insert: (v: unknown) => { inserts.push(v); return Promise.resolve({ error: null }); },
      };
      return chain;
    },
    rpc: () => { throw new Error("no rpc expected"); },
  });
  const failed: unknown[] = [];
  await supabaseMirrorDb(fakeClient({ data: null, error: { code: "PGRST000" } }, failed)).alert("s", "critical", "x", {});
  assertEquals(failed.length, 0);
  const none: unknown[] = [];
  await supabaseMirrorDb(fakeClient({ data: [], error: null }, none)).alert("s", "critical", "x", {});
  assertEquals(none.length, 1);
  const open: unknown[] = [];
  await supabaseMirrorDb(fakeClient({ data: [{ id: 1 }], error: null }, open)).alert("s", "critical", "x", {});
  assertEquals(open.length, 0);
});
