import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { adjustCaloricTargetTool } from "../nutrition/adjustCaloricTarget.ts";

Deno.test("adjustCaloricTarget — schema accepts valid args (minimal)", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -300,
    ttlDays: 7,
  });
  assertEquals(result.success, true);
});

Deno.test("adjustCaloricTarget — schema accepts valid args (full)", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: 400,
    ttlDays: 14,
    startDate: "2026-04-20",
    reason: "heavy training week",
  });
  assertEquals(result.success, true);
});

Deno.test("adjustCaloricTarget — schema rejects deltaKcal below -1500", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -1501,
    ttlDays: 7,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects deltaKcal above 1500", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: 1501,
    ttlDays: 7,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects non-integer deltaKcal", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: 100.5,
    ttlDays: 7,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects ttlDays of 0", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -200,
    ttlDays: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects ttlDays above 28", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -200,
    ttlDays: 29,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects non-integer ttlDays", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -200,
    ttlDays: 7.5,
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects malformed startDate", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -200,
    ttlDays: 7,
    startDate: "2026/04/20",
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema rejects reason >120 chars", () => {
  const result = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -200,
    ttlDays: 7,
    reason: "x".repeat(121),
  });
  assertEquals(result.success, false);
});

Deno.test("adjustCaloricTarget — schema accepts boundary values", () => {
  const min = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: -1500,
    ttlDays: 1,
  });
  assertEquals(min.success, true);
  const max = adjustCaloricTargetTool.schema.safeParse({
    deltaKcal: 1500,
    ttlDays: 28,
  });
  assertEquals(max.success, true);
});

Deno.test("adjustCaloricTarget — intentBuilder produces correct shape", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: -300,
    ttlDays: 7,
    startDate: "2026-04-20",
    reason: "cutting for event",
  }) as { type: string; payload: Record<string, unknown>; confirmationClass: string; previewSummary: string };

  assertEquals(intent.type, "adjust_caloric_target");
  assertEquals(intent.payload.delta_kcal, -300);
  assertEquals(intent.payload.ttl_days, 7);
  assertEquals(intent.payload.start_date, "2026-04-20");
  assertEquals(intent.payload.reason, "cutting for event");
});

Deno.test("adjustCaloricTarget — intentBuilder defaults startDate + reason to null when absent", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: 100,
    ttlDays: 3,
  }) as { payload: Record<string, unknown> };

  assertEquals(intent.payload.start_date, null);
  assertEquals(intent.payload.reason, null);
});

// Dynamic confirmationClass branching: |delta| <= 200 → trivial, |delta| > 200 → reviewable.
Deno.test("adjustCaloricTarget — confirmationClass = trivial when delta = 200 (positive boundary)", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: 200,
    ttlDays: 5,
  }) as { confirmationClass: string };
  assertEquals(intent.confirmationClass, "trivial");
});

Deno.test("adjustCaloricTarget — confirmationClass = reviewable when delta = 201 (positive over)", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: 201,
    ttlDays: 5,
  }) as { confirmationClass: string };
  assertEquals(intent.confirmationClass, "reviewable");
});

Deno.test("adjustCaloricTarget — confirmationClass = trivial when delta = -200 (negative boundary)", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: -200,
    ttlDays: 5,
  }) as { confirmationClass: string };
  assertEquals(intent.confirmationClass, "trivial");
});

Deno.test("adjustCaloricTarget — confirmationClass = reviewable when delta = -1500 (negative max)", () => {
  const intent = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: -1500,
    ttlDays: 5,
  }) as { confirmationClass: string };
  assertEquals(intent.confirmationClass, "reviewable");
});

Deno.test("adjustCaloricTarget — previewSummary includes sign + day word + reason", () => {
  const positive = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: 400,
    ttlDays: 1,
    reason: "refuel day",
  }) as { previewSummary: string };
  // "+400 kcal/day for 1 day — refuel day"
  assertEquals(positive.previewSummary.startsWith("+400"), true);
  assertEquals(positive.previewSummary.includes("1 day"), true);
  assertEquals(positive.previewSummary.includes("refuel day"), true);

  const negative = adjustCaloricTargetTool.intentBuilder!({
    deltaKcal: -300,
    ttlDays: 7,
  }) as { previewSummary: string };
  assertEquals(negative.previewSummary.startsWith("-300"), true);
  assertEquals(negative.previewSummary.includes("7 days"), true);
});

Deno.test("adjustCaloricTarget — metadata", () => {
  assertEquals(adjustCaloricTargetTool.tier, "pro");
  assertEquals(adjustCaloricTargetTool.kind, "write");
  assertEquals(adjustCaloricTargetTool.family, "nutrition");
  assertEquals(adjustCaloricTargetTool.name, "adjustCaloricTarget");
  // Static default is reviewable (worst-case); intent overrides per delta.
  assertEquals(adjustCaloricTargetTool.confirmationClass, "reviewable");
});

Deno.test("adjustCaloricTarget — description present and non-empty", () => {
  assertEquals(typeof adjustCaloricTargetTool.description, "string");
  assertEquals(adjustCaloricTargetTool.description.length > 0, true);
});
