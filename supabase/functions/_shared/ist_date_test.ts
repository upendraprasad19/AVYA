import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { istYesterdayWindow } from "./ist_date.ts";

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
