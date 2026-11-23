// supabase/functions/_shared/revenuecat_mirror.ts
//
// OI-519 (+51), plan docs/plans/2026-11-23-revenuecat-play-billing-51.md section 4. The ONE place that turns a RevenueCat
// customer into our `subscriptions` row. Every trigger (revenuecat-webhook, revenuecat-sync, revenuecat-reconcile) calls
// mirrorRevenueCatCustomer(uid): it re-reads the truth from RevenueCat's REST API with the secret key and upserts through
// public.upsert_play_subscription (migration 182). Nothing from a webhook body or the phone is ever written.
//
// One Play row per user: RevenueCat REST v1 keys `subscriber.subscriptions` by the Google subscription id WITHOUT the
// base-plan suffix (`avya_pro`) and returns the base plan in `product_plan_identifier` (plan section 18, U0).
//
// Log safety (payment-log-safety contract): this module never logs a request or response body, a key, or a user id.

import { isEnvExactlyTrue, type EnvReader } from "./subscription_stacking.ts";

export const MIRROR_ENABLE_ENV = "ENABLE_PLAY_BILLING_MIRROR";
export const REVENUECAT_SECRET_ENV = "REVENUECAT_SECRET_KEY";
export const REVENUECAT_API_BASE = "https://api.revenuecat.com/v1";
/** The Google Play subscription id (RevenueCat REST key, no base-plan suffix). */
export const PLAY_SUBSCRIPTION_ID = "avya_pro";
/** A renewing row stays active this long past the store expiry while the renewal is posted (plan section 4 rule 2). */
export const PLAY_RENEWAL_WINDOW_MS = 3 * 60 * 60 * 1000;
export const REVENUECAT_TIMEOUT_MS = 10_000;
export const UNKNOWN_PRODUCT_ALERT_SOURCE = "revenuecat_unknown_product";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isMirrorEnabled(env?: EnvReader): boolean {
  return env ? isEnvExactlyTrue(MIRROR_ENABLE_ENV, env) : isEnvExactlyTrue(MIRROR_ENABLE_ENV);
}

export function isUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

export type PlayPlan = "monthly" | "yearly";
export type PlayStatus = "active" | "expired" | "cancelled";

export type PlayRow = {
  productId: string;
  plan: PlayPlan;
  status: PlayStatus;
  startIso: string;
  endIso: string;
  autoRenew: boolean;
  environment: "SANDBOX" | "PRODUCTION";
  originalTxn: string | null;
  storeExpiresIso: string;
};

export type MapIssue = { kind: "unknown_product" | "unknown_plan" | "bad_entry"; productId: string };

function parseMs(v: unknown): number | null {
  if (typeof v !== "string" || v.length === 0) return null;
  const ms = Date.parse(v);
  return Number.isFinite(ms) ? ms : null;
}

function iso(ms: number): string {
  return new Date(ms).toISOString();
}

/**
 * Pure. Maps a RevenueCat REST v1 customer (`GET /v1/subscribers/{id}` body) to our Play rows at instant `nowMs`.
 * Rules, first match wins (plan section 4):
 *   1. refunded: refunded_at >= P (the latest period's purchase_date)  -> cancelled, end = refunded_at
 *   2. renewing: no unsubscribe, no billing issue, not paused          -> active iff E + 3 h > now, end = E + 3 h
 *   3. otherwise: effective end = max(E, G)                           -> active iff > now, else expired
 * Always: store_expires_at = E, start = P, environment from is_sandbox.
 */
