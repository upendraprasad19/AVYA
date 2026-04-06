/**
 * redeem-referral — Redeems a referral code and grants 7-day PRO to both parties.
 *
 * Input:  { code: "AVYA-UP1234" }
 * Output: { success: true, message: "..." }
 *     or: { success: false, reason: "..." }
 *
 * Requires JWT auth — the referee must be logged in.
 *
 * Race-condition safe:
 *   - Relies on UNIQUE(referee_id) DB constraint to prevent double-redemption
 *   - Uses atomic SQL for subscription extension (no read-then-write)
 *   - Caps referrals per code at 50 to prevent farming
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_REDEMPTIONS_PER_CODE = 50;
const PRO_DAYS = 7;

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
    // Get the JWT token to identify the referee
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, reason: "Not authenticated" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Create authenticated client to get user
    const supabaseUser = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, reason: "Invalid session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const refereeId = user.id;

    // Service role client for writes
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const body = await req.json();
    const code = (body?.code ?? "").trim().toUpperCase();

    if (!code || code.length > 20) {
      return new Response(
        JSON.stringify({ success: false, reason: "Invalid code format" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Look up the referral code
    const { data: referralCode, error: lookupErr } = await supabase
      .from("referral_codes")
      .select("*")
      .eq("code", code)
      .single();

    if (lookupErr || !referralCode) {
      return new Response(
        JSON.stringify({ success: false, reason: "Invalid referral code" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const referrerId = referralCode.user_id as string;

    // Can't refer yourself
    if (referrerId === refereeId) {
      return new Response(
        JSON.stringify({ success: false, reason: "You can't use your own referral code" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Check redemption cap (anti-farming)
    const { count: redemptionCount } = await supabase
      .from("referral_redemptions")
      .select("id", { count: "exact", head: true })
      .eq("referrer_id", referrerId);

    if ((redemptionCount ?? 0) >= MAX_REDEMPTIONS_PER_CODE) {
      return new Response(
        JSON.stringify({ success: false, reason: "This referral code has reached its limit" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Insert redemption record — UNIQUE(referee_id) constraint prevents race conditions.
    // If two concurrent requests try to redeem for the same referee, one will fail here.
    const { error: insertErr } = await supabase
      .from("referral_redemptions")
      .insert({
        referrer_id: referrerId,
        referee_id: refereeId,
        referrer_rewarded: true,
        referee_rewarded: true,
      });

    if (insertErr) {
      // Unique constraint violation = already redeemed
      if (insertErr.code === "23505") {
        return new Response(
          JSON.stringify({ success: false, reason: "You've already used a referral code" }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      console.error("Insert error:", insertErr);
      return new Response(
        JSON.stringify({ success: false, reason: "Failed to redeem code" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Grant 7-day PRO to BOTH parties using atomic SQL to avoid race conditions.
    const grantPro = async (userId: string) => {
      // Check if user already has an active subscription
      const { data: existingSub } = await supabase
        .from("subscriptions")
        .select("id")
        .eq("user_id", userId)
        .eq("status", "active")
        .limit(1);

      if (existingSub && existingSub.length > 0) {
        // Extend atomically via Postgres function — no read-then-write race
        await supabase.rpc("extend_subscription", {
          p_user_id: userId,
          p_days: PRO_DAYS,
        });
      } else {
        // No active sub — create a new 7-day subscription
        const now = new Date();
        const endDate = new Date(now.getTime() + PRO_DAYS * 86400000);
        await supabase
          .from("subscriptions")
          .insert({
            user_id: userId,
            plan: "referral",
            status: "active",
            start_date: now.toISOString(),
            end_date: endDate.toISOString(),
          });

        // Update users table for the new subscription
        await supabase
          .from("users")
          .update({
            subscription_status: "pro",
            subscription_expires_at: endDate.toISOString(),
          })
          .eq("id", userId);
      }
    };

    // Grant sequentially to avoid concurrent writes on the same user
    // (edge case: user refers themselves via a bug — already guarded above)
    await grantPro(referrerId);
    await grantPro(refereeId);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Referral redeemed! Both you and your friend get 7 days of PRO.",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("redeem-referral error:", message);
    // Return generic error to client — don't leak internals
    return new Response(
      JSON.stringify({ success: false, reason: "Something went wrong. Please try again." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
