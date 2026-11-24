// OI-519 U3: revenuecat-reconcile run and the referral defer drain (plan section 8, T-REC and T-DEFER, server half; the SQL
// half is test/sql/play_subscriptions_local_cases.sql). An in-memory deferral table with the same compare-and-set rules as
// the Supabase adapter: claim only from pending, every mark only from in_flight with the matching token, one in flight per user.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type MirrorOutcome, type PlayRow, RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";
import {
  decide,
  handler,
  NEEDS_CHECK_ALERT_SOURCE,
  type ReconcileDb,
  type ReconcileDeps,
  RECONCILE_STARVED_ALERT_SOURCE,
  STALL_ALERT_SOURCE,
} from "./logic.ts";

const NOW = Date.parse("2026-11-24T10:00:00Z");
const H = 3600 * 1000;
const U1 = "00000000-0000-4000-8000-000000000001";
const U2 = "00000000-0000-4000-8000-000000000002";

type Row = { id: string; user_id: string; days: number; status: string; token: string | null; seen?: number };
function playRow(status: PlayRow["status"], expiresMs: number): PlayRow {
  return {
    productId: "avya_pro", plan: "monthly", status, startIso: "2026-11-01T00:00:00Z", endIso: new Date(expiresMs + 3 * H).toISOString(),
    autoRenew: true, environment: "SANDBOX", originalTxn: "GPA.1", storeExpiresIso: new Date(expiresMs).toISOString(),
  };
}
const mirrored = (rows: PlayRow[]): MirrorOutcome => ({ outcome: "mirrored", rows: [], mapped: rows });
const ACTIVE = mirrored([playRow("active", NOW + 10 * 24 * H)]);
const IN_WINDOW = mirrored([playRow("active", NOW - H)]);
const GONE = mirrored([playRow("expired", NOW - 5 * 24 * H)]);

class Fake {
  rows: Row[] = [];
  posts: string[] = [];
  alerts: string[] = [];
  fallBacks: string[] = [];
  mirrors: string[] = [];
  telemetry: string[] = [];
  uids: string[] = [];
  crashed: { id: string; token: string }[] = [];
  claimThrowsFor: string | null = null;
  touches = 0;
  db(): ReconcileDb {
    return {
      stallCounts: () => Promise.resolve({ pendingOld: 0, inFlightOld: 0, needsCheck: this.rows.filter((r) => r.status === "needs_check").length }),
      reconcileUids: () => Promise.resolve([...this.uids]),
      crashedInFlight: () => Promise.resolve([...this.crashed]),
      // Least recently touched first, then insertion order (the adapter orders by updated_at, then created_at).
      pendingRows: (n) => Promise.resolve(this.rows.filter((r) => r.status === "pending").map((r, i) => ({ r, i }))
        .sort((a, b) => (a.r.seen ?? 0) - (b.r.seen ?? 0) || a.i - b.i).slice(0, n).map(({ r: { id, user_id, days } }) => ({ id, user_id, days }))),
      touch: (id) => {
        const r = this.rows.find((x) => x.id === id && x.status === "pending");
        if (r) r.seen = ++this.touches;
        return Promise.resolve();
      },
      claim: (id) => {
        if (id === this.claimThrowsFor) return Promise.reject(new Error("claim failed"));
        const r = this.rows.find((x) => x.id === id && x.status === "pending");
        if (!r) return Promise.resolve(null);
        if (this.rows.some((x) => x.user_id === r.user_id && x.status === "in_flight")) return Promise.resolve(null);
        r.status = "in_flight";
        r.token = `tok-${id}`;
        return Promise.resolve(r.token);
      },
      mark: (id, token, status) => {
        const r = this.rows.find((x) => x.id === id && x.status === "in_flight" && x.token === token);
        if (!r) return Promise.resolve(false);
        r.status = status;
        if (status === "pending") r.token = null;
        return Promise.resolve(true);
      },
      fallBack: (id, token) => {
        const r = this.rows.find((x) => x.id === id &&
          ((x.status === "pending" && token === null) || ((x.status === "in_flight" || x.status === "needs_check") && x.token === token)));
        if (!r) return Promise.resolve("noop");
        r.status = "fell_back";
        this.fallBacks.push(id);
        return Promise.resolve("fell_back");
      },
    };
  }
}

function deps(f: Fake, o: {
  on?: boolean;
  mirror?: (uid: string, call: number) => MirrorOutcome | Error;
  defer?: (uid: string, call: number) => number | Error;
  authorized?: boolean;
  clock?: () => number;
} = {}): ReconcileDeps {
  let mc = 0, dc = 0;
  return {
    authorized: () => Promise.resolve(o.authorized ?? true),
    telemetryStart: () => { f.telemetry.push("start"); return Promise.resolve(1); },
    telemetryEnd: (_id, status) => { f.telemetry.push(`end:${status}`); return Promise.resolve(); },
    mirrorEnabled: () => o.on ?? true,
    db: f.db(),
    mirror: (uid) => {
      f.mirrors.push(uid);
      const r = (o.mirror ?? (() => ACTIVE))(uid, mc++);
      return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
    },
    postDefer: (uid, days) => {
      f.posts.push(`${uid}:${days}`);
      const r = (o.defer ?? (() => 200))(uid, dc++);
      return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
    },
    alert: (source) => { f.alerts.push(source); return Promise.resolve(); },
    nowMs: o.clock ?? (() => NOW),
  };
}
const run = (f: Fake, o: Parameters<typeof deps>[1] = {}) => handler(new Request("http://x", { method: "POST" }), deps(f, o));
const status = (f: Fake, id: string) => f.rows.find((r) => r.id === id)!.status;

