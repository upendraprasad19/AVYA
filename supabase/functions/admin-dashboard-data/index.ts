/**
 * admin-dashboard-data — read endpoint for the founder-only admin business
 * dashboard (Flutter `/admin` route, web-only).
 *
 * Auth (mirrors promote-community-item's audited v8 gate, diagnose 7ad0c5):
 *   1. Service-role caller (signature-verified via isAuthorizedCronCall) — passes.
 *   2. Authenticated JWT whose user.id is in ADMIN_USER_IDS — passes.
 *   Everything else (anon, authenticated non-admin, missing/invalid token)
 *   returns 403. ADMIN_USER_IDS unset -> fail-secure, reject every caller.
 *
 * Data sources:
 *   - admin_metrics_daily (migration 102) — last 30 days, for trend charts.
 *   - public.founder_metrics_for_admin_api() (migration 101) — current
 *     growth/subscription counts (wraps the existing private.founder_metrics()).
 *   - subscriptions.plan breakdown (live query, ~11 rows today) — for the
 *     derived-MRR calc; not in the daily snapshot since the plan only
 *     promised a *current* MRR figure, not a trend, for v1.
 *   - users.subscription_expires_at (live query, canonical field per
 *     founder_metrics()'s own convention) — expiring/expired lists.
 *   - alerts table (live query) — reused as-is for the Ops Health feed.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Admin allowlist — same env var promote-community-item already depends on
// (verify it's populated before deploying; don't create a duplicate secret).
const ADMIN_USER_IDS = (Deno.env.get("ADMIN_USER_IDS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const TREND_DAYS = 30;
const EXPIRY_WINDOW_DAYS = 30;
const MONTHLY_PRICE_INR = 349;
const YEARLY_PRICE_INR = 2999;

/** Pure — no I/O. Fail-secure: an empty allowlist rejects every authenticated caller. */
export function isAuthorizedAdminCaller(opts: {
  isServiceRole: boolean;
  userId: string | null;
  adminUserIds: string[];
}): boolean {
  if (opts.isServiceRole) return true;
  if (opts.userId == null) return false;
  if (opts.adminUserIds.length === 0) return false;
  return opts.adminUserIds.includes(opts.userId);
}

export interface ExpirySubscriptionRow {
  user_id: string;
  email: string | null;
  subscription_expires_at: string;
}

export interface ExpiryBuckets {
  expired: ExpirySubscriptionRow[];
  expiring7d: ExpirySubscriptionRow[];
  expiring30d: ExpirySubscriptionRow[];
}

/** Pure — takes `now` as a parameter so it never reads the system clock itself. */
export function bucketSubscriptionsByExpiry(
  rows: ExpirySubscriptionRow[],
  now: Date,
): ExpiryBuckets {
  const buckets: ExpiryBuckets = { expired: [], expiring7d: [], expiring30d: [] };
  const in7d = now.getTime() + 7 * 24 * 60 * 60 * 1000;
  const in30d = now.getTime() + 30 * 24 * 60 * 60 * 1000;
  for (const row of rows) {
    const expiresAt = new Date(row.subscription_expires_at).getTime();
    if (expiresAt <= now.getTime()) {
      buckets.expired.push(row);
    } else if (expiresAt <= in7d) {
      buckets.expiring7d.push(row);
    } else if (expiresAt <= in30d) {
      buckets.expiring30d.push(row);
    }
    // Beyond 30 days out: not shown on this tab, intentionally.
  }
  return buckets;
}

export interface PlanCounts {
  monthlyActive: number;
  yearlyActive: number;
  trialActive: number;
  otherActive: number;
}

/**
 * Pure. Buckets active-subscription rows by plan. `monthly` / `yearly` are
 * the paying plans; `referral_trial` is a non-paying trial (surfaced so the
 * split reconciles against the active-sub count); anything else falls into
 * `otherActive` so a future unforeseen plan value is visible, never silently
 * dropped. monthlyActive + yearlyActive + trialActive + otherActive == rows.length.
 */
export function bucketActivePlans(
  rows: Array<{ plan: string | null }>,
): PlanCounts {
  const counts: PlanCounts = {
    monthlyActive: 0,
    yearlyActive: 0,
    trialActive: 0,
    otherActive: 0,
  };
  for (const row of rows) {
    if (row.plan === "monthly") counts.monthlyActive++;
    else if (row.plan === "yearly") counts.yearlyActive++;
    else if (row.plan === "referral_trial") counts.trialActive++;
    else counts.otherActive++;
  }
  return counts;
}

