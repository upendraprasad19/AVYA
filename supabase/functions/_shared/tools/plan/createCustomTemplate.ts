import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";
import type { ToolDefinition } from "../types.ts";

const exerciseSchema = z.object({
  exerciseId: z.string().min(1).describe(
    "Exercise ID. Use the exact `exercise_id` from `snapshot.today_workout.exercises[]` OR `snapshot.custom_exercises[]` for user-created customs. Never invent IDs.",
  ),
  exerciseName: z.string().min(1).describe(
    "Display name (must match the exerciseId's actual name in the user's library).",
  ),
  sets: z.number().int().min(1).max(10).describe(
    "Number of sets (1-10).",
  ),
  reps: z.string().min(1).describe(
    "Reps prescription. Can be a single number ('10'), a range ('8-12'), or 'AMRAP'.",
  ),
  restSeconds: z.number().int().min(0).max(600).optional().describe(
    "Rest between sets in seconds (0-600). Defaults to 60 if omitted.",
  ),
  durationSeconds: z.number().int().min(5).max(3600).optional().describe(
    "For timed exercises (plank, hold). Set instead of reps when the movement is held for time.",
  ),
});

const daySchema = z.object({
  dayName: z.string().min(1).max(40).describe(
    "Day name shown in the user's templates list (e.g. 'Push Day', 'Lower Body A', 'Pull Day'). Each day becomes its own template entry the user can schedule independently.",
  ),
  exercises: z.array(exerciseSchema).min(1).max(15).describe(
    "Exercises for this day (1-15). Order matters — first exercise is performed first.",
  ),
});

const schema = z.object({
  name: z.string().min(3).max(60).describe(
    "Template group name shown in the user's saved templates list (each day is suffixed, e.g. 'Hypertrophy Split - Push Day').",
  ),
  description: z.string().max(200).optional().describe(
    "Optional one-line description of the template's focus.",
  ),
  days: z.array(daySchema).min(1).max(7).describe(
    "Per-day structure (1-7 days). Each day is a complete workout. The template is saved to the library but NOT auto-scheduled — use scheduleTemplate (Phase D.7) to put days on the calendar.",
  ),
  assignedDays: z.array(z.number().int().min(1).max(7)).max(7).optional()
    .describe(
      "Optional default weekday assignments (1=Mon, 7=Sun). Length should match `days.length`. Used by the Train UI's calendar overlay; does NOT auto-schedule.",
    ),
});

type Args = z.infer<typeof schema>;

export const createCustomTemplateTool: ToolDefinition<Args> = {
  name: "createCustomTemplate",
  family: "plan",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Create a custom multi-day workout template in the user's library. Use AFTER gathering requirements through multi-turn dialog — ALWAYS ask the user about (a) equipment available, (b) preferred session length, (c) target muscle groups or focus, and (d) how many days per week BEFORE calling this tool. The template is saved to the user's library but NOT auto-scheduled (use scheduleTemplate next to put it on the calendar). Each day is a complete workout with ordered exercises. Reference existing exercise IDs from `snapshot.today_workout.exercises[].exercise_id` or `snapshot.custom_exercises[].id` — never invent IDs.",
  schema,
  intentBuilder: (args) => {
    const dayCount = args.days.length;
    const exerciseCount = args.days.reduce(
      (s, d) => s + d.exercises.length,
      0,
    );
    return {
      type: "create_custom_template",
      payload: {
        name: args.name,
        description: args.description ?? null,
        days: args.days,
        assigned_days: args.assignedDays ?? [],
      },
      confirmationClass: "destructive",
      previewSummary: `Create template: ${args.name} (${dayCount} day${
        dayCount === 1 ? "" : "s"
      }, ${exerciseCount} exercises total)`,
    };
  },
};
