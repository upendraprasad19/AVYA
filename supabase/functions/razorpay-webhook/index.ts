/**
 * razorpay-webhook — Razorpay → Supabase payment lifecycle reconciliation.
 *
 * Trigger: HTTP POST from Razorpay webhook (configured in Razorpay dashboard).
 *          NOT user-invoked. Webhook URL is the public function URL.
 *
 * Input shape: standard Razorpay webhook envelope —
 *   { event: "payment.captured" | "subscription.activated" | "subscription.cancelled" | ...,
 *     payload: { payment: {...} | subscription: {...} },
 *     created_at: number }
 *   Plus the `X-Razorpay-Signature` HMAC-SHA256 header, verified below at
 *   `verifySignature(rawBody, signature, RAZORPAY_KEY_SECRET)`.
 *
 *   ⚠ THE DASHBOARD WEBHOOK SECRET **IS** `RAZORPAY_KEY_SECRET`. This block
 *   previously said the opposite ("NOT the Razorpay key secret; separate
 *   value") and listed a `RAZORPAY_WEBHOOK_SECRET` env var that is read
 *   NOWHERE in this repo. Prod worked only because the configured dashboard
 *   secret happened to equal the key secret.
 *   When creating the LIVE-mode webhook, Razorpay prompts for a secret: enter
 *   the live `RAZORPAY_KEY_SECRET` verbatim. Generating a distinct value makes
 *   every live payment fail this HMAC with a 400 — silently, with no crash and
 *   no user ever upgraded to PRO. Open since 2026-06-11
 *   (`docs/audit/2026_06_11_audit_closures.yaml:93`).
 *
 * Output shape: 200 `{ ok: true }` on success / processed.
 *               400 on signature mismatch or malformed body (no PII).
 *               5xx on transient DB / Razorpay API errors — Razorpay retries.
 *
 * Env secrets used:
 *   - RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET (Authorization for outbound API calls)
 *   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (DB writes to subscriptions, payment_audit_log)
 *
 * verify_jwt: false (Razorpay does not send JWT; we authenticate via signature).
 *
 * Idempotency: keyed on `razorpay_payment_id` + event type. Re-delivery of the
 * same event is a no-op; we UPSERT into `payment_audit_log` first and bail if
 * the row already reflects the terminal state. See diagnose-docs referenced from
 * CLAUDE.md §4.4 rule 19 (server-side subscription verification) for the full
 * payment hardening history (TDZ bugs OI-26/27/29, audit Hermes Phase A→D).
 */
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as hexEncode } from "https://deno.land/std@0.177.0/encoding/hex.ts";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import {
  isEnvExactlyTrue,
  isStackingEnabled,
  isValidPaymentId,
  plainEndDate,
  recordPaidSubscription,
} from "../_shared/subscription_stacking.ts";
import { checkStackingMismatch, reportPaymentRecordFailure } from "../_shared/payment_alert.ts";
import { boundedText, codeToken, errorName, notesShape, pgErrorCode, razorpayErrorSummary } from "../_shared/payment_log_safe.ts";

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

// Replay windows per event (OI-341 Piece B2a, plan 2.6; see the replay block in the handler).
const CAPTURED_MAX_AGE_SEC = 24 * 3600 + 600;
const AUTHORIZED_MAX_AGE_SEC = 300;

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
 * Derive the plan type from a Razorpay payment amount.
 *
 * 1. Exact match against full prices.
 * 2. If a promo code is present, compute discounted prices and match.
 * 3. Returns { plan, promoApplied, promoCode, originalPaise, discountPct }
 *    or null if no match.
 *
 * Mirrored from verify-payment/index.ts — keep in sync.
 */
