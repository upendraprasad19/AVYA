import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { countDistinctDates } from "./distinct_dates.ts";

Deno.test("countDistinctDates: two rows on the same date count once", () => {
  assertEquals(countDistinctDates([{ date: "2026-11-01" }, { date: "2026-11-01" }]), 1);
});

Deno.test("countDistinctDates: 17-style duplicates (several two-row dates) count distinct days", () => {
  const rows = [];
  for (let d = 1; d <= 20; d++) {
    const date = `2026-10-${String(d).padStart(2, "0")}`;
    rows.push({ date });
    if (d <= 17) rows.push({ date }); // the double-row dates
  }
  assertEquals(rows.length, 37);
  assertEquals(countDistinctDates(rows), 20);
});

Deno.test("countDistinctDates: NULL, undefined and empty dates are ignored", () => {
  assertEquals(
    countDistinctDates([{ date: null }, {}, { date: "" }, { date: "   " }, { date: "2026-11-02" }]),
    1,
  );
});

Deno.test("countDistinctDates: malformed dates are ignored (M52)", () => {
  assertEquals(
    countDistinctDates([
      { date: "2026-1-5" },
      { date: "not a date" },
      { date: "20261110" },
      { date: "2026-11-10T05:30:00Z" },
      { date: "2026-11-10" },
    ]),
    1,
  );
});

Deno.test("countDistinctDates: a padded valid date is trimmed and counted once", () => {
  assertEquals(countDistinctDates([{ date: " 2026-11-10 " }, { date: "2026-11-10" }]), 1);
});

Deno.test("countDistinctDates: empty input is 0", () => {
  assertEquals(countDistinctDates([]), 0);
});
