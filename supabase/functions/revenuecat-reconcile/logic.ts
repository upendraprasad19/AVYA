// revenuecat-reconcile/logic.ts — OI-519 (+51), plan section 4 entry point 3 and item 4 (the referral defer drain).
//
// Hourly cron (cron_auth + cron_telemetry). Order of a run:
//   1. Stall alert FIRST, even with the switch OFF: deferral rows pending > 24 h, in flight > 2 h, or needs_check.
//   2. Switch OFF -> stop (nothing read from RevenueCat, nothing written).
//   3. Crashed claims: an in_flight row older than 1 h -> needs_check (never re-sent).
//   4. Drain the 20 oldest pending deferrals: fresh read per row; active with a future store expiry -> claim (CAS) ->
//      POST defer; no Play entitlement -> fall back to ordinary days; anything else (renewal window, grace, read error)
//      -> stays pending. A defer whose outcome is unknown is NEVER re-sent and NEVER auto-confirmed (plan v7). One row's
//      error is counted and the next row is tried (B-pass F4); a row that fails after its claim stays in_flight, so step 3
//      of a later run moves it to needs_check.
//   5. Reconcile: re-mirror every user whose Play row ends within [now - 3 d, now + 1 d] or is active and was last read
//      more than 24 h ago (bounded), so renewals, expiries and refunds land even when every webhook retry failed.
// Steps 4 and 5 share one time budget (RUN_BUDGET_MS, B-pass F3): a slow RevenueCat cannot run the function into the
// platform's wall-clock limit (no telemetry end, no drain). The drain goes first, so referral days are never starved by
// the reconcile list. A run whose reconcile reads ALL failed, or whose drain had an error, ends `failed` (B-pass F9).

