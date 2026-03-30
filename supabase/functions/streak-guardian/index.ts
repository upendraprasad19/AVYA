/**
 * streak-guardian — Daily 8PM IST cron.
 *
 * Finds users with streak > 2 weeks who have NOT logged a workout today.
 * Sends a push notification via OneSignal to nudge them.
 *
 * Respects user notification_preferences.streak_alerts setting
 * stored in the user_daily_snapshots.snapshot_json field.
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

/**
 * Returns today's date in IST (UTC+5:30) as YYYY-MM-DD.
 */
function getTodayIST(): string {
  const now = new Date();
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  return istDate.toISOString().split("T")[0];
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const todayIST = getTodayIST();

    // 1. Find users with active streaks > 2 weeks.
    const { data: streakUsers, error: streakErr } = await supabase
      .from("user_progress")
      .select("user_id, current_streak_weeks")
      .gte("current_streak_weeks", 2);

    if (streakErr || !streakUsers || streakUsers.length === 0) {
      return new Response(
        JSON.stringify({
          status: "success",
          message: "No users with streak > 2 weeks",
          users_checked: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userIds = streakUsers.map((u: Record<string, unknown>) => u.user_id as string);

    // 2. Check which of these users have logged a workout today.
    const { data: todayLogs } = await supabase
      .from("workout_logs")
      .select("user_id")
      .in("user_id", userIds)
      .eq("date", todayIST);

    const loggedUserIds = new Set(
      (todayLogs ?? []).map((l: Record<string, unknown>) => l.user_id as string),
    );

    // 3. Filter to users who have NOT logged today.
    const atRiskUsers = streakUsers.filter(
      (u: Record<string, unknown>) => !loggedUserIds.has(u.user_id as string),
    );

    if (atRiskUsers.length === 0) {
      return new Response(
        JSON.stringify({
          status: "success",
          message: "All streak users have logged today",
          users_checked: streakUsers.length,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 4. Check notification preferences from user_daily_snapshots.
    let sent = 0;
    let skipped = 0;

    for (const user of atRiskUsers) {
      const userId = user.user_id as string;
      const streakWeeks = user.current_streak_weeks as number;

      // Check if user has streak_alerts enabled via configBox sync.
      // We store notification_preferences in snapshot_json for server access.
      const { data: snapshot } = await supabase
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();

      const prefs = snapshot?.snapshot_json?.notification_preferences;
      if (prefs?.streak_alerts?.enabled === false) {
        skipped++;
        continue;
      }

      // 5. Send push notification.
      const ok = await sendPushNotification({
        userId,
        title: "Don't break your streak!",
        message: `It's late. You haven't logged today. Don't break your ${streakWeeks}-week streak.`,
        screen: "/train",
      });

      if (ok) sent++;
    }

    return new Response(
      JSON.stringify({
        status: "success",
        users_checked: streakUsers.length,
        at_risk: atRiskUsers.length,
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
    console.error("streak-guardian error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
