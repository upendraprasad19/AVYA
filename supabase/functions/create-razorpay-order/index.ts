/**
 * create-razorpay-order — Server-side Razorpay Order creation.
 *
 * Flow (client calls us BEFORE opening Razorpay checkout):
 *   1. Client sends { plan, promo_code?, discount_pct? } with JWT.
 *   2. We validate the JWT, look up the user, derive price.
 *   3. Call Razorpay POST /v1/orders with `payment_capture: 1`.
 *      This tells Razorpay to auto-capture the payment as soon as it's
 *      authorized — no manual capture step needed. Fixes the bug where
 *      UPI test payments (and some live UPI + wallet flows) stay in
 *      `authorized` status indefinitely because Razorpay was waiting
 *      for an explicit capture call that never came.
 *   4. Return order_id + key_id to the client, who passes order_id to
 *      Razorpay SDK's `open()` call.
 *   5. When payment completes, Razorpay fires `payment.captured` webhook
 *      immediately (no `payment.authorized` wait).
 *
 * Security:
 *   - verify_jwt: false — the Supabase gateway's JWT check is buggy
 *     (same issue docs/architecture/ai.md documents for ai-proxy / ai-proxy-pro):
 *     valid client JWTs are rejected with 401 before the function runs.
 *     We flip the gateway flag off and do the JWT validation ourselves
 *     via `supabase.auth.getUser(token)` below — that is the real gate.
 *     Observed 2026-04-17 as four consecutive 401s on icanbefitter@gmail.com
 *     trying to upgrade to PRO with a fresh valid JWT; other functions
 *     using `SupabaseService.callFunction` (ai-proxy) returned 200 in the
 *     same second with the same auth token.
 *   - We manually validate the JWT and use the authenticated user_id in
 *     order.notes — never trust client-supplied user_id.
 *   - Price is derived server-side from the plan + promo lookup — never
 *     trust client-supplied amount.
 *
 * The purchase door (OI-341 Piece B2a, docs/plans/oi341-piece-b2-door.md 2.2):
 *   - ONE guard read of the caller's active, unexpired rows. A read ERROR answers
 *     500 `subscription_check_unavailable` and creates no order (before B2a a
 *     failed read created the order: a double-payment hole).
 *   - Door SHUT (anything but BOTH `ENABLE_TRIAL_PURCHASE` and
 *     `ENABLE_SUBSCRIPTION_STACKING` exactly "true", read once per request): any
 *     active row answers today's 409 `already_pro` from the latest-ending row.
 *   - Door OPEN: a paid (non-`referral_trial`) row answers 409 from the
 *     latest-ending PAID row; a user with only trial rows (or none) gets the
 *     order, and the response and the order notes carry `stacks_after` (the
 *     latest trial end, null when none; dashboard/estimate only, never read back
 *     for entitlement: the writers compute their own base, payment.md rule 1).
 *   - The shut response carries no `stacks_after` key.
 *   - Env is read inside the handler, so importing this module does no I/O;
 *     `serve()` runs only as the entrypoint.
 * Catastrophic tier (docs/blast_radius.yaml).
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import { isEnvExactlyTrue, isStackingEnabled, isTrialPurchaseEnabled } from "../_shared/subscription_stacking.ts";
import { boundedText, errorName, pgErrorCode, razorpayErrorSummary, stackFrames } from "../_shared/payment_log_safe.ts";
import { promoUsableAt } from "../_shared/promo_rules.ts";
import { ORDER_ABUSE_GUARDS_DISABLE_ENV, retryMinutes, secondsLeftInBucket } from "../_shared/order_abuse_guards.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** The one plan value a trial grant row carries (migration 159 `grant_referral_days`). */
const REFERRAL_TRIAL_PLAN = "referral_trial";

// Canonical plan prices in paise. Keep in sync with razorpay-webhook +
// verify-payment + AppConstants in Flutter.
const MONTHLY_PAISE = 34900; // ₹349
const YEARLY_PAISE = 299900; // ₹2,999

