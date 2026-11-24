// OI-519 (+51): drives the REAL revenuecat-reconcile database adapters (reconcileDb in
// supabase/functions/revenuecat-reconcile/index.ts) through the same supabase-js the function ships with, against a
// local PostgREST in front of a local database that carries migration 182. Run by revenuecat_reconcile_postgrest_local.sh
// (never against a live host: the URL is fixed to 127.0.0.1). The Deno unit tests use a fake db; this file is the only
// proof that the claim / mark / candidate filters mean the same thing to PostgREST.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { reconcileDb } from "../../supabase/functions/revenuecat-reconcile/index.ts";
import { ledgerWriter } from "../../supabase/functions/revenuecat-webhook/index.ts";
import { PAID_ROW_FILTER } from "../../supabase/functions/redeem-referral/index.ts";
import { type PlayRow, supabaseMirrorDb } from "../../supabase/functions/_shared/revenuecat_mirror.ts";

const BASE = "http://127.0.0.1:" + (Deno.env.get("OI519_PGRST_PORT") ?? "54399");
const KEY = Deno.env.get("OI519_SERVICE_JWT") ?? "";
// supabase-js calls <url>/rest/v1/...; a bare PostgREST serves at the root.
const rewrite: typeof fetch = (input, init) => {
  const u = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  return fetch(u.replace("/rest/v1", ""), init);
};
const client = createClient(BASE, KEY, { auth: { persistSession: false }, global: { fetch: rewrite } });
const db = reconcileDb(client);

