import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "Exercise name (e.g. 'Bench Press', 'Squat'). Use the EXACT name from snapshot.today_workout.exercises[].name or snapshot.personal_records keys.",
  ),
  weeks: z.number().int().min(1).max(52).describe(
    "How many weeks back to fetch (1-52). Use 4 for monthly progression, 12 for quarterly, 52 for yearly.",
  ),
});

type Args = z.infer<typeof schema>;

interface HistoryEntry {
  date: string; // YYYY-MM-DD
  weight_kg: number;
  reps: number;
  sets: number;
  is_pr: boolean;
  total_volume_kg: number; // weight * reps * sets
}

interface ExerciseHistoryResponse {
  exercise_id: string;
  weeks: number;
  total_sessions: number;
  pr_count: number;
  best_weight_kg: number | null;
  best_volume_kg: number | null;
  current_weight_kg: number | null; // Most recent log
  weight_change_kg: number | null; // Most recent - oldest
  history: HistoryEntry[]; // Chronological, oldest first
  notes: string[];
}

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<ExerciseHistoryResponse> {
  const { sb, userId } = ctx;
  const since = new Date(Date.now() - args.weeks * 7 * 86400_000).toISOString();

  // Per CLAUDE.md §11, workout_log_exercises is the per-exercise summary table.
  // Schema (verified via execute_sql): exercise_id (text, NOT NULL) carries the
  // stable exercise name; set_number = total completed sets; weight_kg = best
  // across sets; reps = cumulative reps; is_pr boolean; completed_at timestamptz.
  const { data, error } = await sb
    .from("workout_log_exercises")
    .select(
      "workout_log_id, exercise_id, weight_kg, reps, set_number, is_pr, completed_at",
    )
    .eq("user_id", userId)
    .ilike("exercise_id", args.exerciseId) // case-insensitive name match
    .gte("completed_at", since)
    .order("completed_at", { ascending: true });

  if (error) {
    throw new Error(`getExerciseHistory query failed: ${error.message}`);
  }

  if (!data || data.length === 0) {
    return {
      exercise_id: args.exerciseId,
      weeks: args.weeks,
      total_sessions: 0,
      pr_count: 0,
      best_weight_kg: null,
      best_volume_kg: null,
      current_weight_kg: null,
      weight_change_kg: null,
      history: [],
      notes: [
        `No history for "${args.exerciseId}" in the last ${args.weeks} weeks. Check the spelling against snapshot.today_workout or snapshot.personal_records.`,
      ],
    };
  }

  const history: HistoryEntry[] = (data as Array<{
    completed_at: string;
    weight_kg: number | null;
    reps: number | null;
    set_number: number | null;
    is_pr: boolean | null;
  }>).map((row) => {
    const w = row.weight_kg ?? 0;
    const r = row.reps ?? 0;
    const s = row.set_number ?? 1;
    return {
      date: row.completed_at.slice(0, 10),
      weight_kg: w,
      reps: r,
      sets: s,
      is_pr: row.is_pr ?? false,
      total_volume_kg: Math.round(w * r * s),
    };
  });

  const prCount = history.filter((h) => h.is_pr).length;
  const bestWeight = Math.max(...history.map((h) => h.weight_kg));
  const bestVolume = Math.max(...history.map((h) => h.total_volume_kg));
  const currentWeight = history[history.length - 1].weight_kg;
  const oldestWeight = history[0].weight_kg;
  const weightChange = Number((currentWeight - oldestWeight).toFixed(2));

  const notes: string[] = [];
  if (history.length === 1) {
    notes.push(
      `Only one logged session for "${args.exerciseId}" in this window — limited progression signal.`,
    );
  }
  if (weightChange < 0) {
    notes.push(
      `Weight has decreased ${Math.abs(weightChange).toFixed(1)}kg over the period.`,
    );
  } else if (weightChange === 0 && history.length >= 4) {
    notes.push(
      `Weight has been stable at ${currentWeight}kg for the period.`,
    );
  }

  return {
    exercise_id: args.exerciseId,
    weeks: args.weeks,
    total_sessions: history.length,
    pr_count: prCount,
    best_weight_kg: bestWeight,
    best_volume_kg: bestVolume,
    current_weight_kg: currentWeight,
    weight_change_kg: weightChange,
    history,
    notes,
  };
}

export const getExerciseHistoryTool: ToolDefinition<
  Args,
  ExerciseHistoryResponse
> = {
  name: "getExerciseHistory",
  family: "progress",
  kind: "read",
  tier: "pro",
  description:
    "Fetch the chronological progression of one specific exercise over the last N weeks (1-52). Returns each session's weight × reps × sets, PR flags, best weight, weight change. Use when the user asks 'how is my bench progressing?', 'show my squat over 3 months', 'what's my PR history on deadlift'. The user's snapshot has top-5 PRs only — call this for full progression of a single lift.",
  schema,
  maxLatencyMs: 4000,
  handler,
};
