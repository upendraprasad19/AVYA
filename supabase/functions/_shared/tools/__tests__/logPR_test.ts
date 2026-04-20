import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { logPRTool } from "../progress/logPR.ts";

Deno.test("logPR — schema accepts minimal args (exerciseId + weightKg)", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Deadlift",
    weightKg: 120,
  });
  assertEquals(result.success, true);
});

Deno.test("logPR — schema accepts full args", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Bench Press",
    weightKg: 100,
    reps: 3,
    date: "2026-04-20",
  });
  assertEquals(result.success, true);
});

Deno.test("logPR — schema accepts weightKg = 0 (bodyweight movements)", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Pull Up",
    weightKg: 0,
  });
  assertEquals(result.success, true);
});

Deno.test("logPR — schema rejects negative weightKg", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Deadlift",
    weightKg: -10,
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — schema rejects weightKg > 500", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Deadlift",
    weightKg: 501,
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — schema rejects reps < 1", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Bench Press",
    weightKg: 100,
    reps: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — schema rejects reps > 50", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Bench Press",
    weightKg: 100,
    reps: 51,
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — schema rejects malformed date", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "Bench Press",
    weightKg: 100,
    date: "20-04-2026",
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — schema rejects empty exerciseId", () => {
  const result = logPRTool.schema.safeParse({
    exerciseId: "",
    weightKg: 100,
  });
  assertEquals(result.success, false);
});

Deno.test("logPR — intentBuilder defaults reps to 1 and date to null", () => {
  const intent = logPRTool.intentBuilder!({
    exerciseId: "Deadlift",
    weightKg: 120,
  });
  assertEquals(intent.type, "log_pr");
  assertEquals(intent.payload.exerciseId, "Deadlift");
  assertEquals(intent.payload.weightKg, 120);
  assertEquals(intent.payload.reps, 1);
  assertEquals(intent.payload.date, null);
  assertEquals(intent.confirmationClass, "trivial");
});

Deno.test("logPR — intentBuilder uses supplied reps and date", () => {
  const intent = logPRTool.intentBuilder!({
    exerciseId: "Bench Press",
    weightKg: 100,
    reps: 3,
    date: "2026-04-19",
  });
  assertEquals(intent.payload.reps, 3);
  assertEquals(intent.payload.date, "2026-04-19");
  assertEquals(intent.previewSummary, "PR: Bench Press 100kg \u00d7 3");
});

Deno.test("logPR — metadata", () => {
  assertEquals(logPRTool.tier, "free");
  assertEquals(logPRTool.kind, "write");
  assertEquals(logPRTool.family, "progress");
  assertEquals(logPRTool.confirmationClass, "trivial");
});
