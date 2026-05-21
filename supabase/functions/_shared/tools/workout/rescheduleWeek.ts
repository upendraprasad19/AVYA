import { z } from "https://deno.land/x/zod@v3.25.76/mod.ts";
import type { ToolDefinition } from "../types.ts";

const dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const schema = z.object({
  daysAvailable: z.array(z.number().int().min(1).max(7)).min(1).max(7).describe(
    "Weekdays the user is available to train. 1=Monday, 7=Sunday. E.g. [1,3,5] for Mon/Wed/Fri.",
  ),
  weekStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe(
    "Optional start of week to reshuffle (YYYY-MM-DD, must be a Monday). Defaults to current week's Monday.",
  ),
});

type Args = z.infer<typeof schema>;

export const rescheduleWeekTool: ToolDefinition<Args> = {
  name: "rescheduleWeek",
  family: "workout",
  kind: "write",
  confirmationClass: "destructive",
  tier: "pro",
  description:
    "Reshuffle this week's scheduled workouts to fit a new set of available days. Use when the user says 'I'm only free Mon/Wed/Fri this week', 'cut me down to 3 days', etc. The system moves workouts to the nearest available day; workouts that don't fit are DROPPED (not merged). Always destructive — review the full move plan before confirming.",
  selectionHints:
    "Use when user wants to MOVE a workout to a different day (e.g., 'move Friday's pull to today', 'shift this week back by 1 day'). Distinct from logSet (records completed work) and pausePlan (rest day).",
  schema,
  intentBuilder: (args) => {
    const sortedDays = [...args.daysAvailable].sort((a, b) => a - b);
    const dayLabels = sortedDays.map((d) => dayNames[d - 1]).join(", ");
    return {
      type: "reschedule_week",
      payload: {
        daysAvailable: sortedDays,
        weekStart: args.weekStart ?? null,
      },
      confirmationClass: "destructive",
      previewSummary:
        `Reshuffle week to ${sortedDays.length} day${sortedDays.length > 1 ? "s" : ""}: ${dayLabels}`,
    };
  },
};
