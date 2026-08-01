/**
 * streak-guardian — Daily 20:00 IST (8 PM, 14:30 UTC) cron.
 *
 * Finds users with streak > 2 weeks who have NOT logged a workout today.
 * Sends a push notification via OneSignal to nudge them.
 *
 * Respects user notification_preferences.streak_alerts setting
 * stored in the user_daily_snapshots.snapshot_json field.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import { markProactiveSent, shouldSendProactive } from "../_shared/proactive_dedup.ts";
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat, MODEL_FLASH } from "../_shared/gemini.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier, sanitizeJsonForPrompt } from "../_shared/sanitize_for_prompt.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import { fetchAllByIds, fetchAllPages } from "../_shared/paged_fetch.ts";

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

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── Audit 2026-05-16 / E.14.C — JWT signature + role-claim auth.
  //
  // See `supabase/functions/_shared/cron_auth.ts` for the rationale —
  // env-equality drift was the Test #16 P1-D root cause. CRON_SECRET
  // opaque-token path is preserved inside the helper as escape hatch.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const logId = await logCronStart("streak-guardian");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const todayIST = getTodayIST();

    // 1. Find users with active streaks > 2 weeks.
    //    OI-79: paged — an un-ranged read caps at 1000 with no error, so past
    //    1000 users on a streak the tail would silently stop being guarded.
    //
    //    The old guard here was `if (streakErr || !streakUsers || length === 0)`
    //    → log cron "success", return 200 "No users with streak > 2 weeks".
    //    That conflated a FAILED read with an EMPTY one: a broken query reported
    //    a healthy tick and nobody's streak got guarded, invisibly. Same class as
    //    diagnose a7e2c4 (Edge-Function reads coercing a failure into empty
    //    data). `fetchAllPages` throws, so the error now propagates to the outer
    //    catch → cron telemetry "failed" → next tick retries. The genuinely-empty
    //    case still exits 200.
    const streakUsers = await fetchAllPages<Record<string, unknown>>(
      () =>
        supabase
          .from("user_progress")
          .select("user_id, current_streak_weeks")
          .gte("current_streak_weeks", 2),
      { orderBy: "id", label: "streak-guardian streak-users" },
    );

    if (streakUsers.length === 0) {
      await logCronEnd(logId, "success", { httpStatus: 200 });
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
    //    OI-79 — Class 1 (silently WRONG). This set EXCLUDES users who already
    //    trained, so anything missing from it becomes a false "your streak is at
    //    risk" push to someone who worked out hours ago.
    //    Two independent routes produced that outcome and both are closed here:
    //    (a) truncation past db-max-rows — no error, just a short list; and
    //    (b) the read did not destructure `error` at all, so a genuine query
    //        failure coerced to `?? []` = "nobody logged today" = alert everyone.
    //        That is the a7e2c4 bug class; this site was missed by that sweep.
    //    `fetchAllByIds` pages, chunks, and throws — all three routes closed.
    const todayLogs = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("workout_logs")
          .select("user_id")
          .in("user_id", chunk)
          .eq("date", todayIST),
      userIds,
      { orderBy: "id", label: "streak-guardian today-logs" },
    );

    const loggedUserIds = new Set(
      (todayLogs ?? []).map((l: Record<string, unknown>) => l.user_id as string),
    );

    // 3. Filter to users who have NOT logged today.
    const atRiskUsers = streakUsers.filter(
      (u: Record<string, unknown>) => !loggedUserIds.has(u.user_id as string),
    );

    if (atRiskUsers.length === 0) {
      await logCronEnd(logId, "success", { httpStatus: 200 });
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
      const { data: snapshot, error: snapErr } = await supabase
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .single();
      // Unit C (§2.24) — `.single()` returns PGRST116 for a user with NO snapshot
      // row; that is NOT an error — fall through to send (a user whose streak is on
      // the line must still get the guard nudge, preserving pre-fix behavior). Only a
      // GENUINE error (network/permission) skips — pre-fix a silent failure coerced to
      // `snapshot=null` and pushed regardless of a disabled streak_alerts preference.
      if (snapErr && snapErr.code !== "PGRST116") {
        skipped++;
        continue;
      }

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

      // Fallback: hardcoded English messages preserved as safety net.
      let title = "Don't break your streak!";
      let fallbackMessage = `You haven't logged today. ${streakWeeks}-week streak on the line!`;

      if (streakDays === 7) {
        title = "1 week strong!";
        fallbackMessage = "You've hit 7 days straight — that's the hardest week done. Don't stop now!";
      } else if (streakDays === 14) {
        title = "2 weeks! You're building a habit.";
        fallbackMessage = "14 days of consistency. Most people quit by now — you didn't. Keep going!";
      } else if (streakDays === 30) {
        title = "30-day warrior!";
        fallbackMessage = "A full month of training. You're in the top 5% of users. Log today to keep it alive!";
      } else if (streakDays === 50) {
        title = "50 days. Legendary.";
        fallbackMessage = "Half a century of consistency. This streak is worth protecting — don't miss today!";
      } else if (streakDays === 100) {
        title = "100-DAY STREAK!";
        fallbackMessage = "Triple digits. You're officially unstoppable. One workout away from 101!";
      } else if (streakDays % 10 === 0 && streakDays > 10) {
        title = `${streakDays}-day milestone!`;
        fallbackMessage = `${streakDays} days of showing up. That's elite. Don't let today be the one you miss.`;
      } else if (recentPR) {
        title = "You hit a PR recently!";
        fallbackMessage = `New best on ${recentPR} this week. Momentum is real — keep your ${streakWeeks}-week streak alive!`;
      } else if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
        title = "Almost at your goal weight!";
        fallbackMessage = `You're within 2kg of your target. Don't miss today — every session counts now.`;
      } else {
        const variants = [
          `It's getting late. Your ${streakWeeks}-week streak is waiting for today's workout.`,
          `${streakDays} days of consistency so far. One workout keeps it alive.`,
          `You didn't come this far to only come this far. ${streakWeeks} weeks and counting!`,
          `Your future self will thank you. Log a workout before midnight to keep your streak.`,
        ];
        fallbackMessage = variants[streakDays % variants.length];
      }

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          streak_days: streakDays,
          streak_weeks: streakWeeks,
          recent_pr_exercise: recentPR,
          current_weight_kg: weight,
          target_weight_kg: targetWeight,
          workout_logged_today: false,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${sanitizeJsonForPrompt(userState)}.\n\n` +
            `Generate a streak protection nudge — user has not logged today and their ` +
            `${streakDays}-day streak is at risk.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[streak-guardian] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
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

    await logCronEnd(logId, "success", { httpStatus: 200 });
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
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      requestId,
      errorSummary: String(err),
    });
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
