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

// F3 (Task 27 fix round, review "Minor" finding): ISO_DATE above validates
// SHAPE only — "2026-02-30" and "2026-13-01" both match the regex despite
// not being real calendar dates. This is real-CALENDAR-date validation:
// parse as UTC and require the round-trip (year/month/day read back off the
// constructed Date) to equal the input. `new Date(Date.UTC(2026, 1, 30))`
// silently rolls forward to March 2 rather than throwing, which is exactly
// why a naive `!isNaN(Date.parse(...))` check would NOT catch this — the
// round-trip comparison is what catches the overflow. Applied via
// `.refine()` so a failure still produces the same `safeParse({success:
// false})` shape the existing regex check already produces (Zod issue on
// the field) — no new error shape, no change to how tool-loop.ts /
// zodToGemini.ts consume this schema.
function isRealCalendarDate(value: string): boolean {
  if (!ISO_DATE.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return (
    dt.getUTCFullYear() === y &&
    dt.getUTCMonth() === m - 1 &&
    dt.getUTCDate() === d
  );
}

const dateField = z.string().regex(ISO_DATE).refine(isRealCalendarDate, {
  message: "must be a real calendar date (YYYY-MM-DD), not just the right shape",
});

const schema = z.object({
  dateA: dateField.describe(
    "First IST date of the pair to swap, YYYY-MM-DD.",
  ),
  dateB: dateField.describe(
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
