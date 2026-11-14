import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  minutes: z.number().int().min(10).max(120).describe(
    "Target session duration in minutes (10-120). The system drops accessory work and keeps compound movements to fit the budget.",
  ),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Date in YYYY-MM-DD format. Defaults to today.",
  ),
});

type Args = z.infer<typeof schema>;

export const shortenWorkoutTool: ToolDefinition<Args> = {
  name: "shortenWorkout",
  family: "workout",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  description:
    "Trim today's workout to fit a shorter time budget. Use when the user says 'I only have 20 minutes', 'shorten this session', etc. The system keeps compound movements (squat, bench, deadlift, row, OHP variants) and drops accessory/isolation work to fit the target. Cap is 10-120 minutes.",
  schema,
  intentBuilder: (args) => ({
    type: "shorten_workout",
    payload: {
      minutes: args.minutes,
      date: args.date ?? null,
    },
    confirmationClass: "trivial",
    previewSummary: `Shorten ${args.date ?? "today's"} workout to ${args.minutes} min`,
  }),
};
