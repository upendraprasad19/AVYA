import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getExerciseHistoryTool } from "../progress/getExerciseHistory.ts";

Deno.test("getExerciseHistory — schema accepts valid args", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Bench Press",
    weeks: 4,
  });
  assertEquals(result.success, true);
});

Deno.test("getExerciseHistory — schema accepts max weeks (52)", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 52,
  });
  assertEquals(result.success, true);
});

Deno.test("getExerciseHistory — schema rejects weeks < 1", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects weeks > 52", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 53,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects non-integer weeks", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 4.5,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects empty exerciseId", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "",
    weeks: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema requires both fields", () => {
  const noWeeks = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Bench Press",
  });
  assertEquals(noWeeks.success, false);
  const noId = getExerciseHistoryTool.schema.safeParse({ weeks: 4 });
  assertEquals(noId.success, false);
});

Deno.test("getExerciseHistory — metadata", () => {
  assertEquals(getExerciseHistoryTool.tier, "pro");
  assertEquals(getExerciseHistoryTool.kind, "read");
  assertEquals(getExerciseHistoryTool.family, "progress");
  assertEquals(getExerciseHistoryTool.maxLatencyMs, 4000);
});

// NOTE: handler() integration tests against real Supabase require a seeded
// test DB and are deferred. The shape tests above + manual prod verification
// in D.8 cover the handler.
