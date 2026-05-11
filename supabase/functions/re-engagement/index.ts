/**
 * re-engagement — Brainstorm §5 trigger #8.
 *
 * Cron: 30 06 * * * (UTC) = 12:00 IST = noon IST daily. Mid-day to maximise
 * the chance the phone is on hand. Cron registration deferred to T6.
 *
 * Goal: nudge users who have gone silent for 3+ days. Two-path candidate
 * detection — both run in the same invocation, results unioned:
 *
 *   Path A (preferred) — coach_memory.dropout_risk_score >= 0.5. The
 *   nightly `compute_coach_signals_for_user` RPC populates this from a
 *   blend of workout frequency, chat silence, weigh-in gap and sleep
 *   averages. One read, multi-signal — strictly better than the raw
 *   per-table check.
 *
 *   Path B (fallback) — for users without a coach_memory row yet (the
 *   warmup gap before the nightly cron has run for them), we fall back
 *   to a direct `max(activity)` check across workout_logs, nutrition_logs
 *   and weight_logs. If `users.last_active_at` is recent (<3d) we skip
 *   the per-table queries entirely — fast path for the engaged majority.
 *
 * Tier: BOTH free + PRO. Re-engagement matters for everyone — there is
 * no monetisation logic gating the nudge. (Distinct from plateau-alert,
 * which is PRO-only retention.)
 *
 * Copy: single softest-possible message ("no judgment, just check in").
 * Brainstorm rule — coach asks, never tells. The full conversation
 * reset happens when the user taps in.
 *
 * Dedup: shouldSendProactive("re_engagement") gates one nudge per IST
 * day per user. So a user sitting at >3d silence won't get blasted
 * every noon — they get one nudge, then we hold until the next type.
 *
 * Privacy: respects coach_memory.private_mode (suppresses preferred
 * name; nudge still ships). Path B users have no preferred name to
 * suppress.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { sendPushNotification } from "../_shared/send_notification.ts";
import {
  markProactiveSent,
  shouldSendProactive,
} from "../_shared/proactive_dedup.ts";
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat, MODEL_FLASH } from "../_shared/gemini.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * Threshold tuned to "medium dropout risk" — the brainstorm spec calls
 * for action at 3 days silence. The compute_coach_signals formula
 * already weights silence heavily so 0.5 is the natural cut-off.
 */
const DROPOUT_THRESHOLD = 0.5;
const SILENCE_DAYS_FALLBACK = 3;

