/**
 * validate-promo — Validates a promo code for the paywall.
 *
 * Input:  { code: "LAUNCH20" }
 * Output: { valid: true, discount_pct: 20 }
 *     or: { valid: false, reason: "Code expired" }
 *
 * Does NOT increment used_count — that happens on payment success
 * in the razorpay-webhook Edge Function.
 *
 * OI-366 (payment-hardening U3): at most PROMO_QUOTA_LIMIT checks per user per fixed 1-hour UTC bucket, and the
 * one usability rule shared with create-razorpay-order (`_shared/promo_rules.ts`, the IST day). Every refusal is
 * an HTTP 200 `{valid: false, reason}`: the paywall shows any non-2xx as "Network error", and installed builds
 * read this shape. Kill switch DISABLE_ORDER_ABUSE_GUARDS (exactly "true", shared with create-razorpay-order)
 * restores the pre-OI-366 path verbatim. `handler` is exported and `serve()` runs only as the entrypoint, so a
 * test imports it without binding a port; env is read inside the handler.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { isEnvExactlyTrue } from "../_shared/subscription_stacking.ts";
import { errorName, pgErrorCode, stackFrames } from "../_shared/payment_log_safe.ts";
import { promoUsableAt } from "../_shared/promo_rules.ts";
import { ORDER_ABUSE_GUARDS_DISABLE_ENV, retryMinutes, secondsLeftInBucket } from "../_shared/order_abuse_guards.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PROMO_QUOTA_KEY = "promo_validate";
const PROMO_QUOTA_LIMIT = 20;
const PROMO_RATE_WINDOW_MS = 60 * 60 * 1000;
/** The same switch create-razorpay-order reads: one constant, in _shared/order_abuse_guards.ts. */
export const PROMO_GUARDS_DISABLE_ENV = ORDER_ABUSE_GUARDS_DISABLE_ENV;

/** The limit's refusal names the real wait: the bucket is a fixed UTC hour, so it can be a minute (hermes H3). */
export function rateLimitedReason(retryAfterSeconds: number): string {
  return `Too many attempts. Try again in ${retryMinutes(retryAfterSeconds)}.`;
}
export const CHECK_UNAVAILABLE_REASON = "Couldn't check the code right now. Try again shortly.";

function answer(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export async function handler(req: Request): Promise<Response> {
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return answer({ error: "Method not allowed" }, 405);
  }

  try {
    // Validate JWT — prevent unauthenticated promo code enumeration
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return answer({ error: "Missing authorization header" }, 401);
    }

    const supabaseAuth = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAuth.auth.getUser(token);

    if (authError || !user) {
      return answer({ error: "Invalid or expired token" }, 401);
    }

    // ── OI-366: per-user check limit, before the body and the lookup ──
    const guardsOn = !isEnvExactlyTrue(PROMO_GUARDS_DISABLE_ENV);
    console.log(`[validate-promo] order_abuse_guards=${guardsOn ? "on" : "off"}`);
    if (guardsOn) {
      const bucketStartMs = Math.floor(Date.now() / PROMO_RATE_WINDOW_MS) * PROMO_RATE_WINDOW_MS;
      const bucketStart = new Date(bucketStartMs).toISOString();
      const { data: usedCount, error: rateErr } = await supabaseAuth.rpc("consume_quota", {
        p_user_id: user.id,
        p_quota_key: PROMO_QUOTA_KEY,
        p_window_start: bucketStart,
        p_limit: PROMO_QUOTA_LIMIT,
      });
      if (rateErr) {
        console.error(`[validate-promo] check limit unavailable (fail-closed) code=${pgErrorCode(rateErr)}`);
        return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });
      }
      // consume_quota answers -1 or a count >= 1; anything else is an unreadable counter (fail CLOSED too).
      if (!Number.isInteger(usedCount) || (usedCount < 1 && usedCount !== -1)) {
        console.error(`[validate-promo] check limit unavailable (fail-closed) code=bad_result`);
        return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });
      }
      if (usedCount === -1) {
        console.warn(`[validate-promo] user=${user.id} rate-limited (quota_key=${PROMO_QUOTA_KEY}, limit=${PROMO_QUOTA_LIMIT})`);
        const retryAfterSeconds = secondsLeftInBucket(bucketStartMs, PROMO_RATE_WINDOW_MS);
        return answer({ valid: false, reason: rateLimitedReason(retryAfterSeconds) });
      }
    }

    const body = await req.json();
    const code = (body?.code ?? "").trim().toUpperCase();

    if (!code) {
      return answer({ valid: false, reason: "No code provided" });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    if (guardsOn) {
      // One rule with the order (promo_rules.ts); a read error is an outage, not "Invalid promo code".
      const { data: promo, error } = await supabase
        .from("promo_codes")
        .select("*")
        .eq("code", code)
        .maybeSingle();
      if (error) {
        console.error(`[validate-promo] promo read failed code=${pgErrorCode(error)}`);
        return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });
      }
      if (!promo) return answer({ valid: false, reason: "Invalid promo code" });
      const usability = promoUsableAt(promo);
      switch (usability) {
        case "inactive":
          return answer({ valid: false, reason: "This code is no longer active" });
        case "expired":
          return answer({ valid: false, reason: "This code has expired" });
        case "exhausted":
          return answer({ valid: false, reason: "This code has reached its maximum uses" });
        case "ok":
          return answer({ valid: true, discount_pct: promo.discount_pct as number });
        default: {
          // A new PromoUsability member is answered here (refused), never by the tolerant path below.
          const unhandled: never = usability;
          void unhandled;
          console.error(`[validate-promo] unhandled promo usability (fail-closed)`);
          return answer({ valid: false, reason: CHECK_UNAVAILABLE_REASON });
        }
      }
    }

    // ── Kill switch ON: the pre-OI-366 path, verbatim ──

    // Look up the promo code.
    const { data: promo, error } = await supabase
      .from("promo_codes")
      .select("*")
      .eq("code", code)
      .single();

    if (error || !promo) {
      return answer({ valid: false, reason: "Invalid promo code" });
    }

    // Check if active.
    if (!promo.is_active) {
      return answer({ valid: false, reason: "This code is no longer active" });
    }

    // Check expiry date.
    const validUntil = new Date(promo.valid_until as string);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (validUntil < today) {
      return answer({ valid: false, reason: "This code has expired" });
    }

    // Check max uses.
    if (
      promo.max_uses !== null &&
      (promo.used_count as number) >= (promo.max_uses as number)
    ) {
      return answer({
        valid: false,
        reason: "This code has reached its maximum uses",
      });
    }

    // Valid!
    return answer({
      valid: true,
      discount_pct: promo.discount_pct as number,
    });
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    // Name and frames only (hermes H10): a req.json() SyntaxError's message quotes the request body.
    console.error(`[validate-promo] request_id=${requestId} unhandled ${errorName(err)} at ${stackFrames(err)}`);
    return answer({ error: "Internal server error", request_id: requestId }, 500);
  }
}

// `serve()` only when run as the entrypoint, so tests can import `handler` without binding a port.
if (import.meta.main) serve(handler);
