import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getNutritionHistoryTool } from "../nutrition/getNutritionHistory.ts";
import { fakeSb } from "./fake_sb.ts";
import { istDateStr } from "../../ist_date.ts";

// deno-lint-ignore no-explicit-any
const mkCtx = (sb: any) => ({ userId: "u1", isPro: false, sb, requestId: "t" });
const dayStr = (i: number) => istDateStr(new Date(Date.UTC(2026, 0, 1 + i)));
const logs = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `l${i}`, user_id: "u1", date: dayStr(i), total_calories: 100, total_protein: 10,
    total_carbs: 1, total_fat: 1, total_fiber: 1, meal_type: "lunch",
  }));
const items = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: i + 1, log_id: `l${i}`, food_name: "rice", calories: 1, protein: 1, carbs: 1, fat: 1,
  }));

Deno.test("getNutritionHistory — per_day over 31 days: totals, NO items, note (default call never fails)", async () => {
  const { sb, calls } = fakeSb({ nutrition_logs: logs(60), nutrition_log_items: items(60) });
  const r = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(59), aggregation: "per_day",
  });
  assertEquals(r.days!.length, 60);
  assertEquals(r.days!.every((d) => d.items.length === 0), true);
  assertEquals(r.note, "items omitted for ranges over 31 days");
  assertEquals(calls.some((c) => c.table === "nutrition_log_items"), false);
});

Deno.test("getNutritionHistory — per_day within 31 days attaches items", async () => {
  const { sb } = fakeSb({ nutrition_logs: logs(10), nutrition_log_items: items(10) });
  const r = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(9), aggregation: "per_day",
  });
  assertEquals(r.days!.every((d) => d.items.length === 1), true);
  assertEquals(r.note, undefined);
});

Deno.test("getNutritionHistory — total never reads items", async () => {
  const { sb, calls } = fakeSb({ nutrition_logs: logs(10), nutrition_log_items: items(10) });
  const r = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(9), aggregation: "total",
  });
  assertEquals(r.total!.days_with_logs, 10);
  assertEquals(calls.some((c) => c.table === "nutrition_log_items"), false);
});

Deno.test("getNutritionHistory — 1,200 log rows are all read (paging past the 1,000 cap)", async () => {
  const many = Array.from({ length: 1200 }, (_, i) => ({
    id: `l${String(i).padStart(5, "0")}`, user_id: "u1", date: dayStr(i % 300), total_calories: 1,
    total_protein: 0, total_carbs: 0, total_fat: 0, total_fiber: 0, meal_type: "x",
  }));
  const { sb } = fakeSb({ nutrition_logs: many });
  const r = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(299), aggregation: "total",
  });
  assertEquals(r.total!.meal_count, 1200);
});

Deno.test("getNutritionHistory — 31-day boundary attaches items, 32 does not", async () => {
  const { sb } = fakeSb({ nutrition_logs: logs(32), nutrition_log_items: items(32) });
  const r31 = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(30), aggregation: "per_day",
  });
  assertEquals(r31.note, undefined);
  const r32 = await getNutritionHistoryTool.handler!(mkCtx(sb), {
    date_from: dayStr(0), date_to: dayStr(31), aggregation: "per_day",
  });
  assertEquals(r32.note, "items omitted for ranges over 31 days");
});
