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
 *   200 { verified: true, plan, end_date: ISO, source }
 *   200 { verified: false, error }               // not captured; OR a replay whose stored row is not
 *                                                //   `active` ("Subscription for this payment is not active");
 *                                                //   OR a replay whose row cannot be read ("Could not
 *                                                //   confirm this payment yet; please retry") (OI-410)
 *   400/401/403/405/429/502 { error, ... }       // validation, auth, ownership, method, rate limit, Razorpay
 *   500 { error[, verified: false], request_id } // the row could not be recorded (client retries) / catch-all
 *
 * Env secrets used:
 *   - RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET (signature verify + order fetch)
 *   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (subscriptions table writes)
 *
 * verify_jwt: true at deploy — the calling user MUST be authenticated.
 *
 * Idempotency: re-calling with the same payment_id replays the stored row. A replay
 * answers `verified: true` ONLY after this request has read that row as `active`
 * (the early read filters on it; the three replay arms below go through
 * `replayGate` / `replayVerdict`, OI-410). A row that exists but is not `active`
 * answers the soft failure above, and a replay whose row cannot be read is
 * "unconfirmed", never `verified: true`. The webhook may beat the client to the DB
 * write; that active row is the normal replay.
 *
 * Canonical plan prices in paise are duplicated below; they MUST stay in sync
 * with `razorpay-webhook/index.ts` and `lib/core/constants/app_constants.dart`.
 */
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import {
  isStackingEnabled,
  isValidPaymentId,
  plainEndDate,
  recordPaidSubscription,
} from "../_shared/subscription_stacking.ts";
import { checkStackingMismatch, reportPaymentRecordFailure } from "../_shared/payment_alert.ts";
import { boundedText, codeToken, errorName, pgErrorCode, razorpayErrorSummary, stackFrames } from "../_shared/payment_log_safe.ts";

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
  supabase: SupabaseClient,
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
          `Promo ${boundedText(promoCode)} ${isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'} ` +
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
  supabase: SupabaseClient,
  promoCode: string,
  userId: string,
  plan: string,
  originalPaise: number,
  discountPct: number,
  finalPaise: number,
) {
  try {
    // Atomically increment used_count. supabase-js RETURNS its errors (it does not throw them), so each
    // call's error is checked and logged by label and code (R-6, payment-hardening U0): used_count gates
    // promo exhaustion at order time (U3), so a silent failure here is a promo that never runs out.
    const { error: incErr } = await supabase.rpc("increment_promo_used_count", { p_code: promoCode });
    if (incErr) {
      console.error(`[verify-payment] promo redemption: increment_promo_used_count failed code=${pgErrorCode(incErr)}`);
    }

    // Audit trail
    const { error: useErr } = await supabase.from("promo_code_uses").insert({
      code: promoCode,
      user_id: userId,
      plan_purchased: plan,
      original_amount: originalPaise,
      discount_applied: originalPaise - finalPaise,
      final_amount: finalPaise,
    });
    if (useErr) {
      // 23505 = UNIQUE(code, user_id) (migration 025): this user used the code before and the audit row exists.
      // Expected on a repeat purchase, so not an error line (hermes H9).
      if (pgErrorCode(useErr) === "23505") {
        console.log(`[verify-payment] promo redemption: repeat use by this user, audit row already exists`);
      } else {
        console.error(`[verify-payment] promo redemption: promo_code_uses insert failed code=${pgErrorCode(useErr)}`);
      }
    }
  } catch (e) {
    console.error(`[verify-payment] promo redemption threw (non-fatal): ${errorName(e)} code=${pgErrorCode(e)}`);
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
export async function handler(req: Request): Promise<Response> {
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
    // C4b); moved onto usage_counters OI-162 slice 4 (f2c8d5).
    // `consume_quota()` CHECKS and INCREMENTS atomically — one call
    // replaces the old count-then-insert pair, which was non-atomic AND
    // (before this fix) read `{ count }` only, never `{ error }`, so a
    // counter-query failure silently proceeded as if under the limit
    // (fail-open BY OMISSION, not by design — unlike delete-account's
    // documented fail-open above, which IS deliberate).
    //
    // FAILS CLOSED here, unlike delete-account: this endpoint is a
    // background confirmation step, not the primary activation path — PRO
    // unlocks OPTIMISTICALLY in Hive the instant Razorpay reports success
    // (razorpay_service.dart, "Fix 2 · OPTIMISTIC LOCAL ACTIVATION"), the
    // webhook is an independent authoritative path, and the client retries
    // this call at 60s/5m/15m regardless. A refused call here costs almost
    // nothing user-visible; a fail-open call under a correlated Postgres
    // hiccup releases the exact brake this limit exists to protect, at the
    // exact moment a retry storm is most dangerous to the Razorpay quota.
    const RATE_LIMIT_MAX = 20;
    const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000; // 10 minutes, FIXED bucket
    const RATE_LIMIT_QUOTA_KEY = "verify_payment";
    // Hermes L21 F3 (2026-09-11): deliberately UTC epoch-floor, not IST —
    // see delete-account/index.ts's identical note for the full reasoning
    // (also diagnose f2c8d5's `ist_handling` field). Same shape here: a
    // sub-day bucket with no user-visible reset, so duration (timezone-
    // invariant) is the only observable property, not a calendar boundary.
    const bucketStartMs =
      Math.floor(Date.now() / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
    const bucketStart = new Date(bucketStartMs).toISOString();
    const { data: usedCount, error: rateErr } = await supabase.rpc(
      "consume_quota",
      {
        p_user_id: userId,
        p_quota_key: RATE_LIMIT_QUOTA_KEY,
        p_window_start: bucketStart,
        p_limit: RATE_LIMIT_MAX,
      },
    );

    if (rateErr) {
      console.error(
        `[verify-payment] consume_quota FAILED for user=${userId} (fail-closed): code=${pgErrorCode(rateErr)}`,
      );
      return new Response(
        JSON.stringify({ error: "Rate limit check failed. Try again shortly." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // consume_quota answers -1 or a count >= 1; anything else is an unreadable counter (fail CLOSED too;
    // payment-hardening B-pass beee28f0d9f2 finding 6).
    if (!Number.isInteger(usedCount) || (usedCount < 1 && usedCount !== -1)) {
      console.error(
        `[verify-payment] consume_quota FAILED for user=${userId} (fail-closed): code=bad_result`,
      );
      return new Response(
        JSON.stringify({ error: "Rate limit check failed. Try again shortly." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (usedCount === -1) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((bucketStartMs + RATE_LIMIT_WINDOW_MS - Date.now()) / 1000),
      );
      // Hermes L29 F2 (2026-09-11): this refusal had NO server-side log —
      // an operator watching prod has zero visibility into how often the
      // 20/10min limit actually fires, which matters for tuning it and for
      // spotting abuse. Mirrors delete-account's equivalent warn (this
      // file's own fail-closed branch above already logs `user=${userId}`
      // in the same style — no request_id is computed this early in this
      // file, unlike delete-account, so this matches the LOCAL convention).
      console.warn(
        `[verify-payment] user=${userId} rate-limited ` +
          `(quota_key=${RATE_LIMIT_QUOTA_KEY}, limit=${RATE_LIMIT_MAX})`,
      );
      return new Response(
        JSON.stringify({
          error: "Too many verification attempts. Try again in a few minutes.",
          retry_after_seconds: retryAfterSeconds,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": String(retryAfterSeconds),
          },
        },
      );
    }

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

    // OI-341 Piece A (plan 2.4): the id is interpolated into the Razorpay API
    // URLs below and into a PostgREST logic tree by the stacking read, and is
    // stored verbatim in a UNIQUE column that only dedupes the exact string.
    // Every real Razorpay id is `pay_` + alphanumerics; not switch-gated.
    if (!isValidPaymentId(paymentId)) {
      return new Response(
        JSON.stringify({ error: "Invalid payment_id" }),
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
      `${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`,
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
        `Razorpay API error: ${razorpayResponse.status} ${boundedText(razorpayResponse.statusText)}`,
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

    // OI-350 / OI-359 (payment-hardening U1, 2026-10-24): the ownership guards run FIRST, directly
    // after the GET and before the capture and the status echo. Before this, another user's AUTHORIZED
    // payment was captured by this caller and any payment's status was echoed with a 200; the 403
    // only came once the payment was captured. The GET above is a read; nothing before this point
    // touches anything that is not the caller's.
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
          `[verify-payment] capture failed for ${paymentId}: ${razorpayErrorSummary(captureResp.status, body)}`,
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

    // ── Derive plan from payment amount (NOT from body.plan) ────
    const actualPaise = payment.amount as number;
    const promoCode = payment.notes?.promo_code as string | undefined;

    const derived = await derivePlanFromAmount(actualPaise, promoCode, supabase);
    if (!derived) {
      console.error(
        `Amount mismatch: ${actualPaise} paise does not match any plan payment_id=${paymentId}` +
          (promoCode ? ` (promo: ${boundedText(promoCode)})` : ""),
      );
      // OI-341 Piece B2a (hermes seat 4 F4): a captured payment of this caller
      // (ownership is checked above) that no row can record: page it. The
      // response is unchanged.
      await reportPaymentRecordFailure(supabase, {
        fn: "verify-payment",
        requestId: crypto.randomUUID().split("-")[0],
        paymentId,
        userId,
        plan: "unknown",
        amountPaise: actualPaise,
        code: "amount_no_match",
      });
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
        `Plan mismatch: client claimed ${boundedText(clientClaimedPlan)}, derived '${plan}' from amount ${actualPaise}`,
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
    // The idempotency pre-SELECT mirrors razorpay-webhook's H-19 skip but gates the answer
    // on ACTIVE: an ACTIVE row already present means the creator already redeemed any promo,
    // so we skip the insert and the redemption (non-active: OI-410, see replayGate).
    // Review d6b736 F1/F2: report the canonical subscriptions row's end_date
    // (never re-anchor it to verify-time on a replay / race), and surface a
    // pre-SELECT DB error instead of silently treating it as "no row".
    let weInsertedTheRow = false;
    let canonicalEndDateIso = endDate.toISOString();
    // NB: a different `existingSub` (active-only, early-return) is declared near
    // the top of this handler — this idempotency pre-SELECT MUST use a distinct
    // name or the duplicate `const` is a module-load SyntaxError (Hermes L21/L36).
    // Hermes L23 (2026-09-11, PARTIAL — not independently exploitable: by
    // this point `payment.notes.user_id === userId` is already enforced
    // above, so `paymentId` is already proven to belong to this caller).
    // `.eq("user_id", userId)` added anyway as defense-in-depth — cheap, and
    // guards this read even if a future refactor ever reordered the checks
    // above or reached this line by a path that skipped them.
    const { data: paymentSubRow, error: preSelectError } = await supabase
      .from("subscriptions")
      .select("id, end_date, status")
      .eq("razorpay_payment_id", paymentId)
      .eq("user_id", userId)
      .maybeSingle();
    if (preSelectError) {
      console.warn(
        `[verify-payment] idempotency pre-SELECT failed (continuing to insert): code=${pgErrorCode(preSelectError)}`,
      );
    }

    // OI-341: the stacking switch is read ONCE per request (exactly "true"; absent = OFF).
    const stackingOn = isStackingEnabled();
    // OI-341 Piece B2a (plan 2.3): which state this isolate read, for every payment that reaches the insert branch.
    if (paymentSubRow === null) {
      console.log(`[verify-payment] stacking_switch=${stackingOn ? "on" : "off"} payment_id=${paymentId}`);
    }
    // Set only when the OFF branch itself inserted the row: the mismatch alarm's precondition (plan 2.5).
    let offInserted: { start: string; end: string } | null = null;

    if (paymentSubRow === null && stackingOn) {
      // OI-341 Piece B1 ON path: ONE call to public.record_paid_subscription
      // (migration 161), which takes the per-user lock shared with the referral
      // redeem and job, re-checks idempotency, stacks on the latest active end and
      // inserts in one transaction. It absorbs the 23505 race the OFF branch
      // handles below, so `inserted` decides promo ownership. A failure answers
      // the existing 500 (the client retries), logs the reconcile line and pages.
      const rec = await recordPaidSubscription(supabase, {
        userId,
        plan,
        paymentId,
        orderId: payment.order_id ?? null,
        signature: razorpaySignatureSentinel,
      });
      if (!rec.ok) {
        const stackFailId = crypto.randomUUID().split("-")[0];
        console.error(
          `[verify-payment] stacking read failed request_id=${stackFailId} ` +
            `payment_id=${paymentId} user_id=${userId} plan=${plan} amount_paise=${actualPaise} code=${codeToken(rec.code)}`,
        );
        await reportPaymentRecordFailure(supabase, {
          fn: "verify-payment",
          requestId: stackFailId,
          paymentId,
          userId,
          plan,
          amountPaise: actualPaise,
          code: rec.code,
        });
        return new Response(
          JSON.stringify({
            verified: false,
            error: "Could not record subscription; please retry",
            request_id: stackFailId,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      canonicalEndDateIso = rec.endDate.toISOString();
      weInsertedTheRow = rec.inserted;
      console.log(
        `[verify-payment] stacking=on payment_id=${paymentId} inserted=${rec.inserted}`,
      );
      if (!rec.inserted) {
        // The rpc returned a STORED row whatever its status (migration 161, idempotency fast
        // path); this request did not insert it, so it must read it as `active` (OI-410).
        const { data: storedRow, error: storedError } = await supabase
          .from("subscriptions")
          .select("status")
          .eq("razorpay_payment_id", paymentId)
          .eq("user_id", userId)
          .maybeSingle();
        const refused = replayGate(storedRow, storedError, paymentId);
        if (refused) return refused;
      }
    } else if (paymentSubRow === null) {
      // OFF branch (the default): exactly `now + days`; the insert and its 23505
      // handling are today's code. Its one added request is the mismatch alarm
      // after the promo (Piece B2a plan 2.5), which never changes the response.
      const storedEnd = plainEndDate(now, plan === "yearly" ? 365 : 30);
      // Seeded BEFORE the insert: the response reports the value this call stored when the insert succeeds.
      // (d6b736 F2 also used it when a 23505 winner's row could not be re-read; since OI-410 that case is
      // `unconfirmed` and answers a soft failure instead.)
      canonicalEndDateIso = storedEnd.toISOString();
      const { error: insertError } = await supabase
        .from("subscriptions")
        .insert({
          user_id: userId,
          plan,
          status: "active",
          start_date: now.toISOString(),
          end_date: storedEnd.toISOString(),
          razorpay_payment_id: paymentId,
          razorpay_order_id: payment.order_id ?? null,
          razorpay_signature: razorpaySignatureSentinel,
          created_at: now.toISOString(),
        });

      if (!insertError) {
        weInsertedTheRow = true;
        offInserted = { start: now.toISOString(), end: storedEnd.toISOString() };
      } else {
        // 23505 unique-violation = we lost the race to the webhook between the
        // pre-SELECT and the insert. The webhook owns the row AND the promo
        // redemption, so an ACTIVE winner is idempotent success WITHOUT redeeming.
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
          // The reconcile fields of the stacking line above under this branch's OWN prefix (money is captured
          // and no row exists, so the ids stay); never the error object, whose `details` echoes the row.
          console.error(
            `[verify-payment] subscription insert failed (non-23505) request_id=${failId} ` +
              `payment_id=${paymentId} user_id=${userId} plan=${plan} amount_paise=${actualPaise} ` +
              `code=${pgErrorCode(insertError)}`,
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
        // The webhook owns the row; report ITS end_date so the response
        // matches the canonical row.
        const { data: raceRow, error: raceError } = await supabase
          .from("subscriptions")
          .select("end_date, status")
          .eq("razorpay_payment_id", paymentId)
          .eq("user_id", userId)
          .maybeSingle();
        // OI-410: the winner's row must read back as `active`; a non-active row, or one that
        // cannot be read, is a soft failure, not the seeded `verified: true` of d6b736 F2.
        const refused = replayGate(raceRow, raceError, paymentId);
        if (refused) return refused;
        const raceEnd = (raceRow as { end_date?: string } | null)?.end_date;
        if (raceEnd) canonicalEndDateIso = raceEnd;
        console.log(
          "[verify-payment] 23505 race — webhook already wrote the row; not redeeming promo again.",
        );
      }
    } else {
      // Row already exists (webhook or a prior verify-payment). It answers
      // `verified: true` only if it is `active` (OI-410: a cancelled/expired row for this
      // payment is not a verification). A failed pre-select leaves `paymentSubRow` null and
      // goes to the insert branch above, whose two replay doors check the same thing.
      const refused = replayGate(paymentSubRow, null, paymentId);
      if (refused) return refused;
      // Use its canonical end_date — do NOT re-anchor the expiry to this call's time.
      const existingEnd = (paymentSubRow as { end_date?: string }).end_date;
      if (existingEnd) canonicalEndDateIso = existingEnd;
    }

    // OI-202: no `users` mirror write. users.subscription_status /
    // users.subscription_expires_at are dropped (migration 152); the
    // `subscriptions` row written above (or already present) is the only
    // entitlement record. `canonicalEndDateIso` is still what the response
    // reports, so the client sees the canonical row's end_date.

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

    // OI-341 Piece B2a (plan 2.5): the switch-mismatch alarm, after the promo so
    // it can never skip it. Only when THIS request's OFF branch inserted the row
    // (not the existing-row path, not the 23505 race arm, not the ON path). It
    // detects and pages; it never changes the row or this response.
    if (offInserted !== null) {
      await checkStackingMismatch(supabase, {
        fn: "verify-payment",
        paymentId,
        userId,
        plan,
        rowStart: offInserted.start,
        rowEnd: offInserted.end,
      });
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
    // Name and frames only (hermes H10): a req.json() SyntaxError's message quotes the request body.
    console.error(`[verify-payment] request_id=${requestId} unhandled ${errorName(err)} at ${stackFrames(err)}`);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
}

// ── OI-410: what a REPLAY arm may answer about a stored row it did not insert ──
// `verified: true` for a row this request did not insert needs a read, in THIS request, that
// saw `status === "active"`. Strict equality like the early read's `.eq("status", "active")`:
// `null`, "", "ACTIVE", cancelled, expired, refunded and any future value are `not_active`.
// An absent row or a failed read is `unconfirmed` (fail safe: the client retries; no 500 path).
export type ReplayVerdict = "ok" | "not_active" | "unconfirmed";
export function replayVerdict(row: unknown, readFailed: boolean): ReplayVerdict {
  if (readFailed || row == null || typeof row !== "object") return "unconfirmed";
  return (row as { status?: unknown }).status === "active" ? "ok" : "not_active";
}

/** `null` when the replay may proceed (the row read back as active); else the soft-failure response. */
function replayGate(row: unknown, readError: unknown, paymentId: string): Response | null {
  const verdict = replayVerdict(row, readError != null);
  if (verdict === "ok") return null;
  const headers = { ...corsHeaders, "Content-Type": "application/json" };
  if (verdict === "not_active") {
    const rowStatus = (row as { status?: unknown }).status;
    console.log(
      `[verify-payment] replay refused, row not active payment_id=${paymentId} status=${codeToken(rowStatus)}`,
    );
    return new Response(
      JSON.stringify({ verified: false, error: "Subscription for this payment is not active" }),
      { status: 200, headers },
    );
  }
  console.warn(
    `[verify-payment] replay unconfirmed payment_id=${paymentId} code=${pgErrorCode(readError)}`,
  );
  return new Response(
    JSON.stringify({ verified: false, error: "Could not confirm this payment yet; please retry" }),
    { status: 200, headers },
  );
}

// `serve()` only when run as the entrypoint, so tests can import `handler`
// without binding a port (OI-341 Piece A, plan 2.3).
if (import.meta.main) serve(handler);