import { errorName } from "../_shared/payment_log_safe.ts";
import { type MirrorOutcome, PLAY_SUBSCRIPTION_ID, RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";

export const FN_NAME = "revenuecat-reconcile";
export const DRAIN_BATCH = 20;
/** Steps 4 and 5 start no new row or user after this long (one row can still take ~50 s: two reads and a POST). */
export const RUN_BUDGET_MS = 60_000;
export const STALL_ALERT_SOURCE = "store_reward_deferrals_stalled";
export const NEEDS_CHECK_ALERT_SOURCE = "store_reward_needs_check";
/** The drain used the whole budget and no reconcile read ran (B-pass round 2, F3). */
export const RECONCILE_STARVED_ALERT_SOURCE = "revenuecat_reconcile_starved";

export type DeferralRow = { id: string; user_id: string; days: number };
export type MarkStatus = "applied" | "needs_check" | "pending";

export type ReconcileDb = {
  stallCounts: (nowMs: number) => Promise<{ pendingOld: number; inFlightOld: number; needsCheck: number }>;
  reconcileUids: (nowMs: number) => Promise<string[]>;
  crashedInFlight: (nowMs: number) => Promise<{ id: string; token: string }[]>;
  /** Pending rows, least recently looked at first (updated_at, then created_at). */
  pendingRows: (limit: number) => Promise<DeferralRow[]>;
  /** Marks a pending row as looked at (updated_at = now), so rows that keep waiting rotate behind the others. */
  touch: (id: string) => Promise<void>;
  claim: (id: string) => Promise<string | null>;
  mark: (id: string, token: string, status: MarkStatus) => Promise<boolean>;
  fallBack: (id: string, token: string | null) => Promise<string>;
};

export type ReconcileDeps = {
  authorized: (req: Request) => Promise<boolean>;
  telemetryStart: () => Promise<number | null>;
  telemetryEnd: (id: number | null, status: "success" | "failed", opts: { httpStatus: number; errorSummary?: string }) => Promise<void>;
  mirrorEnabled: () => boolean;
  db: ReconcileDb;
  mirror: (uid: string) => Promise<MirrorOutcome>;
  postDefer: (uid: string, days: number) => Promise<number>;
  alert: (source: string, summary: string, context: Record<string, unknown>) => Promise<void>;
  nowMs?: () => number;
};

export type Decision = "claim" | "fall_back" | "wait" | "skip";

/** Pure: what to do with a pending deferral given a fresh mirror of the user. */
export function decide(out: MirrorOutcome, nowMs: number): Decision {
  if (out.outcome !== "mirrored") return "skip";
  const row = out.mapped.find((r) => r.productId === PLAY_SUBSCRIPTION_ID);
  if (!row) return "fall_back";
  if (row.status === "active" && Date.parse(row.storeExpiresIso) > nowMs) return "claim";
  if (row.status === "active") return "wait"; // renewal window or billing grace: Google has not moved the period yet
  return "fall_back";
}

async function freshDecision(deps: ReconcileDeps, uid: string, nowMs: number): Promise<Decision> {
  try {
    return decide(await deps.mirror(uid), nowMs);
  } catch (_) {
    return "wait"; // a read error never falls back or claims
  }
}

export type RunSummary = Record<string, number | string>;

export type DrainSummary = {
  claimed: number; applied: number; fell_back: number; waiting: number; skipped: number; back_to_pending: number;
  needs_check: number; errors: number; not_reached: number;
};

async function drainRow(deps: ReconcileDeps, row: DeferralRow, nowMs: number, s: DrainSummary): Promise<void> {
  const d = await freshDecision(deps, row.user_id, nowMs);
  // A row that waits (renewal window, grace, a read error) or is skipped goes to the back of the queue: otherwise 20 such
  // rows would hold the batch and no newer row would ever be reached (B-pass round 2, F3).
  if (d === "skip") { s.skipped++; await deps.db.touch(row.id); return; }
  if (d === "wait") { s.waiting++; await deps.db.touch(row.id); return; }
  if (d === "fall_back") {
    if ((await deps.db.fallBack(row.id, null)) === "fell_back") s.fell_back++;
    return;
  }
  const token = await deps.db.claim(row.id);
  if (!token) { s.skipped++; return; } // another run has it, or another defer is in flight for this user
  s.claimed++;

  let status: number | null = null;
  try {
    status = await deps.postDefer(row.user_id, row.days);
  } catch (_) {
    status = null; // timeout / network: outcome unknown
  }

  if (status !== null && status >= 200 && status < 300) {
    if (await deps.db.mark(row.id, token, "applied")) s.applied++;
    try { await deps.mirror(row.user_id); } catch (_) { /* the webhook and the next run mirror it */ }
  } else if (status === 429) {
    if (await deps.db.mark(row.id, token, "pending")) s.back_to_pending++;
  } else if (status !== null && status >= 400 && status < 500) {
    // Refused, so nothing was applied. Decide again on a fresh read.
    let again: Decision;
    try { again = decide(await deps.mirror(row.user_id), nowMs); } catch (_) { again = "wait"; }
    if (again === "fall_back") {
      if ((await deps.db.fallBack(row.id, token)) === "fell_back") s.fell_back++;
    } else if (again === "wait" || again === "skip") {
      if (await deps.db.mark(row.id, token, "pending")) s.back_to_pending++;
    } else if (await deps.db.mark(row.id, token, "needs_check")) {
      // Still active and Google refused: falling back would run the days alongside paid time, so a human decides.
      s.needs_check++;
    }
  } else {
    // 5xx, timeout, network: the defer MAY have been applied. Never re-send; a human checks.
    if (await deps.db.mark(row.id, token, "needs_check")) s.needs_check++;
  }
}

export async function runDrain(
  deps: ReconcileDeps,
  nowMs: number,
  deadlineMs = Number.POSITIVE_INFINITY,
  clock: () => number = () => nowMs,
): Promise<DrainSummary> {
  const s: DrainSummary = {
    claimed: 0, applied: 0, fell_back: 0, waiting: 0, skipped: 0, back_to_pending: 0, needs_check: 0, errors: 0, not_reached: 0,
  };
  const rows = await deps.db.pendingRows(DRAIN_BATCH);
  for (let i = 0; i < rows.length; i++) {
    if (clock() >= deadlineMs) { s.not_reached = rows.length - i; break; }
    try {
      await drainRow(deps, rows[i], nowMs, s);
    } catch (e) {
      // One bad row (a lock, a vanished user, a failed write) must not starve the rows behind it.
      s.errors++;
      console.error(`[${FN_NAME}] drain row failed name=${errorName(e)}`);
    }
  }
  if (s.needs_check > 0) {
    await deps.alert(NEEDS_CHECK_ALERT_SOURCE, `${s.needs_check} referral defer(s) need a manual check in RevenueCat`, {
      needs_check: s.needs_check,
    });
  }
  return s;
}

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

export async function handler(req: Request, deps: ReconcileDeps): Promise<Response> {
  if (!(await deps.authorized(req))) return json(401, { error: "Unauthorized" });
  const clock = deps.nowMs ?? Date.now;
  const now = clock();
  const deadline = now + RUN_BUDGET_MS;
  const logId = await deps.telemetryStart();
  try {
    // 1. Stall alert first: an early return below must never hide a stuck reward (migrations CLAUDE.md, stall rows).
    const st = await deps.db.stallCounts(now);
    if (st.pendingOld + st.inFlightOld + st.needsCheck > 0) {
      await deps.alert(STALL_ALERT_SOURCE, "Referral days for Play subscribers are waiting (pending > 24 h, in flight > 2 h, or needs check)", st);
    }

    // 2. Switch.
    if (!deps.mirrorEnabled()) {
      await deps.telemetryEnd(logId, "success", { httpStatus: 200, errorSummary: "switch_off" });
      return json(200, { skipped: "switch_off", ...st });
    }

    // 3. Crashed claims.
    let crashed = 0;
    for (const c of await deps.db.crashedInFlight(now)) {
      if (await deps.db.mark(c.id, c.token, "needs_check")) crashed++;
    }
    if (crashed > 0) {
      await deps.alert(NEEDS_CHECK_ALERT_SOURCE, `${crashed} referral defer(s) were left in flight by a crashed run`, { crashed });
    }

    // 4. Drain (before the reconcile: see the header).
    const drain = await runDrain(deps, now, deadline, clock);

    // 5. Reconcile, inside the same budget.
    let mirrored = 0, other = 0, failed = 0, notReached = 0;
    const codes: Record<string, number> = {};
    const uids = await deps.db.reconcileUids(now);
    for (let i = 0; i < uids.length; i++) {
      if (clock() >= deadline) { notReached = uids.length - i; break; }
      try {
        if ((await deps.mirror(uids[i])).outcome === "mirrored") mirrored++;
        else other++;
      } catch (e) {
        failed++;
        const code = e instanceof RevenueCatReadError ? e.code : (e as { name?: string })?.name ?? "error";
        codes[code] = (codes[code] ?? 0) + 1;
      }
    }

    const summary = {
      mirrored, mirror_other: other, mirror_failed: failed, reconcile_not_reached: notReached, crashed,
      ...Object.fromEntries(Object.entries(drain).map(([k, v]) => [k === "errors" ? "drain_errors" : k === "not_reached" ? "drain_not_reached" : k, v])),
    };
    console.log(`[${FN_NAME}] ${Object.entries(summary).map(([k, v]) => `${k}=${v}`).join(" ")}`);
    // A run in which no reconcile read reached RevenueCat successfully while some failed (RevenueCat down, the secret key
    // unset) or a drain row errored is a FAILED run, so the cron-failure alert sees it. `other` (refused uid, unknown user)
    // returns before any RevenueCat call, so it proves nothing about RevenueCat (B-pass round 2, F2).
    const bad = (failed > 0 && mirrored === 0) || drain.errors > 0;
    if (notReached > 0 && mirrored + other + failed === 0) {
      await deps.alert(RECONCILE_STARVED_ALERT_SOURCE, "The referral drain used the whole run budget; no Play re-read ran this hour", {
        reconcile_not_reached: notReached,
      });
    }
    const parts = [
      failed > 0 ? `mirror_failed=${failed} codes=${Object.entries(codes).map(([k, v]) => `${k}:${v}`).join(",")}` : "",
      drain.errors > 0 ? `drain_errors=${drain.errors}` : "",
      notReached + drain.not_reached > 0 ? `budget_cut=${notReached + drain.not_reached}` : "",
    ].filter((x) => x);
    await deps.telemetryEnd(logId, bad ? "failed" : "success", {
      httpStatus: bad ? 500 : 200,
      errorSummary: parts.length > 0 ? parts.join(" ") : undefined,
    });
    return json(bad ? 500 : 200, summary);
  } catch (e) {
    const name = (e as { name?: string })?.name ?? "error";
    console.error(`[${FN_NAME}] run failed ${name}`);
    await deps.telemetryEnd(logId, "failed", { httpStatus: 500, errorSummary: `run failed ${name}` });
    return json(500, { error: "Internal server error" });
  }
}
