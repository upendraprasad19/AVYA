import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { istWeekStartIso, istYesterdayWindow } from "./ist_date.ts";

Deno.test("istYesterdayWindow — UTC evening still lands on the same IST calendar day boundary", () => {
  // 2026-09-13 20:00 UTC = 2026-09-14 01:30 IST — "today" is the 14th, "yesterday" the 13th.
  const now = new Date("2026-09-13T20:00:00.000Z");
  const { yStart, tStart, label } = istYesterdayWindow(now);
  assertEquals(label, "2026-09-13");
  // tStart = start of 2026-09-14 IST = 2026-09-13T18:30:00.000Z
  assertEquals(tStart, "2026-09-13T18:30:00.000Z");
  // yStart = start of 2026-09-13 IST = 2026-09-12T18:30:00.000Z
  assertEquals(yStart, "2026-09-12T18:30:00.000Z");
});

Deno.test("istWeekStartIso — Sunday 23:59 IST still lands on THAT week's Monday", () => {
  // 2026-09-27T18:29:00.000Z + 5:30 = 2026-09-27 23:59:00 IST (a Sunday —
  // 2026-09-26 is a verified Saturday, see this task's coordinator notes).
  // The week Mon 2026-09-21 .. Sun 2026-09-27 has not rolled over yet.
  const now = new Date("2026-09-27T18:29:00.000Z");
  assertEquals(istWeekStartIso(now), "2026-09-21T00:00:00+05:30");
});

Deno.test("istWeekStartIso — Monday 00:00 IST rolls to the NEW week", () => {
  // 2026-09-27T18:30:00.000Z + 5:30 = 2026-09-28 00:00:00 IST (Monday).
  const now = new Date("2026-09-27T18:30:00.000Z");
  assertEquals(istWeekStartIso(now), "2026-09-28T00:00:00+05:30");
});

Deno.test("istWeekStartIso — mid-week Saturday resolves to that week's Monday", () => {
  // 2026-09-26T12:00:00.000Z + 5:30 = 2026-09-26 17:30 IST, still Saturday.
  const now = new Date("2026-09-26T12:00:00.000Z");
  assertEquals(istWeekStartIso(now), "2026-09-21T00:00:00+05:30");
});

Deno.test("istWeekStartIso — called exactly on a Monday returns that same day", () => {
  const now = new Date("2026-09-28T04:00:00.000Z"); // 2026-09-28 09:30 IST, Monday
  assertEquals(istWeekStartIso(now), "2026-09-28T00:00:00+05:30");
});
