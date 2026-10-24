import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateHotelWorkoutTool } from "../workout/generateHotelWorkout.ts";
import type { ToolContext } from "../types.ts";

function ctx(): ToolContext {
  return { userId: "u1", isPro: false, sb: null as any, requestId: "test" };
}

Deno.test("generateHotelWorkout — schema accepts valid days", () => {
  const result = generateHotelWorkoutTool.schema.safeParse({ days: 3 });
  assertEquals(result.success, true);
});

Deno.test("generateHotelWorkout — schema accepts boundary days (1, 7)", () => {
  assertEquals(generateHotelWorkoutTool.schema.safeParse({ days: 1 }).success, true);
  assertEquals(generateHotelWorkoutTool.schema.safeParse({ days: 7 }).success, true);
});

Deno.test("generateHotelWorkout — schema rejects days < 1", () => {
  const result = generateHotelWorkoutTool.schema.safeParse({ days: 0 });
  assertEquals(result.success, false);
});

Deno.test("generateHotelWorkout — schema rejects days > 7", () => {
  const result = generateHotelWorkoutTool.schema.safeParse({ days: 8 });
  assertEquals(result.success, false);
});

Deno.test("generateHotelWorkout — schema rejects non-integer days", () => {
  const result = generateHotelWorkoutTool.schema.safeParse({ days: 3.5 });
  assertEquals(result.success, false);
});

Deno.test("generateHotelWorkout — schema rejects malformed startDate", () => {
  const result = generateHotelWorkoutTool.schema.safeParse({
    days: 3,
    startDate: "20-04-2026",
  });
  assertEquals(result.success, false);
});

Deno.test("generateHotelWorkout — intentBuilder produces correct shape without startDate", async () => {
  const intent = await generateHotelWorkoutTool.intentBuilder!({ days: 4 }, ctx());
  assertEquals(intent.type, "generate_hotel_workout");
  assertEquals(intent.payload.days, 4);
  assertEquals(intent.payload.startDate, null);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Generate 4-day bodyweight plan");
});

Deno.test("generateHotelWorkout — intentBuilder includes startDate in preview", async () => {
  const intent = await generateHotelWorkoutTool.intentBuilder!({
    days: 2,
    startDate: "2026-04-25",
  }, ctx());
  assertEquals(intent.payload.startDate, "2026-04-25");
  assertEquals(intent.previewSummary, "Generate 2-day bodyweight plan starting 2026-04-25");
});

Deno.test("generateHotelWorkout — metadata", () => {
  assertEquals(generateHotelWorkoutTool.tier, "pro");
  assertEquals(generateHotelWorkoutTool.kind, "write");
  assertEquals(generateHotelWorkoutTool.family, "workout");
  assertEquals(generateHotelWorkoutTool.confirmationClass, "destructive");
});
