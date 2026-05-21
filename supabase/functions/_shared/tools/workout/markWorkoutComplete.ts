import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Date in YYYY-MM-DD format. Defaults to today if omitted. Use only for past dates the user mentions completing.",
  ),
});

type Args = z.infer<typeof schema>;

export const markWorkoutCompleteTool: ToolDefinition<Args> = {
  name: "markWorkoutComplete",
  family: "workout",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  description:
    "Mark a scheduled workout as completed. Use when the user says 'mark today done', 'I finished my workout yesterday', etc. Only call this if the user explicitly says they completed the workout (don't infer from chat context). Optional date parameter — defaults to today.",
  schema,
  intentBuilder: (args) => ({
    type: "mark_workout_complete",
    payload: {
      date: args.date ?? null, // null means today; client resolves
    },
    confirmationClass: "trivial",
    previewSummary: args.date
      ? `Mark ${args.date} workout complete`
      : "Mark today's workout complete",
  }),
};
