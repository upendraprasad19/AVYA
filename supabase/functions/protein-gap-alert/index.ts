/**
 * protein-gap-alert — Brainstorm §5 trigger #3 (PRO only).
 *
 * Cron: 30 14 * * * (UTC) = 20:00 IST = 8pm IST daily.
 * Cron registration deferred to T6 (batched migration).
 *
 * Scans active PRO users whose today's protein intake is < 60% of their
 * daily protein target. Pushes a "Xg short" nudge with a diet-aware
 * quick-fix suggestion (paneer/milk for veg, chicken/eggs for non-veg).
 * Offers to follow up with a full dinner suggestion via the AI coach.
 *
 * Tier: PRO only (filtered via subscriptions.status='active' AND end_date > now()).
 *
 * Target resolution priority:
 *   1) user_profile.protein_grams (the canonical target column written by
 *      BmrCalculator on every onboarding/edit)
 *   2) snapshot_json.daily_targets.protein (defensive fallback if a future
 *      snapshot writer adds it — current snapshots do NOT include this key)
 *   3) skip user — never nudge without a confirmed target (false positives
 *      are worse than silence on a PRO push).
 *
 * Dedup: each user gets at most one protein_gap push per day, gated via
 * _shared/proactive_dedup.ts → coach_memory.last_proactive_type.
 *
 * Notification preference: respects
 * snapshot_json.notification_preferences.protein_alerts.enabled
 * (default = enabled when absent — most permissive default per T1 pattern).
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
  const logId = await logCronStart("protein-gap-alert");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const todayIST = getTodayIST();

    // 1. All active PRO users (status='active' AND end_date > now()).
    //    Mirrors weekly-report's PRO gate.
    //    OI-79: paginated. An un-ranged read stops at PostgREST's db-max-rows
    //    (1000) with HTTP 200 and error===null, so past 1000 active subs the
    //    tail of the PRO base would silently stop receiving this alert.
    // Pinned once, outside the per-page closure — an inline `new Date()` is
    // re-evaluated on every page request, so pages get offset into different
    // result sets and a subscription expiring mid-scan silently drops the row
    // at the page boundary. See _shared/subscription.ts for the full note.
    const cutoffIso = new Date().toISOString();
    const proSubs = await fetchAllPages<{ user_id: string }>(
      () =>
        supabase
          .from("subscriptions")
          .select("user_id")
          .eq("status", "active")
          .gt("end_date", cutoffIso),
      { orderBy: "id", label: "protein-gap-alert pro-subs" },
    );

    if (!proSubs || proSubs.length === 0) {
      console.log(
        `[protein-gap-alert] request_id=${requestId} no active PRO users`,
      );
      await logCronEnd(logId, "success", { httpStatus: 200, requestId });
      return new Response(
        JSON.stringify({ status: "success", pro_users: 0, sent: 0 }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const proUserIds = [
      ...new Set(
        proSubs.map((s: Record<string, unknown>) => s.user_id as string),
      ),
    ];

    // 2. Sum today's protein per user from nutrition_logs (one row per
    //    meal_type per day; column is `total_protein`, NOT `total_protein_g`).
    //
    //    OI-79 — this is the single most exposed read in the cron fleet, and
    //    truncating it is worse than missing a user: it produces a WRONG push.
    //    nutrition_logs holds up to 4 rows per user per day (one per meal
    //    type, live-verified), so a bare .in() read clips at ~250 active PRO
    //    users. The rows that fall off are meals the user DID log, so their
    //    protein sums low, and someone who hit their target gets told they are
    //    short. Paged + chunked: fetchAllByIds bounds the URL (chunk) AND the
    //    row count (page) — chunking alone bounds only the former.
    const nutritionRows = await fetchAllByIds<Record<string, unknown>>(
      (chunk) =>
        supabase
          .from("nutrition_logs")
          .select("user_id, total_protein")
          .eq("date", todayIST)
          .in("user_id", chunk),
      proUserIds,
      { orderBy: "id", label: "protein-gap-alert nutrition" },
    );

    const proteinByUser = new Map<string, number>();
    for (const row of nutritionRows ?? []) {
      const uid = (row as Record<string, unknown>).user_id as string;
      const p = Number((row as Record<string, unknown>).total_protein) || 0;
      proteinByUser.set(uid, (proteinByUser.get(uid) ?? 0) + p);
    }

    // 3. Resolve protein target per user.
    //    Primary: user_profile.protein_grams (the canonical column).
    //    Defensive: snapshot_json.daily_targets.protein (not currently
    //    populated by the snapshot writer — kept for forward compat).
    //    OI-79 — both reads are paged as well as chunked. The snapshots read in
    //    particular is the exact failure the Unit C note below describes,
    //    arriving by a different route: truncation past db-max-rows drops
    //    snapshot rows with NO error, the preference lookup then falls through
    //    to its most-permissive default, and users who DISABLED protein alerts
    //    get pushed. `fetchAllByIds` throws on a page error, so the Unit C
    //    "throw → cron telemetry failed → next tick retries" contract holds.
    const [profiles, snapshots] = await Promise.all([
      fetchAllByIds<Record<string, unknown>>(
        (chunk) =>
          supabase
            .from("user_profile")
            .select("user_id, protein_grams, diet_preference")
            .in("user_id", chunk),
        proUserIds,
        { orderBy: "id", label: "protein-gap-alert profiles" },
      ),
      fetchAllByIds<Record<string, unknown>>(
        (chunk) =>
          supabase
            .from("user_daily_snapshots")
            .select("user_id, snapshot_json")
            .eq("snapshot_date", todayIST)
            .in("user_id", chunk),
        proUserIds,
        { orderBy: "id", label: "protein-gap-alert snapshots" },
      ),
    ]);

    const profileByUser = new Map<string, Record<string, unknown>>(
      (profiles ?? []).map((p: Record<string, unknown>) => [
        p.user_id as string,
        p,
      ]),
    );
    const snapByUser = new Map<string, Record<string, unknown>>(
      (snapshots ?? []).map((s: Record<string, unknown>) => [
        s.user_id as string,
        (s.snapshot_json ?? {}) as Record<string, unknown>,
      ]),
    );

    // 4. Walk each PRO user, decide if at-risk, send.
    let sent = 0;
    let onTrack = 0;
    let noTarget = 0;
    let dedupSkipped = 0;
    let prefSkipped = 0;
    let errors = 0;

    // F7 — preferences come from the LATEST snapshot per user, separately from
    // the today-pinned content read above. One extra batched query per run.
    const notifPrefs = await fetchNotificationPrefs(supabase, proUserIds);

    for (const userId of proUserIds) {
      const profile = profileByUser.get(userId) ?? {};
      const snap = snapByUser.get(userId) ?? {};

      // Target resolution (profile first, snapshot fallback).
      const profileTarget = profile.protein_grams as number | undefined;
      const snapTargets = (snap.daily_targets ?? null) as
        | Record<string, unknown>
        | null;
      const snapTarget = snapTargets?.protein as number | undefined;
      const target = (typeof profileTarget === "number" && profileTarget > 0)
        ? profileTarget
        : (typeof snapTarget === "number" && snapTarget > 0)
        ? snapTarget
        : null;

      if (!target || target <= 0) {
        noTarget++;
        continue;
      }

      const consumed = proteinByUser.get(userId) ?? 0;
      const ratio = consumed / target;
      if (ratio >= 0.6) {
        onTrack++;
        continue;
      }

      // Notification preference — read from the LATEST snapshot, not this
      // today-pinned one (F7 / Unit E).
      //
      // The date pin above is correct for CONTENT: a protein-gap alert needs
      // today's intake. It was wrong for PREFERENCES. Live, only 1 of 91
      // snapshot rows is dated today, so for ~16 of 17 users `snap` simply did
      // not exist and this check never ran — the toggle looked implemented and
      // was inert. Preferences are not time-series data; the most recent known
      // value is the right one however old.
      if (!isNotificationEnabled(notifPrefs, userId, "protein_alerts")) {
        prefSkipped++;
        continue;
      }

      // Dedup gate.
      const allow = await shouldSendProactive(supabase, userId, "protein_gap");
      if (!allow) {
        dedupSkipped++;
        continue;
      }

      // Personalize: preferred_name from coach_memory (private_mode aware),
      // diet_preference from user_profile (Indian app uses 'veg' / 'non_veg' /
      // 'vegan' / 'eggetarian' values — NOT 'vegetarian').
      const memory = await fetchCoachMemory(supabase, userId);
      const usableMemory = memory?.private_mode ? null : memory;
      const preferredName = usableMemory?.preferred_name as string | null;
      // OI-47 round 1: this firstName reaches the FALLBACK message that
      // actually ships when Gemini fails or times out -- the sanitised
      // Gemini path is only the success case. Splitting on whitespace
      // drops spaces but not CR, U+2028/2029/0085, controls or angle runs.
      const firstName = preferredName
          ? sanitizeIdentifier(preferredName.split(" ")[0], { maxLen: 32 })
          : null;
      const diet = (profile.diet_preference as string | null) ?? null;

      const gap = Math.round(target - consumed);
      const quickFix = pickQuickFix(gap, diet);
      const greeting = firstName ? `${firstName} — ` : "";
      // Fallback: existing hardcoded English copy preserved as safety net.
      const fallbackMessage =
        `${greeting}${gap}g short on protein today. ${quickFix} Want a dinner suggestion?`;

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          first_name: firstName,
          protein_gap_g: gap,
          protein_consumed_g: Math.round(consumed),
          protein_target_g: Math.round(target),
          diet_preference: diet,
          quick_fix_suggestion: quickFix,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${sanitizeJsonForPrompt(userState)}.\n\n` +
            `Generate a protein gap alert — user is ${gap}g short on protein today ` +
            `and needs a quick fix suggestion before end of day.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[protein-gap-alert] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: "Protein gap",
          message,
          screen: "/ai_coach",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "protein_gap");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(
          `[protein-gap-alert] send failed for ${userId}:`,
          e,
        );
        errors++;
      }
    }

    console.log(
      `[protein-gap-alert] request_id=${requestId} pro_users=${proUserIds.length} sent=${sent} on_track=${onTrack} no_target=${noTarget} dedup_skipped=${dedupSkipped} pref_skipped=${prefSkipped} errors=${errors}`,
    );

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        status: "success",
        pro_users: proUserIds.length,
        sent,
        on_track: onTrack,
        no_target: noTarget,
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
    console.error(`[protein-gap-alert] request_id=${requestId}`, err);
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

/**
 * Pick a quick-fix protein suggestion based on gap size and diet.
 *
 * Diet values from user_profile.diet_preference (Indian app enum):
 *   - 'veg' / 'vegan'  → vegetarian suggestions (paneer, milk, almonds)
 *   - 'eggetarian'     → eggs allowed (treated as non-veg for protein density)
 *   - 'non_veg' / null → all options on the table (chicken, eggs)
 *
 * 6 variants total: 3 gap buckets × {veg, non-veg}.
 */
function pickQuickFix(gap: number, diet: string | null): string {
  const isVeg = diet === "veg" || diet === "vegan";
  if (gap >= 40) {
    return isVeg
      ? "Quick fix: 200g paneer + a glass of milk."
      : "Quick fix: 150g chicken breast or 4 boiled eggs.";
  }
  if (gap >= 20) {
    return isVeg
      ? "Quick fix: 100g paneer or a scoop of whey."
      : "Quick fix: 100g chicken or 3 boiled eggs.";
  }
  return isVeg
    ? "Quick fix: a glass of milk + 30g almonds."
    : "Quick fix: 2 boiled eggs.";
}
