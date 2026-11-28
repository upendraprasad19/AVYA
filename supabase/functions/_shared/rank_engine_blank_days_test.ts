// d7a3e5 (Piece B) — the server mirror of the client's blank-day rule in
// completionRateOverWindow. Client twin: lib/features/train/repositories/
// workout_repository.dart completionRateOverWindow; test twin:
// test/contracts/lapse_gap_policy_behavioral_test.dart ("73-day blank gap").
//
// Run: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/rank_engine_blank_days_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { blankDaysInWindow, completionRateOverWindow } from "./rank_engine.ts";

const day = (offset: number): string =>
  new Date(Date.now() - offset * 24 * 3600 * 1000).toISOString().split("T")[0];

Deno.test("blankDaysInWindow: counts absent days from the first row up to the latest row", () => {
  const present = new Set([day(10), day(5)]);
  // first row 10 days ago, last row 5 days ago: days 9,8,7,6 are blank
  assertEquals(blankDaysInWindow(present, day(10), day(10), day(0)), 4);
});

Deno.test("blankDaysInWindow: a trailing gap after the last row is not a miss", () => {
  assertEquals(blankDaysInWindow(new Set([day(10)]), day(10), day(10), day(0)), 0);
});

Deno.test("blankDaysInWindow: a future last row still stops at today (exclusive)", () => {
  const present = new Set([day(4), day(-3)]);
  // first 4 ago, last in 3 days: days 3,2,1 ago are blank, today is excluded
  assertEquals(blankDaysInWindow(present, day(4), day(20), day(0)), 3);
});

Deno.test("blankDaysInWindow: days before the first row are never counted", () => {
  const present = new Set([day(3), day(1)]);
  // first row 3 ago, window starts 20 ago, last row 1 ago: only day 2 is blank
  assertEquals(blankDaysInWindow(present, day(3), day(20), day(0)), 1);
});

Deno.test("blankDaysInWindow: no first row -> 0; window start after first row wins", () => {
  assertEquals(blankDaysInWindow(new Set(), null, day(5), day(0)), 0);
  assertEquals(
    blankDaysInWindow(new Set([day(1), day(30)]), day(30), day(5), day(0)),
    4, // days 5,4,3,2 ago blank; 1 ago present
  );
});

function fakeClient(
  rows: Array<{ status: string; scheduled_date: string }>,
  first: string | null,
): SupabaseClient {
  return {
    from: (_t: string) => ({
      select: (cols: string) => ({
        eq: () => cols.includes("status")
          ? { gte: () => Promise.resolve({ data: rows, error: null }) }
          : {
            order: (_c: string, o: { ascending: boolean }) => ({
              limit: () =>
                Promise.resolve({
                  // an ascending read returns the OLDEST row; a flipped one the newest
                  data: first ? [{ scheduled_date: o.ascending ? first : day(0) }] : [],
                  error: null,
                }),
            }),
          },
      }),
    }),
  } as unknown as SupabaseClient;
}

Deno.test("completionRateOverWindow: opt-in counts the blank gap, default keeps the old rate", async () => {
  // 4-week window; 4 completed days a fortnight ago, nothing since.
  const rows = [14, 13, 12, 11].map((d) => ({
    status: "completed",
    scheduled_date: day(d),
  }));
  rows.push({ status: "planned", scheduled_date: day(-3) }); // the next phase
  const client = fakeClient(rows, day(14));
  assertEquals(await completionRateOverWindow(client, "u", 4), 4 / 5);
  // first row 14 days ago, a future row after the gap: days 14..1 ago = 14,
  // 4 present -> 10 blank; scheduled = 4 done + 1 planned + 10 blank = 15.
  const withBlank = await completionRateOverWindow(client, "u", 4, true);
  assertEquals(Math.abs(withBlank - 4 / 15) < 1e-9, true);
});

Deno.test("completionRateOverWindow: kill switch env restores the old rate", async () => {
  Deno.env.set("DISABLE_LAPSE_GAP_POLICY", "true");
  try {
    const rows = [{ status: "completed", scheduled_date: day(14) }];
    assertEquals(
      await completionRateOverWindow(fakeClient(rows, day(14)), "u", 4, true),
      1.0,
    );
  } finally {
    Deno.env.delete("DISABLE_LAPSE_GAP_POLICY");
  }
});

Deno.test("evaluate-rank-promotions opts in to blank days (call-site pin, presence only)", async () => {
  const src = await Deno.readTextFile(
    new URL("../evaluate-rank-promotions/index.ts", import.meta.url),
  );
  assertEquals(
    src.includes("completionRateOverWindow(supabase, userId, windowWeeks, true)"),
    true,
  );
});
