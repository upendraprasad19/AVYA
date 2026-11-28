// OI-519 U3: revenuecat-sync handler (plan section 8, T-SYNC). Fake deps; no network, no database.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type MirrorOutcome, RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";
import { type CurrentRow, handler, SYNC_QUOTA_LIMIT, type SyncDeps } from "./logic.ts";

const U1 = "00000000-0000-4000-8000-000000000001";
const NOW = Date.parse("2026-11-24T10:20:00Z");
const ROW: CurrentRow = {
  plan: "monthly", end_date: "2026-12-24T12:00:00Z", store: "play", auto_renew: true, store_expires_at: "2026-12-24T09:00:00Z",
};
type Log = string[];
function deps(log: Log, o: Partial<SyncDeps> & { quota?: { data: unknown; error: unknown } } = {}): SyncDeps {
  return {
    authUser: (t) => Promise.resolve(t === "good" ? U1 : null),
    consumeQuota: (a) => {
      assertEquals(a.p_quota_key, "revenuecat_sync");
      log.push(`quota:${a.p_user_id}:${a.p_window_start}:${a.p_limit}`);
      return Promise.resolve(o.quota ?? { data: 1, error: null });
    },
    mirrorEnabled: o.mirrorEnabled ?? (() => true),
    mirror: o.mirror ?? ((uid) => {
      log.push(`mirror:${uid}`);
      return Promise.resolve({ outcome: "mirrored", rows: [], mapped: [] } as MirrorOutcome);
    }),
    readCurrent: o.readCurrent ?? (() => Promise.resolve(ROW)),
    nowMs: () => NOW,
    requestId: () => "rid00002",
  };
}
const req = (auth: string | null = "Bearer good", body = "{}") =>
  new Request("http://x/revenuecat-sync", { method: "POST", headers: auth ? { Authorization: auth } : {}, body });

Deno.test("no / bad JWT -> 401, no quota, no mirror", async () => {
  for (const a of [null, "Bearer bad"]) {
    const log: Log = [];
    assertEquals((await handler(req(a), deps(log))).status, 401);
    assertEquals(log, []);
  }
});

Deno.test("uid from the JWT only: a body uid is ignored", async () => {
  const log: Log = [];
  await handler(req("Bearer good", JSON.stringify({ user_id: "00000000-0000-4000-8000-0000000000ff" })), deps(log));
  assertEquals(log.filter((l) => l.startsWith("mirror:")), [`mirror:${U1}`]);
});

Deno.test("quota is consumed BEFORE the mirror, hour bucket, limit 20", async () => {
  const log: Log = [];
  await handler(req(), deps(log));
  assertEquals(log, [`quota:${U1}:2026-11-24T10:00:00.000Z:${SYNC_QUOTA_LIMIT}`, `mirror:${U1}`]);
});

Deno.test("quota RPC error / bad_result -> 429 rate_limit_unavailable and NO mirror (fail closed)", async () => {
  for (const q of [{ data: null, error: { code: "XX000" } }, { data: "x", error: null }, { data: 0, error: null }]) {
    const log: Log = [];
    const r = await handler(req(), deps(log, { quota: q }));
    assertEquals(r.status, 429);
    assertEquals((await r.json()).error_code, "rate_limit_unavailable");
    assertEquals(log.some((l) => l.startsWith("mirror:")), false);
  }
});

Deno.test("quota exhausted (-1) -> 429 rate_limited with Retry-After, NO mirror", async () => {
  const log: Log = [];
  const r = await handler(req(), deps(log, { quota: { data: -1, error: null } }));
  assertEquals(r.status, 429);
  const b = await r.json();
  assertEquals(b.error_code, "rate_limited");
  assertEquals(r.headers.get("Retry-After"), String(40 * 60));
  assertEquals(log.some((l) => l.startsWith("mirror:")), false);
});

Deno.test("switch OFF -> no mirror, current row returned", async () => {
  const log: Log = [];
  const r = await handler(req(), deps(log, { mirrorEnabled: () => false }));
  assertEquals(r.status, 200);
  assertEquals(log.some((l) => l.startsWith("mirror:")), false);
  const body = await r.json();
  assertEquals(body.is_pro, true);
  assertEquals(body.store_checked, false, "the store was not read: never proof of 'no PRO'");
  const on = await (await handler(req(), deps([]))).json();
  assertEquals("store_checked" in on, false, "a real store read carries no flag");
});

Deno.test("mirror failure -> 503 store_unavailable", async () => {
  const r = await handler(req(), deps([], { mirror: () => Promise.reject(new RevenueCatReadError("timeout")) }));
  assertEquals(r.status, 503);
  assertEquals((await r.json()).error_code, "store_unavailable");
});

Deno.test("response: verify-subscription's shape + Play fields; no row / expired row -> not PRO", async () => {
  const b = await (await handler(req(), deps([]))).json();
  assertEquals(b, {
    is_pro: true, plan: "monthly", expires_at: ROW!.end_date, store: "play", auto_renew: true, store_expires_at: ROW!.store_expires_at,
  });
  for (const row of [null, { ...ROW!, end_date: "2026-11-24T10:00:00Z" }]) {
    const b2 = await (await handler(req(), deps([], { readCurrent: () => Promise.resolve(row) }))).json();
    assertEquals(b2.is_pro, false);
    assertEquals(b2.expires_at, null);
  }
});

Deno.test("shape(): PRO ends AT end_date: one ms before is PRO, exactly at it is not (B-pass F6, mutant S3)", async () => {
  const { shape } = await import("./logic.ts");
  const end = Date.parse(ROW!.end_date!);
  assertEquals(shape(ROW, end - 1).is_pro, true);
  assertEquals(shape(ROW, end).is_pro, false);
});

Deno.test("a missing secret key (the mirror throws no_secret) -> 503 store_unavailable, never a 200 not-PRO (B-pass F2)", async () => {
  const log: Log = [];
  const r = await handler(req(), deps(log, { mirror: () => Promise.reject(new RevenueCatReadError("no_secret")) }));
  assertEquals(r.status, 503);
  assertEquals((await r.json()).error_code, "store_unavailable");
});

Deno.test("an exhausted quota leaves a log line with the request id only (hermes seat 2)", async () => {
  const src = (await Deno.readTextFile(new URL("./logic.ts", import.meta.url))).replace(/\s+/g, " ");
  assertEquals(src.includes('if (used === -1) { const retry = Math.max(1, Math.ceil((bucketStartMs + SYNC_WINDOW_MS - now()) / 1000)); // Telemetry on the over-limit path (hermes seat 2): the request id only, never the user. console.warn(`[revenuecat-sync] request_id=${rid} rate_limited`);'), true);
});
