import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Canonical plan prices in paise.
// Keep in sync with razorpay-webhook/index.ts and AppConstants in Flutter.
const MONTHLY_PAISE = 34900; // ₹349
const YEARLY_PAISE = 299900; // ₹2,999

/**
 * Derive the plan type from a Razorpay payment amount.
 *
 * 1. Exact match against full prices.
 * 2. If a promo code is present, compute discounted prices and match.
 * 3. Returns { plan, promoApplied, promoCode, originalPaise, discountPct }
 *    or null if no match.
 */
async function derivePlanFromAmount(
  amountPaise: number,
  promoCode: string | undefined,
  supabase: ReturnType<typeof createClient>,
): Promise<{
  plan: "monthly" | "yearly";
  promoApplied: boolean;
  promoCode: string | null;
  originalPaise: number;
  discountPct: number;
} | null> {
  // 1. Exact full-price match
  if (amountPaise === MONTHLY_PAISE) {
    return { plan: "monthly", promoApplied: false, promoCode: null, originalPaise: MONTHLY_PAISE, discountPct: 0 };
  }
  if (amountPaise === YEARLY_PAISE) {
    return { plan: "yearly", promoApplied: false, promoCode: null, originalPaise: YEARLY_PAISE, discountPct: 0 };
  }

  // 2. Promo-discounted price
  if (promoCode) {
    const { data: promo } = await supabase
      .from("promo_codes")
      .select("discount_pct, is_active, valid_until, max_uses, used_count")
      .eq("code", promoCode)
      .maybeSingle();

    if (promo) {
      // Tolerant validation: accept the discounted amount even if promo has
      // since expired or exhausted. The promo was valid when checkout opened;
      // Razorpay capture can take seconds to minutes. Rejecting a paid amount
      // over a race condition causes user complaints and refund hassles.
      const now = new Date();
      const validUntil = new Date(promo.valid_until);
      const isExpired = validUntil < now;
      const isExhausted = promo.max_uses !== null && (promo.used_count as number) >= (promo.max_uses as number);
      const isInactive = !promo.is_active;

      if (isExpired || isExhausted || isInactive) {
        console.warn(
          `Promo '${promoCode}' ${isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'} ` +
          `— honoring anyway (was valid at checkout time)`
        );
      }

      const pct = promo.discount_pct as number;
      const discountedMonthly = Math.round(MONTHLY_PAISE * (100 - pct) / 100);
      const discountedYearly = Math.round(YEARLY_PAISE * (100 - pct) / 100);

      if (amountPaise === discountedMonthly) {
        return { plan: "monthly", promoApplied: true, promoCode, originalPaise: MONTHLY_PAISE, discountPct: pct };
      }
      if (amountPaise === discountedYearly) {
        return { plan: "yearly", promoApplied: true, promoCode, originalPaise: YEARLY_PAISE, discountPct: pct };
      }
    }
  }

  return null; // No match
}

/**
 * Record promo code usage (non-fatal — subscription is already created).
 * Identical logic in razorpay-webhook/index.ts.
 */
async function redeemPromo(
  supabase: ReturnType<typeof createClient>,
  promoCode: string,
  userId: string,
  plan: string,
  originalPaise: number,
  discountPct: number,
  finalPaise: number,
) {
  try {
    // Atomically increment used_count
    await supabase.rpc("increment_promo_used_count", { p_code: promoCode });

    // Audit trail
    await supabase.from("promo_code_uses").insert({
      code: promoCode,
      user_id: userId,
      plan_purchased: plan,
      original_amount: originalPaise,
      discount_applied: originalPaise - finalPaise,
      final_amount: finalPaise,
    });
  } catch (e) {
    console.error("Non-fatal: promo redemption failed:", e);
  }
}

