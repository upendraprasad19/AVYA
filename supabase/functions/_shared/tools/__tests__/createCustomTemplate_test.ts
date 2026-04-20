import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createCustomTemplateTool } from "../plan/createCustomTemplate.ts";

const validExercise = {
  exerciseId: "bench_press",
  exerciseName: "Bench Press",
  sets: 4,
  reps: "8-12",
};

const validDay = {
  dayName: "Push Day",
  exercises: [validExercise],
};

Deno.test("createCustomTemplate — schema accepts minimal valid args", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "My Template",
    days: [validDay],
  });
  assertEquals(result.success, true);
});

Deno.test("createCustomTemplate — schema accepts full args (description + assignedDays)", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Hypertrophy Split",
    description: "4-day split focused on muscle growth",
    days: [
      validDay,
      { dayName: "Pull Day", exercises: [validExercise] },
    ],
    assignedDays: [1, 4],
  });
  assertEquals(result.success, true);
});

Deno.test("createCustomTemplate — schema accepts optional restSeconds and durationSeconds on exercises", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Mixed Template",
    days: [{
      dayName: "Day 1",
      exercises: [{
        exerciseId: "plank",
        exerciseName: "Plank",
        sets: 3,
        reps: "30s",
        restSeconds: 60,
        durationSeconds: 30,
      }],
    }],
  });
  assertEquals(result.success, true);
});

Deno.test("createCustomTemplate — schema rejects name < 3 chars", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "AB",
    days: [validDay],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects name > 60 chars", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "x".repeat(61),
    days: [validDay],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects empty days array", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects > 7 days", () => {
  const days = Array.from({ length: 8 }, () => validDay);
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days,
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects empty exercises in a day", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [{ dayName: "Push Day", exercises: [] }],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects > 15 exercises in a day", () => {
  const exercises = Array.from({ length: 16 }, () => validExercise);
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [{ dayName: "Push Day", exercises }],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects sets < 1", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [{
      dayName: "Push Day",
      exercises: [{ ...validExercise, sets: 0 }],
    }],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects sets > 10", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [{
      dayName: "Push Day",
      exercises: [{ ...validExercise, sets: 11 }],
    }],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — schema rejects assignedDays out of range", () => {
  const result = createCustomTemplateTool.schema.safeParse({
    name: "Template",
    days: [validDay],
    assignedDays: [0, 8],
  });
  assertEquals(result.success, false);
});

Deno.test("createCustomTemplate — intentBuilder counts days and exercises", () => {
  const intent = createCustomTemplateTool.intentBuilder!({
    name: "Hypertrophy Split",
    days: [
      { dayName: "Push", exercises: [validExercise, validExercise] },
      { dayName: "Pull", exercises: [validExercise] },
      { dayName: "Legs", exercises: [validExercise, validExercise, validExercise] },
    ],
  });
  assertEquals(intent.type, "create_custom_template");
  assertEquals(intent.payload.name, "Hypertrophy Split");
  assertEquals(intent.payload.description, null);
  assertEquals(intent.payload.assigned_days, []);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(
    intent.previewSummary,
    "Create template: Hypertrophy Split (3 days, 6 exercises total)",
  );
});

Deno.test("createCustomTemplate — intentBuilder uses singular 'day' for one day", () => {
  const intent = createCustomTemplateTool.intentBuilder!({
    name: "Single",
    days: [validDay],
  });
  assertEquals(intent.previewSummary, "Create template: Single (1 day, 1 exercises total)");
});

Deno.test("createCustomTemplate — intentBuilder passes through assignedDays + description", () => {
  const intent = createCustomTemplateTool.intentBuilder!({
    name: "Template",
    description: "Focus on hypertrophy",
    days: [validDay],
    assignedDays: [1, 4],
  });
  assertEquals(intent.payload.description, "Focus on hypertrophy");
  assertEquals(intent.payload.assigned_days, [1, 4]);
});

Deno.test("createCustomTemplate — metadata", () => {
  assertEquals(createCustomTemplateTool.tier, "pro");
  assertEquals(createCustomTemplateTool.kind, "write");
  assertEquals(createCustomTemplateTool.family, "plan");
  assertEquals(createCustomTemplateTool.confirmationClass, "destructive");
});
