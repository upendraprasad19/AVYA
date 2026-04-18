import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as hexEncode } from "https://deno.land/std@0.177.0/encoding/hex.ts";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-razorpay-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Canonical plan prices in paise.
// Keep in sync with verify-payment/index.ts and AppConstants in Flutter.
const MONTHLY_PAISE = 34900; // ₹349
const YEARLY_PAISE = 299900; // ₹2,999

async function verifySignature(
  body: string,
  signature: string,
  secret: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const expectedSignature = new TextDecoder().decode(
    hexEncode(new Uint8Array(signed)),
  );
  return expectedSignature === signature;
}

/**
 * Compute the expected payment amount in paise for a given plan,
 * optionally adjusted by a valid promo code.
 *
 * Returns { expectedPaise, promoApplied, discountPct } or null if promo invalid.
 * Identical logic in verify-payment/index.ts.
 */
async function computeExpectedAmount(
  plan: string,
  promoCode: string | undefined,
  supabaseClient: ReturnType<typeof createClient>,
): Promise<{ expectedPaise: number; promoApplied: boolean; discountPct: number }> {
  const fullPrice = plan === "monthly" ? MONTHLY_PAISE : YEARLY_PAISE;

  if (!promoCode) {
    return { expectedPaise: fullPrice, promoApplied: false, discountPct: 0 };
  }

  // Look up promo code in database
  const { data: promo } = await supabaseClient
    .from("promo_codes")
    .select("discount_pct, is_active, valid_until, max_uses, used_count")
    .eq("code", promoCode)
    .maybeSingle();

  if (!promo) {
    console.warn(`Promo code '${promoCode}' not found — using full price`);
    return { expectedPaise: fullPrice, promoApplied: false, discountPct: 0 };
  }

  // Tolerant validation: accept the discounted amount even if promo has since
  // expired or exhausted, as long as the promo EXISTS and the discount math
  // matches. The promo was valid when the user started checkout; Razorpay
  // capture can take seconds to minutes. Rejecting a paid amount over a race
  // condition causes user complaints and refund hassles.
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
  const discountedPrice = Math.round(fullPrice * (100 - pct) / 100);
  return { expectedPaise: discountedPrice, promoApplied: true, discountPct: pct };
}

/**
 * Record promo code usage (non-fatal — subscription is already created).
 * Identical logic in verify-payment/index.ts.
 */
