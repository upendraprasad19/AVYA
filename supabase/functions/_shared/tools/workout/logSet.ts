import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  exerciseId: z.string().min(1).describe(
    "ID of the exercise being logged. From snapshot.today_workout.exercises[].id or snapshot.custom_exercises[].id.",
  ),
  weightKg: z.number().nonnegative().max(500).describe(
    "Weight lifted in kilograms. 0 for bodyweight exercises. Cap 500kg.",
  ),
  reps: z.number().int().min(1).max(100).describe(
    "Repetitions per set.",
  ),
  sets: z.number().int().min(1).max(20).describe(
    "Number of sets completed at this weight × reps.",
  ),
});

type LogSetArgs = z.infer<typeof schema>;

export const logSetTool: ToolDefinition<LogSetArgs> = {
  name: "logSet",
  family: "workout",
  kind: "write",
  confirmationClass: "trivial",
  tier: "free",
  description:
    "Log a completed exercise (sets × reps × weight). Use when the user reports finishing an exercise via chat (e.g. 'log my bench: 80kg 4 sets of 10', 'just did 3x12 squats at 100'). Always parse weight in kg. PR detection happens automatically client-side after logging.",
  selectionHints:
    "Use when user describes completed sets (with weight/reps/duration). Don't use when user is asking to reschedule, swap, or pause — those are different tools.",
  schema,
  intentBuilder: (args) => ({
    type: "log_set",
    payload: {
      exerciseId: args.exerciseId,
      weightKg: args.weightKg,
      reps: args.reps,
      sets: args.sets,
    },
    confirmationClass: "trivial",
    previewSummary: `Log: ${args.exerciseId} ${args.weightKg}kg × ${args.reps} × ${args.sets} sets`,
  }),
};
