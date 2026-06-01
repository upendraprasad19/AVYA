// supabase/functions/_shared/tools/progress/getPRTimeline.ts
//
// Captain coach tool: returns dated PR progression for a specific exercise.
// Closes audit P1 G-10 (PR timing) + temporal-query stress test S3.x.
//
// Source: APK Test #4 Plan C / C7.

import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "Exercise name (e.g. 'Bench Press', 'Deadlift'). Matched case-insensitively against workout_log_exercises.exercise_id.",
  ),
  from: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe(
      "Optional ISO date (YYYY-MM-DD). Lower bound on completed_at. Default: beginning of time (all history).",
    ),
  to: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe(
      "Optional ISO date (YYYY-MM-DD). Upper bound on completed_at. Default: today.",
    ),
});

type Args = z.infer<typeof schema>;

interface PREntry {
  date: string;        // YYYY-MM-DD
  weight_kg: number;
  reps: number;
  sets: number;        // set_number = total completed sets
  logging_type: string | null;
  duration_seconds: number | null;
  distance_km: number | null;
}

interface GetPRTimelineResponse {
  exercise_id: string;
  from: string | null;
  to: string | null;
  pr_count: number;
  best_weight_kg: number | null;
  first_pr_date: string | null;
  latest_pr_date: string | null;
  prs: PREntry[]; // Most recent first
  notes: string[];
}

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<GetPRTimelineResponse> {
  const { sb, userId } = ctx;
  const name = args.exerciseId.trim();

  // Per CLAUDE.md §11: exercise_id is the stable identity (= exercise_name).
  // is_pr=true flags the set as a PR. set_number = total completed sets.
  // Schema verified 2026-04-27: exercise_id, weight_kg, reps, set_number,
  // logging_type, duration_seconds, distance_km, is_pr, completed_at all present.
  let q = sb
    .from("workout_log_exercises")
    .select(
      "exercise_id, weight_kg, reps, set_number, logging_type, duration_seconds, distance_km, completed_at",
    )
    .eq("user_id", userId)
    .ilike("exercise_id", name)
    .eq("is_pr", true)
    .order("completed_at", { ascending: false })
    .limit(50);

  if (args.from) q = q.gte("completed_at", args.from);
  if (args.to) q = q.lte("completed_at", args.to + "T23:59:59Z");

  const { data, error } = await q;

  if (error) {
    throw new Error(`getPRTimeline query failed: ${error.message}`);
  }

  if (!data || data.length === 0) {
    return {
      exercise_id: name,
      from: args.from ?? null,
      to: args.to ?? null,
      pr_count: 0,
      best_weight_kg: null,
      first_pr_date: null,
      latest_pr_date: null,
      prs: [],
      notes: [
        `No PR records found for "${name}"${args.from || args.to ? " in the specified date range" : ""}. Check the exercise name against snapshot.personal_records or try getExerciseHistory to see all logged sets.`,
      ],
    };
  }

  type Row = {
    exercise_id: string;
    weight_kg: number | null;
    reps: number | null;
    set_number: number | null;
    logging_type: string | null;
    duration_seconds: number | null;
    distance_km: number | null;
    completed_at: string;
  };

  const prs: PREntry[] = (data as Row[]).map((row) => ({
    date: row.completed_at.slice(0, 10),
    weight_kg: row.weight_kg ?? 0,
    reps: row.reps ?? 0,
    sets: row.set_number ?? 1,
    logging_type: row.logging_type ?? null,
    duration_seconds: row.duration_seconds ?? null,
    distance_km: row.distance_km ?? null,
  }));

  const weights = prs.map((p) => p.weight_kg).filter((w) => w > 0);
  const bestWeight = weights.length > 0 ? Math.max(...weights) : null;

  // data is ordered desc by completed_at, so last element is oldest
  const latestPrDate = prs[0].date;
  const firstPrDate = prs[prs.length - 1].date;

  const notes: string[] = [];
  if (prs.length === 1) {
    notes.push(`Only one PR on record for "${name}". Not enough data for trend analysis.`);
  }
  if (prs.length >= 2) {
    const latestWeight = prs[0].weight_kg;
    const earliestWeight = prs[prs.length - 1].weight_kg;
    const delta = Number((latestWeight - earliestWeight).toFixed(2));
    if (delta > 0) {
      notes.push(
        `Weight progression: ${earliestWeight}kg (${firstPrDate}) → ${latestWeight}kg (${latestPrDate}), +${delta}kg overall.`,
      );
    } else if (delta < 0) {
      notes.push(
        `Weight has regressed from ${earliestWeight}kg (${firstPrDate}) to ${latestWeight}kg (${latestPrDate}).`,
      );
    } else {
      notes.push(
        `Weight has been stable at ${latestWeight}kg since ${firstPrDate}.`,
      );
    }
  }

  return {
    exercise_id: name,
    from: args.from ?? null,
    to: args.to ?? null,
    pr_count: prs.length,
    best_weight_kg: bestWeight,
    first_pr_date: firstPrDate,
    latest_pr_date: latestPrDate,
    prs,
    notes,
  };
}

export const getPRTimelineTool: ToolDefinition<Args, GetPRTimelineResponse> = {
  name: "getPRTimeline",
  family: "progress",
  kind: "read",
  tier: "free",
  description:
    "Returns the dated personal-record (PR) progression for a specific exercise. Call when the user asks about PR history, 'when did I last hit a PR', 'show my deadlift PRs over the last year', 'what was my bench PR in March'. Filters is_pr=true rows only. Supports optional from/to date range (YYYY-MM-DD). Returns PRs newest-first with weight, reps, sets, and a trend note. Use getExerciseHistory for all logged sessions including non-PRs.",
  schema,
  maxLatencyMs: 4000,
  handler,
};