export function mapCustomerToRows(customer: unknown, nowMs: number): { rows: PlayRow[]; issues: MapIssue[] } {
  const rows: PlayRow[] = [];
  const issues: MapIssue[] = [];
  const subs = (customer as { subscriber?: { subscriptions?: unknown } } | null)?.subscriber?.subscriptions;
  if (!subs || typeof subs !== "object") return { rows, issues };

  for (const [productId, raw] of Object.entries(subs as Record<string, unknown>)) {
    const e = raw as Record<string, unknown> | null;
    if (!e || typeof e !== "object" || e.store !== "play_store") continue; // other stores are not ours to mirror
    if (productId !== PLAY_SUBSCRIPTION_ID) {
      issues.push({ kind: "unknown_product", productId });
      continue;
    }
    const plan = e.product_plan_identifier;
    if (plan !== "monthly" && plan !== "yearly") {
      issues.push({ kind: "unknown_plan", productId });
      continue;
    }
    const P = parseMs(e.purchase_date);
    const E = parseMs(e.expires_date);
    if (P === null || E === null || typeof e.is_sandbox !== "boolean") {
      issues.push({ kind: "bad_entry", productId });
      continue;
    }
    const refundedAt = parseMs(e.refunded_at);
    const unsubscribed = e.unsubscribe_detected_at != null;
    const billingIssue = e.billing_issues_detected_at != null;
    const paused = e.auto_resume_date != null;
    const renewing = !unsubscribed && !billingIssue && !paused;

    let status: PlayStatus;
    let endMs: number;
    if (refundedAt !== null && refundedAt >= P) {
      status = "cancelled";
      endMs = refundedAt;
    } else if (renewing) {
      endMs = E + PLAY_RENEWAL_WINDOW_MS;
      status = endMs > nowMs ? "active" : "expired";
    } else {
      const G = billingIssue ? parseMs(e.grace_period_expires_date) : null;
      endMs = G !== null && G > E ? G : E;
      status = endMs > nowMs ? "active" : "expired";
    }

    const txn = e.store_transaction_id;
    rows.push({
      productId,
      plan,
      status,
      startIso: iso(P),
      endIso: iso(endMs),
      autoRenew: renewing,
      environment: e.is_sandbox ? "SANDBOX" : "PRODUCTION",
      originalTxn: typeof txn === "string" || typeof txn === "number" ? String(txn) : null,
      storeExpiresIso: iso(E),
    });
  }
  return { rows, issues };
}

// ------------------------------------------------------------------------------------------------------------------
// IO
// ------------------------------------------------------------------------------------------------------------------

export type UpsertResult = "written" | "stale_read";

export type MirrorDb = {
  userExists(uid: string): Promise<boolean>;
  upsertPlayRow(uid: string, row: PlayRow, readAtIso: string): Promise<UpsertResult>;
  alert(source: string, severity: "warn" | "critical", summary: string, context: Record<string, unknown>): Promise<void>;
};

export type MirrorDeps = {
  db: MirrorDb;
  secretKey: string | undefined;
  fetchFn?: typeof fetch;
  nowMs?: () => number;
  timeoutMs?: number;
};

export type MirrorOutcome =
  | { outcome: "mirrored"; rows: { productId: string; status: PlayStatus; result: UpsertResult }[]; mapped: PlayRow[] }
  | { outcome: "refused_uid" | "unknown_user" | "no_secret" };

export class RevenueCatReadError extends Error {
  constructor(public readonly code: string) {
    super(`revenuecat read failed: ${code}`);
    this.name = "RevenueCatReadError";
  }
}

/** One GET with a timeout; one retry on 5xx / 429 / network error. Returns the parsed body. */
export async function fetchRevenueCatCustomer(
  uid: string,
  secretKey: string,
  fetchFn: typeof fetch = fetch,
  timeoutMs = REVENUECAT_TIMEOUT_MS,
): Promise<unknown> {
  let lastCode = "unknown";
  for (let attempt = 1; attempt <= 2; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetchFn(`${REVENUECAT_API_BASE}/subscribers/${encodeURIComponent(uid)}`, {
        method: "GET",
        headers: { Authorization: `Bearer ${secretKey}`, Accept: "application/json" },
        signal: ctrl.signal,
      });
      if (res.status === 200 || res.status === 201) {
        return await res.json();
      }
      await res.body?.cancel();
      lastCode = `http_${res.status}`;
      if (!(res.status >= 500 || res.status === 429)) break; // a 4xx other than 429 will not get better
    } catch (e) {
      lastCode = (e as { name?: string })?.name === "AbortError" ? "timeout" : "network";
    } finally {
      clearTimeout(timer);
    }
  }
  throw new RevenueCatReadError(lastCode);
}

