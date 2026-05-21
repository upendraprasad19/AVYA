import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  name: z.string().min(3).max(60).describe(
    "Display name for the new exercise. 3-60 chars. Will be shown in the user's library and on workout cards.",
  ),
  category: z.enum([
    "push",
    "pull",
    "legs",
    "core",
    "cardio",
    "flexibility",
    "calisthenics",
    "indian_traditional",
  ]).describe(
    "Top-level category. Pick the closest match — push for chest/shoulder/triceps press movements, pull for back/biceps/rear delt, legs for quad/glute/ham/calf, core for abs/oblique/lower back.",
  ),
  equipment: z.enum([
    "bodyweight",
    "home_dumbbells",
    "basic_gym",
    "full_gym",
  ]).describe(
    "Minimum equipment tier required. bodyweight = no gear, home_dumbbells = dumbbells/bands at home, basic_gym = barbell+rack, full_gym = machines+cables.",
  ),
  loggingType: z.enum([
    "weight_reps",
    "bodyweight_reps",
    "weighted_bodyweight",
    "timed",
    "cardio",
    "distance",
  ]).describe(
    "How sets are logged. weight_reps for free weights, bodyweight_reps for push-ups/pull-ups, weighted_bodyweight for dips with belt, timed for plank, cardio for running, distance for loaded carries.",
  ),
  primaryMuscles: z.array(z.string()).max(5).optional().describe(
    "Optional list of primary muscles worked (e.g. ['Biceps', 'Forearms']). Up to 5.",
  ),
  defaultSets: z.number().int().min(1).max(10).optional().describe(
    "Suggested default set count. Defaults to 3 if omitted.",
  ),
  defaultReps: z.number().int().min(1).max(100).optional().describe(
    "Suggested default reps per set. Required for weight_reps / bodyweight_reps / weighted_bodyweight. Omit for timed / cardio / distance.",
  ),
  defaultDurationSeconds: z.number().int().min(5).max(3600).optional().describe(
    "Suggested default duration in seconds. Required for timed / cardio. Omit for rep-based.",
  ),
});

type Args = z.infer<typeof schema>;

export const createCustomExerciseTool: ToolDefinition<Args> = {
  name: "createCustomExercise",
  family: "workout",
  kind: "write",
  confirmationClass: "reviewable",
  tier: "free",
  description:
    "Create a new custom exercise in the user's personal library. Use after the user mentions an exercise that's NOT in their snapshot's exercise list or custom_exercises list — e.g. they ask 'add hammer curl with water bottle' or describe a homemade movement. Ask follow-up questions to gather the required fields (category, equipment tier, logging type) before calling. After confirmation, the exercise becomes available immediately for swapExercise and other tools on the next turn.",
  schema,
  intentBuilder: (args) => ({
    type: "create_custom_exercise",
    payload: {
      name: args.name,
      category: args.category,
      equipment: args.equipment,
      loggingType: args.loggingType,
      primaryMuscles: args.primaryMuscles ?? [],
      defaultSets: args.defaultSets ?? 3,
      defaultReps: args.defaultReps,
      defaultDurationSeconds: args.defaultDurationSeconds,
    },
    confirmationClass: "reviewable",
    previewSummary:
      `Create custom exercise: ${args.name} (${args.category}, ${args.equipment})`,
  }),
};
