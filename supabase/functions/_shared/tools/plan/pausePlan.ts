import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";

const schema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe(
    "First date to pause (YYYY-MM-DD). Use today's date if the user says 'starting today' / 'from today'.",
  ),
  days: z.number().int().min(1).max(30).describe(
    "How many consecutive days to pause (1-30). For travel/vacation use the actual trip duration; for illness 'a few days' = 3-5.",
  ),
  reason: z.string().max(120).optional().describe(
    "Optional brief reason ('Goa trip', 'sick', 'work travel') shown in the confirmation card and stored on each paused entry.",
  ),
});

type Args = z.infer<typeof schema>;

export const pausePlanTool: ToolDefinition<Args> = {
  name: "pausePlan",
  family: "plan",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Pause the user's scheduled workouts for a date range (1-30 days). Use when the user mentions travel, illness, scheduled rest, or any reason they won't be training. Each affected scheduled_workout becomes status='paused' (preserved, not deleted) — the user can resume by manually completing or by regenerating the plan. Already-completed workouts are NOT paused (skipped silently).",
  selectionHints:
    "Use when user wants today (or a future day) marked as REST or skipped. Distinct from rescheduleWeek (moves the workout to another day) and logSet (records completed work).",
  schema,
  intentBuilder: (args) => ({
    type: "pause_plan",
    payload: {
      start_date: args.startDate,
      days: args.days,
      reason: args.reason ?? null,
    },
    confirmationClass: "destructive",
    previewSummary: `Pause ${args.days} day${args.days === 1 ? "" : "s"} from ${args.startDate}${args.reason ? ` (${args.reason})` : ""}`,
  }),
};
