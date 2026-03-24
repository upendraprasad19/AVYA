import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { encode as hexEncode } from "https://deno.land/std@0.177.0/encoding/hex.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-razorpay-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

    // Razorpay sends event-based webhooks
    const event = payload.event;
    if (event !== "payment.captured") {
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

    const razorpayOrderId = paymentEntity.order_id;
    const razorpayPaymentId = paymentEntity.id;
    const razorpaySignature = signature;

    // Extract user_id and plan from notes (set during checkout creation)
    const notes = paymentEntity.notes ?? {};
    const userId = notes.user_id;
    const plan = notes.plan; // 'monthly' or 'yearly'

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
    const now = new Date();
    const endDate = new Date(now);

    if (plan === "monthly") {
      endDate.setDate(endDate.getDate() + 30);
    } else {
      endDate.setDate(endDate.getDate() + 365);
    }

    // Write to subscriptions table
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

    if (insertError) {
      console.error("Failed to insert subscription:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create subscription record" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
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
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("Webhook error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
