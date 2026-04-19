import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { shortenWorkoutTool } from "../workout/shortenWorkout.ts";

Deno.test("shortenWorkout — schema accepts valid args", () => {
  const result = shortenWorkoutTool.schema.safeParse({ minutes: 30 });
  assertEquals(result.success, true);
});

Deno.test("shortenWorkout — schema accepts boundary minutes (10, 120)", () => {
  assertEquals(shortenWorkoutTool.schema.safeParse({ minutes: 10 }).success, true);
  assertEquals(shortenWorkoutTool.schema.safeParse({ minutes: 120 }).success, true);
});

Deno.test("shortenWorkout — schema rejects minutes < 10", () => {
  const result = shortenWorkoutTool.schema.safeParse({ minutes: 9 });
  assertEquals(result.success, false);
});

Deno.test("shortenWorkout — schema rejects minutes > 120", () => {
  const result = shortenWorkoutTool.schema.safeParse({ minutes: 121 });
  assertEquals(result.success, false);
});

Deno.test("shortenWorkout — schema rejects non-integer minutes", () => {
  const result = shortenWorkoutTool.schema.safeParse({ minutes: 30.5 });
  assertEquals(result.success, false);
});

Deno.test("shortenWorkout — schema rejects malformed date", () => {
  const result = shortenWorkoutTool.schema.safeParse({ minutes: 30, date: "2026/04/19" });
  assertEquals(result.success, false);
});

Deno.test("shortenWorkout — intentBuilder produces correct shape with date", () => {
  const intent = shortenWorkoutTool.intentBuilder!({ minutes: 25, date: "2026-04-20" });
  assertEquals(intent.type, "shorten_workout");
  assertEquals(intent.payload.minutes, 25);
  assertEquals(intent.payload.date, "2026-04-20");
  assertEquals(intent.confirmationClass, "trivial");
  assertEquals(intent.previewSummary, "Shorten 2026-04-20 workout to 25 min");
});

Deno.test("shortenWorkout — intentBuilder defaults date to null", () => {
  const intent = shortenWorkoutTool.intentBuilder!({ minutes: 20 });
  assertEquals(intent.payload.date, null);
  assertEquals(intent.previewSummary, "Shorten today's workout to 20 min");
});

Deno.test("shortenWorkout — metadata", () => {
  assertEquals(shortenWorkoutTool.tier, "free");
  assertEquals(shortenWorkoutTool.kind, "write");
  assertEquals(shortenWorkoutTool.family, "workout");
  assertEquals(shortenWorkoutTool.confirmationClass, "trivial");
});
