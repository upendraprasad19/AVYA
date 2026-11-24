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

import { pgErrorCode } from "./payment_log_safe.ts";
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
/** A running Play row whose customer read shows no avya_pro Play entry (hermes seat 1). */
export const ENTRY_MISSING_ALERT_SOURCE = "revenuecat_entry_missing";
/** The secret REST key is unset while the switch is on: every read fails, so nobody gets PRO from Play (B-pass F2). */
export const SECRET_MISSING_ALERT_SOURCE = "revenuecat_secret_missing";

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

/** `sandbox_refused`: a SANDBOX read was not allowed to replace a running PRODUCTION row (migration 182, B-pass F1). */
export type UpsertResult = "written" | "stale_read" | "sandbox_refused";

export type MirrorDb = {
  userExists(uid: string): Promise<boolean>;
  upsertPlayRow(uid: string, row: PlayRow, readAtIso: string): Promise<UpsertResult>;
  alert(source: string, severity: "warn" | "critical", summary: string, context: Record<string, unknown>): Promise<void>;
  /** Whether the user holds an `active` Play row. Optional: absent = the entry-missing check is skipped. */
  hasActivePlayRow?(uid: string): Promise<boolean>;
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
  | { outcome: "refused_uid" | "unknown_user" };

export class RevenueCatReadError extends Error {
  constructor(public readonly code: string) {
    super(`revenuecat read failed: ${code}`);
    this.name = "RevenueCatReadError";
  }
}

/** PURE. Text from RevenueCat's body for a jsonb field: at most [n] characters, no control or line-separator or
 *  format characters (replaced by "?"), never quoted (B-pass on the hermes fixes, seat A: `boundedText` adds quotes). */
export function plainBounded(v: unknown, n: number): string {
  return String(v).slice(0, n).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff]/g, "?");
}

export const RETRY_429_DEFAULT_WAIT_MS = 500;
export const RETRY_429_MAX_WAIT_MS = 2000;

/** One GET with a timeout; one retry on 5xx / 429 / network error (a 429 waits first). Returns the parsed body. */
export async function fetchRevenueCatCustomer(
  uid: string,
  secretKey: string,
  fetchFn: typeof fetch = fetch,
  timeoutMs = REVENUECAT_TIMEOUT_MS,
  sleepFn: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
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
      if (res.status === 429 && attempt === 1) {
        // An immediate retry of a 429 is a second 429: wait Retry-After (seconds), bounded (hermes seat 2).
        const ra = Number(res.headers.get("Retry-After") ?? "");
        await sleepFn(Number.isFinite(ra) && ra > 0 ? Math.min(ra * 1000, RETRY_429_MAX_WAIT_MS) : RETRY_429_DEFAULT_WAIT_MS);
      }
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
 * lets a database error propagate: the caller answers 5xx so the trigger is retried. A missing secret key is a failed read
 * too (code `no_secret`, after a critical alert): an answer of "nothing to do" would let a paying user silently stay free.
 */
export async function mirrorRevenueCatCustomer(uid: string, deps: MirrorDeps): Promise<MirrorOutcome> {
  if (!isUuid(uid)) return { outcome: "refused_uid" };
  if (!deps.secretKey) {
    try {
      await deps.db.alert(SECRET_MISSING_ALERT_SOURCE, "critical", "REVENUECAT_SECRET_KEY is unset while the Play mirror is on: no Play purchase can be confirmed", {});
    } catch (_) { /* the typed throw below must win over any alert failure (B-pass round 2, F1) */ }
    throw new RevenueCatReadError("no_secret");
  }
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
      // productId comes from RevenueCat's body: bounded and escaped before it is stored (hermes seat 4).
      { kind: issue.kind, product_id: plainBounded(issue.productId, 64) },
    );
  }

  const out: { productId: string; status: PlayStatus; result: UpsertResult }[] = [];
  for (const row of rows) {
    const result = await deps.db.upsertPlayRow(uid, row, readAtIso);
    if (result === "sandbox_refused") {
      // A license tester's SANDBOX read met a running PRODUCTION row (migration 182 keeps the PRODUCTION row). Rare: say so.
      console.warn("[revenuecat-mirror] upsert result=sandbox_refused (a SANDBOX read was not allowed over PRODUCTION)");
    }
    out.push({ productId: row.productId, status: row.status, result });
  }
  // A good read with NO avya_pro Play entry while our Play row still grants PRO: nothing writes that row (the mirror
  // never revokes on an absence: a missing entry can be a RevenueCat-side oddity, and a wrong revoke takes PRO from a
  // payer). The founder checks it by hand (hermes seat 1, 2026-11-24).
  // Diagnostic only: its read or alert failing must never turn a good mirror into a failed one (B-pass on the hermes
  // fixes, seat A). One open alert per source per day (the shared `alert` dedup): the summary says how to find the rest.
  if (rows.length === 0 && issues.length === 0 && deps.db.hasActivePlayRow) {
    try {
      if (await deps.db.hasActivePlayRow(uid)) {
        await deps.db.alert(
          ENTRY_MISSING_ALERT_SOURCE,
          "critical",
          "A Play row grants PRO but RevenueCat shows no Play subscription for this customer: check it by hand " +
            "(one alert per day; others may exist: compare every active Play row with RevenueCat)",
          { user_id: uid },
        );
      }
    } catch (e) {
      console.warn(`[revenuecat-mirror] entry-missing check failed (ignored) code=${pgErrorCode(e)}`);
    }
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
    async hasActivePlayRow(uid) {
      const { data, error } = await client.from("subscriptions").select("id").eq("user_id", uid).eq("store", "play")
        .eq("status", "active").limit(1);
      if (error) throw new Error(`play row read failed: ${(error as { code?: string }).code ?? "unknown"}`);
      return Array.isArray(data) && data.length > 0;
    },
    async upsertPlayRow(uid, row, readAtIso) {
      // oi79-ok: the function RETURNS text (one scalar: 'written', 'stale_read' or 'sandbox_refused'); any other answer throws below.
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
      if (data !== "written" && data !== "stale_read" && data !== "sandbox_refused") {
        throw new Error("upsert_play_subscription returned an unknown value");
      }
      return data;
    },
    async alert(source, severity, summary, context) {
      try {
        const since = new Date(Date.now() - 23 * 3600 * 1000).toISOString();
        const { data, error: readErr } = await client.from("alerts").select("id").eq("source", source).eq("acknowledged", false)
          .gte("detected_at", since).limit(1);
        if (readErr) {
          // An unreadable dedup must not become one alert per call (up to ~220 a reconcile run): say so and send none.
          console.error(`[revenuecat_mirror] alert dedup read failed for source=${source} code=${pgErrorCode(readErr)}`);
          return;
        }
        if (Array.isArray(data) && data.length > 0) return; // one open alert per source per day
        const { error } = await client.from("alerts").insert({ source, severity, summary, context_json: context });
        if (error) console.error(`[revenuecat_mirror] alert insert failed for source=${source} code=${pgErrorCode(error)}`);
      } catch (_) {
        console.error(`[revenuecat_mirror] alert insert failed for source=${source}`);
      }
    },
  };
}
