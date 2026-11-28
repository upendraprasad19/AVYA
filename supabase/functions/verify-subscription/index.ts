import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { playDisplayFields } from "./logic.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * verify-subscription — Server-side PRO status verification.
 *
 * The Flutter client stores `isPro` in Hive (offline-first), which is
 * spoofable on rooted devices. This edge function provides an authoritative
 * check against the `subscriptions` table.
 *
 * Called from SubscriptionService.verifyFromServer() with a 5-minute cache TTL.
 * If offline or server error → client keeps its cached Hive state.
 *
 * Response:
 *   { is_pro: boolean, plan: string | null, expires_at: string | null,
 *     store: "play" | null, auto_renew: boolean | null, store_expires_at: string | null }
 * The last three are OI-519's additive Play display fields (logic.ts; null on every non-Play row).
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
    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const userId = user.id;

    // Query subscriptions table for active subscription
    // The Play display fields (playDisplayFields) come from THIS row only: a user whose active Play row ends before
    // another active row (a web purchase on top of Play) gets them null, so the app shows plain PRO with no Google
    // Play manage link. delete-account still cancels the Play row server-side (B-pass seat A, 2026-11-24).
    const { data: subscription, error: subError } = await supabaseClient
      .from("subscriptions")
      .select("plan, status, end_date, store, auto_renew, store_expires_at")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("end_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (subError) {
      console.error(`verify-subscription error for ${userId}:`, subError);
      return new Response(
        JSON.stringify({ error: "Database query failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // No active subscription found
    if (!subscription) {
      return new Response(
        JSON.stringify({ is_pro: false, plan: null, expires_at: null, ...playDisplayFields(null) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const endDate = subscription.end_date as string | null;
    if (!endDate) {
      return new Response(
        JSON.stringify({ is_pro: false, plan: null, expires_at: null, ...playDisplayFields(null) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const expiresAt = new Date(endDate);
    const isActive = expiresAt.getTime() > Date.now();

    return new Response(
      JSON.stringify({
        is_pro: isActive,
        plan: isActive ? (subscription.plan ?? "monthly") : null,
        expires_at: isActive ? endDate : null,
        ...playDisplayFields(isActive ? subscription : null),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[verify-subscription] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
