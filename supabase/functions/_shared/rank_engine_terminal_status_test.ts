// e8f4a3 B-pass P1 — completionRateOverWindow must skip TERMINAL/PAUSED
// schedule rows exactly like the client does.
//
// Writer: tool_dispatcher._executeRescheduleWeek persists terminal
//         `moved`/`dropped` rows (and pauseRange persists `paused`) to cloud
//         `scheduled_workouts` — pre-batch moved/dropped were raw-deleted and
//         never reached cloud, so the server denominator never saw them.
// Reader: `WorkoutScheduleReadService.invisibleScheduleStatuses`
//         (lib/core/services/workout_schedule_read_service.dart:889) = the
//         client's canonical {paused, moved, dropped} set, skipped by
//         WorkoutRepository.completionRateOverWindow (the rank UI's rate).
//
// Without the server-side mirror, every reschedule move/drop permanently
// deflates the SERVER-side rate consumed by the evaluate-rank-promotions cron
// (`completionRateMinimum` promotion gate) while the client rank UI excludes
// them — client display and server promotion gate diverge.
//
// Run: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/rank_engine_terminal_status_test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { completionRateOverWindow } from "./rank_engine.ts";

/** Minimal query-chain fake: completionRateOverWindow issues exactly
 *  `.from('scheduled_workouts').select('status, scheduled_date').eq('user_id', uid).gte('scheduled_date', since)`. */
function fakeClient(
  rows: Array<{ status: string; scheduled_date: string }>,
): SupabaseClient {
  return {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          gte: () => Promise.resolve({ data: rows, error: null }),
        }),
      }),
    }),
  } as unknown as SupabaseClient;
}

Deno.test(
  "completionRateOverWindow — paused/moved/dropped rows are excluded from BOTH numerator and denominator (client invisibleScheduleStatuses parity)",
  async () => {
    const rows = [
      { status: "planned", scheduled_date: "2026-08-01" },
      { status: "planned", scheduled_date: "2026-08-02" },
      { status: "completed", scheduled_date: "2026-08-03" },
      { status: "completed", scheduled_date: "2026-08-04" },
      { status: "completed", scheduled_date: "2026-08-05" },
      { status: "paused", scheduled_date: "2026-08-06" },
      { status: "moved", scheduled_date: "2026-08-07" },
      { status: "dropped", scheduled_date: "2026-08-08" },
    ];
    const rate = await completionRateOverWindow(fakeClient(rows), "u1", 4);
    // Denominator = planned + completed ONLY (5). The paused/moved/dropped
    // rows must not count as scheduled-not-completed (pre-fix: 3/8 = 0.375),
    // and `rest` was already excluded before this fix.
    assertEquals(rate, 3 / 5);
  },
);

Deno.test(
  "completionRateOverWindow — a terminal row can never inflate the numerator either",
  async () => {
    const rows = [
      { status: "completed", scheduled_date: "2026-08-01" },
      { status: "moved", scheduled_date: "2026-08-02" },
      { status: "dropped", scheduled_date: "2026-08-03" },
      { status: "paused", scheduled_date: "2026-08-04" },
      { status: "rest", scheduled_date: "2026-08-05" },
    ];
    const rate = await completionRateOverWindow(fakeClient(rows), "u1", 4);
    assertEquals(rate, 1.0); // one real scheduled row, completed
  },
);

Deno.test(
  "completionRateOverWindow — an all-terminal window reads 0.0 (empty denominator), not a division artifact",
  async () => {
    const rows = [
      { status: "paused", scheduled_date: "2026-08-01" },
      { status: "moved", scheduled_date: "2026-08-02" },
      { status: "dropped", scheduled_date: "2026-08-03" },
    ];
    const rate = await completionRateOverWindow(fakeClient(rows), "u1", 4);
    assertEquals(rate, 0.0);
  },
);
