import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { swapWorkoutDaysTool } from "../swapWorkoutDays.ts";
import type { ToolContext } from "../../types.ts";

function ctx(): ToolContext {
  return { userId: "u1", isPro: true, sb: null as any, requestId: "test" };
}

Deno.test("swapWorkoutDays — schema accepts two valid IST dates", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2026-09-25",
    dateB: "2026-09-26",
  });
  assertEquals(result.success, true);
});

Deno.test("swapWorkoutDays — schema rejects a malformed dateA", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "September 25 2026",
    dateB: "2026-09-26",
  });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — schema rejects a malformed dateB", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2026-09-25",
    dateB: "26-09-2026",
  });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — schema rejects a missing dateB", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({ dateA: "2026-09-25" });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — schema rejects extra unknown fields loosely typed as strings", () => {
  // dateA/dateB must stay plain Zod strings (spec §5.8 — zodToGemini throws on
  // unsupported Zod types, and the client validates the dates anyway), so a
  // non-string value on either field must fail regardless of shape.
  const result = swapWorkoutDaysTool.schema.safeParse({ dateA: 20260925, dateB: "2026-09-26" });
  assertEquals(result.success, false);
});

// F3 — real-calendar-date validation (review "Minor" finding): ISO_DATE's
// regex matches shape only, so "2026-02-30" (no such day) and "2026-13-01"
// (no such month) both passed the OLD schema. `dateField`'s `.refine()` now
// requires the UTC round-trip to equal the input, catching the overflow
// `Date.UTC` would otherwise silently roll forward (e.g. Feb 30 -> Mar 2).
Deno.test("swapWorkoutDays — schema rejects an impossible calendar date (2026-02-30)", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2026-02-30",
    dateB: "2026-09-26",
  });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — schema rejects an impossible calendar month (2026-13-01)", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2026-09-25",
    dateB: "2026-13-01",
  });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — schema accepts a valid leap day (2028-02-29, 2028 is a leap year)", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2028-02-29",
    dateB: "2028-03-01",
  });
  assertEquals(result.success, true);
});

Deno.test("swapWorkoutDays — schema rejects a non-leap-year Feb 29 (2027-02-29, 2027 is not a leap year)", () => {
  const result = swapWorkoutDaysTool.schema.safeParse({
    dateA: "2027-02-29",
    dateB: "2027-03-01",
  });
  assertEquals(result.success, false);
});

Deno.test("swapWorkoutDays — intentBuilder shapes the intent from validated args", async () => {
  const intent = await swapWorkoutDaysTool.intentBuilder!(
    { dateA: "2026-09-25", dateB: "2026-09-26" },
    ctx(),
  );
  assertEquals(intent.type, "swap_workout_days");
  assertEquals(intent.payload, { dateA: "2026-09-25", dateB: "2026-09-26" });
  assertEquals(intent.confirmationClass, "reviewable");
  assertEquals(intent.previewSummary, "Swap 2026-09-25 and 2026-09-26");
});

Deno.test("swapWorkoutDays — metadata: PRO, reviewable, workout family, write, capability-gated", () => {
  assertEquals(swapWorkoutDaysTool.tier, "pro");
  assertEquals(swapWorkoutDaysTool.kind, "write");
  assertEquals(swapWorkoutDaysTool.family, "workout");
  assertEquals(swapWorkoutDaysTool.confirmationClass, "reviewable");
  assertEquals(swapWorkoutDaysTool.requiresCapability, "swap_workout_days");
});

Deno.test("swapWorkoutDays — requiresCapability is the CAPABILITY_SWAP_WORKOUT_DAYS constant, not a re-typed literal", async () => {
  const { CAPABILITY_SWAP_WORKOUT_DAYS } = await import("../../../day_swap_routing.ts");
  assertEquals(swapWorkoutDaysTool.requiresCapability, CAPABILITY_SWAP_WORKOUT_DAYS);
});

Deno.test("swapWorkoutDays — selectionHints distinguishes it from rescheduleWeek", () => {
  const hints = swapWorkoutDaysTool.selectionHints ?? "";
  if (!hints.toLowerCase().includes("swap")) {
    throw new Error("selectionHints must mention swapping/exchanging/trading two days.");
  }
});