async function derivePlanFromAmount(
  amountPaise: number,
  promoCode: string | undefined,
  supabaseClient: SupabaseClient,
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
    const { data: promo } = await supabaseClient
      .from("promo_codes")
      .select("discount_pct, is_active, valid_until, max_uses, used_count")
      .eq("code", promoCode)
      .maybeSingle();

    if (promo) {
      // Tolerant: honour the discounted amount even if the promo has since
      // expired or exhausted — it was valid when checkout opened.
      const now = new Date();
      const isExpired = new Date(promo.valid_until) < now;
      const isExhausted = promo.max_uses !== null && (promo.used_count as number) >= (promo.max_uses as number);
      const isInactive = !promo.is_active;

      if (isExpired || isExhausted || isInactive) {
        console.warn(
          `[razorpay-webhook] Promo ${boundedText(promoCode)} ${isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'} ` +
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
 * Compute the expected payment amount in paise for a given plan,
 * optionally adjusted by a valid promo code.
 *
 * Returns { expectedPaise, promoApplied, discountPct } or null if promo invalid.
 * Used as a cross-check AFTER derivePlanFromAmount determines the plan.
 * Identical logic in verify-payment/index.ts.
 */
async function computeExpectedAmount(
  plan: string,
  promoCode: string | undefined,
  supabaseClient: SupabaseClient,
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
    console.warn(`Promo code ${boundedText(promoCode)} not found — using full price`);
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
      `Promo ${boundedText(promoCode)} ${isInactive ? 'inactive' : isExpired ? 'expired' : 'exhausted'} ` +
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
  supabaseClient: SupabaseClient,
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
    const { error: incErr } = await supabaseClient.rpc("increment_promo_used_count", { p_code: promoCode });
    if (incErr) {
      console.error(`[razorpay-webhook] promo redemption: increment_promo_used_count failed code=${pgErrorCode(incErr)}`);
    }

    // Audit trail
    const { error: useErr } = await supabaseClient.from("promo_code_uses").insert({
      code: promoCode,
      user_id: userId,
      plan_purchased: plan,
      original_amount: originalPaise,
      discount_applied: originalPaise - finalPaise,
      final_amount: finalPaise,
    });
    if (useErr) {
      console.error(`[razorpay-webhook] promo redemption: promo_code_uses insert failed code=${pgErrorCode(useErr)}`);
    }
  } catch (e) {
    console.error(`[razorpay-webhook] promo redemption threw (non-fatal): ${errorName(e)} code=${pgErrorCode(e)}`);
  }
}

/** Kill switch for the already-captured recovery (payment-hardening U2, OI-351): exactly "true" = today's 502. */
export const CAPTURE_RECOVERY_DISABLE_ENV = "DISABLE_WEBHOOK_CAPTURE_RECOVERY";
/** How long the recovery GET may take; a hang must not hold Razorpay's 5 s delivery clock. */
export const RECOVERY_GET_TIMEOUT_MS = 1500;

/**
 * After Razorpay REFUSED our capture of an authorized payment: is it in fact already captured, for exactly
 * this amount? (It is, when a first delivery captured it and then failed to record the row, so every replay
 * of the same `payment.authorized` event used to meet "already captured" and answer 502 for up to a day.)
 * Never throws: a non-OK answer, a malformed body, a network error or a hang past [timeoutMs] is `false`.
 * The body read sits INSIDE the race, so a hang after the headers is bounded too.
 */
export async function rereadIsCaptured(
  paymentId: string,
  expectedAmount: unknown,
  credentials: string,
  timeoutMs: number = RECOVERY_GET_TIMEOUT_MS,
): Promise<boolean> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<false>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve(false);
    }, timeoutMs);
  });
  const read = (async (): Promise<boolean> => {
    const resp = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
      method: "GET",
      headers: { "Authorization": `Basic ${credentials}`, "Content-Type": "application/json" },
      signal: controller.signal,
    });
    if (!resp.ok) return false;
    const p: unknown = await resp.json();
    if (p === null || typeof p !== "object" || Array.isArray(p)) return false;
    const e = p as { id?: unknown; amount?: unknown; captured?: unknown; status?: unknown };
    return e.id === paymentId &&
      typeof e.amount === "number" && e.amount === expectedAmount &&
      e.captured === true &&
      e.status === "captured";
  })().catch(() => false);
  try {
    return await Promise.race([read, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

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

    // OI-341 Piece A (plan 2.4): the same strict shape verify-payment enforces, checked BEFORE the replay
    // block below so a malformed id is never interpolated into a log line (the replay rejection logs the id).
    // The id comes from an HMAC-verified payload so a real one always conforms; the check is not switch-gated,
    // so the switch OFF and ON paths treat a malformed id identically.
    if (!isValidPaymentId(paymentEntity.id)) {
      console.error("[razorpay-webhook] rejecting a payment id that is not pay_ + alphanumerics");
      return new Response(
        JSON.stringify({ error: "Invalid payment id" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Replay protection — reject webhook DELIVERIES older than the event's window.
    //
    // Age MUST be measured from the webhook EVENT time (`payload.created_at`),
    // NOT the payment entity's `created_at`. A UPI-collect payment is *created*
    // when the user initiates but *captured / authorized* (and the webhook
    // fired) minutes later when they approve in their UPI app — so
    // `payment.entity.created_at` can legitimately be many minutes before the
    // event. Keying the replay window off it rejected slowly-approved captures
    // FOREVER, so PRO never unlocked via the webhook (F32, audit-2026-06-07).
    //
    // OI-341 Piece B2a (plan 2.6): the window depends on the event. Razorpay
    // retries a delivery "for 24 hours after event creation" (its webhook docs),
    // and nothing shows that a retry re-stamps `created_at`, so a 5-minute window
    // could reject a legitimate retry of a captured payment for good. So:
    //   - `payment.captured`: 24 h + 10 min. A stale signed captured event reaches
    //     only idempotent code (the H-19 pre-SELECT, the second pre-SELECT, the
    //     B1 function or the OFF 23505 catch; the promo redeems only when
    //     `!alreadyProcessed`).
    //   - `payment.authorized`: 5 minutes, because its path calls Razorpay's
    //     capture API.
    // Every event keeps the future-skew rejection. Stated residual risks: a signed
    // captured event up to a day old can re-create a row an operator deleted by
    // hand (or after a refund) within that day; and a captured event first
    // DELIVERED late (Razorpay's retries after our outage) records the row from
    // the delivery time, so the user gets up to that delay in extra days
    // (bounded by the window, in the user's favour); a captured event for an
    // account deleted since then fails the insert (FK) and retries for up to the
    // window (the ON path pages once, deduped). Operators therefore CANCEL a
    // tester row, never delete it, within the window (plan step 0 (d)). Epoch seconds, Razorpay standard.
    // Missing → skip the check (never fail closed on missing telemetry).
    const eventCreatedAtSec = payload.created_at as number | undefined;
    if (typeof eventCreatedAtSec === "number" && eventCreatedAtSec > 0) {
      // Review d6b736 F3: signed age — positive = stale (past), negative =
      // future-stamped (clock skew or a crafted replay). NO Math.abs: a future
      // timestamp must not masquerade as "fresh". Tolerate <=120s forward skew;
      // reject older than 5 min. (Idempotency pre-SELECT + 23505 is the backstop.)
      const ageSec = Date.now() / 1000 - eventCreatedAtSec;
      const maxAgeSec = event === "payment.captured" ? CAPTURED_MAX_AGE_SEC : AUTHORIZED_MAX_AGE_SEC;
      if (ageSec > maxAgeSec || ageSec < -120) {
        console.warn(
          `[razorpay-webhook] rejecting replay: payment_id=${paymentEntity.id} event_age=${Math.round(ageSec)}s`,
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

    // OI-26 (audit-2026-05-17 Hermes F1) — `supabaseClient` MUST be declared
    // BEFORE the H-19 idempotency pre-SELECT below. Pre-fix the const lived
    // at the user-id-validation block ~130 lines down, leaving the SELECT in
    // temporal dead zone → ReferenceError on every webhook invocation that
    // wasn't an early-return (HMAC fail / age fail). Razorpay retried for
    // 24h; users paying never unlocked PRO. closes-diagnose: see below.
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // H-19 (audit-2026-05-11) — idempotency pre-SELECT moved BEFORE
    // auto-capture. Pre-fix the order was capture-then-pre-SELECT, so
    // a replayed `payment.authorized` for an already-captured payment
    // fired a second Razorpay capture call → Razorpay 4xx ("already
    // captured") → we returned 502 → Razorpay kept retrying. Now we
    // short-circuit the entire pipeline (capture + insert + promo
    // redemption) for any payment_id already present in subscriptions.
    const { data: idemRow } = await supabaseClient
      .from("subscriptions")
      .select("id")
      .eq("razorpay_payment_id", razorpayPaymentId)
      .maybeSingle();
    if (idemRow !== null) {
      console.log(
        `[razorpay-webhook] H-19 idempotent skip: payment ${razorpayPaymentId} already processed; bypassing capture + insert`,
      );
      return new Response(
        JSON.stringify({
          success: true,
          alreadyProcessed: true,
          payment_id: razorpayPaymentId,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // If this is a payment.authorized event, capture the payment now so
    // it becomes final. Razorpay will fire a second payment.captured
    // event after our capture call, which we handle idempotently above
    // (the H-19 pre-SELECT short-circuits the replay before we reach
    // here a second time).
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
      // payment-hardening U2 (OI-351): a REFUSED capture is no longer an immediate 502. The switch is read
      // once per request; set to exactly "true" it restores today's 502 on every refusal.
      const recoveryDisabled = isEnvExactlyTrue(CAPTURE_RECOVERY_DISABLE_ENV);
      const credentials = base64Encode(
        `${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`,
      );
      let captureRefused = false;
      let refusal = "";
      try {
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
          captureRefused = true;
          refusal = `capture failed for ${razorpayPaymentId}: ${razorpayErrorSummary(captureResp.status, body)}`;
        } else {
          console.log(
            `[razorpay-webhook] auto-captured authorized payment ${razorpayPaymentId}`,
          );
          // We continue below to write the subscription. Razorpay will also
          // send payment.captured later — that call will hit the UNIQUE
          // constraint and be a no-op (idempotent).
        }
      } catch (e) {
        captureRefused = true;
        refusal = `capture threw for ${razorpayPaymentId}: ${errorName(e)}`;
      }
      if (captureRefused) {
        // Recovery: the usual refusal on a REPLAY is "already captured" (a first delivery captured it, then
        // failed to record the row). If Razorpay says it is captured, for this amount, record it now from the
        // signed event (amount, notes and plan come from the event, as on the payment.captured path).
        if (!recoveryDisabled && await rereadIsCaptured(razorpayPaymentId, paymentEntity.amount, credentials)) {
          console.warn(
            `[razorpay-webhook] capture refused, payment already captured; continuing payment_id=${razorpayPaymentId}`,
          );
        } else {
          console.error(`[razorpay-webhook] ${refusal}`);
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
      }
    }

    // Extract user_id and promo from notes (set during checkout creation).
    // NOTE: notes.plan is intentionally NOT used for entitlement — plan is
    // derived server-side from the on-wire amount via derivePlanFromAmount
    // per docs/architecture/payment.md rule 1. A client that spoofs notes.plan cannot
    // claim a different plan than what the amount actually paid for.
    const notes = paymentEntity.notes ?? {};
    const userId = notes.user_id;
    const promoCode = notes.promo_code as string | undefined;

    if (!userId) {
      console.error(`[razorpay-webhook] Missing user_id in payment notes: ${notesShape(notes)}`);
      return new Response(
        JSON.stringify({ error: "Missing user_id in payment notes" }),
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
      console.error(
        `[razorpay-webhook] Invalid user_id format in payment notes: type=${typeof userId} length=${String(userId).length}`,
      );
      return new Response(
        JSON.stringify({ error: "Invalid user_id format" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Derive plan from amount (primary — docs/architecture/payment.md rule 1) ───────────
    // Plan is determined from the actual payment amount, NOT from
    // client-supplied notes.plan. This prevents a ₹349 monthly payment
    // from claiming yearly entitlement by spoofing notes.plan = 'yearly'.
    const actualPaise = paymentEntity.amount as number;
    const derived = await derivePlanFromAmount(actualPaise, promoCode, supabaseClient);
    if (!derived) {
      console.error(
        `[razorpay-webhook] amount ${actualPaise} paise does not match any plan` +
          (promoCode ? ` (promo: ${boundedText(promoCode)})` : ""),
      );
      // OI-341 Piece B2a (hermes seat 4 F4): the money is captured and no row
      // can be written (the promo was edited or deleted between order and
      // capture, or the amount matches no price), so page it. The response is
      // unchanged.
      await reportPaymentRecordFailure(supabaseClient, {
        fn: "razorpay-webhook",
        requestId: crypto.randomUUID().split("-")[0],
        paymentId: razorpayPaymentId,
        userId,
        plan: "unknown",
        amountPaise: actualPaise,
        code: "amount_no_match",
      }, { timeoutMs: 1000 });
      return new Response(
        JSON.stringify({ error: "amount_does_not_match_any_plan" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const plan = derived.plan;

    // Log if client-claimed plan disagrees with the derived plan (diagnostic only —
    // the derived plan is the source of truth, notes.plan is discarded).
    const clientClaimedPlan = notes.plan as string | undefined;
    if (clientClaimedPlan && clientClaimedPlan !== plan) {
      console.warn(
        `[razorpay-webhook] notes.plan mismatch: client claimed ${boundedText(clientClaimedPlan)}, derived '${plan}' from amount ${actualPaise} — using derived`,
      );
    }

    // ── Belt-and-suspenders cross-check (computeExpectedAmount) ────────────
    // derivePlanFromAmount already confirmed the amount matches the plan, but
    // computeExpectedAmount re-derives the expected amount from the plan and
    // promo and checks they agree. If both pass, we have a fully internally
    // consistent amount ↔ plan ↔ promo triple.
    const { expectedPaise } =
      await computeExpectedAmount(plan, promoCode, supabaseClient);

    if (actualPaise !== expectedPaise) {
      // This should be unreachable if derivePlanFromAmount is correct, but
      // guard defensively in case of rounding/DB-lookup differences.
      console.error(
        `[razorpay-webhook] cross-check failed: derivePlanFromAmount returned '${plan}' ` +
          `but computeExpectedAmount gives ${expectedPaise} paise, got ${actualPaise}`,
      );
      await reportPaymentRecordFailure(supabaseClient, {
        fn: "razorpay-webhook",
        requestId: crypto.randomUUID().split("-")[0],
        paymentId: razorpayPaymentId,
        userId,
        plan,
        amountPaise: actualPaise,
        code: "amount_cross_check",
      }, { timeoutMs: 1000 });
      return new Response(
        JSON.stringify({ error: "amount_mismatch" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const now = new Date();
    let endDate = new Date(now);

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
    // this payment_id we skip the insert AND the promo redemption below
    // (`!alreadyProcessed` gate): increment_promo_used_count is NOT
    // idempotent, so redeeming again would double-burn used_count. The same
    // holds when the insert itself loses a race (23505, below).
    const { data: existing } = await supabaseClient
      .from("subscriptions")
      .select("id")
      .eq("razorpay_payment_id", razorpayPaymentId)
      .maybeSingle();

    let alreadyProcessed = existing !== null;
    // OI-341: the stacking switch is read ONCE per request (exactly "true"; absent = OFF).
    const stackingOn = isStackingEnabled();
    // OI-341 Piece B2a (plan 2.3): which state this isolate read, for every payment that reaches the insert branch.
    if (!alreadyProcessed) {
      console.log(`[razorpay-webhook] stacking_switch=${stackingOn ? "on" : "off"} payment_id=${razorpayPaymentId}`);
    }
    // Set only when the OFF branch itself inserted the row: the mismatch alarm's precondition (plan 2.5).
    let offInserted: { start: string; end: string } | null = null;
    if (alreadyProcessed) {
      console.log(
        `Idempotent webhook: payment ${razorpayPaymentId} already recorded, skipping insert`,
      );
    } else if (stackingOn) {
      // OI-341 Piece B1 ON path: ONE call to public.record_paid_subscription
      // (migration 161): per-user lock shared with the referral redeem and job,
      // idempotency, stacked end and insert in one transaction. It absorbs the
      // 23505 race the OFF branch handles below, so `inserted` decides promo
      // ownership. A failure returns 500 (Razorpay retries), logs the reconcile
      // line and pages (the payment is captured, the row is not written).
      const rec = await recordPaidSubscription(supabaseClient, {
        userId,
        plan,
        paymentId: razorpayPaymentId,
        orderId: razorpayOrderId,
        signature: razorpaySignature,
      });
      if (!rec.ok) {
        const stackFailId = crypto.randomUUID().split("-")[0];
        console.error(
          `[razorpay-webhook] stacking read failed request_id=${stackFailId} ` +
            `payment_id=${razorpayPaymentId} user_id=${userId} plan=${plan} amount_paise=${actualPaise} code=${codeToken(rec.code)}`,
        );
        await reportPaymentRecordFailure(supabaseClient, {
          fn: "razorpay-webhook",
          requestId: stackFailId,
          paymentId: razorpayPaymentId,
          userId,
          plan,
          amountPaise: actualPaise,
          code: rec.code,
        }, { timeoutMs: 1000 }); // plan 2.4: two 1 s round trips keep the 500 near Razorpay's 5 s clock
        return new Response(
          JSON.stringify({ error: "Failed to create subscription record" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      endDate = rec.endDate;
      alreadyProcessed = !rec.inserted;
      console.log(
        `[razorpay-webhook] stacking=on payment_id=${razorpayPaymentId} inserted=${rec.inserted}`,
      );
    } else {
      // OFF branch (the default): exactly `now + days`; the insert and its 23505
      // handling are today's code. Its one added request is the mismatch alarm
      // after the promo (Piece B2a plan 2.5), which never changes the response.
      endDate = plainEndDate(now, plan === "monthly" ? 30 : 365);
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

      // 23505 = unique_violation (Postgres). A concurrent racer (another
      // webhook delivery, or verify-payment) beat us to the insert — not an
      // error, the row exists either way. Whoever CREATED the row owns the
      // promo redemption, so this path must NOT redeem again: mark it processed
      // (Hermes L21 2026-09-29 — before this the 23505 arm fell through with
      // alreadyProcessed=false and double-burned used_count; verify-payment's
      // weInsertedTheRow gate is the mirror of this).
      if (insertError && insertError.code === "23505") {
        alreadyProcessed = true;
      }
      if (!insertError) {
        offInserted = { start: now.toISOString(), end: endDate.toISOString() };
      }
      if (insertError && insertError.code !== "23505") {
        // Never the error object (its `details` echoes the row, signature included). Money is captured and no
        // row exists on this OFF-path branch, so the ids stay. No request_id: this 500's body carries none.
        console.error(
          `[razorpay-webhook] subscription insert failed (non-23505) payment_id=${razorpayPaymentId} ` +
            `user_id=${userId} plan=${plan} amount_paise=${actualPaise} code=${pgErrorCode(insertError)}`,
        );
        return new Response(
          JSON.stringify({ error: "Failed to create subscription record" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // OI-202: there is deliberately NO `users` write here any more. This
    // handler used to mirror (status, end_date) onto users.subscription_status /
    // users.subscription_expires_at. Both columns are dropped (migration 152) —
    // `subscriptions` is the only entitlement record, and the insert above is
    // the complete, idempotent write. A failed insert returns 500 (Razorpay
    // then retries; the 23505 guard makes the retry safe).

    // ── Redeem promo code if applied ────────────────────────────
    // Skip on idempotent replay — increment_promo_used_count is NOT
    // idempotent and would double-count the redemption against
    // promo_codes.used_count.
    // Use derived.originalPaise (from primary derivation) as the full price —
    // this is the canonical source, not a re-derived value.
    if (!alreadyProcessed && derived.promoApplied && derived.promoCode) {
      await redeemPromo(
        supabaseClient,
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
    // (not the skip paths, not the 23505 race arm, not the ON path). It detects
    // and pages; it never changes the row or this response.
    if (offInserted !== null) {
      await checkStackingMismatch(supabaseClient, {
        fn: "razorpay-webhook",
        paymentId: razorpayPaymentId,
        userId,
        plan,
        rowStart: offInserted.start,
        rowEnd: offInserted.end,
      });
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
}

// `serve()` only when run as the entrypoint, so tests can import `handler`
// without binding a port (OI-341 Piece A, plan 2.3).
if (import.meta.main) serve(handler);
