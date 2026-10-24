import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { weekWorkoutRows } from "./week_rows.ts";
import { buildDayMap, istDatesEnding } from "../_shared/exercise_day.ts";
import { workoutLogIdForDate } from "../_shared/uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z");
const W = istDatesEnding(7, NOW);
const mk = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "bench",
  exercise_name: "Bench",
  set_number: 3,
  reps: 24,
  weight_kg: 60,
  is_pr: false,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  ...over,
});

Deno.test("weekWorkoutRows — window is exactly 7 IST dates (8-days-ago excluded)", () => {
  assertEquals(W.length, 7);
  assertEquals(W[6], "2026-10-07");
  assertEquals(W[0], "2026-10-01");
});

Deno.test("weekWorkoutRows — superseded row dropped; PR counted from the winner only", async () => {
  const m = await buildDayMap(NOW);
  const out = weekWorkoutRows([
    await mk("2026-10-05", { id: 1, set_number: 3, is_pr: true }),
    await mk("2026-10-05", { id: 2, set_number: 4, is_pr: false }),
  ], m, W);
  assertEquals(out.length, 1);
  assertEquals(out[0].sets_completed, 4);
  assertEquals(out[0].is_pr, false);
});

Deno.test("weekWorkoutRows — edited old log is excluded; date is the RESOLVED day; chronological regardless of id order", async () => {
  const m = await buildDayMap(NOW);
  const out = weekWorkoutRows([
    await mk("2026-10-06", { id: 5, exercise_id: "later", completed_at: "2026-10-06T05:00:00Z" }),
    await mk("2026-10-03", { id: 900, exercise_id: "earlier", completed_at: "2026-10-03T05:00:00Z" }),
    await mk("2026-08-01", { id: 3, exercise_id: "old", completed_at: "2026-10-06T06:00:00Z" }),
  ], m, W);
  assertEquals(out.map((r) => r.date), ["2026-10-03", "2026-10-06"]);
});

Deno.test("weekly-report wires ONE window into all three reads", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(src.includes("istDatesEnding(7, now)"));
  assert(!src.includes("sevenDaysAgo.setDate"), "the 8-date window must be gone");
  assert(!src.includes('.gte("completed_at", sevenDaysAgoStr'), "wle must not be selected by completed_at");
  assert(src.includes('.in("workout_log_id", ids)'));
  assertEquals((src.match(/\.gte\("date", sevenDaysAgoStr\)/g) ?? []).length, 2); // nutrition + workout_logs
});
