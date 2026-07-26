import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { istDateStr } from "../_shared/ist_date.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface WorkoutLog {
  user_id: string;
  exercise_id: string;
  exercise_name: string;
  weight_kg: number | null;
  reps: number | null;
  completed_at: string;
  date: string; // derived from completed_at
}

interface ScheduledWorkout {
  user_id: string;
  status: string;
  scheduled_date: string;
}

/**
 * Calculates experience level based on 4 weeks of workout data.
 *
 * Scoring:
 * - Weight progression: Did they increase weight on key exercises? (0-25)
 * - Completion rate: Workouts done / planned (0-25)
 * - Exercise variety: Unique exercises used (0-25)
 * - Consistency: How many of the 4 weeks had at least 1 workout (0-25)
 *
 * Total: 0-100
 * beginner: 0-39, intermediate: 40-69, advanced: 70-100
 */
function calculateExperienceLevel(
  logs: WorkoutLog[],
  scheduled: ScheduledWorkout[],
): string {
  if (logs.length === 0) return "beginner";

  // --- Weight Progression Score (0-25) ---
  // Group logs by exercise, check if weight increased over the 4 weeks
  const exerciseWeights: Record<string, { date: string; weight: number }[]> = {};
  for (const log of logs) {
    if (log.weight_kg && log.weight_kg > 0) {
      const key = log.exercise_id ?? log.exercise_name;
      if (!exerciseWeights[key]) exerciseWeights[key] = [];
      exerciseWeights[key].push({ date: log.date, weight: log.weight_kg });
    }
  }

  let progressingExercises = 0;
  let totalWeightedExercises = 0;
  for (const entries of Object.values(exerciseWeights)) {
    if (entries.length < 2) continue;
    totalWeightedExercises++;
    const sorted = entries.sort(
      (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
    );
    const firstWeight = sorted[0].weight;
    const lastWeight = sorted[sorted.length - 1].weight;
    if (lastWeight > firstWeight) progressingExercises++;
  }

  const progressionScore =
    totalWeightedExercises > 0
      ? Math.round((progressingExercises / totalWeightedExercises) * 25)
      : 0;

  // --- Completion Rate Score (0-25) ---
  const totalPlanned = scheduled.length || 1;
  const totalCompleted = scheduled.filter((s) => s.status === "completed").length;
  const completionScore = Math.round(
    Math.min(totalCompleted / totalPlanned, 1) * 25,
  );

  // --- Exercise Variety Score (0-25) ---
  const uniqueExercises = new Set(
    logs.map((l) => l.exercise_id ?? l.exercise_name),
  );
  // 15+ unique exercises in 4 weeks = max score
  const varietyScore = Math.round(Math.min(uniqueExercises.size / 15, 1) * 25);

  // --- Consistency Score (0-25) ---
  // How many of the 4 weeks had at least 1 workout logged
  const weeksWithWorkouts = new Set<number>();
  const now = new Date();
  for (const log of logs) {
    const logDate = new Date(log.date);
    const weekNum = Math.floor(
      (now.getTime() - logDate.getTime()) / (7 * 24 * 60 * 60 * 1000),
    );
    if (weekNum >= 0 && weekNum < 4) weeksWithWorkouts.add(weekNum);
  }
  const consistencyScore = Math.round((weeksWithWorkouts.size / 4) * 25);

  const totalScore =
    progressionScore + completionScore + varietyScore + consistencyScore;

  if (totalScore >= 70) return "advanced";
  if (totalScore >= 40) return "intermediate";
  return "beginner";
}

/**
 * Fetches all rows from a table with pagination to handle large datasets.
 * Supabase JS client returns max 1000 rows by default; this fetches all pages.
 */
async function fetchAllRows<T>(
  supabaseClient: SupabaseClient,
  table: string,
  selectCols: string,
  dateColumn: string,
  dateGte: string,
): Promise<T[]> {
  const PAGE_SIZE = 1000;
  const allRows: T[] = [];
  let offset = 0;
  let hasMore = true;

  while (hasMore) {
    const { data, error } = await supabaseClient
      .from(table)
      .select(selectCols)
      .gte(dateColumn, dateGte)
      .range(offset, offset + PAGE_SIZE - 1);

    if (error) {
      throw new Error(`Failed to fetch ${table} at offset ${offset}: ${error.message}`);
    }

    if (data && data.length > 0) {
      allRows.push(...(data as T[]));
      offset += data.length;
      // If we got fewer rows than PAGE_SIZE, we've reached the end
      hasMore = data.length === PAGE_SIZE;
    } else {
      hasMore = false;
    }
  }

  return allRows;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ── Auth gate added 2026-07-26 (diagnose c3f8a1, Hermes L23/L24).
  //
  // This function shipped verify_jwt=false with NO authentication of any kind
  // while creating a SERVICE-ROLE client below — so any unauthenticated POST
  // from anywhere on the internet could drive a full-fleet recalculation over
  // every user. It escaped every guard because it is scheduled by nothing (zero
  // cron.job rows) and its client constant `weeklyRecalcFunction` is declared
  // but never invoked, so neither the cron registry nor any call-site grep saw
  // it — while `cron_auth_adoption_test.dart` omitted it and
  // `cron_telemetry_adoption_test.dart` listed it, the two hand-maintained
  // lists disagreeing about what it even is.
  //
  // Exactly the F44 shape: an unguarded verify_jwt=false service-role endpoint
  // invisible because no list covered it.
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[weekly-recalc] unauthorized caller; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // OI-21 / audit-2026-05-29 EF-2: in-function execution telemetry so the
  // alert_edge_function_health cron (migrations 076/077) can SEE weekly-recalc
  // failures via cron_call_log. pg_cron's job_run_details only reflects the
  // net.http_post dispatch, not the EF's actual HTTP outcome.
  //
  // Placed AFTER the gate above — before it, an anonymous caller would get an
  // unauthenticated INSERT into public.cron_call_log (see _shared/cron_auth.ts).
  const logId = await logCronStart("weekly-recalc");

  try {
    const start = Date.now();

    // Cron-shaped job: service-role client, authorized by the CRON_SECRET gate
    // above rather than by a caller JWT.
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // audit-2026-05-11 H-8 — 4-week window now IST-anchored so the
    // weekly recalc covers IST weeks not UTC weeks (5h30m drift
    // would mis-align with the user's actual training calendar).
    const fourWeeksAgo = new Date();
    fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);
    const fourWeeksAgoStr = istDateStr(fourWeeksAgo);

    // ── STEP 1: Bulk fetch ALL data in 2 parallel queries ──
    // Read from workout_log_exercises (per-exercise data) instead of workout_logs
    // (which now stores summary rows after sync refactor).
    const [rawLogs, allScheduled] = await Promise.all([
      fetchAllRows<{ user_id: string; exercise_id: string; exercise_name: string; weight_kg: number | null; reps: number | null; completed_at: string }>(
        supabaseClient,
        "workout_log_exercises",
        "user_id, exercise_id, exercise_name, weight_kg, reps, completed_at",
        "completed_at",
        fourWeeksAgoStr + "T00:00:00Z",
      ),
      fetchAllRows<ScheduledWorkout>(
        supabaseClient,
        "scheduled_workouts",
        "user_id, status, scheduled_date",
        "scheduled_date",
        fourWeeksAgoStr,
      ),
    ]);

    // Derive date from completed_at for downstream scoring
    const allLogs: WorkoutLog[] = rawLogs.map((r) => ({
      ...r,
      date: r.completed_at ? r.completed_at.split("T")[0] : fourWeeksAgoStr,
    }));

    console.log(
      `weekly-recalc: fetched ${allLogs.length} logs, ${allScheduled.length} scheduled in ${Date.now() - start}ms`,
    );

    // ── STEP 2: Group by user_id in JavaScript ──
    const logsByUser = new Map<string, WorkoutLog[]>();
    for (const log of allLogs) {
      const list = logsByUser.get(log.user_id);
      if (list) {
        list.push(log);
      } else {
        logsByUser.set(log.user_id, [log]);
      }
    }

    const scheduledByUser = new Map<string, ScheduledWorkout[]>();
    for (const sw of allScheduled) {
      const list = scheduledByUser.get(sw.user_id);
      if (list) {
        list.push(sw);
      } else {
        scheduledByUser.set(sw.user_id, [sw]);
      }
    }

    // Merge all user IDs from both maps (a user might have logs but no schedule, or vice versa)
    const allUserIds = new Set<string>([
      ...logsByUser.keys(),
      ...scheduledByUser.keys(),
    ]);

    console.log(
      `weekly-recalc: grouped data for ${allUserIds.size} users in ${Date.now() - start}ms`,
    );

    // ── STEP 3: Calculate experience level for each user locally ──
    const levels = new Map<string, string>();
    const workoutCounts = new Map<string, number>();

    for (const userId of allUserIds) {
      const userLogs = logsByUser.get(userId) || [];
      const userScheduled = scheduledByUser.get(userId) || [];

      const level = calculateExperienceLevel(userLogs, userScheduled);
      levels.set(userId, level);
      // Count distinct workout dates, not exercise rows.
      // Each row is a per-exercise summary; a 6-exercise workout = 6 rows but 1 workout.
      const distinctDates = new Set(userLogs.map((l) => l.date));
      workoutCounts.set(userId, distinctDates.size);
    }

    console.log(
      `weekly-recalc: calculated levels for ${levels.size} users in ${Date.now() - start}ms`,
    );

    // ── STEP 4: Batch UPDATE in chunks of 100 concurrent upserts ──
    const BATCH_SIZE = 100;
    const userIds = Array.from(allUserIds);
    let processed = 0;
    let errors = 0;
    const nowIso = new Date().toISOString();

    // Diagnose 3a7b9f (2026-05-27, c2 audit finding): `total_workouts_done`
    // is a LIFETIME monotonic counter incremented by client at workout
    // completion (train_provider.dart:1420). Pre-fix this cron overwrote
    // it with the count of distinct dates from the LAST 4 WEEKS of
    // workout_log_exercises (recompute window at line 174-176 + line 251).
    // For any user who trained more than 4 weeks ago, the recalc would
    // silently DECREASE their lifetime counter every Sunday. Defense:
    // pre-fetch existing values and apply GREATEST in the upsert payload.
    // Same monotonic-field-recompute class as the rank demotion fix.
    const existingProgress = new Map<string, number>();
    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
      const chunk = userIds.slice(i, i + BATCH_SIZE);
      const { data: rows } = await supabaseClient
        .from("user_progress")
        .select("user_id, total_workouts_done")
        .in("user_id", chunk);
      for (const row of (rows ?? []) as Array<Record<string, unknown>>) {
        existingProgress.set(
          row.user_id as string,
          (row.total_workouts_done as number | null) ?? 0,
        );
      }
    }

    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
      const chunk = userIds.slice(i, i + BATCH_SIZE);

      const results = await Promise.all(
        chunk.map((userId) => {
          const recomputed = workoutCounts.get(userId) || 0;
          const existing = existingProgress.get(userId) || 0;
          const monotonicTotal = Math.max(recomputed, existing);
          return supabaseClient
            .from("user_progress")
            .upsert(
              {
                user_id: userId,
                detected_experience_level: levels.get(userId),
                experience_last_calculated: nowIso,
                total_workouts_done: monotonicTotal,
              },
              { onConflict: "user_id" },
            )
            .then((res) => ({ userId, error: res.error }));
        }),
      );

      for (const result of results) {
        if (result.error) {
          console.error(
            `Failed to update experience for user ${result.userId}:`,
            result.error,
          );
          errors++;
        } else {
          processed++;
        }
      }
    }

    const totalTime = Date.now() - start;
    console.log(
      `weekly-recalc: processed ${processed} users, ${errors} errors in ${totalTime}ms`,
    );

    const status = errors === 0 ? "success" : (errors > processed ? "failed" : "partial");
    const httpStatus = errors > processed ? 500 : 200;
    await logCronEnd(logId, httpStatus >= 400 ? "failed" : "success", {
      httpStatus,
      errorSummary: errors > 0 ? `${errors} user-update errors` : undefined,
    });
    return new Response(
      JSON.stringify({
        status,
        users_processed: processed,
        errors,
        total_users: allUserIds.size,
        total_logs: allLogs.length,
        total_scheduled: allScheduled.length,
        duration_ms: totalTime,
      }),
      {
        status: httpStatus,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    // Sanitised 5xx: never leak raw exception / SQL text.
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[weekly-recalc] request_id=${requestId}`, err);
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
