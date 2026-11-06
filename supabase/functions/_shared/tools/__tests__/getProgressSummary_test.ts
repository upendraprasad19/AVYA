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
  assertEquals(getProgressSummaryTool.maxLatencyMs, 6000);
});

// NOTE: handler() integration tests against real Supabase require a seeded
// test DB and are deferred. The shape tests above + manual prod verification
// in A.13 cover the handler.

// ── L1b behavioural tests (handler against a table-backed fake) ──────────────
import { fakeSb } from "./fake_sb.ts";
import { workoutLogIdForDate } from "../../uuid_v5.ts";
import { istDatesEnding } from "../../exercise_day.ts";

// deno-lint-ignore no-explicit-any
const mkCtx = (sb: any) => ({ userId: "u1", isPro: false, sb, requestId: "t" });
const D = istDatesEnding(7); // window of periodDays=7
const today = D[D.length - 1];
const wle = async (date: string, over: Record<string, unknown> = {}) => ({
  id: Math.floor(Math.random() * 1e9),
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "bench",
  set_number: 3,
  is_pr: false,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  weight_kg: 50,
  reps: 30,
  ...over,
});

Deno.test("getProgressSummary — superseded summary rows are counted ONCE (volume, PR)", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await wle(today, { id: 1, set_number: 3, is_pr: true, reps: 30 }),
      await wle(today, { id: 2, set_number: 4, is_pr: false, reps: 40 }),
    ],
  });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.total_volume_kg, 50 * 40); // winner only
  assertEquals(r.pr_count, 0); // stale PR on the superseded row is dropped
  assertEquals(r.workouts_completed, 1);
});

Deno.test("getProgressSummary — an edited OLD log (old id, recent completed_at) is outside the window", async () => {
  const old = D[0] > "2026-01-01" ? "2026-01-05" : "2025-01-05";
  const { sb } = fakeSb({
    workout_log_exercises: [await wle(old, { completed_at: `${today}T04:00:00Z` })],
  });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.workouts_completed, 0);
  assertEquals(r.total_volume_kg, 0);
});

Deno.test("getProgressSummary — a rescheduled-forward log (future id) is dropped", async () => {
  const future = istDatesEnding(1, new Date(Date.now() + 5 * 86400_000))[0];
  const { sb } = fakeSb({
    workout_log_exercises: [await wle(future, { completed_at: `${today}T04:00:00Z` })],
  });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.workouts_completed, 0);
});

Deno.test("getProgressSummary — more than 1,000 rows are all read (paging)", async () => {
  const rows = [];
  for (let i = 0; i < 1500; i++) {
    rows.push(await wle(today, { id: i + 1, exercise_id: `ex${i}`, weight_kg: 1, reps: 1 }));
  }
  const { sb } = fakeSb({ workout_log_exercises: rows });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.total_volume_kg, 1500);
});

Deno.test("getProgressSummary — adherence counts only past/today non-rest days (future days excluded)", async () => {
  const fut = istDatesEnding(1, new Date(Date.now() + 3 * 86400_000))[0];
  const { sb } = fakeSb({
    scheduled_workouts: [
      { id: 1, user_id: "u1", scheduled_date: today, status: "completed" },
      { id: 2, user_id: "u1", scheduled_date: D[0], status: "rest" },
      { id: 3, user_id: "u1", scheduled_date: D[1], status: "moved" },
      { id: 4, user_id: "u1", scheduled_date: D[2], status: "dropped" },
      { id: 5, user_id: "u1", scheduled_date: D[3], status: null },
      { id: 6, user_id: "u1", scheduled_date: fut, status: "planned" },
    ],
    workout_log_exercises: [await wle(today)],
  });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.workouts_planned, 1);
  assertEquals(r.adherence_pct, 100);
});

Deno.test("getProgressSummary — issues exactly the four parallel reads' tables (no q5)", async () => {
  const { sb, calls } = fakeSb({});
  await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  const tables = new Set(calls.map((c) => c.table));
  assertEquals([...tables].sort(), [
    "nutrition_logs", "scheduled_workouts", "weight_logs", "workout_log_exercises",
  ]);
  const wleCalls = calls.filter((c) => c.table === "workout_log_exercises");
  // every wle read selects by id list and tombstone filter, never completed_at
  for (const c of wleCalls) {
    assertEquals(c.filters.some(([op, col]) => op === "in" && col === "workout_log_id"), true);
    assertEquals(c.filters.some(([op, col]) => op === "is" && col === "deleted_at"), true);
    assertEquals(c.filters.some(([, col]) => col === "completed_at"), false);
  }
});

Deno.test("getProgressSummary — a missing-date-bucket row whose IST(completed_at) is outside the window is not counted", async () => {
  const { MISSING_DATE_BUCKET_ID_PROMISE } = await import("../../exercise_day.ts");
  const bucket = await MISSING_DATE_BUCKET_ID_PROMISE;
  const { sb } = fakeSb({
    workout_log_exercises: [
      await wle(today, { id: 1, workout_log_id: bucket, completed_at: "2025-01-05T05:00:00Z", weight_kg: 10, reps: 10 }),
      await wle(today, { id: 2, exercise_id: "squat", weight_kg: 20, reps: 10 }),
    ],
  });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.total_volume_kg, 200);
  assertEquals(r.workouts_completed, 1);
});

Deno.test("getProgressSummary — truncated flag is false on a normal read, true when a read hits its page budget", async () => {
  const { sb } = fakeSb({ workout_log_exercises: [await wle(today)] });
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.truncated, false);
});

Deno.test("getProgressSummary — a read that exhausts its page budget sets truncated:true", async () => {
  const rows = Array.from({ length: 6 }, (_, i) => ({ id: i + 1, user_id: "u1", date: today, weight_kg: 70 + i }));
  const { sb } = fakeSb({ weight_logs: rows }, { pageCap: 1 }); // 1 row per page, budget 5 pages
  const r = await getProgressSummaryTool.handler!(mkCtx(sb), { periodDays: 7 });
  assertEquals(r.truncated, true);
});
