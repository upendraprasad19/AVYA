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
  if (!/select\("user_id, exercise_id, exercise_name, weight_kg, reps, completed_at, deleted_at"\)/.test(src) &&
      !src.includes('"user_id, exercise_id, exercise_name, weight_kg, reps, completed_at, deleted_at"')) {
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