// OI-366 (payment-hardening U3): at most ORDER_QUOTA_LIMIT order attempts per user per fixed 1-hour UTC bucket
// (a sub-day bucket, like delete-account's: only its duration is observable, through Retry-After), and a promo
// code must be usable NOW (promo_rules.ts) to price an order. Kill switch: exactly "true" turns both off.
const ORDER_QUOTA_KEY = "create_order";
const ORDER_QUOTA_LIMIT = 30;
const ORDER_RATE_WINDOW_MS = 60 * 60 * 1000;
// The switch and the wait wording live in _shared/order_abuse_guards.ts (shared with validate-promo and the founder
// digest); re-exported for this function's tests.
export { ORDER_ABUSE_GUARDS_DISABLE_ENV, retryMinutes };

function newRequestId(): string {
  return crypto.randomUUID().split("-")[0];
}

function err(status: number, message: string, extra: Record<string, unknown> = {}) {
  return new Response(
    JSON.stringify({ error: message, ...extra }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

type ActiveRow = { plan: string; end_date: string };

/** The row with the latest `end_date` (instants compared as instants), or null. */
function latestEnding(rows: ActiveRow[]): ActiveRow | null {
  let best: ActiveRow | null = null;
  for (const r of rows) {
    if (best === null || Date.parse(r.end_date) > Date.parse(best.end_date)) best = r;
  }
  return best;
}

function alreadyPro(row: ActiveRow) {
  return err(
    409,
    "You're already a PRO member.",
    {
      error_code: "already_pro",
      current_plan: row.plan,
      current_expires_at: row.end_date,
    },
  );
}

export async function handler(req: Request): Promise<Response> {
  const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
  const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return err(405, "Method not allowed");

  try {
    // ── JWT ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return err(401, "Missing authorization header");
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !user) return err(401, "Invalid or expired token");
    const userId = user.id;

    // ── OI-366: per-user order limit (fails CLOSED), before any other read ──
    // Read once per request; logged so a flip is visible (the write_claim_rule precedent).
    const guardsOn = !isEnvExactlyTrue(ORDER_ABUSE_GUARDS_DISABLE_ENV);
    console.log(`[create-razorpay-order] order_abuse_guards=${guardsOn ? "on" : "off"}`);
    if (guardsOn) {
      const bucketStartMs = Math.floor(Date.now() / ORDER_RATE_WINDOW_MS) * ORDER_RATE_WINDOW_MS;
      const bucketStart = new Date(bucketStartMs).toISOString();
      const { data: usedCount, error: rateErr } = await supabase.rpc("consume_quota", {
        p_user_id: userId,
        p_quota_key: ORDER_QUOTA_KEY,
        p_window_start: bucketStart,
        p_limit: ORDER_QUOTA_LIMIT,
      });
      if (rateErr) {
        const requestId = newRequestId();
        console.error(
          `[create-razorpay-order] request_id=${requestId} order limit check failed (fail-closed) code=${pgErrorCode(rateErr)}`,
        );
        return err(429, "Could not start payment right now. Try again shortly.", {
          error_code: "rate_limit_unavailable",
          request_id: requestId,
        });
      }
      // consume_quota answers -1 or a count >= 1; anything else is an unreadable counter (fail CLOSED too).
      if (!Number.isInteger(usedCount) || (usedCount < 1 && usedCount !== -1)) {
        const requestId = newRequestId();
        console.error(
          `[create-razorpay-order] request_id=${requestId} order limit check failed (fail-closed) code=bad_result`,
        );
        return err(429, "Could not start payment right now. Try again shortly.", {
          error_code: "rate_limit_unavailable",
          request_id: requestId,
        });
      }
      if (usedCount === -1) {
        const retryAfterSeconds = secondsLeftInBucket(bucketStartMs, ORDER_RATE_WINDOW_MS);
        console.warn(
          `[create-razorpay-order] user=${userId} rate-limited (quota_key=${ORDER_QUOTA_KEY}, limit=${ORDER_QUOTA_LIMIT})`,
        );
        return new Response(
          JSON.stringify({
            // A fixed 1-hour bucket: the wait can be up to an hour, so say how long (B-pass beee28f0d9f2 finding 2).
            error: `Too many payment attempts. Try again in ${retryMinutes(retryAfterSeconds)}.`,
            error_code: "rate_limited",
            retry_after_seconds: retryAfterSeconds,
          }),
          {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": String(retryAfterSeconds) },
          },
        );
      }
    }

    // ── APK Test #12.2 / Task #6 — server-side double-payment guard ──
    //
    // Last-resort defense against creating duplicate active subscriptions.
    // If the user already has a non-expired active subscription, reject
    // with 409 + existing entitlement so the client can show
    // "you're already PRO until DDD" instead of opening Razorpay checkout.
    //
    // Why server-side guard exists: the Flutter UI guards via
    // `subscriptionInfoProvider.isPro` reading local Hive — but that read
    // can be a false negative in known PRO-unlock bug paths. Founder
    // discovered this by paying 4 times in 24h on 2026-05-06 (each
    // payment created a new active subscription row) — the UI never
    // showed "already PRO" because local isPro was reading false.
    //
    // OI-341 Piece B2a (plan 2.2): ONE read of every active unexpired row (a
    // user has few), decided in code. A read error is checked: it used to be
    // ignored, so a failed read created the order (fail OPEN).
    // Both switches are read once per request; the door opens only when both are on.
    const doorOpen = isTrialPurchaseEnabled() && isStackingEnabled();
    let stacksAfter: string | null = null;
    {
      const { data: activeRows, error: guardError } = await supabase
        .from("subscriptions")
        .select("plan, end_date")
        .eq("user_id", userId)
        .eq("status", "active")
        .gt("end_date", new Date().toISOString());

      if (guardError || !Array.isArray(activeRows)) {
        const requestId = newRequestId();
        console.error(
          `[create-razorpay-order] request_id=${requestId} subscription guard read failed code=${
            guardError ? pgErrorCode(guardError) : "no_rows_array"
          }`,
        );
        return err(500, "Could not verify your subscription. Please try again.", {
          error_code: "subscription_check_unavailable",
          request_id: requestId,
        });
      }

      const rows = (activeRows as ActiveRow[]).filter((r) => r.end_date);
      if (!doorOpen) {
        const latest = latestEnding(rows);
        if (latest) return alreadyPro(latest);
      } else {
        const latestPaid = latestEnding(rows.filter((r) => r.plan !== REFERRAL_TRIAL_PLAN));
        if (latestPaid) return alreadyPro(latestPaid);
        stacksAfter = latestEnding(rows)?.end_date ?? null;
      }
    }

    // ── Body ──
    const body = await req.json();
    const plan = String(body?.plan ?? "");
    const promoCode = body?.promo_code == null
      ? undefined
      : String(body.promo_code).trim().toUpperCase();

    if (plan !== "monthly" && plan !== "yearly") {
      return err(400, "Invalid plan. Must be 'monthly' or 'yearly'");
    }

    // ── Derive price server-side (NEVER trust client amount) ──
    let amountPaise = plan === "monthly" ? MONTHLY_PAISE : YEARLY_PAISE;
    let appliedPromoCode: string | null = null;
    let discountPct = 0;

    if (promoCode && guardsOn) {
      // OI-366: STRICT at order time. A read error is an outage, never "this code is dead"; an unknown or
      // unusable code gets no order at all (it used to give a silent full-price order). The payment writers
      // stay tolerant (docs/architecture/payment.md rule 2), so a payment made here can always be recorded.
      const { data: promo, error: promoErr } = await supabase
        .from("promo_codes")
        .select("discount_pct, is_active, valid_until, max_uses, used_count")
        .eq("code", promoCode)
        .maybeSingle();
      if (promoErr) {
        const requestId = newRequestId();
        console.error(
          `[create-razorpay-order] request_id=${requestId} promo read failed code=${pgErrorCode(promoErr)}`,
        );
        return err(500, "Could not check the promo code. Try again.", {
          error_code: "promo_check_unavailable",
          request_id: requestId,
        });
      }
      const usable = promo ? promoUsableAt(promo) : "unknown";
      if (usable !== "ok") {
        // The length only (hermes H11): an unknown code is client-supplied text, not a code we issued.
        console.log(`[create-razorpay-order] promo refused: ${usable} code_length=${promoCode.length}`);
        return err(400, "This promo code can no longer be used. Reopen the upgrade screen to pay without it.", {
          error_code: "promo_invalid",
        });
      }
      discountPct = promo!.discount_pct as number;
      amountPaise = Math.round(amountPaise * (100 - discountPct) / 100);
      appliedPromoCode = promoCode;
    } else if (promoCode) {
      // Kill switch ON: the pre-OI-366 tolerant path, verbatim (its logs bound the client-supplied code).
      const { data: promo } = await supabase
        .from("promo_codes")
        .select("discount_pct, is_active, valid_until, max_uses, used_count")
        .eq("code", promoCode)
        .maybeSingle();

      if (promo) {
        const now = new Date();
        const validUntil = promo.valid_until
          ? new Date(promo.valid_until as string)
          : null;
        const maxUses = promo.max_uses as number | null;
        const usedCount = promo.used_count as number;

        const isExpired = validUntil !== null && validUntil < now;
        const isExhausted = maxUses !== null && usedCount >= maxUses;
        const isActive = promo.is_active === true;

        // Tolerant validation — we honour the discount at order-time even
        // if promo has expired / exhausted between checkout open and order
        // create (the user saw the price already). Matches the webhook's
        // tolerant verification. Full reject only if code doesn't exist or
        // is marked inactive.
        if (!isActive) {
          console.log(`[create-order] promo ${boundedText(promoCode)} is inactive — rejecting`);
        } else {
          if (isExpired || isExhausted) {
            console.log(
              `[create-order] promo ${boundedText(promoCode)} race-condition (expired=${isExpired}, exhausted=${isExhausted}) — honouring anyway`,
            );
          }
          discountPct = promo.discount_pct as number;
          amountPaise = Math.round(amountPaise * (100 - discountPct) / 100);
          appliedPromoCode = promoCode;
        }
      }
    }

    // ── Create Razorpay order ──
    const credentials = base64Encode(
      `${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`,
    );

    // `payment_capture: 1` → Razorpay auto-captures the moment the bank
    // or UPI app authorizes. No manual /capture call needed. This is the
    // fix for the `authorized-but-stuck` bug we saw on 2026-04-17.
    const orderResp = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${credentials}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: amountPaise,
        currency: "INR",
        receipt: `rcpt_${userId.substring(0, 8)}_${Date.now()}`,
        payment_capture: 1,
        notes: {
          user_id: userId,
          plan: plan,
          // Dashboard-reconciliation tags only — never read back for entitlement
          // (razorpay-webhook/verify-payment derive plan from the on-wire amount,
          // not from notes; see docs/architecture/payment.md rule 1). Added so
          // orders from this app are distinguishable from the website's own
          // Razorpay orders in the shared live account's dashboard/settlement feed.
          source: "AVYA_app",
          billing_cycle: plan === "monthly" ? "monthly" : "annual",
          ...(appliedPromoCode ? { promo_code: appliedPromoCode } : {}),
          // Door open with an active trial: the paid days start at this instant.
          // Dashboard reconciliation only, never read back for entitlement.
          ...(doorOpen && stacksAfter !== null ? { stacks_after: stacksAfter } : {}),
        },
      }),
    });

    if (!orderResp.ok) {
      const requestId = newRequestId();
      const body = await orderResp.text();
      console.error(
        `[create-razorpay-order] request_id=${requestId} razorpay ${razorpayErrorSummary(orderResp.status, body)}`,
      );
      // 500, not 502, with the guards on (hermes H1): the client's callFunction retries 502/503/504 up to three
      // times, and each retry spends another order-limit unit. The switch keeps the origin's 502.
      return err(guardsOn ? 500 : 502, "Could not create payment order. Please try again.", {
        request_id: requestId,
      });
    }

    const order = await orderResp.json();
    return new Response(
      JSON.stringify({
        order_id: order.id,
        amount: order.amount,
        currency: order.currency,
        key_id: RAZORPAY_KEY_ID,
        plan: plan,
        promo_applied: appliedPromoCode !== null,
        discount_pct: discountPct,
        // The door-open response always carries the key (null = no trial to stack after); the shut one never does.
        ...(doorOpen ? { stacks_after: stacksAfter } : {}),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    const requestId = newRequestId();
    // Name and frames only (hermes H10): a req.json() SyntaxError's message quotes the request body.
    console.error(`[create-razorpay-order] request_id=${requestId} unhandled ${errorName(e)} at ${stackFrames(e)}`);
    return err(500, "Internal server error", { request_id: requestId });
  }
}

// `serve()` only when run as the entrypoint, so tests can import `handler`
// without binding a port (the writers' pattern, OI-341 Piece A plan 2.3).
if (import.meta.main) serve(handler);