/** Pure. Standard MRR convention: annual plans normalized to a monthly-equivalent (÷12). Trials pay 0. */
export function computeDerivedMrr(
  counts: { monthlyActive: number; yearlyActive: number },
  prices: { monthlyInr: number; yearlyInr: number },
): number {
  return counts.monthlyActive * prices.monthlyInr +
    counts.yearlyActive * (prices.yearlyInr / 12);
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return clientError("Method not allowed", 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return clientError("Missing authorization header", 401);
  }
  const token = authHeader.slice("Bearer ".length);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Resolve identity inside a fail-CLOSED try: a transient GoTrue/network
  // reject on getUser must return a sanitized 500 WITH corsHeaders (via
  // serverError), not bubble out of `serve` as a bare CORS-less 500 that the
  // web dashboard reads as an opaque network error (Hermes L21). It also
  // never fails OPEN — an exception can't reach the admin check below.
  let isServiceRole = false;
  let userId: string | null = null;
  try {
    isServiceRole = await isAuthorizedCronCall(req);
    if (!isServiceRole) {
      const { data } = await admin.auth.getUser(token);
      userId = data?.user?.id ?? null;
    }
  } catch (err) {
    return serverError("admin-dashboard-data:auth", err);
  }

  if (!isAuthorizedAdminCaller({ isServiceRole, userId, adminUserIds: ADMIN_USER_IDS })) {
    if (ADMIN_USER_IDS.length === 0) {
      console.error("[admin-dashboard-data] ADMIN_USER_IDS env var not set; rejecting caller by default");
    } else if (userId) {
      console.warn(`[admin-dashboard-data] non-admin caller rejected: user_id=${userId}`);
    }
    return clientError("Admin only", 403);
  }

  try {
    const now = new Date();
    const dayMs = 24 * 60 * 60 * 1000;
    // Expiry window is BOUNDED on both sides: [now-30d, now+30d]. Without a
    // lower bound the "expired" bucket swept EVERY historically-lapsed user
    // forever — unbounded growth, over-exposed emails, no LIMIT (Hermes
    // L1/L21/L37/L40 all flagged it). "Expired" now means "lapsed in the last
    // 30 days" — the actionable win-back set, not all-time history.
    const expiryFloorIso = new Date(now.getTime() - EXPIRY_WINDOW_DAYS * dayMs)
      .toISOString();
    const expiryWindowIso = new Date(now.getTime() + EXPIRY_WINDOW_DAYS * dayMs)
      .toISOString();

    // `current` is LIVE across ALL three metric groups (growth + engagement +
    // ops), same as the growth tab already was — the daily snapshot table is
    // ONLY for the historical `trend` series. Before Hermes L1-F1 the
    // engagement/ops "today" tiles read `trend.last` (up to 24h stale, or 0
    // before the first nightly snapshot); now they read a genuinely-live value.
    const [trendRes, growthRes, engagementRes, opsRes, planRes, expiryRes, alertsRes] =
      await Promise.all([
        admin
          .from("admin_metrics_daily")
          .select("*")
          .order("snapshot_date", { ascending: false })
          .limit(TREND_DAYS),
        admin.rpc("founder_metrics_for_admin_api").single(),
        admin.rpc("founder_metrics_engagement").single(),
        admin.rpc("founder_metrics_ops").single(),
        admin.from("subscriptions").select("plan").eq("status", "active"),
        admin
          .from("users")
          .select("id, email, subscription_expires_at")
          .not("subscription_expires_at", "is", null)
          .gte("subscription_expires_at", expiryFloorIso)
          .lte("subscription_expires_at", expiryWindowIso),
        admin
          .from("alerts")
          .select("id, detected_at, source, severity, summary, suggested_action")
          .is("resolved_at", null)
          .order("detected_at", { ascending: false })
          .limit(20),
      ]);

    const firstError = trendRes.error || growthRes.error || engagementRes.error ||
      opsRes.error || planRes.error || expiryRes.error || alertsRes.error;
    if (firstError) {
      return serverError("admin-dashboard-data", firstError);
    }

    // Plan split across ACTIVE subscriptions. Live distinct values
    // (2026-07-13): {monthly, referral_trial}; `yearly` has 0 rows today
    // but is a valid future plan. referral_trial subs are NOT paying, so
    // they contribute 0 to MRR but MUST be surfaced — otherwise the tab
    // shows "1 monthly, 0 yearly" against 7 active subs with 6 unexplained.
    // `otherActive` is a catch-all so a future unforeseen plan value can
    // never silently re-open that gap (monthly+yearly+trial+other == active).
    const planCounts = bucketActivePlans(
      (planRes.data ?? []) as Array<{ plan: string | null }>,
    );

    const expiryRows: ExpirySubscriptionRow[] = ((expiryRes.data ?? []) as Array<
      { id: string; email: string | null; subscription_expires_at: string }
    >).map((r) => ({
      user_id: r.id,
      email: r.email,
      subscription_expires_at: r.subscription_expires_at,
    }));
    const expiryBuckets = bucketSubscriptionsByExpiry(expiryRows, now);

    const derivedMrr = computeDerivedMrr(planCounts, {
      monthlyInr: MONTHLY_PRICE_INR,
      yearlyInr: YEARLY_PRICE_INR,
    });

    return ok({
      generated_at: now.toISOString(),
      trend: trendRes.data ?? [],
      // Merge the three live metric-group rows into one `current` object.
      // Each carries its own `generated_at`; the spread keeps the last
      // (ops) one — the model only reads the top-level `generated_at`, so
      // the collision is harmless.
      current: {
        ...(growthRes.data as Record<string, unknown> ?? {}),
        ...(engagementRes.data as Record<string, unknown> ?? {}),
        ...(opsRes.data as Record<string, unknown> ?? {}),
      },
      revenue: {
        monthly_active: planCounts.monthlyActive,
        yearly_active: planCounts.yearlyActive,
        trial_active: planCounts.trialActive,
        other_active: planCounts.otherActive,
        derived_mrr_inr: derivedMrr,
        current_monthly_price_inr: MONTHLY_PRICE_INR,
        current_yearly_price_inr: YEARLY_PRICE_INR,
      },
      subscriptions_expiring: expiryBuckets,
      open_alerts: alertsRes.data ?? [],
    });
  } catch (err) {
    return serverError("admin-dashboard-data", err);
  }
};

if (import.meta.main) {
  serve(handler);
}
