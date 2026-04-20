import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getProgressSummaryTool } from "../progress/getProgressSummary.ts";

Deno.test("getProgressSummary — schema accepts valid period", () => {
  const result = getProgressSummaryTool.schema.safeParse({ periodDays: 30 });
  assertEquals(result.success, true);
});

Deno.test("getProgressSummary — schema rejects period <7", () => {
  const result = getProgressSummaryTool.schema.safeParse({ periodDays: 6 });
  assertEquals(result.success, false);
});

Deno.test("getProgressSummary — schema rejects period >365", () => {
  const result = getProgressSummaryTool.schema.safeParse({ periodDays: 366 });
  assertEquals(result.success, false);
});

Deno.test("getProgressSummary — schema rejects non-integer", () => {
  const result = getProgressSummaryTool.schema.safeParse({ periodDays: 30.5 });
  assertEquals(result.success, false);
});

Deno.test("getProgressSummary — metadata", () => {
  assertEquals(getProgressSummaryTool.tier, "free");
  assertEquals(getProgressSummaryTool.kind, "read");
  assertEquals(getProgressSummaryTool.maxLatencyMs, 3500);
});

// NOTE: handler() integration tests against real Supabase require a seeded
// test DB and are deferred. The shape tests above + manual prod verification
// in A.13 cover the handler.
