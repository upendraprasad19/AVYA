import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { markWorkoutCompleteTool } from "../workout/markWorkoutComplete.ts";

Deno.test("markWorkoutComplete — schema accepts no args (defaults to today)", () => {
  const result = markWorkoutCompleteTool.schema.safeParse({});
  assertEquals(result.success, true);
});

Deno.test("markWorkoutComplete — schema accepts valid YYYY-MM-DD", () => {
  const result = markWorkoutCompleteTool.schema.safeParse({ date: "2026-04-20" });
  assertEquals(result.success, true);
});

Deno.test("markWorkoutComplete — schema rejects malformed date", () => {
  const result = markWorkoutCompleteTool.schema.safeParse({ date: "20-04-2026" });
  assertEquals(result.success, false);
});

Deno.test("markWorkoutComplete — schema rejects partial date", () => {
  const result = markWorkoutCompleteTool.schema.safeParse({ date: "2026-04" });
  assertEquals(result.success, false);
});

Deno.test("markWorkoutComplete — intentBuilder uses date when supplied", () => {
  const intent = markWorkoutCompleteTool.intentBuilder!({ date: "2026-04-19" });
  assertEquals(intent.type, "mark_workout_complete");
  assertEquals(intent.payload.date, "2026-04-19");
  assertEquals(intent.confirmationClass, "trivial");
  assertEquals(intent.previewSummary, "Mark 2026-04-19 workout complete");
});

Deno.test("markWorkoutComplete — intentBuilder defaults date to null when absent", () => {
  const intent = markWorkoutCompleteTool.intentBuilder!({});
  assertEquals(intent.payload.date, null);
  assertEquals(intent.previewSummary, "Mark today's workout complete");
});

Deno.test("markWorkoutComplete — metadata", () => {
  assertEquals(markWorkoutCompleteTool.tier, "free");
  assertEquals(markWorkoutCompleteTool.kind, "write");
  assertEquals(markWorkoutCompleteTool.family, "workout");
  assertEquals(markWorkoutCompleteTool.confirmationClass, "trivial");
});
