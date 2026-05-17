/**
 * evaluate-rank-promotions — nightly cron (00:00 IST / 18:30 UTC).
 *
 * Iterates every signed-up user. For each user, recomputes the rank
 * ceiling from Postgres data (workout_logs total, signup date,
 * deployments_complete from user_progress) and upserts any missing
 * rank_promotions rows + updates the denormalized
 * user_profile.current_rank_code if it lags.
 *
 * Idempotent — UNIQUE (user_id, rank_code) means re-runs are no-ops
 * unless the user's qualified ceiling actually changed.
 *
 * verify_jwt: false  (cron-only). Auth header sent for header-shape
 * consistency with sibling cron functions.
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  EvalState,
  highestQualified,
  LADDER,
  ranksUpTo,
  completionRateOverWindow,
} from "../_shared/rank_engine.ts";
import {
  formatPromotionCeremony,
  rankAddressFor,
  rankDisplayFor,
} from "../_shared/ceremony_text.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronStart, logCronEnd } from "../_shared/cron_telemetry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // audit-2026-05-16 E.14.C — installed shared `isAuthorizedCronCall(req)`
  // gate (no prior inline check existed; cron caller relied on
  // `verify_jwt: false` alone). Survives Vault/env key rotation: verifies
  // JWT signature against SUPABASE_JWT_SECRET + role-claim ===
  // 'service_role'. CRON_SECRET opaque-token escape hatch preserved
  // inside the helper. Closes Test #16 P1-D drift class.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const requestId = crypto.randomUUID().split("-")[0];
  const logId = await logCronStart("evaluate-rank-promotions");

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 1. Pull the user roster (id + signup time).
    const { data: users, error: usersErr } = await supabase
      .from("users")
      .select("id, created_at");

    if (usersErr || !users) {
      console.error(`[evaluate-rank-promotions] request_id=${requestId}`, usersErr);
      await logCronEnd(logId, "failed", {
        httpStatus: 500,
        requestId,
        errorSummary: String(usersErr),
      });
      return new Response(
        JSON.stringify({ error: "Internal server error", request_id: requestId }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let evaluated = 0;
    let promoted = 0;
    const now = new Date();

    for (const u of users as Array<Record<string, unknown>>) {
      const userId = u.id as string;
      const signupAt = new Date(u.created_at as string);
      const weeksSinceSignup = Math.floor(
        (now.getTime() - signupAt.getTime()) / (7 * 24 * 3600 * 1000),
      );

      // Total workouts done (cloud source of truth).
      const { count: totalWorkouts } = await supabase
        .from("workout_logs")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);

      // Read the per-user progress row for streak + deployments.
      const { data: progressRow } = await supabase
        .from("user_progress")
        .select("current_streak_days, deployments_complete, longest_gap_days, last_workout_date")
        .eq("user_id", userId)
        .maybeSingle();

      // Compute days since last workout for the maxGapDays gate (MCPO).
      let lastWorkoutDaysAgo: number | null = null;
      const lastWorkoutDate = progressRow?.last_workout_date as string | undefined;
      if (lastWorkoutDate) {
        const last = new Date(lastWorkoutDate as string);
        lastWorkoutDaysAgo = Math.floor(
          (now.getTime() - last.getTime()) / (24 * 3600 * 1000),
        );
      }

      const state: EvalState = {
        streak: (progressRow?.current_streak_days as number | undefined) ?? 0,
        totalWorkouts: totalWorkouts ?? 0,
        weeksSinceSignup,
        deploymentsComplete:
          (progressRow?.deployments_complete as number | undefined) ?? 0,
        lastWorkoutDaysAgo,
        completionRateProvider: (windowWeeks: number) =>
          completionRateOverWindow(supabase, userId, windowWeeks),
      };

      const winner = await highestQualified(state);
      const eligibleCodes = ranksUpTo(winner.code).map((r) => r.code);

      // What's already on file?
      const { data: existing } = await supabase
        .from("rank_promotions")
        .select("rank_code")
        .eq("user_id", userId);
      const existingCodes = new Set(
        (existing ?? []).map((e: Record<string, unknown>) => e.rank_code as string),
      );

      const toInsert = eligibleCodes
        .filter((c) => !existingCodes.has(c))
        .map((c) => ({
          user_id: userId,
          rank_code: c,
          trigger_type: "combined",
          trigger_metadata: {
            streak: state.streak,
            total_workouts: state.totalWorkouts,
            weeks: state.weeksSinceSignup,
            source: "cron",
          },
        }));

      if (toInsert.length > 0) {
        const { error: insertErr } = await supabase
          .from("rank_promotions")
          .upsert(toInsert, { onConflict: "user_id,rank_code" });
        if (insertErr) {
          console.error(
            `[evaluate-rank-promotions] user=${userId} insert err`,
            insertErr,
          );
          continue;
        }
        promoted += toInsert.length;

        // Insert a Captain-voice ceremony row in ai_coach_interactions for
        // each newly-earned rank, in ladder order. The client surfaces these
        // via _restoreCoachInteractions → coachBox → ChatHistoryNotifier.
        //
        // We reconstruct "old rank" as the highest code already on file
        // before this batch (existingCodes), falling back to "SD2" for a
        // brand-new user. Then we walk the toInsert list in ladder order.
        const ladderOrder = LADDER.map((r) => r.code);
        const sortedNew = toInsert
          .map((row) => row.rank_code)
          .sort(
            (a, b) => ladderOrder.indexOf(a) - ladderOrder.indexOf(b),
          );

        // Determine the starting "previous" rank for ceremony sequencing.
        let prevCode: string = existingCodes.size > 0
          ? [...existingCodes].sort(
              (a, b) => ladderOrder.indexOf(a) - ladderOrder.indexOf(b),
            ).at(-1)! // highest existing rank before this batch
          : "SD2";

        for (const newCode of sortedNew) {
          const ceremonyText = formatPromotionCeremony({
            oldRankAddress: rankAddressFor(prevCode),
            oldRankCode: prevCode,
            newRankCode: newCode,
            newRankDisplay: rankDisplayFor(newCode),
            newRankAddress: rankAddressFor(newCode),
            totalWorkouts: state.totalWorkouts,
            weeksHeld: state.weeksSinceSignup,
          });

          const { error: ceremonyErr } = await supabase
            .from("ai_coach_interactions")
            .insert({
              user_id: userId,
              channel: "promotion_ceremony",
              user_message: "",
              ai_response: ceremonyText,
              model_used: "ceremony_template",
              created_at: new Date().toISOString(),
            });

          if (ceremonyErr) {
            // Non-fatal — log but keep going. The rank_promotion row is
            // already committed; a missing ceremony message is recoverable.
            console.warn(
              `[evaluate-rank-promotions] user=${userId} ceremony insert err for ${newCode}`,
              ceremonyErr,
            );
          }

          prevCode = newCode;
        }
      }

      // Sync denormalized current rank.
      await supabase.from("user_profile").update({
        current_rank_code: winner.code,
        current_rank_achieved_at: now.toISOString(),
      }).eq("user_id", userId);

      evaluated += 1;
    }

    await logCronEnd(logId, "success", { httpStatus: 200, requestId });
    return new Response(
      JSON.stringify({
        status: "success",
        evaluated,
        promoted,
        request_id: requestId,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[evaluate-rank-promotions] request_id=${requestId}`, err);
    await logCronEnd(logId, "failed", {
      httpStatus: 500,
      requestId,
      errorSummary: String(err),
    });
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
