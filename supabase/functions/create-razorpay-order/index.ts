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
 *     (same issue CLAUDE.md §11 documents for ai-proxy / ai-proxy-pro):
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
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Canonical plan prices in paise. Keep in sync with razorpay-webhook +
// verify-payment + AppConstants in Flutter.
const MONTHLY_PAISE = 34900; // ₹349
const YEARLY_PAISE = 299900; // ₹2,999

function newRequestId(): string {
  return crypto.randomUUID().split("-")[0];
}

function err(status: number, message: string, extra: Record<string, unknown> = {}) {
  return new Response(
    JSON.stringify({ error: message, ...extra }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

serve(async (req: Request) => {
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
    {
      const { data: existing } = await supabase
        .from("subscriptions")
        .select("id, plan, end_date")
        .eq("user_id", userId)
        .eq("status", "active")
        .gt("end_date", new Date().toISOString())
        .order("end_date", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existing && existing.end_date) {
        return err(
          409,
          "You're already a PRO member.",
          {
            error_code: "already_pro",
            current_plan: existing.plan,
            current_expires_at: existing.end_date,
          },
        );
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

    if (promoCode) {
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
          console.log(`[create-order] promo ${promoCode} is inactive — rejecting`);
        } else {
          if (isExpired || isExhausted) {
            console.log(
              `[create-order] promo ${promoCode} race-condition (expired=${isExpired}, exhausted=${isExhausted}) — honouring anyway`,
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
          ...(appliedPromoCode ? { promo_code: appliedPromoCode } : {}),
        },
      }),
    });

    if (!orderResp.ok) {
      const requestId = newRequestId();
      const body = await orderResp.text();
      console.error(
        `[create-razorpay-order] request_id=${requestId} razorpay ${orderResp.status}: ${body}`,
      );
      return err(502, "Could not create payment order. Please try again.", {
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
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    const requestId = newRequestId();
    console.error(`[create-razorpay-order] request_id=${requestId}`, e);
    return err(500, "Internal server error", { request_id: requestId });
  }
});
