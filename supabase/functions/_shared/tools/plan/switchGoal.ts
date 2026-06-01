import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  newGoal: z.enum([
    "build_muscle",
    "lose_fat",
    "general_fitness",
    "strength",
  ]).describe(
    "New primary fitness goal. The user's profile is permanently updated to this; their plan is regenerated to match.",
  ),
  weeks: z.number().int().min(1).max(12).optional().describe(
    "Optional: weeks of new plan to generate (defaults to 4). Same semantics as regeneratePlanBlock.",
  ),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional start date for the regenerated plan (defaults to today).",
  ),
});

type Args = z.infer<typeof schema>;

export const switchGoalTool: ToolDefinition<Args> = {
  name: "switchGoal",
  family: "plan",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Permanently change the user's primary fitness goal AND regenerate their plan to match. Use when the user explicitly says 'switch to [goal]', 'change my goal to [goal]', 'I want to focus on [goal] now'. The four supported goals are build_muscle, lose_fat, general_fitness, strength. The user's profile is updated and the next 4 weeks (default) of scheduled workouts are regenerated. Always destructive — the diff sheet shows both the goal change AND the new first-week workout structure.",
  schema,
  intentBuilder: (args) => ({
    type: "switch_goal",
    payload: {
      new_goal: args.newGoal,
      weeks: args.weeks ?? 4,
      start_date: args.startDate ?? null,
    },
    confirmationClass: "destructive",
    previewSummary: `Switch goal \u2192 ${args.newGoal} + regenerate ${
      args.weeks ?? 4
    } weeks`,
  }),
};
