import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  days: z.number().int().min(1).max(7).describe(
    "Number of consecutive days to generate (1-7). Capped at 7.",
  ),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional start date (YYYY-MM-DD). Defaults to today.",
  ),
});

type Args = z.infer<typeof schema>;

export const generateHotelWorkoutTool: ToolDefinition<Args> = {
  name: "generateHotelWorkout",
  family: "workout",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Replace the user's scheduled workouts for the next N days (1-7) with a bodyweight-only plan suited for hotels, travel, or no-equipment situations. Use when the user mentions travel, vacation, business trip, no gym access, etc. Calls the same PlanGenerator the app uses internally with equipment='bodyweight'. OVERWRITES any non-completed scheduled workouts in that window — completed workouts are preserved. Always destructive — review the plan before confirming.",
  schema,
  intentBuilder: (args) => ({
    type: "generate_hotel_workout",
    payload: {
      days: args.days,
      startDate: args.startDate ?? null,
    },
    confirmationClass: "destructive",
    previewSummary: `Generate ${args.days}-day bodyweight plan${
      args.startDate ? " starting " + args.startDate : ""
    }`,
  }),
};
