/**
 * workout-window-closing — Brainstorm §5 trigger #2.
 *
 * Cron: 30 15 * * * (UTC) = 21:00 IST = 9pm IST daily.
 * Cron registration deferred to T6 (batched migration).
 *
 * Scans all users who had a non-completed scheduled workout today
 * but no workout_logs row for today, and pushes a single-line
 * "still happening?" nudge via OneSignal.
 *
 * Tier: both free + PRO (this is operational nudging, not a PRO feature).
 *
 * Dedup: each user gets at most one workout_window push per day, gated
 * via _shared/proactive_dedup.ts → coach_memory.last_proactive_type.
 *
 * Notification preference: respects
 * snapshot_json.notification_preferences.workout_reminders.enabled
 * (default = enabled when absent — new users haven't toggled).
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { fetchCoachMemory } from "../_shared/coach_memory.ts";
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat, MODEL_FLASH } from "../_shared/gemini.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier, sanitizeJsonForPrompt } from "../_shared/sanitize_for_prompt.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Returns today's date in IST (UTC+5:30) as YYYY-MM-DD. */
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

  // audit-2026-05-16 E.14.C — replaced inline env-equality JWT auth
  // (Test #16 P1-D drift class) with shared `isAuthorizedCronCall(req)`.
  // Survives Vault/env key rotation: verifies JWT signature against
  // SUPABASE_JWT_SECRET + role-claim === 'service_role'. CRON_SECRET
  // opaque-token escape hatch preserved inside the helper.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const requestId = crypto.randomUUID().split("-")[0];
  const logId = await logCronStart("workout-window-closing");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const todayIST = getTodayIST();

    // 1. Find all scheduled workouts today that are NOT completed/paused/
    //    skipped/rest. (In prod today only 'planned' and 'rest' exist;
    //    we explicitly exclude the terminal/non-actionable ones to stay
    //    forward-compatible with new statuses.)
    const { data: scheduled, error: schedErr } = await supabase
      .from("scheduled_workouts")
      .select("user_id, template_id, scheduled_date, status")
      .eq("scheduled_date", todayIST)
      .not("status", "in", "(completed,paused,skipped,rest)");

    if (schedErr) throw schedErr;

    if (!scheduled || scheduled.length === 0) {
      console.log(
        `[workout-window-closing] request_id=${requestId} no actionable scheduled workouts for ${todayIST}`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(
        JSON.stringify({
          status: "success",
          message: "No actionable scheduled workouts today",
          users_checked: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 2. Of those users, find which have ALREADY logged a workout today.
    const userIds = [
      ...new Set(
        scheduled.map((s: Record<string, unknown>) => s.user_id as string),
      ),
    ];
    const { data: todayLogs, error: logErr } = await supabase
      .from("workout_logs")
      .select("user_id")
      .in("user_id", userIds)
      .eq("date", todayIST);

    if (logErr) throw logErr;
    const loggedUserIds = new Set(
      (todayLogs ?? []).map((l: Record<string, unknown>) => l.user_id as string),
    );

    // 3. At-risk = scheduled but not logged. Dedupe by user_id (a user
    //    can only get one nudge even if multiple scheduled rows exist).
    const atRiskByUser = new Map<string, Record<string, unknown>>();
    for (const sched of scheduled) {
      const uid = sched.user_id as string;
      if (loggedUserIds.has(uid)) continue;
      if (!atRiskByUser.has(uid)) atRiskByUser.set(uid, sched);
    }

    if (atRiskByUser.size === 0) {
      console.log(
        `[workout-window-closing] request_id=${requestId} all ${scheduled.length} scheduled users have logged`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(
        JSON.stringify({
          status: "success",
          message: "All scheduled users have logged today",
          users_checked: scheduled.length,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 4. Pull workout names (template.name) and user names in batch.
    const atRiskUserIds = [...atRiskByUser.keys()];
    const templateIds = [
      ...new Set(
        [...atRiskByUser.values()]
          .map((s) => s.template_id as string | null)
          .filter((t): t is string => !!t),
      ),
    ];

    const [{ data: users, error: usersErr }, { data: templates, error: templatesErr }] =
      await Promise.all([
        supabase.from("users").select("id, full_name").in("id", atRiskUserIds),
        templateIds.length > 0
          ? supabase
              .from("workout_templates")
              .select("id, name")
              .in("id", templateIds)
          : Promise.resolve(
              { data: [] as { id: string; name: string }[], error: null },
            ),
      ]);
    // Unit C (§2.24) — batch read: surface a failure instead of coercing to empty
    // Maps (which silently drops every user's name/template personalization). The
    // outer try/catch closes cron telemetry as "failed".
    const batchErr = usersErr ?? templatesErr;
    if (batchErr) throw batchErr;

    const userById = new Map(
      (users ?? []).map((u: Record<string, unknown>) => [
        u.id as string,
        u.full_name as string | null,
      ]),
    );
    const templateNameById = new Map(
      (templates ?? []).map((t: Record<string, unknown>) => [
        t.id as string,
        t.name as string,
      ]),
    );

    let sent = 0;
    let dedupSkipped = 0;
    let prefSkipped = 0;
    let errors = 0;

    for (const [userId, sched] of atRiskByUser) {
      // 4a. Notification preference check.
      const { data: snapshot, error: snapErr } = await supabase
        .from("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", userId)
        .order("snapshot_date", { ascending: false })
        .limit(1)
        .maybeSingle();
      // Unit C (§2.24) — per-user read: on a GENUINE error skip THIS user (do NOT
      // send — we can't verify they didn't disable workout_reminders). `.maybeSingle`
      // returns {data:null,error:null} for a user with no snapshot → that falls
      // through to the most-permissive send below (unchanged for new users).
      if (snapErr) {
        errors++;
        continue;
      }

      const prefs = snapshot?.snapshot_json?.notification_preferences;
      // Most-permissive default: only skip if explicitly disabled.
      // Field name 'workout_reminders' is the natural fit for this
      // trigger. If the client hasn't surfaced a toggle yet, it's
      // absent → we send.
      if (prefs?.workout_reminders?.enabled === false) {
        prefSkipped++;
        continue;
      }

      // 4b. Dedup gate (same calendar day in IST).
      const allow = await shouldSendProactive(supabase, userId, "workout_window");
      if (!allow) {
        console.log(
          `[workout-window-closing] skipping ${userId}: dedup hit for workout_window`,
        );
        dedupSkipped++;
        continue;
      }

      // 4c. Personalize from coach_memory (preferred_name overrides
      //     full_name; private_mode strips coach_memory entirely).
      const memory = await fetchCoachMemory(supabase, userId);
      const usableMemory = memory?.private_mode ? null : memory;
      const preferredName = (usableMemory?.preferred_name as string | null) ??
        userById.get(userId) ??
        null;
      const firstName = preferredName ? preferredName.split(" ")[0] : null;

      const templateId = sched.template_id as string | null;
      const workoutName = (templateId && templateNameById.get(templateId)) ||
        "your workout";

      // Fallback: existing hardcoded English copy preserved as safety net.
      const greeting = firstName ? `${firstName} — ` : "";
      const fallbackMessage =
        `${greeting}haven't seen ${workoutName} logged yet. Still happening? Even 20 mins counts.`;

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          first_name: firstName,
          workout_name: workoutName,
          window_closing: true,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${sanitizeJsonForPrompt(userState)}.\n\n` +
            `Generate a workout window closing nudge — user has a scheduled workout ` +
            // OI-47: `workoutName` is a BARE interpolation of a user-editable
            // schedule/template name -- the only free-text field in this family
            // that no JSON.stringify protects. The other five alerts interpolate
            // only numbers here.
            `(${
              sanitizeIdentifier(workoutName, { fallback: "your session" })
            }) they haven't logged yet and the day is almost over.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[workout-window-closing] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: "Workout window closing",
          message,
          screen: "/ai_coach",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "workout_window");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(
          `[workout-window-closing] send failed for ${userId}:`,
          e,
        );
        errors++;
      }
    }

    console.log(
      `[workout-window-closing] request_id=${requestId} checked=${atRiskByUser.size} sent=${sent} dedup_skipped=${dedupSkipped} pref_skipped=${prefSkipped} errors=${errors}`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        status: "success",
        users_checked: atRiskByUser.size,
        notifications_sent: sent,
        dedup_skipped: dedupSkipped,
        pref_skipped: prefSkipped,
        errors,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx — never leak raw exception / SQL text.
    console.error(`[workout-window-closing] request_id=${requestId}`, err);
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
