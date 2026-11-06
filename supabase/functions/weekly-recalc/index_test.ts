import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { excludeDeletedLogs } from "./live_log_filter.ts";

// OI-246 follow-up (round-2 review finding P2, 2026-09-29).

Deno.test("excludeDeletedLogs: drops a row with a non-null deleted_at", () => {
  const rows = [
    { id: "live-1", deleted_at: null },
    { id: "dead-1", deleted_at: "2026-09-29T00:00:00Z" },
  ];
  const kept = excludeDeletedLogs(rows);
  assertEquals(kept.map((r) => r.id), ["live-1"]);
});

Deno.test("excludeDeletedLogs: keeps every row when none are deleted", () => {
  const rows = [
    { id: "a", deleted_at: null },
    { id: "b", deleted_at: null },
  ];
  assertEquals(excludeDeletedLogs(rows).length, 2);
});

Deno.test("excludeDeletedLogs: drops every row when all are deleted", () => {
  const rows = [
    { id: "a", deleted_at: "2026-09-29T00:00:00Z" },
    { id: "b", deleted_at: "2026-09-28T00:00:00Z" },
  ];
  assertEquals(excludeDeletedLogs(rows), []);
});

Deno.test("excludeDeletedLogs: empty input yields empty output", () => {
  assertEquals(excludeDeletedLogs([]), []);
});

// Wiring — the fetch must select deleted_at, and the fetched rows must be
// routed through excludeDeletedLogs before building allLogs. A source-grep
// check because the main handler makes a live Supabase call and is not
// otherwise unit-tested at the Deno level (same scope note as
// workout-window-closing/index_test.ts).
Deno.test("weekly-recalc: selects deleted_at and filters through excludeDeletedLogs before building allLogs", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("deleted_at: string | null")) {
    throw new Error("expected the workout_log_exercises fetch to select+type deleted_at");
  }
  if (!src.includes('completed_at, deleted_at"')) {
    throw new Error("expected the workout_log_exercises select column list to include deleted_at");
  }
  if (!src.includes("excludeDeletedLogs(rawLogs)")) {
    throw new Error("expected rawLogs to be routed through excludeDeletedLogs(rawLogs) before building allLogs");
  }
  const filterIdx = src.indexOf("excludeDeletedLogs(rawLogs)");
  const allLogsIdx = src.indexOf("const allLogs: WorkoutLog[] =");
  if (filterIdx === -1 || allLogsIdx === -1 || filterIdx > allLogsIdx) {
    throw new Error("expected excludeDeletedLogs to run BEFORE allLogs is built, not after");
  }
});

// ── L1b behavioural: liveLogsForWindow ───────────────────────────────────────
import { liveLogsForWindow } from "./live_log_filter.ts";
import { buildDayMap, istDatesEnding } from "../_shared/exercise_day.ts";
import { workoutLogIdForDate } from "../_shared/uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z");
const mkLog = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "bench",
  set_number: 3,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  ...over,
});

Deno.test("liveLogsForWindow: the progression input has ONE row per (user, day, exercise)", async () => {
  const m = await buildDayMap(NOW);
  const dates = istDatesEnding(28, NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-10-06", { id: 1, set_number: 3 }),
    await mkLog("2026-10-06", { id: 2, set_number: 4 }),
  ], m, dates);
  assertEquals(out.length, 1);
  assertEquals(out[0].set_number, 4);
  assertEquals(out[0].date, "2026-10-06");
});

Deno.test("liveLogsForWindow: an edited old log (old id, recent completed_at) is outside the 28-day window; date = resolved day", async () => {
  const m = await buildDayMap(NOW);
  const dates = istDatesEnding(28, NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-06-01", { completed_at: "2026-10-06T05:00:00Z" }),
    await mkLog("2026-10-01", { completed_at: "2026-10-06T05:00:00Z" }),
  ], m, dates);
  assertEquals(out.map((r) => r.date), ["2026-10-01"]);
});

Deno.test("liveLogsForWindow: two users on the same day/exercise both survive", async () => {
  const m = await buildDayMap(NOW);
  const out = liveLogsForWindow([
    await mkLog("2026-10-06", { user_id: "u1" }),
    await mkLog("2026-10-06", { user_id: "u2" }),
  ], m, istDatesEnding(28, NOW));
  assertEquals(out.length, 2);
});

// PRESENCE-ONLY: index.ts calls serve() at import. The window is exactly 28 IST dates and the
// wle read selects by workout_log_id, not completed_at (the write time).
Deno.test("weekly-recalc: 28-date window, wle selected by workout_log_id ids", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!src.includes("istDatesEnding(28)")) throw new Error("expected a 28-date IST window");
  if (!src.includes('.in("workout_log_id", chunk)')) throw new Error("expected the wle read to select by id list");
  if (src.includes('"completed_at",\n        fourWeeksAgoStr')) throw new Error("wle must not be selected by completed_at");
});