async function redeemPromo(
  supabaseClient: ReturnType<typeof createClient>,
  promoCode: string,
  userId: string,
  plan: string,
  originalPaise: number,
  discountPct: number,
  finalPaise: number,
) {
  try {
    // Atomically increment used_count
    await supabaseClient.rpc("increment_promo_used_count", { p_code: promoCode });

    // Audit trail
    await supabaseClient.from("promo_code_uses").insert({
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
    const rawBody = await req.text();
    const signature = req.headers.get("x-razorpay-signature");

    // MANDATORY: Verify HMAC-SHA256 signature
    if (!signature) {
      return new Response(
        JSON.stringify({ error: "Missing x-razorpay-signature header" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const isValid = await verifySignature(rawBody, signature, RAZORPAY_KEY_SECRET);
    if (!isValid) {
      console.error("Invalid Razorpay signature");
      return new Response(
        JSON.stringify({ error: "Invalid signature" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const payload = JSON.parse(rawBody);

    // Razorpay sends event-based webhooks. We handle two events:
    //   - payment.captured: the normal happy path (money moved, we record)
    //   - payment.authorized: UPI/wallet payment that auth'd but wasn't
    //     auto-captured by Razorpay. Happens in test mode and occasionally
    //     in live mode when the payment was created WITHOUT
    //     `payment_capture: 1` at order time. We call Razorpay's capture
    //     API server-side, then proceed as if it were captured. This is
    //     the belt-and-braces fix for the 2026-04-17 stuck-payment bug.
    const event = payload.event;
    if (event !== "payment.captured" && event !== "payment.authorized") {
      // Acknowledge non-payment events without processing
      return new Response(JSON.stringify({ status: "ignored", event }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const paymentEntity = payload.payload?.payment?.entity;
    if (!paymentEntity) {
      return new Response(JSON.stringify({ error: "Missing payment entity" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Replay protection — reject webhooks older than 5 minutes.
    //
    // Razorpay's own retry policy sends webhooks within seconds (and
    // re-fires failures for up to 24h, but each retry bumps the event's
    // created_at forward). Anything 5+ minutes old reaching us here is
    // either (a) a replay attack by an adversary who captured a valid
    // webhook request, or (b) a delayed webhook for an event our
    // idempotency (pre-SELECT + 23505 catch) has already processed.
    // Both cases are safe to reject. `paymentEntity.created_at` is epoch
    // seconds (Razorpay standard). If the field is missing we skip the
    // check (defensive — never fail closed on missing telemetry).
    const createdAtSec = paymentEntity.created_at as number | undefined;
    if (typeof createdAtSec === "number" && createdAtSec > 0) {
      const ageSec = Math.abs(Date.now() / 1000 - createdAtSec);
      if (ageSec > 300) {
        console.warn(
          `[razorpay-webhook] rejecting replay: payment_id=${paymentEntity.id} age=${Math.round(ageSec)}s`,
        );
        return new Response(
          JSON.stringify({ error: "Webhook too old", age_seconds: Math.round(ageSec) }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    const razorpayOrderId = paymentEntity.order_id;
    const razorpayPaymentId = paymentEntity.id;
    const razorpaySignature = signature;

    // If this is a payment.authorized event, capture the payment now so
    // it becomes final. Razorpay will fire a second payment.captured
    // event after our capture call, which we handle idempotently below
    // (UNIQUE(razorpay_payment_id) on subscriptions makes the second
    // webhook a no-op).
    if (event === "payment.authorized" && paymentEntity.captured === false) {
      if (!RAZORPAY_KEY_ID) {
        console.error(
          "[razorpay-webhook] RAZORPAY_KEY_ID missing — cannot auto-capture authorized payment",
        );
        return new Response(
          JSON.stringify({
            error: "Server mis-config: cannot auto-capture",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      try {
        const credentials = base64Encode(
          new TextEncoder().encode(
            `${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`,
          ),
        );
        const captureResp = await fetch(
          `https://api.razorpay.com/v1/payments/${razorpayPaymentId}/capture`,
          {
            method: "POST",
            headers: {
              "Authorization": `Basic ${credentials}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              amount: paymentEntity.amount,
              currency: paymentEntity.currency ?? "INR",
            }),
          },
        );
        if (!captureResp.ok) {
          const body = await captureResp.text();
          console.error(
            `[razorpay-webhook] capture failed for ${razorpayPaymentId}: ${captureResp.status} ${body}`,
          );
          // Don't fail the whole webhook — Razorpay will retry
          // payment.authorized; next try may succeed. Return 5xx so
          // Razorpay keeps retrying.
          return new Response(
            JSON.stringify({ error: "Capture failed, will retry" }),
            {
              status: 502,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        console.log(
          `[razorpay-webhook] auto-captured authorized payment ${razorpayPaymentId}`,
        );
        // We continue below to write the subscription. Razorpay will also
        // send payment.captured later — that call will hit the UNIQUE
        // constraint and be a no-op (idempotent).
      } catch (e) {
        console.error(`[razorpay-webhook] capture threw for ${razorpayPaymentId}:`, e);
        return new Response(
          JSON.stringify({ error: "Capture failed, will retry" }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Extract user_id and plan from notes (set during checkout creation)
    const notes = paymentEntity.notes ?? {};
    const userId = notes.user_id;
    const plan = notes.plan; // 'monthly' or 'yearly'
    const promoCode = notes.promo_code as string | undefined;

    if (!userId || !plan) {
      console.error("Missing user_id or plan in payment notes:", notes);
      return new Response(
        JSON.stringify({ error: "Missing user_id or plan in payment notes" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate userId is a proper UUID to prevent injection / spoofing.
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(userId)) {
      console.error("Invalid user_id format in payment notes:", userId);
      return new Response(
        JSON.stringify({ error: "Invalid user_id format" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (plan !== "monthly" && plan !== "yearly") {
      return new Response(
        JSON.stringify({ error: "Invalid plan. Must be 'monthly' or 'yearly'" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Validate payment amount matches expected plan price (promo-aware).
    // HMAC signature proves payload authenticity; this guards against
    // Razorpay-side bugs, test-mode exploits, or illegitimate discounts.
    const { expectedPaise, promoApplied, discountPct } =
      await computeExpectedAmount(plan, promoCode, supabaseClient);
    const actualPaise = paymentEntity.amount;

    if (typeof actualPaise === "number" && actualPaise !== expectedPaise) {
      console.error(
        `Amount mismatch: expected ${expectedPaise} paise for ${plan}` +
          (promoCode ? ` (promo: ${promoCode}, ${discountPct}% off)` : "") +
          `, got ${actualPaise}`,
      );
      return new Response(
        JSON.stringify({ error: "Payment amount does not match plan price" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const now = new Date();
    const endDate = new Date(now);

    if (plan === "monthly") {
      endDate.setDate(endDate.getDate() + 30);
    } else {
      endDate.setDate(endDate.getDate() + 365);
    }

    // ── Idempotency ────────────────────────────────────────────
    // Razorpay retries webhooks on their side (~3 attempts over ~1 hour)
    // if our 200 is slow or lost. Without idempotency each retry would
    // create a duplicate subscription row and double the user's PRO
    // duration. UNIQUE constraint on razorpay_payment_id (migration 010)
    // lets us upsert with ignoreDuplicates. If a row already exists for
    // this payment_id we skip the insert entirely but still proceed to
    // promo redemption / users.subscription_status update (safe because
    // those are idempotent themselves: RPC uses `used_count + 1` under
    // the promo_code_uses audit row which is write-once, and the users
    // update is a pure upsert of the same (status, end_date) pair).
    const { data: existing } = await supabaseClient
      .from("subscriptions")
      .select("id")
      .eq("razorpay_payment_id", razorpayPaymentId)
      .maybeSingle();

    const alreadyProcessed = existing !== null;
    if (alreadyProcessed) {
      console.log(
        `Idempotent webhook: payment ${razorpayPaymentId} already recorded, skipping insert`,
      );
    } else {
      const { error: insertError } = await supabaseClient
        .from("subscriptions")
        .insert({
          user_id: userId,
          plan,
          status: "active",
          start_date: now.toISOString(),
          end_date: endDate.toISOString(),
          razorpay_order_id: razorpayOrderId,
          razorpay_payment_id: razorpayPaymentId,
          razorpay_signature: razorpaySignature,
          created_at: now.toISOString(),
        });

      // 23505 = unique_violation (Postgres). A concurrent webhook racer
      // beat us to the insert — not an error, the row exists either way.
      if (insertError && insertError.code !== "23505") {
        console.error("Failed to insert subscription:", insertError);
        return new Response(
          JSON.stringify({ error: "Failed to create subscription record" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Update users table
    const { error: updateError } = await supabaseClient
      .from("users")
      .update({
        subscription_status: "pro",
        subscription_expires_at: endDate.toISOString(),
      })
      .eq("id", userId);

    if (updateError) {
      console.error("Failed to update user subscription status:", updateError);
      return new Response(
        JSON.stringify({ error: "Subscription created but failed to update user status" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Redeem promo code if applied ────────────────────────────
    // Skip on idempotent replay — increment_promo_used_count is NOT
    // idempotent and would double-count the redemption against
    // promo_codes.used_count.
    if (!alreadyProcessed && promoApplied && promoCode) {
      const fullPrice = plan === "monthly" ? MONTHLY_PAISE : YEARLY_PAISE;
      await redeemPromo(
        supabaseClient,
        promoCode,
        userId,
        plan,
        fullPrice,
        discountPct,
        actualPaise,
      );
    }

    return new Response(
      JSON.stringify({
        status: "success",
        user_id: userId,
        plan,
        expires_at: endDate.toISOString(),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL / signature text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[razorpay-webhook] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
