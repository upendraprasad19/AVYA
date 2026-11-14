import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  bodyPart: z.enum([
    "shoulder",
    "elbow",
    "wrist",
    "lower_back",
    "upper_back",
    "knee",
    "ankle",
    "hip",
    "neck",
    "chest",
    "hamstring",
    "quad",
    "calf",
  ]).describe(
    "Affected body part. Use the closest match — e.g. for biceps tendinitis pick 'elbow', for SI joint pick 'lower_back'.",
  ),
  severity: z.enum(["mild", "moderate", "severe"]).describe(
    "mild = work around it (avoid heavy direct loading); moderate = swap most affected exercises; severe = drop direct loading entirely + recommend rest.",
  ),
  daysAhead: z.number().int().min(1).max(14).optional().describe(
    "How many upcoming scheduled days to modify. Defaults to 7.",
  ),
});

type Args = z.infer<typeof schema>;

export const modifyWorkoutForInjuryTool: ToolDefinition<Args> = {
  name: "modifyWorkoutForInjury",
  family: "workout",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Modify upcoming scheduled workouts to work around an injury. Use when the user mentions an injury, pain, or limitation (e.g. 'tweaked my shoulder', 'knee acting up', 'pulled my hamstring'). The system swaps exercises that load the affected body part for safe substitutes across the next 7 days (default), then records the injury in the user's coach_memory so future plan generations consider it. Always destructive — review the full diff before confirming.",
  schema,
  intentBuilder: (args) => ({
    type: "modify_workout_for_injury",
    payload: {
      bodyPart: args.bodyPart,
      severity: args.severity,
      daysAhead: args.daysAhead ?? 7,
    },
    confirmationClass: "destructive",
    previewSummary:
      `Modify next ${args.daysAhead ?? 7} days for ${args.severity} ${args.bodyPart} injury`,
  }),
};
