import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface WorkoutLog {
  exercise_id: string;
  exercise_name: string;
  weight_kg: number | null;
  sets_completed: number | null;
  reps_completed: number | null;
  date: string;
}

interface ScheduledWorkout {
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

  try {
    // This is a cron job — uses service role key, no JWT validation
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Find users active in the last 7 days
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const { data: activeUsers, error: usersError } = await supabaseClient
      .from("users")
      .select("id")
      .gte("last_active_at", sevenDaysAgo.toISOString());

    if (usersError) {
      console.error("Failed to fetch active users:", usersError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch active users" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!activeUsers || activeUsers.length === 0) {
      return new Response(
        JSON.stringify({ status: "success", users_processed: 0 }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const fourWeeksAgo = new Date();
    fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);
    const fourWeeksAgoStr = fourWeeksAgo.toISOString().split("T")[0];

    let processed = 0;
    let errors = 0;

    for (const { id: userId } of activeUsers) {
      try {
        // Pull last 4 weeks of workout_logs
        const { data: workoutLogs, error: logsError } = await supabaseClient
          .from("workout_logs")
          .select(
            "exercise_id, exercise_name, weight_kg, sets_completed, reps_completed, date",
          )
          .eq("user_id", userId)
          .gte("date", fourWeeksAgoStr);

        if (logsError) {
          console.error(`Failed to fetch logs for user ${userId}:`, logsError);
          errors++;
          continue;
        }

        // Pull scheduled workouts for completion rate
        const { data: scheduledWorkouts, error: schedError } = await supabaseClient
          .from("scheduled_workouts")
          .select("status, scheduled_date")
          .eq("user_id", userId)
          .gte("scheduled_date", fourWeeksAgoStr);

        if (schedError) {
          console.error(
            `Failed to fetch scheduled workouts for user ${userId}:`,
            schedError,
          );
          errors++;
          continue;
        }

        const level = calculateExperienceLevel(
          (workoutLogs ?? []) as WorkoutLog[],
          (scheduledWorkouts ?? []) as ScheduledWorkout[],
        );

        // Update user_progress
        const { error: updateError } = await supabaseClient
          .from("user_progress")
          .update({
            detected_experience_level: level,
            experience_last_calculated: new Date().toISOString(),
          })
          .eq("user_id", userId);

        if (updateError) {
          console.error(
            `Failed to update experience for user ${userId}:`,
            updateError,
          );
          errors++;
          continue;
        }

        processed++;
      } catch (userErr) {
        console.error(`Error processing user ${userId}:`, userErr);
        errors++;
      }
    }

    return new Response(
      JSON.stringify({
        status: "success",
        users_processed: processed,
        errors,
        total_active: activeUsers.length,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("Weekly recalc error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
