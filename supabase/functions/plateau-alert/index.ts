/**
 * plateau-alert — Brainstorm §5 trigger #6 (PRO only).
 *
 * Cron: 30 13 * * * (UTC) = 19:00 IST = 7pm IST daily.
 * Cron registration deferred to T6 (batched migration).
 *
 * MUST run AFTER `compute-coach-signals` (cron `0 21 * * *` UTC = 02:30 IST
 * next day) so this read picks up the freshly-computed scores. 7pm IST runs
 * ~16.5h after the nightly compute — well within the same logical "today".
 *
 * Scans `coach_memory` rows where `plateau_risk_score >= 0.7` (high
 * confidence that weight has been flat AND consumption has been at/above
 * target — the formula is owned by `compute_coach_signals_for_user` SQL
 * RPC, populated nightly). Filters to active PRO subscribers and pushes a
 * single-question diagnostic nudge focused on protein adherence — the
 * brainstorm rule: "Coach asks and suggests, never tells."
 *
 * Tier: PRO only (filtered via subscriptions.status='active' AND
 * end_date > now()). No paywall conversion path here — the trigger
 * exists to retain PRO users who are getting frustrated, not to convert
 * free users (different from protein-gap-alert).
 *
 * Dedup: each user gets at most one plateau_alert push per day, gated via
 * _shared/proactive_dedup.ts → coach_memory.last_proactive_type.
 *
 * Privacy: respects coach_memory.private_mode (suppresses preferred_name
 * personalization but still sends the operationally-important nudge).
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat, MODEL_FLASH } from "../_shared/gemini.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { sanitizeIdentifier, sanitizeJsonForPrompt } from "../_shared/sanitize_for_prompt.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";
import {
  fetchNotificationPrefs,
  isNotificationEnabled,
} from "../_shared/notification_prefs.ts";
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
 * Threshold matches the brainstorm intent ("weight unchanged 10+ days").
 * The actual scoring formula lives in `compute_coach_signals_for_user`
 * (Postgres RPC). We consume the score here without recomputing.
 */
const PLATEAU_THRESHOLD = 0.7;

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
Deno.serve(async (req: Request) => {
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
  const logId = await logCronStart("plateau-alert");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 1. Pull all coach_memory rows above threshold whose signals have
    //    actually been computed (signals_computed_at IS NOT NULL guards
    //    against reading default/uncomputed rows).
    //    OI-79: paged. `coach_memory` is one row per user, so this caps at 1000
    //    at-risk users — past that the tail silently stops being alerted.
    //    orderBy is `user_id` here, not `id`: coach_memory's PK IS user_id
    //    (verified live) — it has no `id` column.
    const highRisk = await fetchAllPages<Record<string, unknown>>(
      () =>
        supabase
          .from("coach_memory")
          .select(
            "user_id, plateau_risk_score, preferred_name, private_mode, signals_computed_at",
          )
          .gte("plateau_risk_score", PLATEAU_THRESHOLD)
          .not("signals_computed_at", "is", null),
      { orderBy: "user_id", label: "plateau-alert high-risk" },
    );

    if (!highRisk || highRisk.length === 0) {
      console.log(
        `[plateau-alert] request_id=${requestId} no users above threshold ${PLATEAU_THRESHOLD}`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(
        JSON.stringify({ status: "success", candidates: 0, sent: 0 }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const candidateIds = (highRisk as Record<string, unknown>[]).map(
      (r) => r.user_id as string,
    );

    // 2. Filter to active PRO subscribers. Mirrors weekly-report /
    //    protein-gap-alert PRO gate.
    //    OI-79 — Class 1 (silently WRONG). `proSet` is an INCLUSION set: a row
    //    missing from it means a paying PRO user is read as free and their
    //    plateau alert is silently suppressed. A user can have multiple
    //    subscription rows (9 rows / 4 users live), so this is not 1:1 with the
    //    id list and truncates sooner than the user count suggests.
    const subs = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("subscriptions")
          .select("user_id")
          .eq("status", "active")
          .gt("end_date", new Date().toISOString())
          .in("user_id", chunk),
      candidateIds,
      { orderBy: "id", label: "plateau-alert pro-subs" },
    );

    const proSet = new Set(
      (subs ?? []).map((s: Record<string, unknown>) => s.user_id as string),
    );

    // Unit E — one batched, latest-desc read for the whole run. NOT
    // today-pinned: live, only 1 of 91 snapshot rows is dated today, so a
    // today-pinned lookup would find nothing for 16 of 17 users and fall
    // through to SEND, leaving the toggle decorative.
    const notifPrefs = await fetchNotificationPrefs(supabase, candidateIds);

    let sent = 0;
    let nonPro = 0;
    let dedupSkipped = 0;
    let prefsOff = 0;
    let errors = 0;

    for (const memory of highRisk as Record<string, unknown>[]) {
      const userId = memory.user_id as string;

      if (!proSet.has(userId)) {
        nonPro++;
        continue;
      }

      // User turned this off. Checked BEFORE the dedup gate so an opted-out
      // user never burns their one-per-day proactive slot on a push that is
      // then discarded — that would suppress a DIFFERENT notification they do
      // still want.
      if (!isNotificationEnabled(notifPrefs, userId, "plateau_alert")) {
        prefsOff++;
        continue;
      }

      // Dedup gate (max one plateau_alert per user per IST day).
      const allow = await shouldSendProactive(supabase, userId, "plateau_alert");
      if (!allow) {
        dedupSkipped++;
        continue;
      }

      // Personalization — coach_memory was already fetched in step 1;
      // no second round-trip. private_mode suppresses name (rule from
      // _shared/coach_memory.ts: private_mode hides personalization but
      // the nudge itself still ships).
      const isPrivate = memory.private_mode === true;
      const preferredName = isPrivate
        ? null
        : (memory.preferred_name as string | null);
      // OI-47 round 1: this firstName reaches the FALLBACK message that
      // actually ships when Gemini fails or times out -- the sanitised
      // Gemini path is only the success case. Splitting on whitespace
      // drops spaces but not CR, U+2028/2029/0085, controls or angle runs.
      const firstName = preferredName
          ? sanitizeIdentifier(preferredName.split(" ")[0], { maxLen: 32 })
          : null;
      const greeting = firstName ? `${firstName} — ` : "";

      // Fallback: existing hardcoded English copy preserved as safety net.
      const fallbackMessage =
        `${greeting}weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?`;

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          first_name: firstName,
          plateau_risk_score: (memory as Record<string, unknown>)
            .plateau_risk_score,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${sanitizeJsonForPrompt(userState)}.\n\n` +
            `Generate a plateau diagnostic nudge — user's weight has not moved in ` +
            `a while. Ask a single diagnostic question before changing anything.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[plateau-alert] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: "Plateau check",
          message,
          screen: "/ai_coach",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "plateau_alert");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(`[plateau-alert] send failed for ${userId}:`, e);
        errors++;
      }
    }

    console.log(
      `[plateau-alert] request_id=${requestId} candidates=${highRisk.length} sent=${sent} non_pro=${nonPro} prefs_off=${prefsOff} dedup_skipped=${dedupSkipped} errors=${errors}`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        status: "success",
        candidates: highRisk.length,
        sent,
        non_pro: nonPro,
        prefs_off: prefsOff,
        dedup_skipped: dedupSkipped,
        errors,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx — never leak raw exception / SQL text.
    console.error(`[plateau-alert] request_id=${requestId}`, err);
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
