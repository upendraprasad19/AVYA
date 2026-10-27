/**
 * redeem-referral — Redeems a referral code and grants 7-day PRO to the REFEREE (the referrer is rewarded later, when the friend pays).
 *
 * Validation cascade (Q4 spec):
 *   1. Format check (AVYA-XXXXXXXX)
 *   2. Code lookup + expires_at < now()
 *   3. Self-referral block
 *   4. Receiver eligibility window (signup ≤ 7 days ago)
 *   5. Idempotency check (UNIQUE on referee_id)
 *   5b. Paid-referee check: an account that has ever PAID is refused (400)
 *   6. Atomic write via redeem_referral_atomic RPC
 *   7. 23505 race fallback returns 200 with alreadyRedeemed:true
 *
 * Since migration 159 the RPC credits the REFEREE only (7 days); the REFERRER is
 * rewarded later, by the hourly job, when that friend pays. Step 5b gives a paid
 * friend a clean 400; the RPC refuses the same account authoritatively
 * (`referee_has_paid_plan`, SQLSTATE P0001) and that refusal maps to the SAME 400.
 *
 * Input:  { code: "AVYA-XXXXXXXX" }
 * Output: { days_granted: 7, request_id: "..." }
 *     or: { error: "...", request_id: "..." }
 *     or: { alreadyRedeemed: true, request_id: "..." }
 *
 * Requires JWT auth — the referee must be logged in.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CODE_FORMAT = /^AVYA-[A-Z0-9]{8}$/;
const SIGNUP_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const DAYS_GRANTED = 7;
// A paid plan row is what migration 159 calls "paid": plan monthly/yearly WITH a Razorpay payment id. The RPC's refusal
// counts a row of ANY status; the hourly reward job additionally wants status active, not cancelled, inside the 90-day
// window. This list and the RPC's must stay in step (test/contracts/redeem_referral_paid_referee_migration_pin_test.dart).
const PAID_PLANS = ["monthly", "yearly"];
const PAID_REFEREE_MESSAGE = "Referral codes are for new recruits who haven't subscribed yet.";

interface RedeemRequest {
  code?: string;
}

export async function handleRedeemReferral(
  body: RedeemRequest,
  supabase: SupabaseClient,
  token: string,
): Promise<Response> {
  const requestId = crypto.randomUUID().split("-")[0];

  // 0. Authenticate the caller.
  // `supabase` is a PURE service-role client (BYPASSRLS). It MUST be — the
  // referral_codes lookup below reads the REFERRER's code row, which an
  // authenticated-context client cannot (own-only RLS: auth.uid()=user_id), AND
  // redeem_referral_atomic is EXECUTE-granted to service_role only. The prior
  // client baked the user JWT into global.headers, which made PostgREST run as
  // `authenticated` → every redemption failed (0 rows ever). We instead pass the
  // token separately and validate it explicitly via getUser(token) (mirror the
  // delete-account e8a1c3 fix). Diagnose: referral-rls-context (2026-06-13 Unit 1).
  const { data: authData, error: authErr } = await supabase.auth.getUser(token);
  if (authErr || !authData?.user) {
    return new Response(
      JSON.stringify({ error: "Authentication required", request_id: requestId }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  const referee = authData.user;

  // 1. Format check
  const code = (body.code ?? "").trim().toUpperCase();
  if (!CODE_FORMAT.test(code)) {
    return jsonError(400, "Codes look like AVYA-XXXXXXXX.", requestId);
  }

  // 2. Code lookup + expiry
  const { data: codeRow, error: codeErr } = await supabase
    .from("referral_codes")
    .select("user_id, expires_at")
    .eq("code", code)
    .single();
  if (codeErr || !codeRow) {
    return jsonError(400, "We don't recognize that code.", requestId);
  }
  if (new Date(codeRow.expires_at).getTime() < Date.now()) {
    return jsonError(
      400,
      "This code has expired. Ask your friend to send a fresh one.",
      requestId,
    );
  }

  // 3. Self-referral block
  if (codeRow.user_id === referee.id) {
    return jsonError(400, "Can't refer yourself, soldier 🫡", requestId);
  }

  // 4. Receiver eligibility window (7 days from signup)
  const refereeSignupAge = Date.now() - new Date(referee.created_at).getTime();
  if (refereeSignupAge > SIGNUP_WINDOW_MS) {
    return jsonError(
      400,
      "Referral codes are for new recruits — within 7 days of signup.",
      requestId,
    );
  }

  // 5. Idempotency check
  const { data: existing } = await supabase
    .from("referral_redemptions")
    .select("id")
    .eq("referee_id", referee.id)
    .maybeSingle();
  if (existing) {
    return jsonError(400, "Code already applied to your account.", requestId);
  }

  // 5b. An account that has ever PAID is refused: free days are for new recruits (migration 159). Placed AFTER the
  // idempotency check so an already-redeemed paid user still reads "Code already applied". A READ ERROR is logged and
  // falls through to the RPC, whose refusal is the authoritative check once migration 159 is applied (this read only buys
  // a clean message; before the apply the RPC refuses nobody, so an unreadable check admits a paid friend, as before).
  const { data: paidRows, error: paidErr } = await supabase
    .from("subscriptions")
    .select("id")
    .eq("user_id", referee.id)
    .in("plan", PAID_PLANS)
    .not("razorpay_payment_id", "is", null)
    .limit(1);
  if (paidErr) {
    console.warn(`[redeem-referral] request_id=${requestId} paid-check read failed: ${paidErr.message}`);
  }
  if (paidRows && paidRows.length > 0) {
    return jsonError(400, PAID_REFEREE_MESSAGE, requestId);
  }

  // 6. Atomic write via RPC
  const { error: rpcErr } = await supabase.rpc("redeem_referral_atomic", {
    p_code: code,
    p_referrer_id: codeRow.user_id,
    p_referee_id: referee.id,
    p_days: DAYS_GRANTED,
  });

  if (rpcErr) {
    // The RPC's own refusal of a paid referee (raised under the referee's lock, so it also covers a payment that landed
    // between step 5b and here): the same clean 400, not the generic 500.
    if (typeof rpcErr.message === "string" && rpcErr.message.includes("referee_has_paid_plan")) {
      return jsonError(400, PAID_REFEREE_MESSAGE, requestId);
    }
    // 7. 23505 race fallback — two concurrent requests slipped past step 5
    if (rpcErr.code === "23505") {
      return new Response(
        // success:true so EVERY success-ish 200 carries the same flag the clients
        // read (invite_friends_sheet checks body['success']) — else the idempotent
        // 23505-race path shows a false "invalid code" error. B-pass P2 (2026-06-13).
        JSON.stringify({ success: true, alreadyRedeemed: true, request_id: requestId }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    console.error(`[redeem-referral] request_id=${requestId}`, rpcErr);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // `success: true` is the canonical success flag all three clients read
  // (referral_repository, invite_friends_sheet, onboarding redeem). `days_granted`
  // kept for back-compat. One shape → no writer/reader drift across callers.
  return new Response(
    JSON.stringify({ success: true, days_granted: DAYS_GRANTED, request_id: requestId }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

function jsonError(status: number, message: string, requestId: string): Response {
  return new Response(
    JSON.stringify({ error: message, request_id: requestId }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");

    // PURE service-role client — NO global Authorization header. Passing the user
    // JWT in global.headers makes PostgREST derive the role from the JWT and run as
    // `authenticated`, RLS-blocking the cross-user referral_codes lookup and the
    // service_role-only RPC (the live P0). The caller is authenticated separately
    // via getUser(token) inside the handler.
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const body = await req.json().catch(() => ({})) as RedeemRequest;
    return await handleRedeemReferral(body, supabase, token);
  } catch (err) {
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[redeem-referral] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
}

// Only when run as the entrypoint: importing this module from a test must not bind a server (deploy runs it as main).
// Wrapped, not passed directly: `serve`'s Handler type expects `(req, connInfo)`.
if (import.meta.main) {
  serve((req) => handler(req));
}
