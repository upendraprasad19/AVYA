// Deno tests pinning the day-swap routing fix in the Captain's Manual
// (day-swapper-sync-load batch, Task 9/U3, spec §1.1/§5.8).
// Run: deno test --allow-all supabase/functions/_shared/captain_manual_day_swap_routing_test.ts
//
// The manual's own multi-intent example used to send a two-day swap
// ("move Friday's pull to today and today's pull to Friday") to
// rescheduleWeek, which reshuffles WHICH weekdays the user trains on and
// silently no-ops a same-week two-day content swap. This pins the fix and
// guards against the stale example creeping back in.

import { assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { CAPTAIN_MANUAL } from "./captain_manual.ts";

Deno.test("multi-intent example routes the Friday/today swap to swapWorkoutDays, not rescheduleWeek", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "swapWorkoutDays for Friday and today");
});

Deno.test("the stale rescheduleWeek phrasing for a two-day swap is gone", () => {
  const stale = "rescheduleWeek from Friday to today";
  if (CAPTAIN_MANUAL.includes(stale)) {
    throw new Error(
      `CAPTAIN_MANUAL still contains the stale phrase "${stale}" — the day-swap misrouting example was not fixed.`,
    );
  }
});

Deno.test("Section 8 TOOL ROUTING carries the day-swap routing rule", () => {
  assertStringIncludes(CAPTAIN_MANUAL, "DAY SWAP ROUTING block");
  assertStringIncludes(
    CAPTAIN_MANUAL,
    "that tool changes WHICH weekdays you train on",
  );
});
