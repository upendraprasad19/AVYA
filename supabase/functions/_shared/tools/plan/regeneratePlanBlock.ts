import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  weeks: z.number().int().min(1).max(12).describe(
    "Number of weeks of new plan to generate (1-12). Typically 4 weeks (one phase block).",
  ),
  goal: z.enum([
    "build_muscle",
    "lose_fat",
    "general_fitness",
    "strength",
  ]).optional().describe(
    "Optional new goal. Defaults to user's current profile goal. Use when the user explicitly mentions changing focus.",
  ),
  daysPerWeek: z.number().int().min(3).max(6).optional().describe(
    "Optional new training frequency (3-6). Defaults to user's current setting. Use when the user mentions changing schedule.",
  ),
  equipment: z.enum([
    "bodyweight",
    "home_dumbbells",
    "basic_gym",
    "full_gym",
  ]).optional().describe(
    "Optional new equipment tier. Defaults to user's current setting. Use when the user mentions equipment changes.",
  ),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional start date (YYYY-MM-DD). Defaults to today.",
  ),
});

type Args = z.infer<typeof schema>;

export const regeneratePlanBlockTool: ToolDefinition<Args> = {
  name: "regeneratePlanBlock",
  family: "plan",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Regenerate the user's scheduled workouts for the next N weeks (1-12, typically 4) using the existing plan generator. Use when the user explicitly asks to start a new phase ('new 4-week hypertrophy block', 'regenerate my plan'), change goal/equipment/frequency, or refresh their plan after a long break. OVERWRITES any non-completed scheduled workouts in the window — completed workouts are preserved. Always destructive — review the plan before confirming.",
  schema,
  intentBuilder: (args) => ({
    type: "regenerate_plan_block",
    payload: {
      weeks: args.weeks,
      goal: args.goal ?? null,
      days_per_week: args.daysPerWeek ?? null,
      equipment: args.equipment ?? null,
      start_date: args.startDate ?? null,
    },
    confirmationClass: "destructive",
    previewSummary: `Regenerate next ${args.weeks} weeks${
      args.goal ? ` for ${args.goal}` : ""
    }${args.daysPerWeek ? ` (${args.daysPerWeek} days/week)` : ""}`,
  }),
};