/**
 * Direct Razorpay payment verification Edge Function.
 *
 * Called by the Flutter app as a fallback when the webhook-based polling
 * fails to confirm a payment within the polling window.
 *
 * Flow:
 *   1. Receives { payment_id, plan? } with JWT auth
 *   2. Calls Razorpay GET /v1/payments/{id} with server credentials
 *   3. Derives plan from payment.amount (NOT from body.plan)
 *   4. If payment is captured → upserts subscription row
 *   5. Returns { verified, plan, end_date }
 */
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // ── Auth ────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userId = user.id;

    // ── Per-user rate limit (20 calls / 10 min) ─────────────────
    //
    // Protects Razorpay API quota from a runaway client that keeps
    // polling verify-payment on every tick. Added 2026-04-18 (audit
    // C4b). Counter lives in `ai_coach_interactions` with
    // channel='verify_payment_attempt' — reusing the existing table
    // so no schema change.
    const cutoff10Min = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { count: recentAttempts } = await supabase
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("channel", "verify_payment_attempt")
      .gte("created_at", cutoff10Min);

    if ((recentAttempts ?? 0) >= 20) {
      return new Response(
        JSON.stringify({
          error: "Too many verification attempts. Try again in a few minutes.",
          retry_after_seconds: 600,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": "600",
          },
        },
      );
    }

    // Record this attempt (fire-and-forget — never block on telemetry).
    supabase
      .from("ai_coach_interactions")
      .insert({
        user_id: userId,
        channel: "verify_payment_attempt",
        user_message: "[verify-payment]",
        ai_response: "",
        model_used: "n/a",
        tokens_used: 0,
      })
      .then((r: { error: unknown }) => {
        if (r.error) console.error("[verify-payment] attempt log failed:", r.error);
      });

    // ── Parse body ─────────────────────────────────────────────
    const body = await req.json();
    const paymentId = body.payment_id as string;
    // body.plan is accepted for backward compat but NOT trusted for entitlement.
    const clientClaimedPlan = (body.plan as string) || "";

    if (!paymentId) {
      return new Response(
        JSON.stringify({ error: "Missing payment_id" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Check if subscription already exists for THIS payment ──
    const { data: existingSub } = await supabase
      .from("subscriptions")
      .select("id, end_date, plan")
      .eq("user_id", userId)
      .eq("razorpay_payment_id", paymentId)
      .eq("status", "active")
      .maybeSingle();

    if (existingSub) {
      // Already activated (webhook beat us)
      return new Response(
        JSON.stringify({
          verified: true,
          plan: existingSub.plan,
          end_date: existingSub.end_date,
          source: "existing",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Call Razorpay API to verify payment ─────────────────────
    const credentials = base64Encode(
      new TextEncoder().encode(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`),
    );

    const razorpayResponse = await fetch(
      `https://api.razorpay.com/v1/payments/${paymentId}`,
      {
        method: "GET",
        headers: {
          Authorization: `Basic ${credentials}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!razorpayResponse.ok) {
      console.error(
        `Razorpay API error: ${razorpayResponse.status} ${razorpayResponse.statusText}`,
      );
      return new Response(
        JSON.stringify({
          verified: false,
          error: "Failed to verify with Razorpay",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let payment = await razorpayResponse.json();

    // If the payment is authorized but not captured (UPI test VPAs,
    // orders created without payment_capture: 1, rare live-mode wallet
    // delays), capture it now from the server side. Same capability the
    // razorpay-webhook gained on 2026-04-17 — keeps verify-payment
    // in lock-step so the client fallback path recovers too.
    if (payment.status === "authorized" && payment.captured === false) {
      const captureResp = await fetch(
        `https://api.razorpay.com/v1/payments/${paymentId}/capture`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${credentials}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            amount: payment.amount,
            currency: payment.currency ?? "INR",
          }),
        },
      );
      if (!captureResp.ok) {
        const body = await captureResp.text();
        console.error(
          `[verify-payment] capture failed for ${paymentId}: ${captureResp.status} ${body}`,
        );
        return new Response(
          JSON.stringify({
            verified: false,
            error: "Payment authorized but capture failed. Please try again.",
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      payment = await captureResp.json();
      console.log(`[verify-payment] auto-captured ${paymentId}`);
    }

    // Verify payment is captured
    if (payment.status !== "captured") {
      return new Response(
        JSON.stringify({
          verified: false,
          error: `Payment status is '${payment.status}', not 'captured'`,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify the user_id in notes matches the authenticated user
    const notesUserId = payment.notes?.user_id;
    if (notesUserId && notesUserId !== userId) {
      return new Response(
        JSON.stringify({
          verified: false,
          error: "Payment does not belong to this user",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Derive plan from payment amount (NOT from body.plan) ────
    const actualPaise = payment.amount as number;
    const promoCode = payment.notes?.promo_code as string | undefined;

    const derived = await derivePlanFromAmount(actualPaise, promoCode, supabase);
    if (!derived) {
      console.error(
        `Amount mismatch: ${actualPaise} paise does not match any plan` +
          (promoCode ? ` (promo: ${promoCode})` : ""),
      );
      return new Response(
        JSON.stringify({
          verified: false,
          error: "Payment amount does not match any known plan price",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const plan = derived.plan;

    // Log if client-claimed plan disagrees with derived plan
    if (clientClaimedPlan && clientClaimedPlan !== plan) {
      console.warn(
        `Plan mismatch: client claimed '${clientClaimedPlan}', derived '${plan}' from amount ${actualPaise}`,
      );
    }

    // ── Create subscription ─────────────────────────────────────
    const now = new Date();
    const endDate = new Date(now);
    if (plan === "yearly") {
      endDate.setDate(endDate.getDate() + 365);
    } else {
      endDate.setDate(endDate.getDate() + 30);
    }

    const { error: insertError } = await supabase
      .from("subscriptions")
      .upsert(
        {
          user_id: userId,
          plan,
          status: "active",
          start_date: now.toISOString(),
          end_date: endDate.toISOString(),
          razorpay_payment_id: paymentId,
          razorpay_order_id: payment.order_id ?? null,
          created_at: now.toISOString(),
        },
        { onConflict: "user_id,razorpay_payment_id" },
      );

    if (insertError) {
      // Try insert without onConflict (table may not have that unique constraint)
      const { error: insertError2 } = await supabase
        .from("subscriptions")
        .insert({
          user_id: userId,
          plan,
          status: "active",
          start_date: now.toISOString(),
          end_date: endDate.toISOString(),
          razorpay_payment_id: paymentId,
          razorpay_order_id: payment.order_id ?? null,
          created_at: now.toISOString(),
        });

      if (insertError2) {
        // H-18 (audit-2026-05-11) — detect 23505 unique-violation
        // and treat it as success. Concurrent webhook + verify-payment
        // race: the webhook may have already inserted the row by the
        // time verify-payment's fallback insert fires. Postgres
        // raises `unique_violation` (SQLSTATE 23505), which the
        // PostgREST client surfaces via `code: '23505'`. The row
        // already exists with the same (user_id, razorpay_payment_id);
        // returning verified=true is correct.
        const code =
          (insertError2 as { code?: string }).code ??
          (insertError2 as { details?: string }).details ??
          "";
        const isUniqueViolation =
          code === "23505" ||
          String(insertError2.message ?? "")
            .toLowerCase()
            .includes("duplicate key value violates unique constraint");
        if (isUniqueViolation) {
          console.log(
            "[verify-payment] H-18 — 23505 on fallback insert; webhook already wrote the row, treating as success.",
          );
          // Fall through — the row exists. Continue to users-table
          // update + success response.
        } else {
          console.error("Failed to insert subscription:", insertError2);
          return new Response(
            JSON.stringify({
              verified: true,
              error: "Payment verified but failed to create subscription record",
              plan,
              end_date: endDate.toISOString(),
            }),
            {
              status: 200,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // Update users table
    await supabase
      .from("users")
      .update({
        subscription_status: "pro",
        subscription_expires_at: endDate.toISOString(),
      })
      .eq("id", userId);

    // ── Redeem promo code if applied ────────────────────────────
    if (derived.promoApplied && derived.promoCode) {
      await redeemPromo(
        supabase,
        derived.promoCode,
        userId,
        plan,
        derived.originalPaise,
        derived.discountPct,
        actualPaise,
      );
    }

    return new Response(
      JSON.stringify({
        verified: true,
        plan,
        end_date: endDate.toISOString(),
        source: "razorpay_api",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / Razorpay API response.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[verify-payment] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
