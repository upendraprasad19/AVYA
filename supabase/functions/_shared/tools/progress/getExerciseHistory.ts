import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { buildDayMap, inWindow, istDatesEnding, resolveDay } from "../../exercise_day.ts";
import { liveSummaryRows, type SummaryRow } from "../../live_exercise_rows.ts";
import { fetchWleWindow } from "../../wle_window_read.ts";

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
  total_reps: number; // cumulative reps across ALL sets of the session
  sets: number;
  is_pr: boolean;
  total_volume_kg: number; // best weight * total reps
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
  // Window = exactly `weeks * 7` IST dates ending today (B3). Summary rows are
  // selected by the UUID v5 of each date (`workout_log_id`), never by
  // `completed_at` (the write time), then attributed to their own day.
  const dates = istDatesEnding(args.weeks * 7);
  const dayMap = await buildDayMap();

  // Per docs/architecture/ai.md, workout_log_exercises is the per-exercise summary table:
  // exercise_id = stable exercise name; set_number = completed-set COUNT; weight_kg =
  // best across sets; reps = CUMULATIVE reps across all sets; is_pr; completed_at.
  const fetched = await fetchWleWindow<SummaryRow>((ids, withCount) =>
    sb
      .from("workout_log_exercises")
      .select(
        "id, user_id, workout_log_id, exercise_id, weight_kg, reps, set_number, is_pr, completed_at, deleted_at",
        withCount ? { count: "exact" } : undefined,
      )
      .eq("user_id", userId)
      .ilike("exercise_id", args.exerciseId) // case-insensitive name match
      .in("workout_log_id", ids)
      .is("deleted_at", null), dates, { maxPages: 5, label: "getExerciseHistory" });

  // One live row per (user, day, exercise); in-window by RESOLVED day; then
  // chronological by (resolved day, completed_at) — pages are keyed by the
  // random id and chunks arrive concurrently, so order is applied here (R9T-2).
  const data = liveSummaryRows(fetched.rows, dayMap)
    .filter((r) => inWindow(r, dayMap, dates))
    .map((r) => ({ r, day: resolveDay(r, dayMap) as string }))
    .sort((x, y) =>
      x.day < y.day ? -1 : x.day > y.day ? 1 : String(x.r.completed_at ?? "").localeCompare(String(y.r.completed_at ?? ""))
    );

  if (data.length === 0) {
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

  const history: HistoryEntry[] = data.map(({ r: row, day }) => {
    const w = row.weight_kg ?? 0;
    const reps = row.reps ?? 0;
    const s = row.set_number ?? 1;
    return {
      date: day,
      weight_kg: w,
      total_reps: reps,
      sets: s,
      is_pr: row.is_pr ?? false,
      // `reps` already holds the cumulative reps of every set: volume is best
      // weight x total reps, never x sets (a pyramid is still overstated).
      total_volume_kg: Math.round(w * reps),
    };
  });

  const prCount = history.filter((h) => h.is_pr).length;
  const bestWeight = Math.max(...history.map((h) => h.weight_kg));
  const bestVolume = Math.max(...history.map((h) => h.total_volume_kg));
  const currentWeight = history[history.length - 1].weight_kg;
  const oldestWeight = history[0].weight_kg;
  const weightChange = Number((currentWeight - oldestWeight).toFixed(2));

  const notes: string[] = [];
  if (fetched.truncated) {
    notes.push("History was truncated at the read limit; older sessions may be missing.");
  }
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
    "Fetch the chronological progression of one specific exercise over the last N weeks (1-52). Returns each session's best weight, total reps across all sets and set count, PR flags, best weight, weight change (total_volume_kg = best weight × total reps). Use when the user asks 'how is my bench progressing?', 'show my squat over 3 months', 'what's my PR history on deadlift'. The user's snapshot has top-5 PRs only — call this for full progression of a single lift.",
  schema,
  maxLatencyMs: 4000,
  handler,
};
