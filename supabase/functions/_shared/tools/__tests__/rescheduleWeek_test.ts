import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { rescheduleWeekTool } from "../workout/rescheduleWeek.ts";

Deno.test("rescheduleWeek — schema accepts valid daysAvailable", () => {
  const result = rescheduleWeekTool.schema.safeParse({ daysAvailable: [1, 3, 5] });
  assertEquals(result.success, true);
});

Deno.test("rescheduleWeek — schema accepts weekStart", () => {
  const result = rescheduleWeekTool.schema.safeParse({
    daysAvailable: [1, 3, 5],
    weekStart: "2026-04-20",
  });
  assertEquals(result.success, true);
});

Deno.test("rescheduleWeek — schema rejects empty daysAvailable", () => {
  const result = rescheduleWeekTool.schema.safeParse({ daysAvailable: [] });
  assertEquals(result.success, false);
});

Deno.test("rescheduleWeek — schema rejects day < 1", () => {
  const result = rescheduleWeekTool.schema.safeParse({ daysAvailable: [0, 1, 2] });
  assertEquals(result.success, false);
});

Deno.test("rescheduleWeek — schema rejects day > 7", () => {
  const result = rescheduleWeekTool.schema.safeParse({ daysAvailable: [7, 8] });
  assertEquals(result.success, false);
});

Deno.test("rescheduleWeek — schema rejects more than 7 days", () => {
  const result = rescheduleWeekTool.schema.safeParse({
    daysAvailable: [1, 2, 3, 4, 5, 6, 7, 1],
  });
  assertEquals(result.success, false);
});

Deno.test("rescheduleWeek — schema rejects malformed weekStart", () => {
  const result = rescheduleWeekTool.schema.safeParse({
    daysAvailable: [1, 3, 5],
    weekStart: "April 20 2026",
  });
  assertEquals(result.success, false);
});

Deno.test("rescheduleWeek — intentBuilder sorts days and labels them", () => {
  const intent = rescheduleWeekTool.intentBuilder!({ daysAvailable: [5, 1, 3] });
  assertEquals(intent.type, "reschedule_week");
  assertEquals(intent.payload.daysAvailable, [1, 3, 5]);
  assertEquals(intent.payload.weekStart, null);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Reshuffle week to 3 days: Mon, Wed, Fri");
});

Deno.test("rescheduleWeek — intentBuilder handles single day", () => {
  const intent = rescheduleWeekTool.intentBuilder!({ daysAvailable: [7] });
  assertEquals(intent.previewSummary, "Reshuffle week to 1 day: Sun");
});

Deno.test("rescheduleWeek — intentBuilder uses weekStart when supplied", () => {
  const intent = rescheduleWeekTool.intentBuilder!({
    daysAvailable: [2, 4],
    weekStart: "2026-04-20",
  });
  assertEquals(intent.payload.weekStart, "2026-04-20");
});

Deno.test("rescheduleWeek — metadata", () => {
  assertEquals(rescheduleWeekTool.tier, "pro");
  assertEquals(rescheduleWeekTool.kind, "write");
  assertEquals(rescheduleWeekTool.family, "workout");
  assertEquals(rescheduleWeekTool.confirmationClass, "destructive");
});
