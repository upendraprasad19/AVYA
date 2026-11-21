import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { recentLivePrs } from "./recent_prs.ts";
import { buildDayMap } from "./exercise_day.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z"); // 09:30 IST 2026-10-07
const mk = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "Bench Press",
  set_number: 3,
  is_pr: true,
  completed_at: "2026-10-07T03:30:00Z",
  deleted_at: null,
  ...over,
});

Deno.test("recentLivePrs — newest completed_at first; today and yesterday kept, 3-days-back and future dropped", async () => {
  const m = await buildDayMap(NOW);
  const rows = [
    await mk("2026-10-07", { exercise_id: "a", completed_at: "2026-10-07T03:00:00Z" }),
    await mk("2026-10-06", { exercise_id: "b", completed_at: "2026-10-07T03:30:00Z" }),
    await mk("2026-10-04", { exercise_id: "c" }),
    await mk("2026-10-09", { exercise_id: "d" }),
  ];
  assertEquals(recentLivePrs(rows, m, NOW).map((r) => r.exercise_id), ["b", "a"]);
});

Deno.test("recentLivePrs — superseded row's stale is_pr loses to the winner's own flag", async () => {
  const m = await buildDayMap(NOW);
  const rows = [
    await mk("2026-10-07", { id: 1, set_number: 3, is_pr: true }),
    await mk("2026-10-07", { id: 2, set_number: 4, is_pr: false }),
  ];
  assertEquals(recentLivePrs(rows, m, NOW).length, 0);
});
