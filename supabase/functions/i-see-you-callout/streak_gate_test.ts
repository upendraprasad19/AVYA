import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hasDeepStreak, readDeepStreak } from "./streak_gate.ts";
import { istDatesEnding, nextIstDate } from "../_shared/exercise_day.ts";
import { istDateStr } from "../_shared/ist_date.ts";
// The day before an IST date, read back in IST (same shape as nextIstDate).
const prevIstDate = (date: string) => istDateStr(new Date(Date.parse(`${date}T00:00:00Z`) - 86_400_000));
import { fakeSb } from "../_shared/tools/__tests__/fake_sb.ts";

const NOW = new Date("2026-11-07T10:00:00Z"); // an IST Saturday
const WINDOW = istDatesEnding(28, NOW);

const datesRows = (n: number) => WINDOW.slice(0, n).map((date) => ({ date }));

Deno.test("hasDeepStreak: 13 distinct dates is false, 14 is true", () => {
  assertEquals(hasDeepStreak(datesRows(13)), false);
  assertEquals(hasDeepStreak(datesRows(14)), true);
});

Deno.test("hasDeepStreak: 20 rows on 7 dates is false (the old row-count gate would pass: M50a)", () => {
  const rows = [];
  for (const date of WINDOW.slice(0, 7)) {
    rows.push({ date }, { date }, { date });
  }
  assert(rows.length >= 20);
  assertEquals(hasDeepStreak(rows), false);
});

Deno.test("hasDeepStreak: a NULL-date row is not counted", () => {
  assertEquals(hasDeepStreak([...datesRows(13), { date: null }]), false);
});

const sbWith = (rows: Array<Record<string, unknown>>, opts?: { pageCap?: number }) =>
  fakeSb({ workout_logs: rows }, opts).sb;

Deno.test("readDeepStreak: reads only inside the 28 IST dates (29-day-old and future rows excluded) (M57)", async () => {
  const old = prevIstDate(WINDOW[0]);
  const future = nextIstDate(WINDOW[27]);
  // 13 in-window dates + an out-of-window old row + a future row: still 13.
  const rows = [
    ...WINDOW.slice(0, 13).map((date, i) => ({ id: i + 1, user_id: "u1", date })),
    { id: 100, user_id: "u1", date: old },
    { id: 101, user_id: "u1", date: future },
  ];
  assertEquals(await readDeepStreak(sbWith(rows), "u1", NOW), false);
  // With a 14th in-window date it flips to true.
  rows.push({ id: 102, user_id: "u1", date: WINDOW[20] });
  assertEquals(await readDeepStreak(sbWith(rows), "u1", NOW), true);
});

Deno.test("readDeepStreak: another user's rows never count", async () => {
  const rows = WINDOW.slice(0, 14).map((date, i) => ({ id: i + 1, user_id: "someone-else", date }));
  assertEquals(await readDeepStreak(sbWith(rows), "u1", NOW), false);
});

Deno.test("readDeepStreak: pages past the server cap", async () => {
  // 14 distinct dates, 2 rows each = 28 rows, server cap of 5 per page.
  const rows: Array<Record<string, unknown>> = [];
  let id = 1;
  for (const date of WINDOW.slice(0, 14)) {
    rows.push({ id: id++, user_id: "u1", date }, { id: id++, user_id: "u1", date });
  }
  assertEquals(await readDeepStreak(sbWith(rows, { pageCap: 5 }), "u1", NOW), true);
});

Deno.test("readDeepStreak: a truncated read THROWS (M56c)", async () => {
  // 20 pages of 1 row each is the ceiling; a 25-row user with cap 1 is cut.
  const rows = WINDOW.slice(0, 25).map((date, i) => ({ id: i + 1, user_id: "u1", date }));
  // count:"exact" reports 25 but only 20 pages x 1 row are read -> truncated.
  const sb = fakeSb({ workout_logs: rows }, { pageCap: 1 }).sb;
  await assertRejects(() => readDeepStreak(sb, "u1", NOW), Error, "truncated");
});

// IST boundary (B-pass S1-F2): at 19:00 UTC on 2026-11-07 the IST date is
// already 2026-11-08, so the 28 IST dates run 2026-10-12 .. 2026-11-08. The
// expected dates are LITERALS (an independent oracle, not istDatesEnding): a
// UTC bucketing would end the window on 2026-11-07 and start it on 2026-10-11.
const LATE = new Date("2026-11-07T19:00:00Z");

Deno.test("readDeepStreak: after 18:30 UTC today's IST date counts and the window starts 2026-10-12", async () => {
  const thirteen = Array.from({ length: 13 }, (_, i) => `2026-10-${String(13 + i).padStart(2, "0")}`);
  const withIstToday = [...thirteen, "2026-11-08"].map((date, i) => ({ id: i + 1, user_id: "u1", date }));
  assertEquals(await readDeepStreak(sbWith(withIstToday), "u1", LATE), true);
  // The day before the IST window start is outside it.
  const withDayBefore = [...thirteen, "2026-10-11"].map((date, i) => ({ id: i + 1, user_id: "u1", date }));
  assertEquals(await readDeepStreak(sbWith(withDayBefore), "u1", LATE), false);
  // The IST window start itself is inside it.
  const withStart = [...thirteen, "2026-10-12"].map((date, i) => ({ id: i + 1, user_id: "u1", date }));
  assertEquals(await readDeepStreak(sbWith(withStart), "u1", LATE), true);
});