// Audit C-4 (2026-05-11, closes-diagnose 7ad0c4): added CRON_SECRET / service-role-key gate.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── C-4 cron-auth gate ───────────────────────────────────────────────
  // Audit 2026-05-11 / closes-diagnose 7ad0c4. These cron functions had
  // `verify_jwt: false` and no manual auth. Now require Bearer == either
  // SUPABASE_SERVICE_ROLE_KEY (existing pg_cron path) OR CRON_SECRET
  // (rotatable hardening). If CRON_SECRET env var is unset, only the
  // service-role-key path works — graceful rollout.
  {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length)
      : "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const cronSecret = Deno.env.get("CRON_SECRET");
    const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
    const isCronSecret = !!cronSecret && token === cronSecret;
    if (!isServiceRole && !isCronSecret) {
      console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  }

  const requestId = crypto.randomUUID().split("-")[0];

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ──────────────────────────────────────────────────────────
    // PATH A — coach_memory.dropout_risk_score >= 0.5
    // ──────────────────────────────────────────────────────────
    const { data: highRisk, error: memError } = await supabase
      .from("coach_memory")
      .select(
        "user_id, dropout_risk_score, preferred_name, private_mode, signals_computed_at",
      )
      .gte("dropout_risk_score", DROPOUT_THRESHOLD)
      .not("signals_computed_at", "is", null);
    if (memError) throw memError;

    const memoryRows = (highRisk ?? []) as Record<string, unknown>[];
    const candidatesFromMemory = new Set<string>(
      memoryRows.map((r) => r.user_id as string),
    );
    const memoryById = new Map<string, Record<string, unknown>>(
      memoryRows.map((r) => [r.user_id as string, r]),
    );

    // ──────────────────────────────────────────────────────────
    // PATH B — fallback for users without coach_memory rows.
    //
    // Pull all active users; skip those already in path A or whose
    // `last_active_at` is fresh; then verify per-table activity.
    // Per-user query cost is small (3 indexed point queries) and
    // user count is bounded — this is fine for daily cron at our
    // current scale.
    // ──────────────────────────────────────────────────────────
    const cutoffMs = Date.now() - SILENCE_DAYS_FALLBACK * 86_400_000;
    const cutoffIso = new Date(cutoffMs).toISOString();
    const cutoffDate = cutoffIso.slice(0, 10); // YYYY-MM-DD

    const { data: allUsers, error: userError } = await supabase
      .from("users")
      .select("id, last_active_at, full_name, is_deleted")
      .or("is_deleted.is.null,is_deleted.eq.false");
    if (userError) throw userError;

    const fallbackCandidates: string[] = [];
    const fallbackNames = new Map<string, string | null>();

    for (const u of (allUsers ?? []) as Record<string, unknown>[]) {
      const userId = u.id as string;

      // Already covered by path A — skip.
      if (candidatesFromMemory.has(userId)) continue;

      // Fast-path: if last_active_at is recent, definitely not silent.
      const lastActiveRaw = u.last_active_at as string | null;
      if (lastActiveRaw) {
        const lastActiveMs = new Date(lastActiveRaw).getTime();
        if (Number.isFinite(lastActiveMs) && lastActiveMs >= cutoffMs) {
          continue;
        }
      }

      // Per-table verification — any activity in the window kicks them out.
      const { data: anyWorkout } = await supabase
        .from("workout_logs")
        .select("date")
        .eq("user_id", userId)
        .gte("date", cutoffDate)
        .limit(1);
      if ((anyWorkout ?? []).length > 0) continue;

      const { data: anyNutrition } = await supabase
        .from("nutrition_logs")
        .select("date")
        .eq("user_id", userId)
        .gte("date", cutoffDate)
        .limit(1);
      if ((anyNutrition ?? []).length > 0) continue;

      const { data: anyWeight } = await supabase
        .from("weight_logs")
        .select("date")
        .eq("user_id", userId)
        .gte("date", cutoffDate)
        .limit(1);
      if ((anyWeight ?? []).length > 0) continue;

      fallbackCandidates.push(userId);
      fallbackNames.set(userId, (u.full_name as string | null) ?? null);
    }

    const allCandidates = [
      ...Array.from(candidatesFromMemory),
      ...fallbackCandidates,
    ];

    if (allCandidates.length === 0) {
      console.log(
        `[re-engagement] request_id=${requestId} no candidates (path_a=0 path_b=0)`,
      );
      return new Response(
        JSON.stringify({
          status: "success",
          from_memory: 0,
          from_fallback: 0,
          sent: 0,
          dedup_skipped: 0,
          errors: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let sent = 0;
    let dedupSkipped = 0;
    let errors = 0;

    for (const userId of allCandidates) {
      // Dedup gate — one re_engagement push per user per IST day.
      const allow = await shouldSendProactive(supabase, userId, "re_engagement");
      if (!allow) {
        dedupSkipped++;
        continue;
      }

      // Resolve a first name without leaking PII through private_mode.
      // Path A users may have curated `preferred_name` in coach_memory;
      // path B users only have raw `full_name` from the users table.
      let firstName: string | null = null;
      const memory = memoryById.get(userId);
      if (memory) {
        const isPrivate = memory.private_mode === true;
        if (!isPrivate) {
          const preferred = memory.preferred_name as string | null;
          if (preferred && preferred.length > 0) {
            firstName = preferred.split(" ")[0];
          }
        }
      } else {
        const fullName = fallbackNames.get(userId);
        if (fullName && fullName.length > 0) {
          firstName = fullName.split(" ")[0];
        }
      }

      const greeting = firstName ? `${firstName} — ` : "";
      // Fallback: existing hardcoded English copy preserved as safety net.
      const fallbackMessage =
        `${greeting}haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.`;

      // Generate Captain-voiced copy via Gemini; fall back to English on error.
      let message = fallbackMessage;
      try {
        const userState = {
          first_name: firstName,
          silence_days_min: SILENCE_DAYS_FALLBACK,
        };
        const { content } = await geminiChat({
          model: MODEL_FLASH,
          systemPrompt: captainPrompt("proactive"),
          userPrompt:
            `User state: ${JSON.stringify(userState)}.\n\n` +
            `Generate a re-engagement nudge for a user who has been silent for ` +
            `${SILENCE_DAYS_FALLBACK}+ days. No judgment — the Captain asks, never tells.`,
          maxTokens: 120,
          temperature: 0.7,
        });
        if (content && content.trim().length > 0) {
          message = content.trim();
        }
      } catch (e) {
        console.warn(
          `[re-engagement] Gemini failed for ${userId}, using fallback copy: ${e}`,
        );
      }

      try {
        const ok = await sendPushNotification({
          userId,
          title: "Just checking in",
          message,
          screen: "/ai_coach",
        });
        if (ok) {
          sent++;
          await markProactiveSent(supabase, userId, "re_engagement");
        } else {
          errors++;
        }
      } catch (e) {
        console.warn(`[re-engagement] send failed for ${userId}:`, e);
        errors++;
      }
    }

    console.log(
      `[re-engagement] request_id=${requestId} from_memory=${candidatesFromMemory.size} from_fallback=${fallbackCandidates.length} sent=${sent} dedup_skipped=${dedupSkipped} errors=${errors}`,
    );

    return new Response(
      JSON.stringify({
        status: "success",
        from_memory: candidatesFromMemory.size,
        from_fallback: fallbackCandidates.length,
        sent,
        dedup_skipped: dedupSkipped,
        errors,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error(`[re-engagement] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
