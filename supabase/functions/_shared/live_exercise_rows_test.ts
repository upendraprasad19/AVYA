import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { liveSummaryRows } from "./live_exercise_rows.ts";
import { buildDayMap, MISSING_DATE_BUCKET_ID_PROMISE } from "./exercise_day.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z");
const base = { user_id: "u1", workout_log_id: "w1", exercise_id: "bench" };

Deno.test("drops tombstoned rows", () => {
  const out = liveSummaryRows([{ ...base, id: 1, set_number: 3, deleted_at: "2026-10-01T00:00:00Z" }]);
  assertEquals(out.length, 0);
});

Deno.test("one row per key: highest set_number wins, then highest id", () => {
  const out = liveSummaryRows([
    { ...base, id: 1, set_number: 3 },
    { ...base, id: 2, set_number: 5 },
    { ...base, id: 3, set_number: 4 },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out[0].set_number, 5);
  const tie = liveSummaryRows([
    { ...base, id: 7, set_number: 4 },
    { ...base, id: 9, set_number: 4 },
    { ...base, id: 8, set_number: 4 },
  ]);
  assertEquals(tie[0].id, 9);
});

Deno.test("two users on the same day/exercise are NOT collapsed (workout_log_id is not user-scoped)", () => {
  const out = liveSummaryRows([
    { ...base, user_id: "u1", id: 1, set_number: 3 },
    { ...base, user_id: "u2", id: 2, set_number: 3 },
  ]);
  assertEquals(out.length, 2);
});

Deno.test("a stale PR on a superseded row is dropped — the winner's OWN is_pr is used", () => {
  const out = liveSummaryRows([
    { ...base, id: 1, set_number: 3, is_pr: true },
    { ...base, id: 2, set_number: 4, is_pr: false },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out.filter((r) => r.is_pr).length, 0);
});

Deno.test("A→B→A documented limit: highest count wins", () => {
  const out = liveSummaryRows([
    { ...base, id: 1, set_number: 3 },
    { ...base, id: 2, set_number: 5 },
    { ...base, id: 3, set_number: 3 },
  ]);
  assertEquals(out[0].set_number, 5);
});

Deno.test("unresolved ids key by IST(completed_at) day — never collapse across days", async () => {
  const m = await buildDayMap(NOW);
  const bucket = await MISSING_DATE_BUCKET_ID_PROMISE;
  const mk = (id: number, at: string) => ({
    user_id: "u1", workout_log_id: bucket, exercise_id: "bench", id, set_number: 3, completed_at: at,
  });
  const out = liveSummaryRows(
    [mk(1, "2026-10-05T04:00:00Z"), mk(2, "2026-10-06T04:00:00Z"), mk(3, "2026-10-06T05:00:00Z")],
    m,
  );
  assertEquals(out.length, 2);
});

Deno.test("resolved ids with a map still key by workout_log_id", async () => {
  const m = await buildDayMap(NOW);
  const a = await workoutLogIdForDate("2026-10-05");
  const b = await workoutLogIdForDate("2026-10-06");
  const out = liveSummaryRows(
    [
      { user_id: "u1", workout_log_id: a, exercise_id: "bench", id: 1, set_number: 3 },
      { user_id: "u1", workout_log_id: b, exercise_id: "bench", id: 2, set_number: 3 },
    ],
    m,
  );
  assertEquals(out.length, 2);
});

Deno.test("exercise_id is keyed case-insensitively (ilike-matched variants are one exercise-day)", () => {
  const out = liveSummaryRows([
    { ...base, exercise_id: "Bench Press", id: 1, set_number: 3 },
    { ...base, exercise_id: "bench press", id: 2, set_number: 4 },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out[0].set_number, 4);
});
