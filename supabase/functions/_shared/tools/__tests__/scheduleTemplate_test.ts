import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { scheduleTemplateTool } from "../plan/scheduleTemplate.ts";
import type { ToolContext } from "../types.ts";

function ctx(): ToolContext {
  return { userId: "u1", isPro: false, sb: null as any, requestId: "test" };
}

Deno.test("scheduleTemplate — schema accepts minimal valid args", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates: ["2026-04-21"],
  });
  assertEquals(result.success, true);
});

Deno.test("scheduleTemplate — schema accepts max dates (14)", () => {
  const dates = Array.from(
    { length: 14 },
    (_, i) => `2026-04-${String(21 + i).padStart(2, "0")}`,
  );
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates,
  });
  assertEquals(result.success, true);
});

Deno.test("scheduleTemplate — schema rejects empty dates array", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates: [],
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema rejects > 14 dates", () => {
  const dates = Array.from(
    { length: 15 },
    (_, i) => `2026-04-${String(20 + i).padStart(2, "0")}`,
  );
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates,
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema rejects malformed date", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates: ["20-04-2026"],
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema rejects partial date", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates: ["2026-04"],
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema rejects mixed valid/invalid dates", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "template_abc",
    dates: ["2026-04-21", "April 22"],
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema rejects empty templateId", () => {
  const result = scheduleTemplateTool.schema.safeParse({
    templateId: "",
    dates: ["2026-04-21"],
  });
  assertEquals(result.success, false);
});

Deno.test("scheduleTemplate — schema requires both templateId and dates", () => {
  const noTpl = scheduleTemplateTool.schema.safeParse({ dates: ["2026-04-21"] });
  assertEquals(noTpl.success, false);
  const noDates = scheduleTemplateTool.schema.safeParse({ templateId: "x" });
  assertEquals(noDates.success, false);
});

Deno.test("scheduleTemplate — intentBuilder shape", async () => {
  const intent = await scheduleTemplateTool.intentBuilder!({
    templateId: "template_abc",
    dates: ["2026-04-21", "2026-04-23", "2026-04-25"],
  }, ctx());
  assertEquals(intent.type, "schedule_template");
  assertEquals(intent.payload.template_id, "template_abc");
  assertEquals(intent.payload.dates, ["2026-04-21", "2026-04-23", "2026-04-25"]);
  assertEquals(intent.confirmationClass, "destructive");
  assertEquals(intent.previewSummary, "Schedule template across 3 dates");
});

Deno.test("scheduleTemplate — intentBuilder uses singular 'date' for one date", async () => {
  const intent = await scheduleTemplateTool.intentBuilder!({
    templateId: "template_abc",
    dates: ["2026-04-21"],
  }, ctx());
  assertEquals(intent.previewSummary, "Schedule template across 1 date");
});

Deno.test("scheduleTemplate — metadata", () => {
  assertEquals(scheduleTemplateTool.tier, "pro");
  assertEquals(scheduleTemplateTool.kind, "write");
  assertEquals(scheduleTemplateTool.family, "plan");
  assertEquals(scheduleTemplateTool.confirmationClass, "destructive");
});
