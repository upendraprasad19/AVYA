import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "Exercise name (e.g. 'Bench Press'). Use exact name from snapshot.today_workout or snapshot.custom_exercises.",
  ),
  weightKg: z.number().nonnegative().max(500).describe(
    "PR weight in kilograms.",
  ),
  reps: z.number().int().min(1).max(50).optional().describe(
    "Optional reps for this PR. Defaults to 1 (1RM-style claim).",
  ),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional date the PR was hit (YYYY-MM-DD). Defaults to today.",
  ),
});

type Args = z.infer<typeof schema>;

export const logPRTool: ToolDefinition<Args> = {
  name: "logPR",
  family: "progress",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  description:
    "Log a personal record (PR) for an exercise. Use when the user reports hitting a new max ('hit 120kg deadlift today!', 'new PR: 100kg bench for 3 reps'). The PR-rescan logic auto-detects whether it's actually a new PR vs ties. If it's not a new PR, the log still goes through but is_pr=false on the underlying entry.",
  schema,
  intentBuilder: (args) => ({
    type: "log_pr",
    payload: {
      exerciseId: args.exerciseId,
      weightKg: args.weightKg,
      reps: args.reps ?? 1,
      date: args.date ?? null,
    },
    confirmationClass: "trivial",
    previewSummary:
      `PR: ${args.exerciseId} ${args.weightKg}kg \u00d7 ${args.reps ?? 1}`,
  }),
};
