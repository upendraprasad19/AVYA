import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { regeneratePlanBlockTool } from "../plan/regeneratePlanBlock.ts";
import type { ToolContext } from "../types.ts";

function ctx(): ToolContext {
  return { userId: "u1", isPro: false, sb: null as any, requestId: "test" };
}

Deno.test("regeneratePlanBlock — schema accepts minimal args (weeks only)", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({ weeks: 4 });
  assertEquals(result.success, true);
});

Deno.test("regeneratePlanBlock — schema accepts full args", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    goal: "build_muscle",
    daysPerWeek: 5,
    equipment: "full_gym",
    startDate: "2026-04-20",
  });
  assertEquals(result.success, true);
});

Deno.test("regeneratePlanBlock — schema accepts recompose goal (F19 sibling)", () => {
  // recompose is a canonical FitnessGoals token; the goal enum must accept it
  // so the AI can regenerate a recomposition block. Was missing while switchGoal
  // already had it — the same F19 fallthrough class, one tool over.
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    goal: "recompose",
  });
  assertEquals(result.success, true);
});

Deno.test("regeneratePlanBlock — schema rejects weeks < 1", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({ weeks: 0 });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects weeks > 12", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({ weeks: 13 });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects non-integer weeks", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({ weeks: 4.5 });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects daysPerWeek < 3", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    daysPerWeek: 2,
  });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects daysPerWeek > 6", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    daysPerWeek: 7,
  });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects invalid goal enum", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    goal: "powerlifting",
  });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects invalid equipment enum", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    equipment: "garage_gym",
  });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — schema rejects malformed startDate", () => {
  const result = regeneratePlanBlockTool.schema.safeParse({
    weeks: 4,
    startDate: "April 20",
  });
  assertEquals(result.success, false);
});

Deno.test("regeneratePlanBlock — intentBuilder defaults all optionals to null", async () => {
  const intent = await regeneratePlanBlockTool.intentBuilder!({ weeks: 4 }, ctx());
  assertEquals(intent.type, "regenerate_plan_block");
  assertEquals(intent.payload.weeks, 4);
  assertEquals(intent.payload.goal, null);
  assertEquals(intent.payload.days_per_week, null);
  assertEquals(intent.payload.equipment, null);
  assertEquals(intent.payload.start_date, null);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Regenerate next 4 weeks");
});

Deno.test("regeneratePlanBlock — intentBuilder includes goal in summary when supplied", async () => {
  const intent = await regeneratePlanBlockTool.intentBuilder!({
    weeks: 4,
    goal: "lose_fat",
  }, ctx());
  assertEquals(intent.payload.goal, "lose_fat");
  assertEquals(intent.previewSummary, "Regenerate next 4 weeks for lose_fat");
});

Deno.test("regeneratePlanBlock — intentBuilder includes daysPerWeek in summary", async () => {
  const intent = await regeneratePlanBlockTool.intentBuilder!({
    weeks: 6,
    goal: "build_muscle",
    daysPerWeek: 5,
  }, ctx());
  assertEquals(
    intent.previewSummary,
    "Regenerate next 6 weeks for build_muscle (5 days/week)",
  );
});

Deno.test("regeneratePlanBlock — metadata", () => {
  assertEquals(regeneratePlanBlockTool.tier, "pro");
  assertEquals(regeneratePlanBlockTool.kind, "write");
  assertEquals(regeneratePlanBlockTool.family, "plan");
  assertEquals(regeneratePlanBlockTool.confirmationClass, "destructive");
});
