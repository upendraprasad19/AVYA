import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pausePlanTool } from "../plan/pausePlan.ts";
import type { ToolContext } from "../types.ts";

function ctx(): ToolContext {
  return { userId: "u1", isPro: false, sb: null as any, requestId: "test" };
}

Deno.test("pausePlan — schema accepts minimal valid args", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 5,
  });
  assertEquals(result.success, true);
});

Deno.test("pausePlan — schema accepts optional reason", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 7,
    reason: "Goa trip",
  });
  assertEquals(result.success, true);
});

Deno.test("pausePlan — schema rejects malformed startDate", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "20-04-2026",
    days: 5,
  });
  assertEquals(result.success, false);
});

Deno.test("pausePlan — schema rejects days < 1", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("pausePlan — schema rejects days > 30", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 31,
  });
  assertEquals(result.success, false);
});

Deno.test("pausePlan — schema rejects non-integer days", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 5.5,
  });
  assertEquals(result.success, false);
});

Deno.test("pausePlan — schema rejects reason > 120 chars", () => {
  const result = pausePlanTool.schema.safeParse({
    startDate: "2026-04-20",
    days: 5,
    reason: "x".repeat(121),
  });
  assertEquals(result.success, false);
});

Deno.test("pausePlan — schema requires startDate and days", () => {
  const noStart = pausePlanTool.schema.safeParse({ days: 5 });
  assertEquals(noStart.success, false);
  const noDays = pausePlanTool.schema.safeParse({ startDate: "2026-04-20" });
  assertEquals(noDays.success, false);
});

Deno.test("pausePlan — intentBuilder defaults reason to null", async () => {
  const intent = await pausePlanTool.intentBuilder!({
    startDate: "2026-04-20",
    days: 5,
  }, ctx());
  assertEquals(intent.type, "pause_plan");
  assertEquals(intent.payload.start_date, "2026-04-20");
  assertEquals(intent.payload.days, 5);
  assertEquals(intent.payload.reason, null);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Pause 5 days from 2026-04-20");
});

Deno.test("pausePlan — intentBuilder includes reason in summary", async () => {
  const intent = await pausePlanTool.intentBuilder!({
    startDate: "2026-04-20",
    days: 7,
    reason: "Goa trip",
  }, ctx());
  assertEquals(intent.payload.reason, "Goa trip");
  assertEquals(intent.previewSummary, "Pause 7 days from 2026-04-20 (Goa trip)");
});

Deno.test("pausePlan — intentBuilder uses singular 'day' for days=1", async () => {
  const intent = await pausePlanTool.intentBuilder!({
    startDate: "2026-04-20",
    days: 1,
  }, ctx());
  assertEquals(intent.previewSummary, "Pause 1 day from 2026-04-20");
});

Deno.test("pausePlan — metadata", () => {
  assertEquals(pausePlanTool.tier, "pro");
  assertEquals(pausePlanTool.kind, "write");
  assertEquals(pausePlanTool.family, "plan");
  assertEquals(pausePlanTool.confirmationClass, "destructive");
});