/**
 * Re-reads the customer from RevenueCat and upserts the Play row(s). Refuses a uid that is not a UUID or has no users row
 * BEFORE any RevenueCat call (a GET creates a missing customer). `read_at` is stamped BEFORE the GET is issued, so a slower,
 * older read can never overwrite a newer one (the upsert's ordering guard). Throws RevenueCatReadError on a failed read and
 * lets a database error propagate: the caller answers 5xx so the trigger is retried.
 */
export async function mirrorRevenueCatCustomer(uid: string, deps: MirrorDeps): Promise<MirrorOutcome> {
  if (!isUuid(uid)) return { outcome: "refused_uid" };
  if (!deps.secretKey) return { outcome: "no_secret" };
  if (!(await deps.db.userExists(uid))) return { outcome: "unknown_user" };

  const now = deps.nowMs ?? Date.now;
  const readAtIso = iso(now());
  const customer = await fetchRevenueCatCustomer(uid, deps.secretKey, deps.fetchFn ?? fetch, deps.timeoutMs);
  const { rows, issues } = mapCustomerToRows(customer, now());

  for (const issue of issues) {
    await deps.db.alert(
      UNKNOWN_PRODUCT_ALERT_SOURCE,
      "critical",
      `RevenueCat returned a Play subscription the mirror does not know (${issue.kind}); no row was written`,
      { kind: issue.kind, product_id: issue.productId },
    );
  }

  const out: { productId: string; status: PlayStatus; result: UpsertResult }[] = [];
  for (const row of rows) {
    const result = await deps.db.upsertPlayRow(uid, row, readAtIso);
    out.push({ productId: row.productId, status: row.status, result });
  }
  return { outcome: "mirrored", rows: out, mapped: rows };
}

// ------------------------------------------------------------------------------------------------------------------
// Supabase adapter (service-role client)
// ------------------------------------------------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
export type ServiceClient = { from: (t: string) => any; rpc: (fn: string, args: Record<string, unknown>) => any };

export function supabaseMirrorDb(client: ServiceClient): MirrorDb {
  return {
    async userExists(uid) {
      const { data, error } = await client.from("users").select("id").eq("id", uid).maybeSingle();
      if (error) throw new Error(`users read failed: ${(error as { code?: string }).code ?? "unknown"}`);
      return !!data;
    },
    async upsertPlayRow(uid, row, readAtIso) {
      // oi79-ok: the function RETURNS text (one scalar, 'written' or 'stale_read'); any other answer throws below.
      const { data, error } = await client.rpc("upsert_play_subscription", {
        p_user_id: uid,
        p_product_id: row.productId,
        p_plan: row.plan,
        p_status: row.status,
        p_start: row.startIso,
        p_end: row.endIso,
        p_auto_renew: row.autoRenew,
        p_environment: row.environment,
        p_original_txn: row.originalTxn,
        p_store_expires_at: row.storeExpiresIso,
        p_read_at: readAtIso,
      });
      if (error) throw new Error(`upsert_play_subscription failed: ${(error as { code?: string }).code ?? "unknown"}`);
      if (data !== "written" && data !== "stale_read") throw new Error("upsert_play_subscription returned an unknown value");
      return data;
    },
    async alert(source, severity, summary, context) {
      try {
        const since = new Date(Date.now() - 23 * 3600 * 1000).toISOString();
        const { data } = await client.from("alerts").select("id").eq("source", source).eq("acknowledged", false)
          .gte("detected_at", since).limit(1);
        if (Array.isArray(data) && data.length > 0) return; // one open alert per source per day
        await client.from("alerts").insert({ source, severity, summary, context_json: context });
      } catch (_) {
        console.error(`[revenuecat_mirror] alert insert failed for source=${source}`);
      }
    },
  };
}
