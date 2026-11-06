import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DAY_SWAP_QUOTA_KEY,
  FREE_DAY_SWAP_LIMIT,
  MAX_WEEKS_AHEAD,
  PRO_DAY_SWAP_LIMIT,
  limitForTier,
  mapQuotaResult,
  validateWeekStart,
  windowStartIso,
} from "./logic.ts";

// Fixed "now": 2026-09-26T12:00:00.000Z = 2026-09-26 17:30 IST (a Saturday;
// 2026-09-26 is independently verified as a Saturday by calendar arithmetic
// from 2026-01-01 = Thursday — see "Notes for the coordinator"). Its IST
// week's Monday is 2026-09-21.
const NOW = new Date("2026-09-26T12:00:00.000Z");
const CURRENT_MONDAY = "2026-09-21";

Deno.test("validateWeekStart — missing week_start", () => {
  const r = validateWeekStart(undefined, NOW);
  assertEquals(r, { ok: false, error: "missing_week_start" });
});

Deno.test("validateWeekStart — non-string week_start", () => {
  const r = validateWeekStart(20260921, NOW);
  assertEquals(r, { ok: false, error: "missing_week_start" });
});

Deno.test("validateWeekStart — wrong format (single-digit month)", () => {
  const r = validateWeekStart("2026-9-21", NOW);
  assertEquals(r, { ok: false, error: "invalid_week_start_format" });
});

Deno.test("validateWeekStart — invalid calendar date rolls over silently in Date.parse", () => {
  // 2026 is not a leap year: Feb has 28 days, so '2026-02-30' would silently
  // roll to 2026-03-02 without the round-trip guard.
  const r = validateWeekStart("2026-02-30", NOW);
  assertEquals(r, { ok: false, error: "invalid_calendar_date" });
});

Deno.test("validateWeekStart — well-formed but not a Monday", () => {
  // 2026-09-22 is a Tuesday (Monday 2026-09-21 + 1 day).
  const r = validateWeekStart("2026-09-22", NOW);
  assertEquals(r, { ok: false, error: "week_start_not_monday" });
});

Deno.test("validateWeekStart — a past Monday is refused", () => {
  // 2026-09-14 is the Monday one week before the current IST Monday.
  const r = validateWeekStart("2026-09-14", NOW);
  assertEquals(r, { ok: false, error: "week_start_in_past" });
});

Deno.test("validateWeekStart — the current IST Monday is allowed (diff = 0)", () => {
  const r = validateWeekStart(CURRENT_MONDAY, NOW);
  assertEquals(r, { ok: true, weekStart: CURRENT_MONDAY });
});

Deno.test("validateWeekStart — exactly 8 weeks ahead is allowed (boundary inclusive)", () => {
  // 2026-09-21 + 56 days = 2026-11-16 (also a Monday: 56 = 8*7).
  const r = validateWeekStart("2026-11-16", NOW);
  assertEquals(r, { ok: true, weekStart: "2026-11-16" });
});

Deno.test("validateWeekStart — 9 weeks ahead is refused", () => {
  // 2026-09-21 + 63 days = 2026-11-23 (also a Monday: 63 = 9*7).
  const r = validateWeekStart("2026-11-23", NOW);
  assertEquals(r, { ok: false, error: "week_start_too_far_ahead" });
});

Deno.test("windowStartIso — appends the IST midnight offset", () => {
  assertEquals(windowStartIso("2026-09-21"), "2026-09-21T00:00:00+05:30");
});

Deno.test("limitForTier — free vs PRO", () => {
  assertEquals(limitForTier(false), FREE_DAY_SWAP_LIMIT);
  assertEquals(limitForTier(true), PRO_DAY_SWAP_LIMIT);
  assertEquals(FREE_DAY_SWAP_LIMIT, 1);
  assertEquals(PRO_DAY_SWAP_LIMIT, 3);
});

Deno.test("mapQuotaResult — -1 maps to allowed:false, used pinned to limit", () => {
  assertEquals(mapQuotaResult(-1, 3), { allowed: false, used: 3, limit: 3 });
  assertEquals(mapQuotaResult(-1, 1), { allowed: false, used: 1, limit: 1 });
});

Deno.test("mapQuotaResult — a positive count maps to allowed:true with that count", () => {
  assertEquals(mapQuotaResult(1, 3), { allowed: true, used: 1, limit: 3 });
  assertEquals(mapQuotaResult(3, 3), { allowed: true, used: 3, limit: 3 });
});

Deno.test("sanity — quota key constant and max-weeks-ahead constant", () => {
  assertEquals(DAY_SWAP_QUOTA_KEY, "day_swap");
  assertEquals(MAX_WEEKS_AHEAD, 8);
});

// Mirror guard for the file-level exemption of this file in
// scripts/check_local_date_key_drift.dart's tsAllowlist. The exemption is only
// safe while this file's clock reads stay exactly what they are today: ONE
// injectable `now: Date = new Date()` default (resolved through
// istWeekStartIso, IST-safe) and ONE Z-anchored toISOString round trip of a
// client-supplied calendar date. Any new clock read or UTC slice must fail
// here and be reviewed, instead of silently riding the file-wide exemption.
Deno.test("logic.ts clock reads stay pinned (guard for the date-key-drift exemption)", async () => {
  const raw = await Deno.readTextFile(new URL("./logic.ts", import.meta.url));
  const src = raw
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((l) => {
      const i = l.search(/(?<!:)\/\//);
      return i === -1 ? l : l.substring(0, i);
    })
    .join("\n");
  const count = (re: RegExp) => (src.match(re) ?? []).length;
  assertEquals(count(/new Date\(\s*\)/g), 1, "zero-arg new Date(): only the injectable `now` default may read the clock");
  assertEquals(count(/Date\.now\(/g), 0, "Date.now(): derive the moment from the injectable `now`");
  assertEquals(count(/\.toISOString\(\)/g), 1, "toISOString(): only the Z-anchored round-trip validity check may slice a UTC date");
});
