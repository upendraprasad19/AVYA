// deno-lint-ignore-file no-explicit-any
// getPromotionStatus counts DISTINCT completed days (coach workout parity 2,
// OI-492): the all-time total from a paged `date` read, the 28-day cadence
// from the existing 365-day read through the pure recent28Dates helper.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getPromotionStatusTool, recent28Dates } from "../progress/getPromotionStatus.ts";
import { istDatesEnding } from "../../exercise_day.ts";
import { istDateStr } from "../../ist_date.ts";
import { fakeSb } from "./fake_sb.ts";
import type { ToolContext } from "../types.ts";

/** fake_sb has no maybeSingle; this LOCAL wrapper adds it (pattern: unit_c_read_hardening_test.ts). */
function withMaybeSingle(base: { from(t: string): any }): any {
  return {
    from(t: string) {
      const b = base.from(t);
      b.maybeSingle = () =>
        b.then((r: { data: any[] }) => ({ data: r.data?.[0] ?? null, error: null }));
      return b;
    },
  };
}

function ctx(tables: Record<string, any[]>, opts: { pageCap?: number } = {}): ToolContext {
  const { sb } = fakeSb(tables, opts);
  return { userId: "u1", isPro: false, sb: withMaybeSingle(sb as any), requestId: "t" } as ToolContext;
}

const base = (workout_logs: any[]): Record<string, any[]> => ({
  user_profile: [{ user_id: "u1", current_rank_code: "SD2", days_per_week: 4 }],
  users: [{ id: "u1", created_at: "2026-01-01T00:00:00Z" }],
  user_progress: [{ user_id: "u1", current_phase: 1 }],
  workout_logs,
});

const rowsFor = (dates: string[]) => dates.map((date, i) => ({ id: i + 1, user_id: "u1", date }));
const daysAgo = (n: number) => {
  const today = istDatesEnding(1)[0];
  return istDateStr(new Date(Date.parse(`${today}T00:00:00Z`) - n * 86_400_000));
};

// ── recent28Dates: pure, FIXED clock ────────────────────────────────────────

const NOW = new Date("2026-11-07T10:00:00Z");
const W = istDatesEnding(28, NOW);

Deno.test("recent28Dates: the window start counts, the day before does not, today counts (M43)", () => {
  const dayBefore = istDateStr(new Date(Date.parse(`${W[0]}T00:00:00Z`) - 86_400_000));
  assertEquals(recent28Dates([{ date: W[0] }], NOW), 1);
  assertEquals(recent28Dates([{ date: dayBefore }], NOW), 0);
  assertEquals(recent28Dates([{ date: W[27] }], NOW), 1);
  assertEquals(recent28Dates([{ date: dayBefore }, { date: W[0] }, { date: W[27] }], NOW), 2);
});

Deno.test("recent28Dates: a double-row date counts once; a NULL date is not counted", () => {
  assertEquals(recent28Dates([{ date: W[3] }, { date: W[3] }, { date: null }, {}], NOW), 1);
});

// ── the handler ─────────────────────────────────────────────────────────────

Deno.test("getPromotionStatus: total_workouts and cadence are DISTINCT days (a double-row date counts once) (M34)", async () => {
  const d = [daysAgo(1), daysAgo(1), daysAgo(2), daysAgo(3), daysAgo(3), daysAgo(4)];
  const out = await getPromotionStatusTool.handler!(ctx(base(rowsFor(d))), {}) as any;
  assertEquals(out.total_workouts, 4);
  assertEquals(out.cadence.actual_4w, 1); // 4 distinct days / 4 weeks
});

Deno.test("getPromotionStatus: a row older than 365 days counts in the all-time total but not in the cadence (M54)", async () => {
  const d = [daysAgo(1), daysAgo(2), daysAgo(400), daysAgo(500)];
  const out = await getPromotionStatusTool.handler!(ctx(base(rowsFor(d))), {}) as any;
  assertEquals(out.total_workouts, 4);
  assertEquals(out.cadence.actual_4w, 0.5); // only the 2 recent days / 4
});

Deno.test("getPromotionStatus: a NULL-date row is not counted", async () => {
  const rows = [...rowsFor([daysAgo(1), daysAgo(2)]), { id: 99, user_id: "u1", date: null }];
  const out = await getPromotionStatusTool.handler!(ctx(base(rows)), {}) as any;
  assertEquals(out.total_workouts, 2);
});

Deno.test("getPromotionStatus: days older than 28 do not feed the cadence", async () => {
  const d = [daysAgo(1), daysAgo(29), daysAgo(60)];
  const out = await getPromotionStatusTool.handler!(ctx(base(rowsFor(d))), {}) as any;
  assertEquals(out.total_workouts, 3);
  assertEquals(out.cadence.actual_4w, 0.25);
});

Deno.test("getPromotionStatus: an all-time read that reports truncated THROWS (M56b)", async () => {
  // 25 rows, a server cap of 1 per page: 20 pages read, 5 never seen. All rows are OLDER than
  // 365 days, so the 365-day streak read (which has its own truncation guard) sees nothing and
  // cannot mask a missing guard on the all-time read.
  const rows = rowsFor(Array.from({ length: 25 }, (_, i) => daysAgo(i + 400)));
  await assertRejects(
    () => getPromotionStatusTool.handler!(ctx(base(rows), { pageCap: 1 }), {}),
    Error,
    "truncated",
  );
});

Deno.test("getPromotionStatus: another user's rows never count", async () => {
  const rows = [
    ...rowsFor([daysAgo(1)]),
    { id: 50, user_id: "someone-else", date: daysAgo(2) },
  ];
  const out = await getPromotionStatusTool.handler!(ctx(base(rows)), {}) as any;
  assertEquals(out.total_workouts, 1);
});

// IST boundary (B-pass S1-F2): at 19:00 UTC on 2026-11-07 the IST date is
// 2026-11-08 and the window starts 2026-10-12 (literals: an independent
// oracle). A UTC bucketing would start it on 2026-10-11.
Deno.test("recent28Dates: after 18:30 UTC the window starts on the IST date 27 days back (2026-10-12)", () => {
  const LATE = new Date("2026-11-07T19:00:00Z");
  assertEquals(recent28Dates([{ date: "2026-10-12" }], LATE), 1);
  assertEquals(recent28Dates([{ date: "2026-10-11" }], LATE), 0);
  assertEquals(recent28Dates([{ date: "2026-11-08" }, { date: "2026-10-12" }], LATE), 2);
});
