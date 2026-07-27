// PR Detection — Brainstorm §5 trigger #5.
// Cron-poll every 15 minutes: scan workout_log_exercises rows with is_pr=true
// inserted in the last 20 minutes (15min interval + 5min buffer for cron drift).
// Group PRs by user, send ONE notification per user mentioning their PR(s).
// Both free + PRO. Dedup via coach_memory.last_proactive_type (1/day max).
// Cron target: */15 * * * * (every 15 min). Registration deferred to T6.

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
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import {
  fetchNotificationPrefs,
  isNotificationEnabled,
} from "../_shared/notification_prefs.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface PRRow {
  user_id: string;
  exercise_id: string; // = exercise name per CLAUDE.md §11
  weight_kg: number | null;
  reps: number | null;
  completed_at: string; // F43: real workout time, not row sync time
}

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── Audit 2026-05-16 / E.14.C — JWT signature + role-claim auth.
  //
  // Was: inline env-equality `token === SUPABASE_SERVICE_ROLE_KEY`. That
  // shape silently 401-stormed when the Vault-stored JWT and the env-
  // injected SUPABASE_SERVICE_ROLE_KEY drifted (Test #16 P1-D root
  // cause). New: verify the JWT signature against SUPABASE_JWT_SECRET and
  // require `role === 'service_role'`. CRON_SECRET opaque-token path is
  // preserved inside the helper as escape hatch.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const requestId = crypto.randomUUID().split("-")[0];
  const logId = await logCronStart("pr-detection");

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Window: last 20 minutes (15min cron + 5min buffer).
    // F43 (2026-06-07 audit): filter/order by `completed_at` — the real
    // workout time — NOT `created_at` (row sync time). An offline workout
    // synced days later carries a fresh created_at; filtering on it fired a
    // stale "New PR!" push for a lift the user set days ago. completed_at is
    // when the workout actually happened, so the recency window is honest.
    const since = new Date(Date.now() - 20 * 60_000).toISOString();

    const { data: rows, error } = await supabase
      .from("workout_log_exercises")
      .select("user_id, exercise_id, weight_kg, reps, completed_at")
      .eq("is_pr", true)
      .gte("completed_at", since)
      .order("completed_at", { ascending: false });
    if (error) throw error;

    if (!rows || rows.length === 0) {
      console.log(
        `[pr-detection] request_id=${requestId} no PRs in window`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(JSON.stringify({ checked: 0, sent: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Group PRs by user
    const prsByUser = new Map<string, PRRow[]>();
    for (const row of rows as PRRow[]) {
      if (!prsByUser.has(row.user_id)) prsByUser.set(row.user_id, []);
      prsByUser.get(row.user_id)!.push(row);
    }

    // Unit E — one batched, latest-desc read for the whole run (NOT
    // today-pinned; see _shared/notification_prefs.ts for why that shape is
    // inert against live data).
    const notifPrefs = await fetchNotificationPrefs(
      supabase,
      [...prsByUser.keys()],
    );

    let sent = 0;
    let dedupSkipped = 0;
    let prefsOff = 0;
    let errors = 0;

    for (const [userId, prs] of prsByUser.entries()) {
      // User turned PR celebrations off. Checked BEFORE the dedup gate so an
      // opted-out user does not burn their one-per-day proactive slot on a
      // push that is then discarded, which would suppress a different
      // notification they still want.
      if (!isNotificationEnabled(notifPrefs, userId, "pr_celebration")) {
        prefsOff++;
        continue;
      }

      // Dedup gate
      if (!(await shouldSendProactive(supabase, userId, "pr_celebration"))) {
        dedupSkipped++;
        continue;
      }

      // Personalization
      const memory = await fetchCoachMemory(supabase, userId);
      const usableMemory = memory?.private_mode ? null : memory;
      const firstName =
        (usableMemory?.preferred_name as string | null) ?? "champ";

      // Fallback: existing hardcoded English copy preserved as safety net.
      const fallbackMessage = composeMessage(firstName, prs);

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const prSummary = prs.slice(0, 3).map((p) => ({
          exercise: p.exercise_id,
          weight_kg: p.weight_kg,
          reps: p.reps,
        }));
        const userState = {
          first_name: firstName,
          new_prs: prSummary,
          total_pr_count: prs.length,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${JSON.stringify(userState)}.\n\n` +
            `Generate a PR celebration nudge — user just set ${prs.length} new ` +
            `personal record(s) in their workout.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[pr-detection] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: prs.length === 1 ? "New PR! 🏆" : `${prs.length} new PRs! 🏆`,
          message,
          screen: "/train",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "pr_celebration");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(`[pr-detection] send failed for ${userId}:`, e);
        errors++;
      }
    }

    console.log(
      `[pr-detection] request_id=${requestId} pr_rows=${rows.length} users=${prsByUser.size} sent=${sent} prefs_off=${prefsOff} dedup_skipped=${dedupSkipped} errors=${errors}`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        pr_rows: rows.length,
        users: prsByUser.size,
        sent,
        prefs_off: prefsOff,
        dedup_skipped: dedupSkipped,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[pr-detection] request_id=${requestId}`, err);
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

/** Build a single-line celebratory message from up to 2 PRs (+N more). */
function composeMessage(firstName: string, prs: PRRow[]): string {
  if (prs.length === 0) return "";

  const fmt = (p: PRRow) => {
    const weight = p.weight_kg ?? 0;
    const reps = p.reps ?? 0;
    if (weight > 0) {
      return `${p.exercise_id} ${weight}kg`;
    }
    return `${p.exercise_id} ${reps} reps`;
  };

  if (prs.length === 1) {
    return `${firstName} — new ${fmt(prs[0])} PR. Want to bump next week's target?`;
  }
  if (prs.length === 2) {
    return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])}. Strong session.`;
  }
  // 3+ PRs
  const tail = prs.length - 2;
  return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])} +${tail} more. Strong session.`;
}
