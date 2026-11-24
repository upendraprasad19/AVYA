// OI-519 U3: revenuecat-webhook handler (plan section 8, T-WH). Fake deps; no network, no database.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { MirrorOutcome } from "../_shared/revenuecat_mirror.ts";
import { RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";
import {
  type EventRecord,
  handler,
  MAX_BODY_BYTES,
  PAID_NO_ROW_ALERT_SOURCE,
  TRANSFER_ALERT_SOURCE,
  type WebhookDeps,
} from "./logic.ts";

const SECRET = "whsec_local_test_value";
const U1 = "00000000-0000-4000-8000-000000000001";
const U2 = "00000000-0000-4000-8000-000000000002";

type Seen = { events: EventRecord[]; mirrored: string[]; alerts: string[] };
function deps(seen: Seen, o: Partial<WebhookDeps> & { secret?: string | undefined; on?: boolean; known?: string[] } = {}): WebhookDeps {
  const known = new Set(o.known ?? [U1, U2]);
  return {
    env: (n) => (n === "REVENUECAT_WEBHOOK_AUTH" ? ("secret" in o ? o.secret : SECRET) : undefined),
    mirrorEnabled: () => o.on ?? true,
    userExists: (uid) => Promise.resolve(known.has(uid)),
    recordEvent: (rec) => {
      seen.events.push(rec);
      return Promise.resolve();
    },
    mirror: o.mirror ?? ((uid) => {
      seen.mirrored.push(uid);
      return Promise.resolve({ outcome: "mirrored", rows: [{ productId: "avya_pro", status: "active", result: "written" }], mapped: [] } as MirrorOutcome);
    }),
    alert: (source) => {
      seen.alerts.push(source);
      return Promise.resolve();
    },
    requestId: () => "rid00001",
  };
}
const fresh = (): Seen => ({ events: [], mirrored: [], alerts: [] });
function post(event: Record<string, unknown>, auth: string | null = SECRET, extra = ""): Request {
  const h = new Headers({ "Content-Type": "application/json" });
  if (auth !== null) h.set("Authorization", auth);
  return new Request("http://x/revenuecat-webhook", { method: "POST", headers: h, body: JSON.stringify({ event }) + extra });
}
const ev = (o: Record<string, unknown> = {}) => ({
  id: "evt_1", type: "RENEWAL", app_user_id: U1, product_id: "avya_pro:monthly", environment: "SANDBOX",
  event_timestamp_ms: 1795428000000, ...o,
});

Deno.test("unset secret -> 500 and nothing written (fail closed)", async () => {
  const s = fresh();
  const r = await handler(post(ev()), deps(s, { secret: undefined }));
  assertEquals(r.status, 500);
  assertEquals(s.events, []);
  assertEquals(s.mirrored, []);
});

Deno.test("wrong or missing Authorization -> 401, nothing written", async () => {
  for (const auth of ["nope", null, "", `Bearer x${SECRET}`, `Bearer  ${SECRET}`, `bearer ${SECRET}`, "Bearer ", `Token ${SECRET}`, `${SECRET}x`]) {
    const s = fresh();
    assertEquals((await handler(post(ev(), auth), deps(s))).status, 401);
    assertEquals(s.events.length + s.mirrored.length, 0);
  }
});

Deno.test("the secret is accepted as is AND after 'Bearer ' (B-pass F8: the RevenueCat field is free text)", async () => {
  for (const auth of [SECRET, `Bearer ${SECRET}`]) {
    const s = fresh();
    assertEquals((await handler(post(ev(), auth), deps(s))).status, 200, String(auth));
    assertEquals(s.mirrored, [U1]);
  }
});

Deno.test("non-POST -> 405; oversized body -> 413; bad JSON / no id -> 400", async () => {
  const s = fresh();
  assertEquals((await handler(new Request("http://x", { method: "GET" }), deps(s))).status, 405);
  assertEquals((await handler(post(ev(), SECRET, " ".repeat(MAX_BODY_BYTES)), deps(s))).status, 413);
  const bad = new Request("http://x", { method: "POST", headers: { Authorization: SECRET }, body: "{not json" });
  assertEquals((await handler(bad, deps(s))).status, 400);
  assertEquals((await handler(post(ev({ id: undefined })), deps(s))).status, 400);
  assertEquals(s.mirrored, []);
});

Deno.test("switch OFF -> 200, event logged switch_off, NO mirror", async () => {
  const s = fresh();
  const r = await handler(post(ev()), deps(s, { on: false }));
  assertEquals(r.status, 200);
  assertEquals(s.events.map((e) => e.outcome), ["switch_off"]);
  assertEquals(s.mirrored, []);
});

Deno.test("TEST -> 200, logged, no mirror", async () => {
  const s = fresh();
  assertEquals((await handler(post(ev({ type: "TEST" })), deps(s))).status, 200);
  assertEquals(s.events[0].outcome, "test");
  assertEquals(s.mirrored, []);
});

Deno.test("RENEWAL for a known user -> mirror that user, 200, ledger keeps user_id", async () => {
  const s = fresh();
  assertEquals((await handler(post(ev()), deps(s))).status, 200);
  assertEquals(s.mirrored, [U1]);
  assertEquals(s.events[0].user_id, U1);
  assertEquals(s.events[0].outcome, "mirrored");
});

Deno.test("unknown / non-UUID app_user_id -> ledger user_id NULL, no raw id stored, mirror refuses", async () => {
  const s = fresh();
  await handler(post(ev({ app_user_id: "$RCAnonymousID:abc" })), deps(s));
  assertEquals(s.events[0].user_id, null);
  assertEquals(JSON.stringify(s.events).includes("RCAnonymousID"), false);
  assertEquals(s.mirrored, []);
  assertEquals(s.events[0].outcome, "no_known_user");
});

Deno.test("UUID with no users row -> ledger user_id NULL", async () => {
  const s = fresh();
  const out: MirrorOutcome = { outcome: "unknown_user" };
  await handler(post(ev()), deps(s, { known: [], mirror: () => Promise.resolve(out) }));
  assertEquals(s.events[0].user_id, null);
  assertEquals(s.events[0].outcome, "unknown_user");
});

Deno.test("mirror failure -> 503 (RevenueCat retries), event logged mirror_failed", async () => {
  const s = fresh();
  const r = await handler(post(ev()), deps(s, { mirror: () => Promise.reject(new RevenueCatReadError("http_502")) }));
  assertEquals(r.status, 503);
  assertEquals(s.events[0].outcome, "mirror_failed");
});

Deno.test("original_app_user_id different -> both mirrored", async () => {
  const s = fresh();
  await handler(post(ev({ original_app_user_id: U2 })), deps(s));
  assertEquals(s.mirrored.sort(), [U1, U2].sort());
});

Deno.test("TRANSFER -> both sides mirrored + critical alert", async () => {
  const s = fresh();
  await handler(post(ev({ type: "TRANSFER", app_user_id: undefined, transferred_from: [U1], transferred_to: [U2] })), deps(s));
  assertEquals(s.mirrored.sort(), [U1, U2].sort());
  assertEquals(s.alerts, [TRANSFER_ALERT_SOURCE]);
});

Deno.test("paid event that mirrors to no active row -> paid-no-row alert; a CANCELLATION does not", async () => {
  const expired: MirrorOutcome = { outcome: "mirrored", rows: [{ productId: "avya_pro", status: "expired", result: "written" }], mapped: [] };
  const s = fresh();
  await handler(post(ev({ type: "INITIAL_PURCHASE" })), deps(s, { mirror: () => Promise.resolve(expired) }));
  assertEquals(s.alerts, [PAID_NO_ROW_ALERT_SOURCE]);
  const s2 = fresh();
  await handler(post(ev({ type: "CANCELLATION" })), deps(s2, { mirror: () => Promise.resolve(expired) }));
  assertEquals(s2.alerts, []);
});

Deno.test("EVERY paid event type pages on no active row; every other known type does not (B-pass F6, mutant W3)", async () => {
  const expired: MirrorOutcome = { outcome: "mirrored", rows: [{ productId: "avya_pro", status: "expired", result: "written" }], mapped: [] };
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"]) {
    const s = fresh();
    await handler(post(ev({ type })), deps(s, { mirror: () => Promise.resolve(expired) }));
    assertEquals(s.alerts, [PAID_NO_ROW_ALERT_SOURCE], type);
  }
  for (const type of ["CANCELLATION", "EXPIRATION", "BILLING_ISSUE", "SUBSCRIPTION_PAUSED", "NON_RENEWING_PURCHASE"]) {
    const s = fresh();
    await handler(post(ev({ type })), deps(s, { mirror: () => Promise.resolve(expired) }));
    assertEquals(s.alerts, [], type);
  }
});

Deno.test("a missing secret key in the mirror (it throws no_secret) -> 503, so RevenueCat retries (B-pass F2)", async () => {
  const s = fresh();
  const r = await handler(post(ev({ type: "INITIAL_PURCHASE" })), deps(s, { mirror: () => Promise.reject(new RevenueCatReadError("no_secret")) }));
  assertEquals(r.status, 503);
  assertEquals(s.events.map((e) => e.outcome), ["mirror_failed"]);
});

Deno.test("duplicate event id (a retry) still re-mirrors: idempotent", async () => {
  const s = fresh();
  await handler(post(ev()), deps(s));
  await handler(post(ev()), deps(s));
  assertEquals(s.mirrored, [U1, U1]);
  assertEquals(s.events.map((e) => e.provider_event_id), ["evt_1", "evt_1"]);
});
