/**
 * expiry-reminder — Daily 6AM IST cron.
 *
 * Finds PRO subscribers whose plan expires within 3 days.
 * Sends a push notification via OneSignal to prompt renewal.
 *
 * Respects user notification_preferences.subscription_reminders setting.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";

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

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    // 1. Find active subscriptions expiring within 3 days.
    const { data: expiringSubs, error: subErr } = await supabase
      .from("subscriptions")
      .select("user_id, end_date, plan")
      .eq("status", "active")
      .gte("end_date", now.toISOString())
      .lte("end_date", threeDaysFromNow.toISOString());

    if (subErr || !expiringSubs || expiringSubs.length === 0) {
      return new Response(
        JSON.stringify({
          status: "success",
          message: "No subscriptions expiring within 3 days",
          users_checked: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let sent = 0;
    let skipped = 0;

    for (const sub of expiringSubs) {
      const userId = sub.user_id as string;
      const endDate = new Date(sub.end_date as string);

      // Calculate days remaining.
      const daysLeft = Math.ceil(
        (endDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
      );

      // Check notification preferences.
      const { data: snapshot } = await supabase
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      const prefs = snapshot?.snapshot_json?.notification_preferences;
      if (prefs?.subscription_reminders?.enabled === false) {
        skipped++;
        continue;
      }

      // Proactive dedup: skip if subscription_expiry already sent today.
      const allow = await shouldSendProactive(
        supabase,
        userId,
        "subscription_expiry",
      );
      if (!allow) {
        console.log(
          `[expiry-reminder] skipping ${userId}: dedup hit for subscription_expiry`,
        );
        skipped++;
        continue;
      }

      // Send push notification.
      const daysText =
        daysLeft <= 0
          ? "today"
          : daysLeft === 1
            ? "tomorrow"
            : `in ${daysLeft} days`;

      const ok = await sendPushNotification({
        userId,
        title: "PRO plan expiring soon",
        message: `Your PRO plan expires ${daysText}. Renew to keep your data and features.`,
        screen: "/profile",
      });

      if (ok) {
        sent++;
        await markProactiveSent(supabase, userId, "subscription_expiry");
      }
    }

    return new Response(
      JSON.stringify({
        status: "success",
        expiring_subscriptions: expiringSubs.length,
        notifications_sent: sent,
        skipped_by_preference: skipped,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[expiry-reminder] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
