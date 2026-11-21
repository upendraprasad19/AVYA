// supabase/functions/_shared/tools/progress/getPRTimeline.ts
//
// Captain coach tool: returns dated PR progression for a specific exercise.
// Closes audit P1 G-10 (PR timing) + temporal-query stress test S3.x.
//
// Source: APK Test #4 Plan C / C7.

import { z } from "npm:zod@3.25.76";
import type { ToolContext, ToolDefinition } from "../types.ts";
import { buildDayMap, resolveDay } from "../../exercise_day.ts";
import { istDateStr } from "../../ist_date.ts";
import { liveSummaryRows, type SummaryRow } from "../../live_exercise_rows.ts";
import { fetchPagesBounded } from "../../paged_fetch_bounded.ts";

/** PRs returned at most; `pr_count` still counts every live PR in range. */
const MAX_PRS = 50;

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "Exercise name (e.g. 'Bench Press', 'Deadlift'). Matched case-insensitively against workout_log_exercises.exercise_id.",
  ),
  from: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe(
      "Optional IST date (YYYY-MM-DD). Earliest workout DAY to include. Default: beginning of time (all history).",
    ),
  to: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe(
      "Optional IST date (YYYY-MM-DD). Latest workout DAY to include. Default: today.",
    ),
});

type Args = z.infer<typeof schema>;

interface PREntry {
  date: string;        // YYYY-MM-DD
  weight_kg: number;
  total_reps: number;  // cumulative reps across all sets
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
  truncated: boolean; // true when more than 50 PRs exist (only the 50 most recent are listed)
  prs: PREntry[]; // Most recent first
  notes: string[];
}

async function handler(
  ctx: ToolContext,
  args: Args,
): Promise<GetPRTimelineResponse> {
  const { sb, userId } = ctx;
  const name = args.exerciseId.trim();

  // Per docs/architecture/ai.md: exercise_id is the stable identity (= exercise_name).
  // Read ALL of the exercise's live summary rows (paged, no is_pr filter, no
  // limit): dedupe must run BEFORE the is_pr filter or a stale PR on a
  // superseded row would survive (B1), and the cap applies after sorting (B6).
  const dayMap = await buildDayMap();
  const fetched = await fetchPagesBounded<SummaryRow>((withCount) =>
    sb
      .from("workout_log_exercises")
      .select(
        "id, user_id, workout_log_id, exercise_id, weight_kg, reps, set_number, logging_type, duration_seconds, distance_km, is_pr, completed_at, deleted_at",
        withCount ? { count: "exact" } : undefined,
      )
      .eq("user_id", userId)
      .ilike("exercise_id", name)
      .is("deleted_at", null), { orderBy: [{ column: "id" }], maxPages: 10, label: "getPRTimeline" });

  // `from` / `to` are IST dates compared with each row's RESOLVED day (not its
  // write time), so an edited old log keeps its own date (B3).
  const live = liveSummaryRows(fetched.rows, dayMap)
    .map((r) => ({ r, day: resolveDay(r, dayMap) }))
    .filter((x): x is { r: SummaryRow; day: string } => x.day !== null)
    .filter((x) => (!args.from || x.day >= args.from) && x.day <= (args.to ?? istDateStr()))
    .filter((x) => x.r.is_pr === true)
    .sort((a, z) =>
      a.day !== z.day
        ? (a.day < z.day ? 1 : -1)
        : String(z.r.completed_at ?? "").localeCompare(String(a.r.completed_at ?? ""))
    );

  if (live.length === 0) {
    return {
      exercise_id: name,
      from: args.from ?? null,
      to: args.to ?? null,
      pr_count: 0,
      best_weight_kg: null,
      first_pr_date: null,
      latest_pr_date: null,
      truncated: false,
      prs: [],
      notes: [
        `No PR records found for "${name}"${args.from || args.to ? " in the specified date range" : ""}. Check the exercise name against snapshot.personal_records or try getExerciseHistory to see all logged sets.`,
      ],
    };
  }

  const toEntry = ({ r: row, day }: { r: SummaryRow; day: string }): PREntry => ({
    date: day,
    weight_kg: row.weight_kg ?? 0,
    total_reps: row.reps ?? 0,
    sets: row.set_number ?? 1,
    logging_type: row.logging_type ?? null,
    duration_seconds: row.duration_seconds ?? null,
    distance_km: row.distance_km ?? null,
  });
  const allCount = live.length;
  const allFirst = live[live.length - 1].day;
  const prs: PREntry[] = live.slice(0, MAX_PRS).map(toEntry);
  const truncated = allCount > MAX_PRS || fetched.truncated;

  const weights = live.map((x) => x.r.weight_kg ?? 0).filter((w) => w > 0);
  const bestWeight = weights.length > 0 ? Math.max(...weights) : null;

  // `live` is sorted newest-first by (resolved day, completed_at).
  const latestPrDate = prs[0].date;
  const firstPrDate = allFirst;

  const notes: string[] = [];
  if (truncated) {
    notes.push(
      `Showing the ${prs.length} most recent of ${allCount} PRs${fetched.truncated ? " (read limit reached; older history may be missing)" : ""}; pr_count and first_pr_date cover every PR found.`,
    );
  }
  if (allCount === 1) {
    notes.push(`Only one PR on record for "${name}". Not enough data for trend analysis.`);
  }
  if (allCount >= 2) {
    const latestWeight = prs[0].weight_kg;
    const earliestWeight = live[live.length - 1].r.weight_kg ?? 0;
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
    pr_count: allCount,
    best_weight_kg: bestWeight,
    first_pr_date: firstPrDate,
    latest_pr_date: latestPrDate,
    truncated,
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
    "Returns the dated personal-record (PR) progression for a specific exercise. Call when the user asks about PR history, 'when did I last hit a PR', 'show my deadlift PRs over the last year', 'what was my bench PR in March'. Lists only PR rows. Supports optional from/to workout-day range (IST, YYYY-MM-DD). Returns up to 50 PRs newest-first with weight, total reps across all sets, set count, and a trend note. Use getExerciseHistory for all logged sessions including non-PRs.",
  schema,
  maxLatencyMs: 4000,
  handler,
};
