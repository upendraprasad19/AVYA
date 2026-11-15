import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getPRTimelineTool } from "../progress/getPRTimeline.ts";
import { fakeSb } from "./fake_sb.ts";
import { istDateStr } from "../../ist_date.ts";
import { workoutLogIdForDate } from "../../uuid_v5.ts";

// deno-lint-ignore no-explicit-any
const mkCtx = (sb: any) => ({ userId: "u1", isPro: false, sb, requestId: "t" });
let n = 1;
const row = async (date: string, over: Record<string, unknown> = {}) => ({
  id: n++,
  user_id: "u1",
  workout_log_id: await workoutLogIdForDate(date),
  exercise_id: "Deadlift",
  set_number: 3,
  is_pr: true,
  completed_at: `${date}T05:00:00Z`,
  deleted_at: null,
  weight_kg: 100,
  reps: 15,
  logging_type: "weight_reps",
  duration_seconds: null,
  distance_km: null,
  ...over,
});

Deno.test("getPRTimeline — a stale PR on a superseded row is not listed (dedupe BEFORE is_pr filter)", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row("2026-09-01", { set_number: 3, is_pr: true }),
      await row("2026-09-01", { set_number: 4, is_pr: false }),
    ],
  });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "deadlift" });
  assertEquals(r.pr_count, 0);
});

Deno.test("getPRTimeline — an edited-old-log PR is dated to its OWN day, even with a past `to`", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row("2026-03-10", { completed_at: "2026-10-05T04:00:00Z" }),
    ],
  });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift", to: "2026-03-31" });
  assertEquals(r.pr_count, 1);
  assertEquals(r.prs[0].date, "2026-03-10");
  const r2 = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift", from: "2026-04-01" });
  assertEquals(r2.pr_count, 0);
});

Deno.test("getPRTimeline — sorted by resolved day desc BEFORE the cap; edited old row is not 'latest'", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row("2026-01-05", { completed_at: "2026-10-06T04:00:00Z", weight_kg: 80 }),
      await row("2026-09-05", { weight_kg: 120 }),
    ],
  });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift" });
  assertEquals(r.latest_pr_date, "2026-09-05");
  assertEquals(r.first_pr_date, "2026-01-05");
  assertEquals(r.prs[0].weight_kg, 120);
});

Deno.test("getPRTimeline — more than 50 PRs: 50 most recent returned, truncated, pr_count over all", async () => {
  const rows = [];
  for (let i = 0; i < 60; i++) {
    const d = istDateStr(new Date(Date.UTC(2026, 0, 1 + i)));
    rows.push(await row(d, { weight_kg: 50 + i }));
  }
  const { sb } = fakeSb({ workout_log_exercises: rows });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift" });
  assertEquals(r.prs.length, 50);
  assertEquals(r.pr_count, 60);
  assertEquals(r.truncated, true);
  assertEquals(r.first_pr_date, "2026-01-01");
  assertEquals(r.prs[0].date, "2026-03-01");
});

Deno.test("getPRTimeline — rows over the 1,000-row page cap are all read (1,100 distinct days)", async () => {
  const rows = [];
  for (let i = 0; i < 1100; i++) {
    const d = istDateStr(new Date(Date.UTC(2023, 0, 1 + i)));
    rows.push(await row(d, { weight_kg: 1 }));
  }
  const { sb } = fakeSb({ workout_log_exercises: rows });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift" });
  assertEquals(r.pr_count, 1100);
  assertEquals(r.first_pr_date, "2023-01-01");
});

Deno.test("getPRTimeline — field is total_reps", async () => {
  const { sb } = fakeSb({ workout_log_exercises: [await row("2026-09-01")] });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift" });
  assertEquals(r.prs[0].total_reps, 15);
  assertEquals("reps" in r.prs[0], false);
});

Deno.test("getPRTimeline — `to` and `from` bound the RESOLVED day: a later PR and an earlier PR are excluded", async () => {
  const { sb } = fakeSb({
    workout_log_exercises: [
      await row("2026-02-01", { weight_kg: 90 }),
      await row("2026-03-10", { weight_kg: 100 }),
      await row("2026-05-01", { weight_kg: 110 }),
    ],
  });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift", from: "2026-03-01", to: "2026-03-31" });
  assertEquals(r.pr_count, 1);
  assertEquals(r.prs[0].weight_kg, 100);
});

Deno.test("getPRTimeline — `to` defaults to today: a rescheduled-forward PR (future day) is not listed", async () => {
  const future = istDateStr(new Date(Date.now() + 5 * 86400_000));
  const { sb } = fakeSb({
    workout_log_exercises: [await row("2026-09-01"), await row(future, { weight_kg: 200 })],
  });
  const r = await getPRTimelineTool.handler!(mkCtx(sb), { exerciseId: "Deadlift" });
  assertEquals(r.pr_count, 1);
  assertEquals(r.latest_pr_date, "2026-09-01");
});
