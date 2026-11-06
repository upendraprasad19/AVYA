// PR Detection — Brainstorm §5 trigger #5.
// Hourly cron (`proactive_pr_detection`, `0 * * * *` since migration 141): scan
// workout_log_exercises rows written in the tick-aligned window
// [floor(now) - 60 min, floor(now)) (window.ts), keep ONE live row per
// (user, day, exercise), then the ones flagged is_pr whose workout day is IST
// yesterday/today (live_pr_filter.ts `celebratablePrs`).
// Group PRs by user, send ONE notification per user mentioning their PR(s).
// Both free + PRO. Dedup via coach_memory.last_proactive_type (1/day max).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { fetchCoachMemory } from "../_shared/coach_memory.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier } from "../_shared/sanitize_for_prompt.ts";
import { composeMessage } from "./message.ts";
import { celebratablePrsInWindow, excludeDeletedPrs } from "./live_pr_filter.ts";
import { prWindow } from "./window.ts";
import { buildDayMap } from "../_shared/exercise_day.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import { fetchAllByIds, fetchAllPages } from "../_shared/paged_fetch.ts";
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
  exercise_id: string; // = exercise name per docs/architecture/ai.md
  weight_kg: number | null;
  reps: number | null;
  completed_at: string; // F43: real workout time, not row sync time
  deleted_at: string | null; // OI-246 follow-up — migrations 150/151
  id: number | string;
  workout_log_id: string | null;
  set_number: number | null;
  is_pr: boolean | null;
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

    // Window: the tick-aligned hour [since, until) — see window.ts. F43
    // (2026-06-07 audit): filter/order by `completed_at` (the device's write
    // time), NOT `created_at` (row sync time); the workout DAY is resolved
    // from `workout_log_id` in `celebratablePrs`.
    const now = new Date();
    const { since, until } = prWindow(now);
    const dayMap = await buildDayMap(now);

    // OI-79: paged. `completed_at` alone is NOT a safe page key (a whole
    // workout shares one timestamp), so `id` is the unique tiebreaker.
    // L1b: the read no longer filters `is_pr` — a superseded row's stale PR
    // must lose to its winner's own flag, so dedupe runs first (B1).
    const rawRows = await fetchAllPages<PRRow>(
      () =>
        supabase
          .from("workout_log_exercises")
          .select(
            "id, user_id, workout_log_id, exercise_id, set_number, is_pr, weight_kg, reps, completed_at, deleted_at",
          )
          .gte("completed_at", since)
          .lt("completed_at", until),
      {
        orderBy: [
          { column: "completed_at", ascending: false },
          { column: "id", ascending: true },
        ],
        label: "pr-detection prs",
      },
    );

    // Context read: a superseded row and its winner can be written in different
    // hours, so dedupe needs EVERY live row of the window rows' (user, day)
    // keys, not just the window's. Chunked by workout_log_id (idx_wle_workout_log_id).
    const windowRows = excludeDeletedPrs(rawRows);
    const keyIds = [
      ...new Set(windowRows.map((r) => r.workout_log_id).filter((x): x is string => !!x)),
    ];
    const keyedRows = keyIds.length === 0 ? [] : await fetchAllByIds<PRRow>(
      (chunk) =>
        supabase
          .from("workout_log_exercises")
          .select(
            "id, user_id, workout_log_id, exercise_id, set_number, is_pr, weight_kg, reps, completed_at, deleted_at",
          )
          .is("deleted_at", null)
          .in("workout_log_id", chunk),
      keyIds,
      { orderBy: "id", label: "pr-detection keyed rows" },
    );
    const seen = new Set<string>();
    const contextRows: PRRow[] = [];
    for (const r of [...keyedRows, ...windowRows.filter((w) => !w.workout_log_id)]) {
      const k = String(r.id);
      if (seen.has(k)) continue;
      seen.add(k);
      contextRows.push(r);
    }

    // OI-246 follow-up — a deleted-then-suffixed row must never reach a push
    // (live_pr_filter.ts header); then dedupe over the context, keep winners
    // written in THIS window that are PRs on a day IST yesterday/today (B1/B3).
    const rows = celebratablePrsInWindow(
      excludeDeletedPrs(contextRows),
      dayMap,
      now,
      since,
      until,
    );

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
      // OI-47 round 1 (historical): firstName feeds composeMessage(), which
      // builds the deterministic template push (cron-ai-removal batch,
      // 2026-09-16, removed the Gemini path this comment used to contrast
      // against).
      const firstName = sanitizeIdentifier(
        usableMemory?.preferred_name as string | null,
        { fallback: "champ", maxLen: 32 },
      );

      const message = composeMessage(firstName, prs);

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
