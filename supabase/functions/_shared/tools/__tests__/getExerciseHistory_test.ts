import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getExerciseHistoryTool } from "../progress/getExerciseHistory.ts";

Deno.test("getExerciseHistory — schema accepts valid args", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Bench Press",
    weeks: 4,
  });
  assertEquals(result.success, true);
});

Deno.test("getExerciseHistory — schema accepts max weeks (52)", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 52,
  });
  assertEquals(result.success, true);
});

Deno.test("getExerciseHistory — schema rejects weeks < 1", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 0,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects weeks > 52", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 53,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects non-integer weeks", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Squat",
    weeks: 4.5,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema rejects empty exerciseId", () => {
  const result = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "",
    weeks: 4,
  });
  assertEquals(result.success, false);
});

Deno.test("getExerciseHistory — schema requires both fields", () => {
  const noWeeks = getExerciseHistoryTool.schema.safeParse({
    exerciseId: "Bench Press",
  });
  assertEquals(noWeeks.success, false);
  const noId = getExerciseHistoryTool.schema.safeParse({ weeks: 4 });
  assertEquals(noId.success, false);
});

Deno.test("getExerciseHistory — metadata", () => {
  assertEquals(getExerciseHistoryTool.tier, "pro");
  assertEquals(getExerciseHistoryTool.kind, "read");
  assertEquals(getExerciseHistoryTool.family, "progress");
  assertEquals(getExerciseHistoryTool.maxLatencyMs, 4000);
});

// NOTE: handler() integration tests against real Supabase require a seeded
// test DB and are deferred. The shape tests above + manual prod verification
// in D.8 cover the handler.

// ── L1b behavioural tests ────────────────────────────────────────────────────
import { fakeSb } from "./fake_sb.ts";
import { workoutLogIdForDate } from "../../uuid_v5.ts";
import { istDatesEnding } from "../../exercise_day.ts";

// deno-lint-ignore no-explicit-any
const mkCtx = (sb: any) => ({ userId: "u1", isPro: true, sb, requestId: "t" });
const W = istDatesEnding(28);
const row = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "Bench Press",
  set_number: 3,
  is_pr: false,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  weight_kg: 60,
  reps: 30,
  ...over,
});

Deno.test("getExerciseHistory — volume is best weight × TOTAL reps (not × sets) and the field is total_reps", async () => {
  const { sb } = fakeSb({ workout_log_exercises: [await row(W[27], { id: 1 })] });
  const r = await getExerciseHistoryTool.handler!(mkCtx(sb), { exerciseId: "bench press", weeks: 4 });
  assertEquals(r.history[0].total_reps, 30);
  assertEquals(r.history[0].total_volume_kg, 1800);
  assertEquals("reps" in r.history[0], false);
});

Deno.test("getExerciseHistory — chronological by resolved day even when row ids sort in reverse", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row(W[26], { id: 900, weight_kg: 60 }), // earlier day, larger id
      await row(W[27], { id: 5, weight_kg: 70 }), // later day, smaller id
    ],
  });
  const r = await getExerciseHistory(sb);
  assertEquals(r.current_weight_kg, 70);
  assertEquals(r.weight_change_kg, 10);
});

async function getExerciseHistory(sb: unknown) {
  return await getExerciseHistoryTool.handler!(mkCtx(sb), { exerciseId: "Bench Press", weeks: 4 });
}

Deno.test("getExerciseHistory — a superseded row is dropped and its PR is not counted", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row(W[27], { id: 1, set_number: 3, is_pr: true }),
      await row(W[27], { id: 2, set_number: 4, is_pr: false }),
    ],
  });
  const r = await getExerciseHistory(sb);
  assertEquals(r.total_sessions, 1);
  assertEquals(r.pr_count, 0);
});

Deno.test("getExerciseHistory — an edited old log is attributed to its own day (outside window => excluded)", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row("2025-01-05", { id: 1, completed_at: `${W[27]}T04:00:00Z` }),
    ],
  });
  const r = await getExerciseHistory(sb);
  assertEquals(r.total_sessions, 0);
});

Deno.test("getExerciseHistory — a 23:50-IST row stays on its IST day", async () => {
  // 23:50 IST on W[27] = 18:20Z same date
  const { sb } = fakeSb({
    workout_log_exercises: [await row(W[27], { id: 1, completed_at: `${W[27]}T18:20:00Z` })],
  });
  const r = await getExerciseHistory(sb);
  assertEquals(r.history[0].date, W[27]);
});

Deno.test("getExerciseHistory — a missing-date-bucket row (selected with the window ids) is attributed by IST(completed_at) and DROPPED when outside the window", async () => {
  const { MISSING_DATE_BUCKET_ID_PROMISE } = await import("../../exercise_day.ts");
  const bucket = await MISSING_DATE_BUCKET_ID_PROMISE;
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row(W[27], { id: 1, workout_log_id: bucket, completed_at: "2025-01-05T05:00:00Z" }), // far outside
      await row(W[26], { id: 2, workout_log_id: bucket, completed_at: `${W[26]}T05:00:00Z` }), // inside
    ],
  });
  const r = await getExerciseHistory(sb);
  assertEquals(r.total_sessions, 1);
  assertEquals(r.history[0].date, W[26]);
});
