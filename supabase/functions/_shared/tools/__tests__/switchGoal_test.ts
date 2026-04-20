import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { switchGoalTool } from "../plan/switchGoal.ts";

Deno.test("switchGoal — schema accepts minimal args (newGoal only)", () => {
  const result = switchGoalTool.schema.safeParse({ newGoal: "build_muscle" });
  assertEquals(result.success, true);
});

Deno.test("switchGoal — schema accepts full args", () => {
  const result = switchGoalTool.schema.safeParse({
    newGoal: "lose_fat",
    weeks: 8,
    startDate: "2026-04-20",
  });
  assertEquals(result.success, true);
});

Deno.test("switchGoal — schema accepts all 4 valid goals", () => {
  for (const g of ["build_muscle", "lose_fat", "general_fitness", "strength"]) {
    const result = switchGoalTool.schema.safeParse({ newGoal: g });
    assertEquals(result.success, true);
  }
});

Deno.test("switchGoal — schema rejects invalid goal enum", () => {
  const result = switchGoalTool.schema.safeParse({ newGoal: "powerlifting" });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — schema rejects missing newGoal", () => {
  const result = switchGoalTool.schema.safeParse({ weeks: 4 });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — schema rejects weeks < 1", () => {
  const result = switchGoalTool.schema.safeParse({
    newGoal: "build_muscle",
    weeks: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — schema rejects weeks > 12", () => {
  const result = switchGoalTool.schema.safeParse({
    newGoal: "build_muscle",
    weeks: 13,
  });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — schema rejects non-integer weeks", () => {
  const result = switchGoalTool.schema.safeParse({
    newGoal: "build_muscle",
    weeks: 4.5,
  });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — schema rejects malformed startDate", () => {
  const result = switchGoalTool.schema.safeParse({
    newGoal: "build_muscle",
    startDate: "April 20",
  });
  assertEquals(result.success, false);
});

Deno.test("switchGoal — intentBuilder defaults weeks to 4 and startDate to null", () => {
  const intent = switchGoalTool.intentBuilder!({ newGoal: "build_muscle" });
  assertEquals(intent.type, "switch_goal");
  assertEquals(intent.payload.new_goal, "build_muscle");
  assertEquals(intent.payload.weeks, 4);
  assertEquals(intent.payload.start_date, null);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(
    intent.previewSummary,
    "Switch goal \u2192 build_muscle + regenerate 4 weeks",
  );
});

Deno.test("switchGoal — intentBuilder uses supplied weeks", () => {
  const intent = switchGoalTool.intentBuilder!({
    newGoal: "lose_fat",
    weeks: 8,
    startDate: "2026-04-20",
  });
  assertEquals(intent.payload.weeks, 8);
  assertEquals(intent.payload.start_date, "2026-04-20");
  assertEquals(
    intent.previewSummary,
    "Switch goal \u2192 lose_fat + regenerate 8 weeks",
  );
});

Deno.test("switchGoal — metadata", () => {
  assertEquals(switchGoalTool.tier, "pro");
  assertEquals(switchGoalTool.kind, "write");
  assertEquals(switchGoalTool.family, "plan");
  assertEquals(switchGoalTool.confirmationClass, "destructive");
});
