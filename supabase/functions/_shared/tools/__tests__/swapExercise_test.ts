import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { swapExerciseTool } from "../workout/swapExercise.ts";

Deno.test("swapExercise — schema accepts valid args", () => {
  const result = swapExerciseTool.schema.safeParse({
    exerciseId: "ex_squat",
    newExerciseId: "ex_goblet_squat",
    reason: "no barbell at home",
  });
  assertEquals(result.success, true);
});

Deno.test("swapExercise — reason is optional", () => {
  const result = swapExerciseTool.schema.safeParse({
    exerciseId: "ex_squat",
    newExerciseId: "ex_goblet_squat",
  });
  assertEquals(result.success, true);
});

Deno.test("swapExercise — schema rejects empty exerciseId", () => {
  const result = swapExerciseTool.schema.safeParse({
    exerciseId: "",
    newExerciseId: "ex_goblet_squat",
  });
  assertEquals(result.success, false);
});

Deno.test("swapExercise — schema rejects reason >200 chars", () => {
  const result = swapExerciseTool.schema.safeParse({
    exerciseId: "ex_squat",
    newExerciseId: "ex_goblet_squat",
    reason: "x".repeat(201),
  });
  assertEquals(result.success, false);
});

Deno.test("swapExercise — intentBuilder produces correct shape", () => {
  const intent = swapExerciseTool.intentBuilder!({
    exerciseId: "ex_squat",
    newExerciseId: "ex_goblet_squat",
    reason: "swap reason",
  });
  assertEquals(intent.type, "swap_exercise");
  assertEquals(intent.payload.exerciseId, "ex_squat");
  assertEquals(intent.payload.newExerciseId, "ex_goblet_squat");
  assertEquals(intent.payload.reason, "swap reason");
  assertEquals(intent.confirmationClass, "reviewable");
});

Deno.test("swapExercise — intent.payload.reason defaults to null when absent", () => {
  const intent = swapExerciseTool.intentBuilder!({
    exerciseId: "ex_squat",
    newExerciseId: "ex_goblet_squat",
  });
  assertEquals(intent.payload.reason, null);
});

Deno.test("swapExercise — metadata", () => {
  assertEquals(swapExerciseTool.tier, "pro");
  assertEquals(swapExerciseTool.kind, "write");
  assertEquals(swapExerciseTool.family, "workout");
});
