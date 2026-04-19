import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  periodDays: z.number().int().min(7).max(365).describe(
    "How many days back to summarize. Use 30 for monthly review, 90 for quarterly, 7 for last week.",
  ),
});

type Args = z.infer<typeof schema>;

interface ProgressSummary {
  period_days: number;
  workouts_completed: number;
  workouts_planned: number;
  adherence_pct: number; // 0-100
  total_volume_kg: number; // sum of weight*reps*sets across all logged exercises in period
  weight_change_kg: number | null; // (latest weight in period) - (earliest weight in period); null if <2 weight logs
  weight_logs_count: number;
  avg_daily_calories: number | null; // null if 0 nutrition logs
  nutrition_log_days: number; // distinct dates with at least one nutrition_log
  pr_count: number; // distinct workout_log_ids with at least one is_pr=true exercise log in the period
}

// Helper: ISO date (YYYY-MM-DD) from any timestamp / date string. Falls back to original
// when input is already a date-only string.
function toDateOnly(s: string): string {
  return s.length >= 10 ? s.slice(0, 10) : s;
}

async function handler(ctx: ToolContext, args: Args): Promise<ProgressSummary> {
  const { sb, userId } = ctx;
  // ISO date N days ago (UTC). Used for `date` columns and as a lower bound on `completed_at`.
  const sinceDate = new Date(Date.now() - args.periodDays * 86400_000).toISOString().slice(0, 10);
  const sinceTs = `${sinceDate}T00:00:00Z`;

  // 1. Workouts completed + total volume (per-exercise summary table).
  //    Schema deviation from spec: `workout_logs.total_volume_kg` does NOT exist in prod.
  //    Per CLAUDE.md §11, exercise-level data lives in `workout_log_exercises`. We derive
  //    distinct workout days from completed_at and compute volume from weight*reps*set_number.
  const { data: exRows } = await sb
    .from("workout_log_exercises")
    .select("completed_at, weight_kg, reps, set_number")
    .eq("user_id", userId)
    .gte("completed_at", sinceTs);

  const workoutDates = new Set<string>();
  let totalVolume = 0;
  for (
    const r of (exRows ?? []) as Array<
      { completed_at: string; weight_kg: number | null; reps: number | null; set_number: number | null }
    >
  ) {
    if (r.completed_at) workoutDates.add(toDateOnly(r.completed_at));
    const w = r.weight_kg ?? 0;
    const reps = r.reps ?? 0;
    const sets = r.set_number ?? 1;
    totalVolume += w * reps * sets;
  }
  const workoutsCompleted = workoutDates.size;

  // 2. Workouts planned (distinct scheduled dates that weren't paused/skipped).
  const { data: scheduled } = await sb
    .from("scheduled_workouts")
    .select("scheduled_date, status")
    .eq("user_id", userId)
    .gte("scheduled_date", sinceDate);

  const plannedDates = new Set(
    ((scheduled ?? []) as Array<{ scheduled_date: string; status: string | null }>)
      .filter((s) => s.status !== "paused" && s.status !== "skipped")
      .map((s) => s.scheduled_date),
  );
  const workoutsPlanned = plannedDates.size;
  const adherencePct = workoutsPlanned > 0
    ? Math.round((workoutsCompleted / workoutsPlanned) * 100)
    : 0;

  // 3. Weight delta.
  const { data: weights } = await sb
    .from("weight_logs")
    .select("date, weight_kg")
    .eq("user_id", userId)
    .gte("date", sinceDate)
    .order("date", { ascending: true });

  const weightRows = (weights ?? []) as Array<{ date: string; weight_kg: number }>;
  const weightLogsCount = weightRows.length;
  let weightChange: number | null = null;
  if (weightLogsCount >= 2) {
    const first = weightRows[0].weight_kg;
    const last = weightRows[weightLogsCount - 1].weight_kg;
    weightChange = Number((last - first).toFixed(2));
  }

  // 4. Nutrition: avg daily calories + days logged.
  const { data: nutrition } = await sb
    .from("nutrition_logs")
    .select("date, total_calories")
    .eq("user_id", userId)
    .gte("date", sinceDate);

  const nutritionRows = (nutrition ?? []) as Array<{ date: string; total_calories: number | null }>;
  const nutritionDates = new Set(nutritionRows.map((n) => n.date));
  const totalKcal = nutritionRows.reduce((s, n) => s + (n.total_calories ?? 0), 0);
  const nutritionLogDays = nutritionDates.size;
  const avgDailyCalories = nutritionLogDays > 0 ? Math.round(totalKcal / nutritionLogDays) : null;

  // 5. PR count: distinct workout_log_ids with any is_pr=true exercise log in the period.
  const { data: prs } = await sb
    .from("workout_log_exercises")
    .select("workout_log_id")
    .eq("user_id", userId)
    .gte("completed_at", sinceTs)
    .eq("is_pr", true);

  const prCount = new Set(
    ((prs ?? []) as Array<{ workout_log_id: string }>).map((p) => p.workout_log_id),
  ).size;

  return {
    period_days: args.periodDays,
    workouts_completed: workoutsCompleted,
    workouts_planned: workoutsPlanned,
    adherence_pct: adherencePct,
    total_volume_kg: Math.round(totalVolume),
    weight_change_kg: weightChange,
    weight_logs_count: weightLogsCount,
    avg_daily_calories: avgDailyCalories,
    nutrition_log_days: nutritionLogDays,
    pr_count: prCount,
  };
}

export const getProgressSummaryTool: ToolDefinition<Args, ProgressSummary> = {
  name: "getProgressSummary",
  family: "progress",
  kind: "read",
  tier: "free",
  description:
    "Fetch an aggregated summary of the user's progress over the last N days (7-365). Returns workouts completed/planned with adherence %, total volume lifted, weight change, average daily calories, days nutrition was logged, and count of PRs hit. Use when the user asks 'how am I tracking', 'show me my progress', 'last month', etc. The user's snapshot already has TODAY and LAST 7 DAYS — only call this tool for periods >7 days.",
  schema,
  maxLatencyMs: 3500,
  handler,
};