let failures = 0;
function check(name: string, ok: boolean, detail = "") {
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? " -- " + detail : ""}`);
  if (!ok) failures++;
}
async function step<T>(name: string, f: () => Promise<T>): Promise<T | undefined> {
  try { return await f(); } catch (e) { check(name, false, `threw ${(e as Error).message}`); return undefined; }
}

const H = 3600 * 1000;
const now = Date.now();
const U1 = "00000000-0000-4000-8000-00000000c001"; // two pending rows
const U2 = "00000000-0000-4000-8000-00000000c002"; // one pending row
const U3 = "00000000-0000-4000-8000-00000000c003"; // crashed in-flight row
const R1 = "66666666-0000-4000-8000-000000000001";
const R2 = "66666666-0000-4000-8000-000000000002";
const R3 = "66666666-0000-4000-8000-000000000003";
const R4 = "66666666-0000-4000-8000-000000000004";

// 1. pendingRows: oldest first, exactly one drain batch.
const rows = await step("pendingRows", () => db.pendingRows(20));
check("pendingRows returns the 3 pending rows oldest first", JSON.stringify(rows?.map((r) => r.id)) === JSON.stringify([R1, R2, R3]),
  JSON.stringify(rows?.map((r) => r.id)));

// 1b. touch: a pending row goes to the back of pendingRows (updated_at, then created_at).
await step("touch R1", () => db.touch(R1));
const after = await step("pendingRows after touch", () => db.pendingRows(20));
check("touch: the touched row now comes last (R2, R3, R1)", JSON.stringify(after?.map((r) => r.id)) === JSON.stringify([R2, R3, R1]),
  JSON.stringify(after?.map((r) => r.id)));

// 2. claim: CAS on pending; a second claim of the same row gets null; a second in-flight row for the same user gets
//    null through the partial unique index (23505).
const t1 = await step("claim R1", () => db.claim(R1));
check("claim of a pending row returns a token", typeof t1 === "string" && t1.length > 0, String(t1));
const t1b = await step("claim R1 again", () => db.claim(R1));
check("a second claim of the same row returns null", t1b === null, String(t1b));
const t2 = await step("claim R2 (same user, R1 in flight)", () => db.claim(R2));
check("a claim while the user has another defer in flight returns null (23505)", t2 === null, String(t2));
const t3 = await step("claim R3", () => db.claim(R3));
check("claim of another user's pending row returns a token", typeof t3 === "string", String(t3));

// 3. mark: needs the row's own token and in_flight.
const wrong = await step("mark wrong token", () => db.mark(R1, crypto.randomUUID(), "applied"));
check("mark with a wrong token changes nothing", wrong === false, String(wrong));
const okMark = await step("mark R1 applied", () => db.mark(R1, t1 as string, "applied"));
check("mark with the row's token returns true", okMark === true, String(okMark));
const again = await step("mark R1 again", () => db.mark(R1, t1 as string, "needs_check"));
check("a second mark of a row no longer in flight returns false", again === false, String(again));
const back = await step("mark R3 pending", () => db.mark(R3, t3 as string, "pending"));
check("mark back to pending returns true", back === true, String(back));

// 4. crashedInFlight: only in-flight rows claimed more than 1 h ago.
const crashed = await step("crashedInFlight", () => db.crashedInFlight(now));
check("crashedInFlight returns only the row claimed 2 h ago", JSON.stringify(crashed?.map((c) => c.id)) === JSON.stringify([R4]),
  JSON.stringify(crashed));

// 5. fallBack (RPC): a pending row with no token falls back; the same call again is a noop.
const fb = await step("fallBack R3", () => db.fallBack(R3, null));
check("fallBack of a pending row returns fell_back", fb === "fell_back", String(fb));
const fb2 = await step("fallBack R3 again", () => db.fallBack(R3, null));
check("a second fallBack returns noop", fb2 === "noop", String(fb2));

// 6. reconcileUids: the .or(...) candidate filter.
const uids = await step("reconcileUids", () => db.reconcileUids(now));
const want = ["00000000-0000-4000-8000-00000000d001", "00000000-0000-4000-8000-00000000d002", "00000000-0000-4000-8000-00000000d003",
  "00000000-0000-4000-8000-00000000d007", "00000000-0000-4000-8000-00000000d009"];
check("reconcileUids = ends within [now-3d, now+1d] OR active and read > 24 h ago (Play rows), PLUS a switch_off webhook in 7 days newer than the user's last Play read",
  JSON.stringify([...(uids ?? [])].sort()) === JSON.stringify(want), JSON.stringify(uids));
check("the switch_off catch-up users come AFTER the regular candidates (newest event first; a noisy tester hides nobody)",
  JSON.stringify((uids ?? []).slice(-2)) === JSON.stringify(["00000000-0000-4000-8000-00000000d009", "00000000-0000-4000-8000-00000000d007"]),
  JSON.stringify(uids));

// 7. stallCounts.
const st = await step("stallCounts", () => db.stallCounts(now));
check("stallCounts counts pending > 24 h, in flight > 2 h, needs_check", JSON.stringify(st) === JSON.stringify({ pendingOld: 1, inFlightOld: 0, needsCheck: 0 }),
  JSON.stringify(st));

// 8. The mirror's adapters (shared by all three functions).
const mdb = supabaseMirrorDb(client);
check("userExists: a users row -> true", (await step("userExists", () => mdb.userExists(U1))) === true);
check("userExists: no users row -> false", (await step("userExists absent", () => mdb.userExists(crypto.randomUUID()))) === false);
const D4 = "00000000-0000-4000-8000-00000000d004";
const prow = (env: "SANDBOX" | "PRODUCTION"): PlayRow => ({
  productId: "avya_pro", plan: "yearly", status: "active", startIso: new Date(now - 10 * 24 * H).toISOString(),
  endIso: new Date(now + 30 * 24 * H).toISOString(), autoRenew: true, environment: env, originalTxn: "GPA.local",
  storeExpiresIso: new Date(now + 30 * 24 * H - 3 * H).toISOString(),
});
const readNow = new Date(now).toISOString();
check("upsertPlayRow: a newer read -> written", (await step("upsert 1", () => mdb.upsertPlayRow(D4, prow("PRODUCTION"), readNow))) === "written");
check("upsertPlayRow: the same read again -> stale_read", (await step("upsert 2", () => mdb.upsertPlayRow(D4, prow("PRODUCTION"), readNow))) === "stale_read");
check("upsertPlayRow: SANDBOX over running PRODUCTION -> sandbox_refused",
  (await step("upsert 3", () => mdb.upsertPlayRow(D4, prow("SANDBOX"), new Date(now + 1000).toISOString()))) === "sandbox_refused");
check("upsertPlayRow: a first read inserts -> written", (await step("upsert 4", () => mdb.upsertPlayRow(U2, prow("SANDBOX"), readNow))) === "written");
const { data: d4 } = await client.from("subscriptions").select("plan, store_read_at, store_environment").eq("user_id", D4).eq("store", "play").limit(5);
check("the written row carries the new read (one Play row per user)", Array.isArray(d4) && d4.length === 1 && d4[0].plan === "yearly" &&
  Date.parse(d4[0].store_read_at) === now && d4[0].store_environment === "PRODUCTION", JSON.stringify(d4));
await mdb.alert("oi519_local_alert", "critical", "local", { n: 1 });
await mdb.alert("oi519_local_alert", "critical", "local", { n: 2 });
const { count: alertCount } = await client.from("alerts").select("id", { count: "exact", head: true }).eq("source", "oi519_local_alert");
check("alert: an open alert of the same source suppresses the second", alertCount === 1, String(alertCount));

// 9. The webhook's ledger write: idempotent on provider_event_id.
const rec = (outcome: string) => ({
  provider_event_id: "evt_local_1", user_id: U1, event_type: "RENEWAL", product_id: "avya_pro:monthly", environment: "SANDBOX" as const,
  event_timestamp_ms: 1795428000000, outcome,
});
await step("ledger write 1", () => ledgerWriter(client)(rec("mirror_failed")));
await step("ledger write 2 (the retry)", () => ledgerWriter(client)(rec("mirrored")));
const { data: ev } = await client.from("subscription_events").select("outcome, provider").eq("provider_event_id", "evt_local_1").limit(5);
check("ledger: a retried event id stays ONE row, with the latest outcome", Array.isArray(ev) && ev.length === 1 && ev[0].outcome === "mirrored" &&
  ev[0].provider === "revenuecat", JSON.stringify(ev));

// 10. U4: redeem-referral's paid pre-check filter, through the REAL PostgREST, means the SQL's "paid" (182): a payment id
// OR a PRODUCTION Play row, any status; a SANDBOX Play row is not paid.
const paid = async (uid: string) => {
  const { data, error } = await client.from("subscriptions").select("id").eq("user_id", uid)
    .in("plan", ["monthly", "yearly"]).or(PAID_ROW_FILTER).limit(1);
  if (error) check(`paid filter read ${uid}`, false, JSON.stringify(error));
  return Array.isArray(data) && data.length > 0;
};
check("paid: a PRODUCTION Play row (active) is paid", await paid("00000000-0000-4000-8000-00000000d002"));
check("paid: a PRODUCTION Play row (expired) is paid", await paid("00000000-0000-4000-8000-00000000d001"));
check("paid: a Razorpay row is paid", await paid("00000000-0000-4000-8000-00000000d006"));
check("paid: a SANDBOX Play row (expired) is NOT paid", !(await paid("00000000-0000-4000-8000-00000000d005")));
check("paid: a SANDBOX Play row (active) is NOT paid", !(await paid(U2)));
check("paid: no subscriptions row is NOT paid", !(await paid(U3)));

console.log(failures === 0 ? "ALL PASSED" : `${failures} FAILED`);
Deno.exit(failures === 0 ? 0 : 1);
