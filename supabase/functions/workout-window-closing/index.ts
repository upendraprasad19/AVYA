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
 * Notification preference: respects `workout_reminders.enabled` via
 * _shared/notification_prefs.ts (source: user_preferences.notification_preferences,
 * legacy snapshot as fallback — OI-98 / e4a1b7).
 * Default = enabled when absent (new users haven't toggled); a GENUINE failure
 * to read preferences skips the user rather than risking a disabled nudge.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  fetchNotificationPrefsDetailed,
  isNotificationEnabled,
} from "../_shared/notification_prefs.ts";
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
import { fetchAllByIds, fetchAllPages } from "../_shared/paged_fetch.ts";

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
    // OI-79: paged. `scheduled_workouts` is already the largest per-user table
    // on the project (565 rows at 18 users), so this scan is the closest in the
    // fleet to the 1000-row ceiling.
    const scheduled = await fetchAllPages<Record<string, unknown>>(
      () =>
        supabase
          .from("scheduled_workouts")
          .select("user_id, template_id, scheduled_date, status")
          .eq("scheduled_date", todayIST)
          .not("status", "in", "(completed,paused,skipped,rest)"),
      { orderBy: "id", label: "workout-window-closing scheduled" },
    );

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
    // OI-79 — Class 1 (silently WRONG, not merely incomplete). This set is used
    // to EXCLUDE users who already trained. A truncated read drops users who
    // DID log, so they fall through to the at-risk branch and get pushed
    // "your training window is closing" hours after they finished their
    // workout. Paged + chunked so the exclusion set is always complete.
    const todayLogs = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("workout_logs")
          .select("user_id")
          .in("user_id", chunk)
          .eq("date", todayIST),
      userIds,
      { orderBy: "id", label: "workout-window-closing today-logs" },
    );

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

    // OI-79 — paged + chunked. Same Unit C (§2.24) contract as before: a failed
    // batch read must surface rather than coerce to an empty Map (which
    // silently drops every user's name/template personalization).
    // `fetchAllByIds` throws on a page error, so the outer try/catch still
    // closes cron telemetry as "failed". The explicit empty-`templateIds`
    // branch is gone because `fetchAllByIds` already short-circuits to [].
    const [users, templates] = await Promise.all([
      fetchAllByIds<Record<string, unknown>>(
        (chunk) => supabase.from("users").select("id, full_name").in("id", chunk),
        atRiskUserIds,
        { orderBy: "id", label: "workout-window-closing users" },
      ),
      fetchAllByIds<Record<string, unknown>>(
        (chunk) => supabase.from("workout_templates").select("id, name").in("id", chunk),
        templateIds,
        { orderBy: "id", label: "workout-window-closing templates" },
      ),
    ]);

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

    // OI-98 / e4a1b7 — ONE batched preference lookup instead of a per-user
    // query inside the loop, reading `user_preferences.notification_preferences`
    // with the legacy snapshot as fallback.
    //
    // `Detailed` is REQUIRED here, not a preference. This function is the one
    // caller whose documented behaviour on "could not read preferences" differs
    // from its behaviour on "no preferences set": it skips rather than risk a
    // nudge the user disabled. The plain `fetchNotificationPrefs` collapses both
    // into ABSENT => SEND, which would silently flip that decision.
    const { prefs: notifPrefs, degraded: prefsDegraded } =
      await fetchNotificationPrefsDetailed(
        supabase,
        [...atRiskByUser.keys()],
      );

    let sent = 0;
    let dedupSkipped = 0;
    let prefSkipped = 0;
    let errors = 0;

    for (const [userId, sched] of atRiskByUser) {
      // 4a. Notification preference check.
      //
      // Unit C (§2.24) — on a GENUINE inability to read preferences, skip (do
      // NOT send: we cannot verify they did not disable workout_reminders).
      // That is counted as an error, exactly as the per-user read did. A user
      // with NO stored preferences is a different case and still sends —
      // `isNotificationEnabled` applies the most-permissive ABSENT => SEND
      // default, unchanged for new users.
      //
      // ⚠ ONE WAY THIS IS NOT IDENTICAL, stated rather than glossed (B-pass
      // Finding 4). The old per-user query failed per USER; `degraded` is
      // batch-wide, because `fetchAllByIds` raises on any page and one lost
      // page makes the whole lookup untrustworthy. So a transient error now
      // skips EVERY candidate this run instead of one. That is the same
      // direction (skip rather than risk an unwanted push) and it is
      // self-healing — the next scheduled run re-reads — but it is a wider
      // blast radius for a transient fault, and calling it "preserved
      // verbatim" would have been an over-claim.
      if (prefsDegraded) {
        errors++;
        continue;
      }
      if (!isNotificationEnabled(notifPrefs, userId, "workout_reminders")) {
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
      // OI-47 round 1: this firstName reaches the FALLBACK message that
      // actually ships when Gemini fails or times out -- the sanitised
      // Gemini path is only the success case. Splitting on whitespace
      // drops spaces but not CR, U+2028/2029/0085, controls or angle runs.
      const firstName = preferredName
          ? sanitizeIdentifier(preferredName.split(" ")[0], { maxLen: 32 })
          : null;

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
