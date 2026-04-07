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

/**
 * Direct Razorpay payment verification Edge Function.
 *
 * Called by the Flutter app as a fallback when the webhook-based polling
 * fails to confirm a payment within the polling window.
 *
 * Flow:
 *   1. Receives { payment_id, plan } with JWT auth
 *   2. Calls Razorpay GET /v1/payments/{id} with server credentials
 *   3. If payment is captured → upserts subscription row
 *   4. Returns { verified, plan, end_date }
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

    // ── Parse body ─────────────────────────────────────────────
    const body = await req.json();
    const paymentId = body.payment_id as string;
    const plan = (body.plan as string) || "monthly";

    if (!paymentId) {
      return new Response(
        JSON.stringify({ error: "Missing payment_id" }),
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

    // ── Check if subscription already exists ───────────────────
    const { data: existingSub } = await supabase
      .from("subscriptions")
      .select("id, end_date, plan")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1)
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

    const payment = await razorpayResponse.json();

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

    // Update users table
    await supabase
      .from("users")
      .update({
        subscription_status: "pro",
        subscription_expires_at: endDate.toISOString(),
      })
      .eq("id", userId);

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
    const message =
      err instanceof Error ? err.message : "Internal server error";
    console.error("Verify payment error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
