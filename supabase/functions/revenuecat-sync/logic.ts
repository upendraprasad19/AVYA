// revenuecat-sync/logic.ts — OI-519 (+51), plan section 4 entry point 2.
//
// The app calls this right after a Play purchase and on RESTORE / CHECK MY PRO STATUS (never on sheet open, never at
// expiry). verify_jwt = true; the user id comes ONLY from the JWT (a body uid is ignored). One consume_quota unit per
// call (20 per user per hour) BEFORE any RevenueCat call, failing CLOSED exactly like create-razorpay-order. With the
// mirror switch OFF it reads nothing from RevenueCat and returns the current row. Response = verify-subscription's shape
// plus the Play display fields.

import { type MirrorOutcome, RevenueCatReadError } from "../_shared/revenuecat_mirror.ts";

export const SYNC_QUOTA_KEY = "revenuecat_sync";
export const SYNC_QUOTA_LIMIT = 20;
export const SYNC_WINDOW_MS = 60 * 60 * 1000;

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Mapped, so the only `p_quota_key:` in this file is the call site in handler (founder_digest_caps_mirror_test.dart
// reads every such site and fails on one it cannot resolve).
export type QuotaArgs = { [k in "p_user_id" | "p_quota_key" | "p_window_start"]: string } & { p_limit: number };

export type CurrentRow = {
  plan: string | null;
  end_date: string | null;
  store: string | null;
  auto_renew: boolean | null;
  store_expires_at: string | null;
} | null;

export type SyncDeps = {
  authUser: (token: string) => Promise<string | null>;
  /** The `consume_quota` RPC with the argument object built in [handler] (the founder digest mirror reads it there). */
  consumeQuota: (args: QuotaArgs) => Promise<{ data: unknown; error: unknown }>;
  mirrorEnabled: () => boolean;
  mirror: (uid: string) => Promise<MirrorOutcome>;
  readCurrent: (uid: string) => Promise<CurrentRow>;
  nowMs?: () => number;
  requestId?: () => string;
};

const json = (status: number, body: Record<string, unknown>, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json", ...extra } });

export function shape(row: CurrentRow, nowMs: number): Record<string, unknown> {
  const end = row?.end_date ? Date.parse(row.end_date) : NaN;
  const active = Number.isFinite(end) && end > nowMs;
  if (!row || !active) {
    return { is_pro: false, plan: null, expires_at: null, store: null, auto_renew: null, store_expires_at: null };
  }
  return {
    is_pro: true,
    plan: row.plan ?? "monthly",
    expires_at: row.end_date,
    store: row.store,
    auto_renew: row.auto_renew,
    store_expires_at: row.store_expires_at,
  };
}

export async function handler(req: Request, deps: SyncDeps): Promise<Response> {
  const rid = (deps.requestId ?? (() => crypto.randomUUID().split("-")[0]))();
  const now = deps.nowMs ?? Date.now;
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const auth = req.headers.get("Authorization");
  if (!auth) return json(401, { error: "Missing authorization header" });
  const uid = await deps.authUser(auth.replace("Bearer ", ""));
  if (!uid) return json(401, { error: "Invalid or expired token" });

  // Rate limit BEFORE any RevenueCat call; fails CLOSED (create-razorpay-order/index.ts:148-189).
  const bucketStartMs = Math.floor(now() / SYNC_WINDOW_MS) * SYNC_WINDOW_MS;
  const syncWindowStart = new Date(bucketStartMs).toISOString();
  const { data: used, error: qErr } = await deps.consumeQuota({
    p_user_id: uid,
    p_quota_key: SYNC_QUOTA_KEY,
    p_window_start: syncWindowStart,
    p_limit: SYNC_QUOTA_LIMIT,
  });
  if (qErr || !Number.isInteger(used) || ((used as number) < 1 && used !== -1)) {
    console.error(`[revenuecat-sync] request_id=${rid} quota check failed (fail-closed) code=${qErr ? "rpc_error" : "bad_result"}`);
    return json(429, { error: "Could not check right now. Try again shortly.", error_code: "rate_limit_unavailable", request_id: rid });
  }
  if (used === -1) {
    const retry = Math.max(1, Math.ceil((bucketStartMs + SYNC_WINDOW_MS - now()) / 1000));
    // Telemetry on the over-limit path (hermes seat 2): the request id only, never the user.
    console.warn(`[revenuecat-sync] request_id=${rid} rate_limited`);
    return json(429, { error: "Too many checks. Try again in an hour.", error_code: "rate_limited", retry_after_seconds: retry }, {
      "Retry-After": String(retry),
    });
  }

  if (deps.mirrorEnabled()) {
    try {
      const out = await deps.mirror(uid);
      console.log(`[revenuecat-sync] request_id=${rid} outcome=${out.outcome}`);
    } catch (e) {
      const code = e instanceof RevenueCatReadError ? e.code : (e as { name?: string })?.name ?? "error";
      console.error(`[revenuecat-sync] request_id=${rid} mirror failed code=${code}`);
      return json(503, { error: "Store check unavailable. Try again shortly.", error_code: "store_unavailable", request_id: rid });
    }
  } else {
    console.log(`[revenuecat-sync] request_id=${rid} outcome=switch_off`);
    // The store was NOT read: say so, so the app never reads this as "no PRO found" (B-pass on the hermes fixes, seat B).
    return json(200, { ...shape(await deps.readCurrent(uid), now()), store_checked: false });
  }

  return json(200, shape(await deps.readCurrent(uid), now()));
}
