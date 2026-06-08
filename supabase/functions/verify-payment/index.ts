/**
 * verify-payment — client-initiated payment verification after Razorpay checkout.
 *
 * Trigger: HTTP POST from the Flutter client immediately after Razorpay's
 *          WebView returns `payment.success`. The client polls this function
 *          until it returns `verified: true` (or `failed`) — the webhook is
 *          authoritative for subscription state, but the client also calls
 *          here to avoid waiting on webhook propagation.
 *
 * Input shape:
 *   {
 *     razorpay_payment_id: string,
 *     razorpay_order_id: string,
 *     razorpay_signature: string,   // client-side HMAC; we re-verify here
 *     plan: "monthly" | "yearly"
 *   }
 *
 * Output shape:
 *   200 { verified: true, subscription_status: "active", end_date: ISO }
 *   200 { verified: false, status: "pending" }   // webhook hasn't fired yet
 *   400 { error: "invalid_signature" | "amount_mismatch" | ... , request_id }
 *   409 { error: "already_pro", request_id }     // user already PRO (idempotent)
 *
 * Env secrets used:
 *   - RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET (signature verify + order fetch)
 *   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (subscriptions table writes)
 *
 * verify_jwt: true at deploy — the calling user MUST be authenticated.
 *
 * Idempotency: re-calling with the same payment_id after a successful verify
 * returns the same 200 payload. The 409 `already_pro` path exists for the case
 * where the webhook beat the client to the DB write.
 *
 * Canonical plan prices in paise are duplicated below; they MUST stay in sync
 * with `razorpay-webhook/index.ts` and `lib/core/constants/app_constants.dart`.
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as base64Encode } from "https://deno.land/std@0.224.0/encoding/base64.ts";

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

    // OI-29 (audit-2026-05-17 Hermes F4) — ownership check is now two-step.
    // Pre-fix `if (notesUserId && notesUserId !== userId)` was fail-open when
    // `notes.user_id` was absent — attacker who knows a captured payment_id
    // without notes could claim entitlement under their own JWT. Now we
    // require notes.user_id to be present AND to match.
    const notesUserId = payment.notes?.user_id;
    if (!notesUserId) {
      return new Response(
        JSON.stringify({
          verified: false,
          error: "Missing user_id in payment notes",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    if (notesUserId !== userId) {
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

    // OI-27 (audit-2026-05-17 Hermes F2) — `razorpay_signature` is NOT NULL
    // since migration 052 (2026-05-13). verify-payment validates via Razorpay
    // REST API (not HMAC), so we synthesize a sentinel marking the
    // verification mode. Without this both upsert + fallback insert below
    // throw 23502 not_null_violation on every fallback path after webhook
    // lag. Sentinel format `verified_via_api:<12-hex>` is grep-able for
    // later analytics on which subscriptions were created via this code path
    // vs the HMAC-verified webhook (which stores the real signature).
    const razorpaySignatureSentinel =
      "verified_via_api:" + paymentId.substring(0, 12);

    // F31/F33 (audit-2026-06-07): redeem-once + honest insert-failure handling.
    //
    // `weInsertedTheRow` gates the promo redemption below — the promo must be
    // redeemed exactly ONCE, by whichever path actually CREATED the subscription
    // row. The webhook redeems when IT inserts; verify-payment must NOT redeem
    // again when it merely finds the webhook's row (F31 — the double-redeem
    // over-counted used_count and duplicated the promo_code_uses audit row).
    //
    // The idempotency pre-SELECT mirrors razorpay-webhook's H-19 guard: a row
    // already present means the creator already redeemed any promo, so we skip
    // both the insert and the redemption (idempotent success).
    // Review d6b736 F1/F2: keep users.subscription_expires_at consistent with the
    // canonical subscriptions row (never re-anchor it to verify-time on a replay /
    // race), and surface a pre-SELECT DB error instead of silently treating it as
    // "no row".
    let weInsertedTheRow = false;
    let canonicalEndDateIso = endDate.toISOString();
    const { data: existingSub, error: preSelectError } = await supabase
      .from("subscriptions")
      .select("id, end_date")
      .eq("razorpay_payment_id", paymentId)
      .maybeSingle();
    if (preSelectError) {
      console.warn(
        `[verify-payment] idempotency pre-SELECT failed (continuing to insert): ${preSelectError.message}`,
      );
    }

    if (existingSub === null) {
      const { error: insertError } = await supabase
        .from("subscriptions")
        .insert({
          user_id: userId,
          plan,
          status: "active",
          start_date: now.toISOString(),
          end_date: endDate.toISOString(),
          razorpay_payment_id: paymentId,
          razorpay_order_id: payment.order_id ?? null,
          razorpay_signature: razorpaySignatureSentinel,
          created_at: now.toISOString(),
        });

      if (!insertError) {
        weInsertedTheRow = true;
      } else {
        // 23505 unique-violation = we lost the race to the webhook between the
        // pre-SELECT and the insert. The webhook owns the row AND the promo
        // redemption, so treat this as idempotent success WITHOUT redeeming.
        const code =
          (insertError as { code?: string }).code ??
          (insertError as { details?: string }).details ??
          "";
        const isUniqueViolation =
          code === "23505" ||
          String(insertError.message ?? "")
            .toLowerCase()
            .includes("duplicate key value violates unique constraint");
        if (!isUniqueViolation) {
          // F33: a REAL insert failure — the row was NOT written. Returning
          // verified:true here let the client grant PRO optimistically; it then
          // vanished on the next cold start (no row to restore). Return
          // verified:false + 500 so the client retries instead of trusting it.
          const failId = crypto.randomUUID().split("-")[0];
          console.error(
            `[verify-payment] subscription insert failed (non-23505) request_id=${failId}`,
            insertError,
          );
          return new Response(
            JSON.stringify({
              verified: false,
              error: "Could not record subscription; please retry",
              request_id: failId,
            }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        // The webhook owns the row; use ITS end_date for the users update so
        // users.subscription_expires_at stays consistent with the canonical row.
        const { data: raceRow } = await supabase
          .from("subscriptions")
          .select("end_date")
          .eq("razorpay_payment_id", paymentId)
          .maybeSingle();
        const raceEnd = (raceRow as { end_date?: string } | null)?.end_date;
        if (raceEnd) canonicalEndDateIso = raceEnd;
        console.log(
          "[verify-payment] 23505 race — webhook already wrote the row; not redeeming promo again.",
        );
      }
    } else {
      // Row already exists (webhook or a prior verify-payment). Use its canonical
      // end_date — do NOT re-anchor the expiry to this call's time.
      const existingEnd = (existingSub as { end_date?: string }).end_date;
      if (existingEnd) canonicalEndDateIso = existingEnd;
    }

    // Update users table — canonical expiry keeps users + subscriptions in sync.
    await supabase
      .from("users")
      .update({
        subscription_status: "pro",
        subscription_expires_at: canonicalEndDateIso,
      })
      .eq("id", userId);

    // ── Redeem promo code if applied (ONCE) ─────────────────────
    // F31: gate on weInsertedTheRow so a webhook-won race (or an already-present
    // row) does NOT redeem a second time — the creator path already did.
    if (derived.promoApplied && derived.promoCode && weInsertedTheRow) {
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
        end_date: canonicalEndDateIso,
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
