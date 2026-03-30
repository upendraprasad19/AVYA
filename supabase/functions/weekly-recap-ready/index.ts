/**
 * weekly-recap-ready — Sunday cron (per user's preferred time).
 *
 * Sends a push notification telling users their weekly recap is ready.
 * Respects user notification_preferences.weekly_recap setting.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";

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

    // Find active users (active in last 14 days for weekly recap relevance).
    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);

    const { data: activeUsers, error: usersErr } = await supabase
      .from("users")
      .select("id, full_name")
      .gte("last_active_at", fourteenDaysAgo.toISOString());

    if (usersErr || !activeUsers || activeUsers.length === 0) {
      return new Response(
        JSON.stringify({
          status: "success",
          message: "No active users for weekly recap",
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

    for (const user of activeUsers) {
      const userId = user.id as string;
      const firstName = ((user.full_name as string) ?? "").split(" ")[0] || "Champion";

      // Check notification preferences.
      const { data: snapshot } = await supabase
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      const prefs = snapshot?.snapshot_json?.notification_preferences;
      if (prefs?.weekly_recap?.enabled === false) {
        skipped++;
        continue;
      }

      // Get current week from user_progress.
      const { data: progress } = await supabase
        .from("user_progress")
        .select("current_week")
        .eq("user_id", userId)
        .single();

      const currentWeek = (progress?.current_week as number) ?? 1;

      const ok = await sendPushNotification({
        userId,
        title: "Weekly Recap Ready",
        message: `${firstName}, your Week ${currentWeek} recap is ready. See how you did!`,
        screen: "/profile/reports",
      });

      if (ok) sent++;
    }

    return new Response(
      JSON.stringify({
        status: "success",
        active_users: activeUsers.length,
        notifications_sent: sent,
        skipped_by_preference: skipped,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Internal server error";
    console.error("weekly-recap-ready error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