Deno.test("decide: active with a future store expiry -> claim; window / grace -> wait; gone -> fall_back; refused -> skip", () => {
  assertEquals(decide(ACTIVE, NOW), "claim");
  assertEquals(decide(IN_WINDOW, NOW), "wait");
  assertEquals(decide(GONE, NOW), "fall_back");
  assertEquals(decide(mirrored([]), NOW), "fall_back");
  assertEquals(decide({ outcome: "unknown_user" }, NOW), "skip");
});

Deno.test("unauthorized -> 401, no telemetry, nothing read", async () => {
  const f = new Fake();
  assertEquals((await run(f, { authorized: false })).status, 401);
  assertEquals(f.telemetry, []);
});

Deno.test("switch OFF: stall alert still fires, no drain, no RevenueCat call", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "needs_check", token: "t" }, { id: "b", user_id: U2, days: 7, status: "pending", token: null });
  const r = await run(f, { on: false });
  assertEquals(r.status, 200);
  assertEquals(f.alerts, [STALL_ALERT_SOURCE]);
  assertEquals(f.posts, []);
  assertEquals(f.mirrors, []);
  assertEquals(status(f, "b"), "pending");
  assertEquals(f.telemetry, ["start", "end:success"]);
});

Deno.test("2xx -> applied, then a best-effort mirror; the POST carries the days", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f);
  assertEquals(status(f, "a"), "applied");
  assertEquals(f.posts, [`${U1}:7`]);
  assertEquals(f.mirrors, [U1, U1]);
});

Deno.test("2xx with the follow-up mirror throwing -> still applied", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { mirror: (_u, n) => (n === 0 ? ACTIVE : new Error("boom")) });
  assertEquals(status(f, "a"), "applied");
});

Deno.test("timeout / network / 5xx -> needs_check at once + alert, and the NEXT run sends NO second POST", async () => {
  for (const outcome of [new Error("timeout"), 503]) {
    const f = new Fake();
    f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
    await run(f, { defer: () => outcome });
    assertEquals(status(f, "a"), "needs_check");
    assertEquals(f.alerts.includes(NEEDS_CHECK_ALERT_SOURCE), true);
    await run(f);
    assertEquals(f.posts.length, 1);
    assertEquals(status(f, "a"), "needs_check");
  }
});

Deno.test("429 -> back to pending (not applied), retried next run", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { defer: () => 429 });
  assertEquals(status(f, "a"), "pending");
  await run(f);
  assertEquals(status(f, "a"), "applied");
  assertEquals(f.posts.length, 2);
});

Deno.test("4xx with the subscription gone on re-read -> fall back with the run's token", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { defer: () => 400, mirror: (_u, n) => (n === 0 ? ACTIVE : GONE) });
  assertEquals(status(f, "a"), "fell_back");
});

Deno.test("4xx with it still active -> needs_check; 4xx with the re-read failing -> pending", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { defer: () => 400 });
  assertEquals(status(f, "a"), "needs_check");
  const g = new Fake();
  g.rows.push({ id: "b", user_id: U1, days: 7, status: "pending", token: null });
  await run(g, { defer: () => 400, mirror: (_u, n) => (n === 0 ? ACTIVE : new Error("read")) });
  assertEquals(status(g, "b"), "pending");
});

Deno.test("no Play entitlement -> fall back without a POST; renewal window / read error -> stays pending", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { mirror: () => GONE });
  assertEquals(status(f, "a"), "fell_back");
  assertEquals(f.posts, []);
  for (const m of [IN_WINDOW, new Error("read")]) {
    const g = new Fake();
    g.rows.push({ id: "b", user_id: U1, days: 7, status: "pending", token: null });
    await run(g, { mirror: () => m });
    assertEquals(status(g, "b"), "pending");
    assertEquals(g.posts, []);
  }
});

Deno.test("unknown user (deleted) -> no POST, row untouched", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null });
  await run(f, { mirror: () => ({ outcome: "unknown_user" }) });
  assertEquals(f.posts, []);
  assertEquals(status(f, "a"), "pending");
});

Deno.test("a second reward for the same user is skipped while one is in flight", async () => {
  const f = new Fake();
  f.rows.push(
    { id: "a", user_id: U1, days: 7, status: "in_flight", token: "other" },
    { id: "b", user_id: U1, days: 7, status: "pending", token: null },
  );
  await run(f);
  assertEquals(f.posts, []);
  assertEquals(status(f, "b"), "pending");
});

