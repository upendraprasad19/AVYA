import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildDayMap,
  chunkIds,
  istDatesEnding,
  istDateWindow,
  MISSING_DATE_BUCKET_ID_PROMISE,
  resolveDay,
  windowLogIds,
} from "./exercise_day.ts";
import { workoutLogIdForDate } from "./uuid_v5.ts";

const NOW = new Date("2026-10-07T04:00:00Z"); // 09:30 IST on 2026-10-07

Deno.test("istDatesEnding — N dates ascending, ending IST today", () => {
  assertEquals(istDatesEnding(3, NOW), ["2026-10-05", "2026-10-06", "2026-10-07"]);
});

Deno.test("istDatesEnding — 00:15 IST and 23:50 IST belong to the IST day, not the UTC day", () => {
  // 2026-10-06T18:45Z = 00:15 IST on 10-07 ; 2026-10-07T18:20Z = 23:50 IST on 10-07
  assertEquals(istDatesEnding(1, new Date("2026-10-06T18:45:00Z")), ["2026-10-07"]);
  assertEquals(istDatesEnding(1, new Date("2026-10-07T18:20:00Z")), ["2026-10-07"]);
});

Deno.test("istDateWindow — half-open [first 00:00+05:30, day after last 00:00+05:30)", () => {
  assertEquals(istDateWindow(["2026-10-06", "2026-10-07"]), {
    start: "2026-10-05T18:30:00.000Z",
    end: "2026-10-07T18:30:00.000Z",
  });
});

Deno.test("buildDayMap — covers 2020-01-01 .. today+400 and round-trips an id", async () => {
  const m = await buildDayMap(NOW);
  assertEquals(m.get(await workoutLogIdForDate("2020-01-01")), "2020-01-01");
  assertEquals(m.get(await workoutLogIdForDate("2026-09-29")), "2026-09-29");
  assertEquals(m.get(await workoutLogIdForDate("2027-11-11")), "2027-11-11"); // today+400
  assertEquals(m.has(await workoutLogIdForDate("2019-12-31")), false);
  assertEquals(m.has(await workoutLogIdForDate("2027-11-12")), false);
});

Deno.test("windowLogIds — v5 of each date plus the missing-date bucket", async () => {
  const ids = await windowLogIds(["2026-10-06", "2026-10-07"]);
  assertEquals(ids.length, 3);
  assertEquals(ids[0], await workoutLogIdForDate("2026-10-06"));
  assertEquals(ids[2], await MISSING_DATE_BUCKET_ID_PROMISE);
});

Deno.test("resolveDay — an edited OLD log (old id, recent completed_at) is attributed to its own day", async () => {
  const m = await buildDayMap(NOW);
  const row = {
    workout_log_id: await workoutLogIdForDate("2026-09-29"),
    completed_at: "2026-10-07T03:00:00Z",
  };
  assertEquals(resolveDay(row, m), "2026-09-29");
});

Deno.test("resolveDay — a forward-moved log (future id, earlier completed_at) resolves to the future day", async () => {
  const m = await buildDayMap(NOW);
  const row = {
    workout_log_id: await workoutLogIdForDate("2026-10-12"),
    completed_at: "2026-10-05T03:00:00Z",
  };
  assertEquals(resolveDay(row, m), "2026-10-12");
});

Deno.test("resolveDay — unresolved id falls back to IST(completed_at); 23:50 IST stays on its day", async () => {
  const m = await buildDayMap(NOW);
  assertEquals(
    resolveDay({ workout_log_id: await MISSING_DATE_BUCKET_ID_PROMISE, completed_at: "2026-10-06T18:20:00Z" }, m),
    "2026-10-06",
  );
  assertEquals(
    resolveDay({ workout_log_id: "not-an-id", completed_at: "2026-10-06T18:45:00Z" }, m),
    "2026-10-07",
  );
  assertEquals(resolveDay({ workout_log_id: null, completed_at: null }, m), null);
});

Deno.test("chunkIds — chunks of at most 100", () => {
  const ids = Array.from({ length: 250 }, (_, i) => String(i));
  assertEquals(chunkIds(ids).map((c) => c.length), [100, 100, 50]);
});
