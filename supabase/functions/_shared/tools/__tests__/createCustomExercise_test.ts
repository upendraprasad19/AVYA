import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createCustomExerciseTool } from "../workout/createCustomExercise.ts";

Deno.test("createCustomExercise — schema accepts minimum valid args", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Hammer Curl with Water Bottle",
    category: "pull",
    equipment: "bodyweight",
    loggingType: "weight_reps",
  });
  assertEquals(result.success, true);
});

Deno.test("createCustomExercise — schema accepts full optional fields", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Bottle Curl",
    category: "pull",
    equipment: "bodyweight",
    loggingType: "weight_reps",
    primaryMuscles: ["Biceps", "Forearms"],
    defaultSets: 3,
    defaultReps: 12,
  });
  assertEquals(result.success, true);
});

Deno.test("createCustomExercise — schema rejects name < 3 chars", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Hi",
    category: "pull",
    equipment: "bodyweight",
    loggingType: "weight_reps",
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects name > 60 chars", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "x".repeat(61),
    category: "pull",
    equipment: "bodyweight",
    loggingType: "weight_reps",
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects invalid category enum", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Test Exercise",
    category: "weightlifting",
    equipment: "bodyweight",
    loggingType: "weight_reps",
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects invalid equipment enum", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Test Exercise",
    category: "push",
    equipment: "olympic_gym",
    loggingType: "weight_reps",
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects invalid loggingType enum", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Test Exercise",
    category: "push",
    equipment: "bodyweight",
    loggingType: "weights",
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects > 5 primaryMuscles", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Test Exercise",
    category: "push",
    equipment: "bodyweight",
    loggingType: "weight_reps",
    primaryMuscles: ["a", "b", "c", "d", "e", "f"],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — schema rejects defaultSets > 10", () => {
  const result = createCustomExerciseTool.schema.safeParse({
    name: "Test Exercise",
    category: "push",
    equipment: "bodyweight",
    loggingType: "weight_reps",
    defaultSets: 11,
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomExercise — intentBuilder fills defaults", () => {
  const intent = createCustomExerciseTool.intentBuilder!({
    name: "Bottle Curl",
    category: "pull",
    equipment: "bodyweight",
    loggingType: "weight_reps",
  });
  assertEquals(intent.type, "create_custom_exercise");
  assertEquals(intent.payload.name, "Bottle Curl");
  assertEquals(intent.payload.category, "pull");
  assertEquals(intent.payload.equipment, "bodyweight");
  assertEquals(intent.payload.loggingType, "weight_reps");
  assertEquals(intent.payload.primaryMuscles, []);
  assertEquals(intent.payload.defaultSets, 3);
  assertEquals(intent.payload.defaultReps, undefined);
  assertEquals(intent.confirmationClass, "reviewable");
  assertEquals(intent.previewSummary, "Create custom exercise: Bottle Curl (pull, bodyweight)");
});

Deno.test("createCustomExercise — metadata", () => {
  assertEquals(createCustomExerciseTool.tier, "free");
  assertEquals(createCustomExerciseTool.kind, "write");
  assertEquals(createCustomExerciseTool.family, "workout");
  assertEquals(createCustomExerciseTool.confirmationClass, "reviewable");
});
