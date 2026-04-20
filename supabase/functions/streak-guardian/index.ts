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
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";

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

      // Proactive dedup: skip if streak_protection already sent today.
      const allow = await shouldSendProactive(supabase, userId, "streak_protection");
      if (!allow) {
        console.log(
          `[streak-guardian] skipping ${userId}: dedup hit for streak_protection`,
        );
        skipped++;
        continue;
      }

      // 5. Build a contextual message based on streak + snapshot data.
      const snap = snapshot?.snapshot_json ?? {};
      const streakDays = (snap?.current_streak_days as number) ?? streakWeeks * 7;
      const recentPR = snap?.recent_pr_exercise as string | null;
      const weight = snap?.current_weight_kg as number | null;
      const targetWeight = snap?.target_weight_kg as number | null;

      let title = "Don't break your streak!";
      let message = `You haven't logged today. ${streakWeeks}-week streak on the line!`;

      // Milestone-based messages
      if (streakDays === 7) {
        title = "1 week strong!";
        message = "You've hit 7 days straight — that's the hardest week done. Don't stop now!";
      } else if (streakDays === 14) {
        title = "2 weeks! You're building a habit.";
        message = "14 days of consistency. Most people quit by now — you didn't. Keep going!";
      } else if (streakDays === 30) {
        title = "30-day warrior!";
        message = "A full month of training. You're in the top 5% of users. Log today to keep it alive!";
      } else if (streakDays === 50) {
        title = "50 days. Legendary.";
        message = "Half a century of consistency. This streak is worth protecting — don't miss today!";
      } else if (streakDays === 100) {
        title = "100-DAY STREAK!";
        message = "Triple digits. You're officially unstoppable. One workout away from 101!";
      } else if (streakDays % 10 === 0 && streakDays > 10) {
        title = `${streakDays}-day milestone!`;
        message = `${streakDays} days of showing up. That's elite. Don't let today be the one you miss.`;
      } else if (recentPR) {
        title = "You hit a PR recently!";
        message = `New best on ${recentPR} this week. Momentum is real — keep your ${streakWeeks}-week streak alive!`;
      } else if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
        title = "Almost at your goal weight!";
        message = `You're within 2kg of your target. Don't miss today — every session counts now.`;
      } else {
        // Varied generic messages
        const variants = [
          `It's getting late. Your ${streakWeeks}-week streak is waiting for today's workout.`,
          `${streakDays} days of consistency so far. One workout keeps it alive.`,
          `You didn't come this far to only come this far. ${streakWeeks} weeks and counting!`,
          `Your future self will thank you. Log a workout before midnight to keep your streak.`,
        ];
        message = variants[streakDays % variants.length];
      }

      const ok = await sendPushNotification({
        userId,
        title,
        message,
        screen: "/train",
      });

      if (ok) {
        sent++;
        await markProactiveSent(supabase, userId, "streak_protection");
      }
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
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[streak-guardian] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