Deno.test("a mark with a wrong token writes nothing (overlapping run)", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "in_flight", token: "theirs" });
  assertEquals(await f.db().mark("a", "mine", "applied"), false);
  assertEquals(await f.db().fallBack("a", null), "noop");
  assertEquals(status(f, "a"), "in_flight");
});

Deno.test("crashed claim (in flight > 1 h) -> needs_check + alert, never re-sent (B-pass F6, mutant R2)", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "in_flight", token: "t-old" });
  f.crashed.push({ id: "a", token: "t-old" });
  const r = await run(f);
  assertEquals(r.status, 200);
  assertEquals(status(f, "a"), "needs_check");
  assertEquals(f.alerts, [NEEDS_CHECK_ALERT_SOURCE]);
  assertEquals(f.posts, []);
});

Deno.test("one row that throws does not starve the rows behind it; the run ends failed (B-pass F4, F9)", async () => {
  const f = new Fake();
  f.rows.push({ id: "a", user_id: U1, days: 7, status: "pending", token: null }, { id: "b", user_id: U2, days: 30, status: "pending", token: null });
  f.claimThrowsFor = "a";
  const r = await run(f);
  assertEquals(status(f, "a"), "pending");
  assertEquals(status(f, "b"), "applied");
  assertEquals(f.posts, [`${U2}:30`]);
  assertEquals(r.status, 500);
  assertEquals((await r.json()).drain_errors, 1);
  assertEquals(f.telemetry, ["start", "end:failed"]);
});

Deno.test("time budget: the drain runs FIRST, no new row or user starts after RUN_BUDGET_MS (B-pass F3)", async () => {
  const f = new Fake();
  const U3 = "00000000-0000-4000-8000-000000000003";
  f.rows.push(
    { id: "a", user_id: U1, days: 7, status: "pending", token: null },
    { id: "b", user_id: U2, days: 7, status: "pending", token: null },
    { id: "c", user_id: U3, days: 7, status: "pending", token: null },
  );
  f.uids = ["00000000-0000-4000-8000-0000000000ff"];
  let t = NOW;
  const r = await run(f, { clock: () => t, mirror: () => { t += 25_000; return ACTIVE; } });
  // a: read (25 s) + POST + read (50 s); b starts at 50 s < 60 s; c would start at 100 s: cut. The reconcile user: cut.
  assertEquals(f.posts, [`${U1}:7`, `${U2}:7`]);
  assertEquals(status(f, "c"), "pending");
  assertEquals(f.mirrors[0], U1);
  assertEquals(f.mirrors.includes("00000000-0000-4000-8000-0000000000ff"), false);
  const body = await r.json();
  assertEquals([r.status, body.drain_not_reached, body.reconcile_not_reached], [200, 1, 1]);
  assertEquals(f.telemetry, ["start", "end:success"]);
  // No reconcile read ran at all: the founder hears about it (B-pass round 2, F3).
  assertEquals(f.alerts, [RECONCILE_STARVED_ALERT_SOURCE]);
});

Deno.test("every reconcile read failing (RevenueCat down / no secret) ends the run failed; a partial failure does not (B-pass F9)", async () => {
  const f = new Fake();
  f.uids = [U1, U2];
  const r = await run(f, { mirror: () => new RevenueCatReadError("no_secret") });
  assertEquals(r.status, 500);
  assertEquals((await r.json()).mirror_failed, 2);
  assertEquals(f.telemetry, ["start", "end:failed"]);

  const g = new Fake();
  g.uids = [U1, U2];
  const r2 = await run(g, { mirror: (uid) => uid === U1 ? new RevenueCatReadError("timeout") : ACTIVE });
  assertEquals(r2.status, 200);
  assertEquals(g.telemetry, ["start", "end:success"]);
});

Deno.test("rows that keep waiting rotate to the back: 20 waiting rows never hide a 21st (B-pass round 2, F3)", async () => {
  const f = new Fake();
  const W = (i: number) => `00000000-0000-4000-8000-0000000001${String(i).padStart(2, "0")}`;
  for (let i = 0; i < 20; i++) f.rows.push({ id: `w${i}`, user_id: W(i), days: 7, status: "pending", token: null });
  f.rows.push({ id: "z", user_id: U2, days: 30, status: "pending", token: null });
  const o = { mirror: (uid: string) => uid === U2 ? ACTIVE : IN_WINDOW };
  await run(f, o);
  assertEquals(f.posts, []); // the batch held only the 20 waiting rows
  await run(f, o);
  assertEquals(f.posts, [`${U2}:30`]);
  assertEquals(status(f, "z"), "applied");
});

Deno.test("an unknown user among failing reads does not hide an outage: the run still ends failed (B-pass round 2, F2)", async () => {
  const f = new Fake();
  const U3 = "00000000-0000-4000-8000-000000000003";
  f.uids = [U1, U2, U3];
  const r = await run(f, { mirror: (uid) => uid === U1 ? { outcome: "unknown_user" } : new RevenueCatReadError("http_503") });
  assertEquals(r.status, 500);
  assertEquals(f.telemetry, ["start", "end:failed"]);
});
