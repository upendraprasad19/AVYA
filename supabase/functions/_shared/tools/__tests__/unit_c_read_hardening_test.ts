// Unit C (§2.24) — behavioral regression tests for the EF read-hardening fixes.
// A fake Supabase client whose EVERY query resolves to {data:null, error} lets us
// assert the fix SURFACES the failure instead of coercing it to empty/default data
// (which pre-fix made the coach report a false "0 workouts" / wrong promotion status,
// and made the rank engine silently block a promotion). Diagnose a7e2c4.
//
// Covers the three cleanly-callable units (the highest-value + subtlest sites):
//   • getProgressSummary (site 1)   — must THROW, not return false zeros
//   • getPromotionStatus (site 12)  — must THROW, not return SD2/0 defaults
//   • completionRateOverWindow (site 10) — must return the -1.0 SENTINEL on error
//     (so the gate fails and highestQualified keeps earned ranks) and the correct
//     rate on success.
// The per-user cron sites (2,3,4,6,7,8,9,11) live inside Deno.serve handlers that
// need a full request/roster mock; they are type-checked by the CI `deno check` step
// (which confirms each edit compiles + captures `error`) and were read line-by-line
// across the ×4 plan review + B-pass. Run: deno test supabase/functions/

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getProgressSummaryTool } from "../progress/getProgressSummary.ts";
import { getPromotionStatusTool } from "../progress/getPromotionStatus.ts";
import { completionRateOverWindow } from "../../rank_engine.ts";
import type { ToolContext } from "../types.ts";

/** A fake Supabase client whose every query resolves to {data:null,error,count:null}. */
// deno-lint-ignore no-explicit-any
function failingSb(error: unknown): any {
  const result = { data: null, error, count: null };
  // deno-lint-ignore no-explicit-any
  const builder: any = {};
  for (
    const m of [
      "from",
      "select",
      "eq",
      "gte",
      "lte",
      "in",
      "order",
      "limit",
      "upsert",
      "insert",
    ]
  ) {
    builder[m] = () => builder;
  }
  builder.maybeSingle = () => Promise.resolve(result);
  builder.single = () => Promise.resolve(result);
  // Thenable → `await sb.from()...gte()` (a query with no terminal .single) resolves
  // to `result`; each element of a Promise.all([...]) does too.
  // deno-lint-ignore no-explicit-any
  builder.then = (resolve: (r: typeof result) => void) => resolve(result);
  return { from: () => builder };
}

/** A fake Supabase client that returns `rows` for a chained (thenable) query. */
// deno-lint-ignore no-explicit-any
function rowsSb(rows: unknown[]): any {
  const result = { data: rows, error: null, count: rows.length };
  // deno-lint-ignore no-explicit-any
  const builder: any = {};
  for (
    const m of ["from", "select", "eq", "gte", "lte", "in", "order", "limit"]
  ) {
    builder[m] = () => builder;
  }
  builder.maybeSingle = () => Promise.resolve({ data: rows[0] ?? null, error: null });
  builder.single = () => Promise.resolve({ data: rows[0] ?? null, error: null });
  // deno-lint-ignore no-explicit-any
  builder.then = (resolve: (r: typeof result) => void) => resolve(result);
  return { from: () => builder };
}

function ctx(sb: unknown): ToolContext {
  return {
    userId: "u1",
    isPro: false,
    // deno-lint-ignore no-explicit-any
    sb: sb as any,
    requestId: "unit-c-test",
  };
}

const DB_ERR = { code: "57014", message: "statement timeout", details: "", hint: "" };

Deno.test("Unit C site 1 — getProgressSummary THROWS on a DB error (no false zero)", async () => {
  await assertRejects(
    () => getProgressSummaryTool.handler!(ctx(failingSb(DB_ERR)), { periodDays: 30 }),
  );
});

Deno.test("Unit C site 12 — getPromotionStatus THROWS on a DB error (no SD2/0 default)", async () => {
  await assertRejects(
    () => getPromotionStatusTool.handler!(ctx(failingSb(DB_ERR)), {}),
  );
});

Deno.test("Unit C site 10 — completionRateOverWindow returns -1.0 SENTINEL on a query error", async () => {
  const rate = await completionRateOverWindow(failingSb(DB_ERR), "u1", 4);
  assertEquals(rate, -1.0);
});

Deno.test("Unit C site 10 — completionRateOverWindow returns the correct rate on success", async () => {
  // 4 non-rest scheduled days, 2 completed → 0.5. A 'rest' day is excluded.
  const rows = [
    { status: "completed", scheduled_date: "2026-07-01" },
    { status: "completed", scheduled_date: "2026-07-02" },
    { status: "planned", scheduled_date: "2026-07-03" },
    { status: "planned", scheduled_date: "2026-07-04" },
    { status: "rest", scheduled_date: "2026-07-05" },
  ];
  const rate = await completionRateOverWindow(rowsSb(rows), "u1", 4);
  assertEquals(rate, 0.5);
});

Deno.test("Unit C site 10 — windowWeeks<=0 stays 0.0 (invalid window is not a DB error)", async () => {
  const rate = await completionRateOverWindow(failingSb(DB_ERR), "u1", 0);
  assertEquals(rate, 0.0);
});
