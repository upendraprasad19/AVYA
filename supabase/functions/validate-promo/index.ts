/**
 * validate-promo — Validates a promo code for the paywall.
 *
 * Input:  { code: "LAUNCH20" }
 * Output: { valid: true, discount_pct: 20 }
 *     or: { valid: false, reason: "Code expired" }
 *
 * Does NOT increment used_count — that happens on payment success
 * in the razorpay-webhook Edge Function.
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
    // Validate JWT — prevent unauthenticated promo code enumeration
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

    const supabaseAuth = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAuth.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const code = (body?.code ?? "").trim().toUpperCase();

    if (!code) {
      return new Response(
        JSON.stringify({ valid: false, reason: "No code provided" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Look up the promo code.
    const { data: promo, error } = await supabase
      .from("promo_codes")
      .select("*")
      .eq("code", code)
      .single();

    if (error || !promo) {
      return new Response(
        JSON.stringify({ valid: false, reason: "Invalid promo code" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if active.
    if (!promo.is_active) {
      return new Response(
        JSON.stringify({ valid: false, reason: "This code is no longer active" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check expiry date.
    const validUntil = new Date(promo.valid_until as string);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (validUntil < today) {
      return new Response(
        JSON.stringify({ valid: false, reason: "This code has expired" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check max uses.
    if (
      promo.max_uses !== null &&
      (promo.used_count as number) >= (promo.max_uses as number)
    ) {
      return new Response(
        JSON.stringify({
          valid: false,
          reason: "This code has reached its maximum uses",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Valid!
    return new Response(
      JSON.stringify({
        valid: true,
        discount_pct: promo.discount_pct as number,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[validate-promo] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
