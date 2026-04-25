/**
 * redeem-referral — Redeems a referral code and grants 7-day PRO to both parties.
 *
 * Validation cascade (Q4 spec):
 *   1. Format check (AVYA-XXXXXXXX)
 *   2. Code lookup + expires_at < now()
 *   3. Self-referral block
 *   4. Receiver eligibility window (signup ≤ 7 days ago)
 *   5. Idempotency check (UNIQUE on referee_id)
 *   6. Atomic write via redeem_referral_atomic RPC
 *   7. 23505 race fallback returns 200 with alreadyRedeemed:true
 *
 * Input:  { code: "AVYA-XXXXXXXX" }
 * Output: { days_granted: 7, request_id: "..." }
 *     or: { error: "...", request_id: "..." }
 *     or: { alreadyRedeemed: true, request_id: "..." }
 *
 * Requires JWT auth — the referee must be logged in.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CODE_FORMAT = /^AVYA-[A-Z0-9]{8}$/;
const SIGNUP_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const DAYS_GRANTED = 7;

interface RedeemRequest {
  code?: string;
}

export async function handleRedeemReferral(
  body: RedeemRequest,
  supabase: ReturnType<typeof createClient>,
): Promise<Response> {
  const requestId = crypto.randomUUID().split("-")[0];

  // 0. Get authenticated user
  const { data: authData, error: authErr } = await supabase.auth.getUser();
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

  // 6. Atomic write via RPC
  const { error: rpcErr } = await supabase.rpc("redeem_referral_atomic", {
    p_code: code,
    p_referrer_id: codeRow.user_id,
    p_referee_id: referee.id,
    p_days: DAYS_GRANTED,
  });

  if (rpcErr) {
    // 7. 23505 race fallback — two concurrent requests slipped past step 5
    if (rpcErr.code === "23505") {
      return new Response(
        JSON.stringify({ alreadyRedeemed: true, request_id: requestId }),
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

  return new Response(
    JSON.stringify({ days_granted: DAYS_GRANTED, request_id: requestId }),
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

serve(async (req: Request) => {
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

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const body = await req.json().catch(() => ({})) as RedeemRequest;
    return await handleRedeemReferral(body, supabase);
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
});
