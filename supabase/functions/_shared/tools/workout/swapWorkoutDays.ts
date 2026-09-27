// supabase/functions/_shared/tools/workout/swapWorkoutDays.ts
//
// Coach tool for a same-week two-day content swap (spec
// 2026-09-26-day-swapper-design.md §5.8). PRO, reviewable (the client shows
// an inline confirm card before applying), gated behind the
// swap_workout_days capability so an old client build — one that predates
// Task 12's engine — is never offered a tool it cannot execute
// (day_swap_routing.ts / client_capabilities.ts, Task 9/U3).
//
// Params are plain Zod strings (not a date-shaped custom type): zodToGemini
// throws on unsupported Zod types (zodToGemini.ts:95), and the ENGINE
// re-validates the dates anyway at apply time (DaySwapRules.pairRefusal +
// lockOf inside SwapService.swapDays) — this tool's own regex is a cheap
// first filter, not the source of truth.

import { z } from "npm:zod@3.25.76";
import type { ToolDefinition } from "../types.ts";
import { CAPABILITY_SWAP_WORKOUT_DAYS } from "../../day_swap_routing.ts";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const schema = z.object({
  dateA: z.string().regex(ISO_DATE).describe(
    "First IST date of the pair to swap, YYYY-MM-DD.",
  ),
  dateB: z.string().regex(ISO_DATE).describe(
    "Second IST date of the pair to swap, YYYY-MM-DD.",
  ),
});

type Args = z.infer<typeof schema>;

export const swapWorkoutDaysTool: ToolDefinition<Args> = {
  name: "swapWorkoutDays",
  family: "workout",
  kind: "write",
  confirmationClass: "reviewable",
  tier: "pro",
  requiresCapability: CAPABILITY_SWAP_WORKOUT_DAYS,
  description:
    "Swap the scheduled content of two days within the same Mon-Sun week (e.g. trade Friday's and Saturday's workouts, or move a single workout to another day this week). Content moves; the identity of each date (phase, week, hold state) stays. Always review the two-day move plan before confirming.",
  selectionHints:
    "Use for a request to swap, exchange or trade two scheduled days, or to move a single workout to another day within the same week (e.g. 'swap Friday and Saturday', 'do Friday's workout on Saturday instead', 'move today's pull to Friday and Friday's to today'). NOT for reshaping which weekdays the user trains on across the whole week — that is rescheduleWeek.",
  schema,
  intentBuilder: (args) => {
    return {
      type: "swap_workout_days",
      payload: { dateA: args.dateA, dateB: args.dateB },
      confirmationClass: "reviewable",
      previewSummary: `Swap ${args.dateA} and ${args.dateB}`,
    };
  },
};
