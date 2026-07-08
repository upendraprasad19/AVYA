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

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  EvalState,
  highestQualified,
  LADDER,
  ranksUpTo,
  completionRateOverWindow,
  buildUserProgressMap,
  buildRankPromotionsMap,
  buildCurrentRankMap,
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

// OPT-E — chunk size for the batch pre-fetch .in("user_id", chunk) calls below.
// Matches the BATCH_SIZE=100 precedent in weekly-recalc/index.ts:267 for the
// identical query shape (unchunked .in() risks PostgREST querystring-length
// limits once the user base is large enough — see docs/plan-reviews for the
// crossover estimate; 7 users today makes this a forward-looking guard, not a
// live bug, but the codebase already has a proven pattern for it).
const BATCH_SIZE = 100;

/** Fetches `columns` for every id in `userIds` from `table`, chunked at
 *  BATCH_SIZE, and returns the concatenated rows. Stops and surfaces the
 *  error on the first failing chunk (partial rows from earlier chunks are
 *  discarded by the caller via the error check, matching the all-or-nothing
 *  semantics of the old single unchunked .in() call).
 *
 *  ⚠️ `scripts/check_schema_column_refs.dart` cannot see the 3 call sites
 *  below — its regex only matches a string LITERAL directly inside
 *  `.from('...')` (documented as `.from(<variable>)` = "NOT validated —
 *  partial coverage by design" in that gate's own header). `table` and
 *  `columns` here are parameters, so a future column rename on
 *  user_progress/rank_promotions/user_profile won't be caught by that gate
 *  for these 3 reads — it WILL fail loudly at runtime instead (42703 →
 *  caught by the error check below → whole-tick abort + failed cron log),
 *  not silently degrade, but it's an unflagged blind spot worth knowing
 *  about before trusting a green gate run after a schema change here. */
async function fetchInChunks(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  table: string,
  columns: string,
  userIds: string[],
): Promise<{ data: Array<Record<string, unknown>>; error: unknown }> {
  const allRows: Array<Record<string, unknown>> = [];
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const chunk = userIds.slice(i, i + BATCH_SIZE);
    const { data, error } = await supabase.from(table).select(columns).in(
      "user_id",
      chunk,
    );
    if (error) return { data: allRows, error };
    allRows.push(...((data ?? []) as Array<Record<string, unknown>>));
  }
  return { data: allRows, error: null };
}

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

    // OPT-E — pre-fetch reads that were previously issued once PER USER
    // (user_progress, rank_promotions, user_profile.current_rank_code) in a
    // single .in() call each. Reduces N*3 queries/tick to 3. Read totalWorkouts
    // (COUNT below) and completionRateOverWindow (via rank_engine, called
    // conditionally per officer-track gate) stay per-user: COUNT batching needs
    // a GROUP BY RPC (invisible to check_schema_column_refs + a migration-
    // sequencing risk if the function deploys before the migration lands), and
    // completionRateOverWindow is rarely invoked (only for users 1+ year in who
    // already cleared every lower gate) with a per-rank window — not worth
    // batching. Batch-read-in-a-whole-batch-cron → throw (Unit C §2.24 precedent,
    // matches the users-roster-fetch abort above: a failed pre-fetch here is as
    // fatal as a failed roster fetch, not a per-user condition).
    const userIds = (users as Array<Record<string, unknown>>).map((u) => u.id as string);
    const [progressBatch, ranksBatch, profileBatch] = await Promise.all([
      fetchInChunks(
        supabase,
        "user_progress",
        "user_id, current_streak_days, deployments_complete, longest_gap_days, last_workout_date",
        userIds,
      ),
      fetchInChunks(supabase, "rank_promotions", "user_id, rank_code", userIds),
      fetchInChunks(supabase, "user_profile", "user_id, current_rank_code", userIds),
    ]);
    const prefetchErr = progressBatch.error ?? ranksBatch.error ?? profileBatch.error;
    if (prefetchErr) {
      console.error(`[evaluate-rank-promotions] request_id=${requestId} pre-fetch batch err`, prefetchErr);
      await logCronEnd(logId, "failed", {
        httpStatus: 500,
        requestId,
        errorSummary: String(prefetchErr),
      });
      return new Response(
        JSON.stringify({ error: "Internal server error", request_id: requestId }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const progressMap = buildUserProgressMap(progressBatch.data ?? []);
    const ranksMap = buildRankPromotionsMap(ranksBatch.data ?? []);
    const currentRankMap = buildCurrentRankMap(profileBatch.data ?? []);

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
      // Unit C (§2.24) — per-user reads in this whole-batch cron CAPTURE the error
      // and SKIP just this user (console.error + continue, matching the insert-error
      // idiom at the upsert below). Pre-fix a silent failure coerced to `?? 0` / null
      // → a WRONG rank state (streak/workouts/deployments read as 0) → a generic or
      // mis-graded promotion ceremony. A top-level throw would zero the WHOLE day's
      // promotions, so skip-one-user (self-heals next daily run) is correct here.
      const { count: totalWorkouts, error: totalWErr } = await supabase
        .from("workout_logs")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);
      if (totalWErr) {
        console.error(`[evaluate-rank-promotions] user=${userId} totalWorkouts err`, totalWErr);
        continue;
      }

      // OPT-E — progress row comes from the batch pre-fetch above (was a
      // per-user .maybeSingle() query; absent-from-map = no row for this user,
      // same as the old query's `data: null` — NOT an error, so `?? 0` below
      // still carries the same meaning it always did).
      const progressRow = progressMap.get(userId) ?? null;

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

      // OPT-E — what's already on file, from the batch pre-fetch above (was a
      // per-user .select().eq() query). Absent-from-map = no earned ranks yet
      // for this user, same as the old query's empty array.
      const existingCodes = ranksMap.get(userId) ?? new Set<string>();

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

      // Sync denormalized current rank — only ever PROMOTE, never demote.
      //
      // Diagnose 3a7b9f (2026-05-27): pre-fix the cron unconditionally
      // overwrote `current_rank_code` with `winner.code` (the currently-
      // qualifying ceiling). When a user broke a sailor-track streak gate
      // (e.g. SD1 → streakAtLeast: 7), `winner.code` recomputed to SD2 and
      // the user was silently demoted. Rank is permanent: `rank_promotions`
      // is the append-only event log; `user_profile.current_rank_code` is
      // its denormalization and must monotonically increase.
      // OPT-E — current_rank_code comes from the batch pre-fetch above (was a
      // per-user .maybeSingle() query). Absent-from-map = no profile row yet,
      // same as the old query's `data: null`.
      const currentCode = currentRankMap.get(userId) ?? null;
      const currentOrdinal = currentCode === null
        ? -1
        : (LADDER.find((r) => r.code === currentCode)?.ordinal ?? -1);
      if (winner.ordinal > currentOrdinal) {
        await supabase.from("user_profile").update({
          current_rank_code: winner.code,
          current_rank_achieved_at: now.toISOString(),
        }).eq("user_id", userId);
      }

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
