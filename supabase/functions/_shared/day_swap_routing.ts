// supabase/functions/_shared/day_swap_routing.ts
//
// Per-request Captain-Manual block for day-swap requests ("swap Friday and
// Saturday", "move Friday's workout to today"), chosen by (isPro, capability
// declared) rather than left for the model to infer — the model has no way
// to know the caller's subscription tier or the client app's build. Fixes
// the misrouting named in spec §1.1/§5.8: the manual's own multi-intent
// example (captain_manual.ts, pre-fix) and rescheduleWeek.ts's own
// selectionHints (pre-fix) both pointed a two-day swap at rescheduleWeek,
// which reshuffles WHICH weekdays the user trains on and no-ops a same-week
// two-day content swap.
//
// Spec: docs/superpowers/specs/2026-09-26-day-swapper-design.md §5.8, §6.4.
// Capability string (decided in brief_common.md, this batch): "swap_workout_days".

// Exported: Task 27's swapWorkoutDays tool imports this for its
// `requiresCapability`, so the spelling lives in exactly one place.
export const CAPABILITY_SWAP_WORKOUT_DAYS = "swap_workout_days";

export type DaySwapRoutingCase = "pro_capable" | "pro_old_app" | "free";

export function daySwapRoutingCase(
  isPro: boolean,
  capabilities: Set<string>,
): DaySwapRoutingCase {
  if (!isPro) return "free";
  return capabilities.has(CAPABILITY_SWAP_WORKOUT_DAYS)
    ? "pro_capable"
    : "pro_old_app";
}

/** Verbatim from spec §6.4 "Coach, free". */
export const DAY_SWAP_FREE_FALLBACK_LINE =
  "Swapping days from here is a PRO order, Recruit. You can do it yourself in two taps: on the Workout tab, tap ⇅ next to Friday and pick Saturday. You have 1 swap this week.";

/** Verbatim from spec §6.4 "Coach, PRO on an old app (NEW)". */
export const DAY_SWAP_OLD_APP_LINE =
  "Swapping days from here needs the latest app. After updating, ask me again or tap ⇅ next to the day on the Workout tab.";

const PRO_CAPABLE_BLOCK = `
## DAY SWAP ROUTING — PRO, capability declared
The user's client supports the swapWorkoutDays tool. For a request to swap,
exchange or trade two scheduled days, or to move a single workout to another
day within the same week ("swap Friday and Saturday", "do Friday's workout on
Saturday instead", "move Friday's pull to today and today's pull to Friday"),
call swapWorkoutDays with the two dates. Do NOT call rescheduleWeek for this —
rescheduleWeek changes WHICH weekdays the user trains on; it does not exchange
the content of two specific days, and it silently no-ops a two-day swap.
Example narration: "Aye, Recruit. Friday and Saturday trade places: Legs +
Core today, Pull + Core tomorrow. Confirm below and it's done."
`;

const FREE_BLOCK = `
## DAY SWAP ROUTING — FREE user
Swapping days is a PRO feature. For a request to swap, exchange or trade two
scheduled days, or to move a single workout to another day within the same
week, do NOT call swapWorkoutDays or rescheduleWeek. Reply with this line,
adjusting the day names and the remaining-swap count to the user's actual
request and allowance — the wording otherwise stays exactly this:
"${DAY_SWAP_FREE_FALLBACK_LINE}"
`;

const PRO_OLD_APP_BLOCK = `
## DAY SWAP ROUTING — PRO, capability NOT declared (old app build)
The user is PRO but their client did not declare the swap_workout_days
capability, meaning their installed app predates this feature. For a request
to swap, exchange or trade two scheduled days, or to move a single workout to
another day within the same week, do NOT call swapWorkoutDays or
rescheduleWeek. Reply with exactly this line:
"${DAY_SWAP_OLD_APP_LINE}"
`;

/**
 * Returns the single Captain-Manual block for THIS request's day-swap
 * routing state. ai-proxy already knows isPro and the declared capability
 * set per request (from the auth lookup and the parsed client_capabilities
 * body field respectively), so exactly one block is injected — the model is
 * never asked to infer tier or app version itself.
 */
export function daySwapRoutingBlock(
  isPro: boolean,
  capabilities: Set<string>,
): string {
  switch (daySwapRoutingCase(isPro, capabilities)) {
    case "pro_capable":
      return PRO_CAPABLE_BLOCK;
    case "pro_old_app":
      return PRO_OLD_APP_BLOCK;
    case "free":
      return FREE_BLOCK;
  }
}
