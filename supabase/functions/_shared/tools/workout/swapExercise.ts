import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "ID of the exercise currently in today's workout to be replaced. Get this from the user's snapshot.today_workout.exercises[].id.",
  ),
  newExerciseId: z.string().min(1).describe(
    "ID of the replacement exercise. Must exist in the user's exercise library (built-in or custom). Get IDs from snapshot.today_workout.exercises or snapshot.custom_exercises.",
  ),
  reason: z.string().max(200).optional().describe(
    "Optional brief explanation of why this swap is suggested (shown to the user in the confirmation card). E.g. 'Equipment substitute for home', 'Easier on the shoulder'.",
  ),
});

type SwapExerciseArgs = z.infer<typeof schema>;

export const swapExerciseTool: ToolDefinition<SwapExerciseArgs> = {
  name: "swapExercise",
  family: "workout",
  kind: "write",
  confirmationClass: "reviewable",
  tier: "pro",
  description:
    "Replace one exercise in today's scheduled workout with a different exercise. Use this when the user asks to swap an exercise (e.g. 'swap squats for goblet squats', 'I don't have a barbell, give me a substitute for bench press'). Always reference real exercise IDs from the user's snapshot — never invent IDs.",
  schema,
  intentBuilder: (args) => ({
    type: "swap_exercise",
    payload: {
      exerciseId: args.exerciseId,
      newExerciseId: args.newExerciseId,
      reason: args.reason ?? null,
    },
    confirmationClass: "reviewable",
    // The client builds a richer preview from local Hive (exercise names from its
    // exercise_library mirror). Server preview is fallback-only.
    previewSummary: `Swap exercise: ${args.exerciseId} → ${args.newExerciseId}`,
  }),
};
