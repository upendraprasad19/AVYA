import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { buildDayMap, inWindow, istDatesEnding, resolveDay } from "../../exercise_day.ts";
import { liveSummaryRows, type SummaryRow } from "../../live_exercise_rows.ts";
import { fetchPagesBounded } from "../../paged_fetch_bounded.ts";
import { fetchWleWindow } from "../../wle_window_read.ts";
import { NON_WORKOUT_STATUSES } from "../../workout_statuses.ts";

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
  truncated: boolean; // true when any read hit its page budget (numbers are a lower bound)
  pr_count: number; // distinct workout days with a live is_pr summary row in the period
}

async function handler(ctx: ToolContext, args: Args): Promise<ProgressSummary> {
  const { sb, userId } = ctx;
  // The window is exactly `periodDays` IST dates ending today (B3). The
  // `date` columns are IST-keyed; summary rows are selected by the UUID v5 of
  // each window date (their `workout_log_id`), NOT by `completed_at`, which is
  // the write time (an edited old log carries a recent one).
  const dates = istDatesEnding(args.periodDays);
  const sinceDate = dates[0];
  const today = dates[dates.length - 1];
  const dayMap = await buildDayMap();

  // Bug t1m5b0 (APK Test #16.2) — the independent SELECTs run via Promise.all
  // so wall clock is the slowest single query, not the sum (3500 -> 6000 ms
  // budget). Pinned by test/contracts/get_progress_summary_parallel_queries_test.dart.
  // L1b: every read is paged (B4) so a long period never stops at PostgREST's
  // 1,000-row cap; summary rows come through the day-window reader (B3).
  const [wle, sched, weights, nutrition] = await Promise.all([
    // 1. Workouts completed + volume + PRs (per-exercise summary rows).
    fetchWleWindow<SummaryRow>((ids, withCount) =>
      sb
        .from("workout_log_exercises")
        .select(
          "id, user_id, workout_log_id, exercise_id, set_number, is_pr, completed_at, deleted_at, weight_kg, reps",
          withCount ? { count: "exact" } : undefined,
        )
        .eq("user_id", userId)
        .in("workout_log_id", ids)
        .is("deleted_at", null), dates, { maxPages: 10, label: "getProgressSummary:wle" }),
    // 2. Workouts planned: scheduled dates up to today that were not paused/skipped/rest/...
    fetchPagesBounded<{ scheduled_date: string; status: string | null }>(
      (withCount) =>
        sb
          .from("scheduled_workouts")
          .select("scheduled_date, status", withCount ? { count: "exact" } : undefined)
          .eq("user_id", userId)
          .gte("scheduled_date", sinceDate)
          .lte("scheduled_date", today),
      {
        orderBy: [{ column: "scheduled_date" }, { column: "id" }],
        maxPages: 5,
        label: "getProgressSummary:scheduled",
      },
    ),
    // 3. Weight delta — period-window weight history.
    fetchPagesBounded<{ date: string; weight_kg: number }>(
      (withCount) =>
        sb
          .from("weight_logs")
          .select("date, weight_kg", withCount ? { count: "exact" } : undefined)
          .eq("user_id", userId)
          .gte("date", sinceDate)
          .lte("date", today),
      {
        orderBy: [{ column: "date" }, { column: "id" }],
        maxPages: 5,
        label: "getProgressSummary:weight",
      },
    ),
    // 4. Nutrition: avg daily calories + days logged.
    fetchPagesBounded<{ date: string; total_calories: number | null }>(
      (withCount) =>
        sb
          .from("nutrition_logs")
          .select("date, total_calories", withCount ? { count: "exact" } : undefined)
          .eq("user_id", userId)
          .gte("date", sinceDate)
          .lte("date", today),
      {
        orderBy: [{ column: "date" }, { column: "id" }],
        maxPages: 10,
        label: "getProgressSummary:nutrition",
      },
    ),
  ]);

  // Unit C (§2.24) — a query failure THROWS (fetchPagesBounded does) instead of
  // being coerced to empty arrays; the tool-loop turns the throw into
  // {error:"execution_failed"} and Gemini narrates honestly.

  // 1. One live row per (user, workout_log_id, exercise_id) (B1), then drop
  //    rows whose RESOLVED day is outside the window (an edited-old row, a
  //    rescheduled-forward row, a missing-date-bucket row from another day).
  const live = liveSummaryRows(wle.rows, dayMap).filter((r) =>
    inWindow(r, dayMap, dates)
  );
  const workoutDates = new Set<string>();
  const prDays = new Set<string>();
  let totalVolume = 0;
  for (const r of live) {
    const day = resolveDay(r, dayMap);
    if (day) workoutDates.add(day);
    // APK Test #12.6 / Obs 8 — `reps` holds CUMULATIVE reps across all sets
    // (3x10 = 30); volume = weight x cumulative reps, never x set_number.
    const w = r.weight_kg ?? 0;
    const reps = r.reps ?? 0;
    totalVolume += w * reps;
    if (r.is_pr && day) prDays.add(day);
  }
  const workoutsCompleted = workoutDates.size;

  // 2. Planned: B7 shared status set (rest days etc. are not workouts).
  const plannedDates = new Set(
    sched.rows
      .filter((s) => s.status !== null && !NON_WORKOUT_STATUSES.has(s.status))
      .map((s) => s.scheduled_date),
  );
  const workoutsPlanned = plannedDates.size;
  const adherencePct = workoutsPlanned > 0
    ? Math.round((workoutsCompleted / workoutsPlanned) * 100)
    : 0;

  // 3. Weight delta.
  const weightRows = weights.rows;
  const weightLogsCount = weightRows.length;
  let weightChange: number | null = null;
  if (weightLogsCount >= 2) {
    const first = weightRows[0].weight_kg;
    const last = weightRows[weightLogsCount - 1].weight_kg;
    weightChange = Number((last - first).toFixed(2));
  }

  // 4. Nutrition: avg daily calories + days logged.
  const nutritionRows = nutrition.rows;
  const nutritionDates = new Set(nutritionRows.map((n) => n.date));
  const totalKcal = nutritionRows.reduce((s, n) => s + (n.total_calories ?? 0), 0);
  const nutritionLogDays = nutritionDates.size;
  const avgDailyCalories = nutritionLogDays > 0 ? Math.round(totalKcal / nutritionLogDays) : null;

  // 5. PR count: distinct workout DAYS with a live is_pr summary row (from
  //    query 1's deduped rows — no separate PR query to disagree with it).
  const prCount = prDays.size;

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
    truncated: wle.truncated || sched.truncated || weights.truncated || nutrition.truncated,
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
  // Bug t1m5b0 (APK Test #16.2) — bumped 3500 -> 6000 ms. With Promise.all
  // the wall clock drops to ~1-1.5 s typical, but cold-Postgres-cache
  // rebuilds (the case the founder hit at 08:34 IST) can take 3-5 s for
  // the largest of the 5 SELECTs. 6 s ceiling preserves headroom without
  // letting genuinely-stuck tool calls block the chat turn indefinitely.
  maxLatencyMs: 6000,
  handler,
};
