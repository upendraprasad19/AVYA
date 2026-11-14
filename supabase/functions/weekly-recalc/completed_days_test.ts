import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { completedDayCounts, mergeMonotonicTotal } from "./completed_days.ts";

Deno.test("completedDayCounts: a user with no workout_logs row is absent (wle-only user gets 0 at the call site)", () => {
  const m = completedDayCounts([{ user_id: "other", date: "2026-11-01" }]);
  assertEquals(m.get("wle-only-user") ?? 0, 0);
});

Deno.test("completedDayCounts: two rows on the same date count once, per user", () => {
  const m = completedDayCounts([
    { user_id: "u1", date: "2026-11-01" },
    { user_id: "u1", date: "2026-11-01" },
    { user_id: "u1", date: "2026-11-02" },
    { user_id: "u2", date: "2026-11-01" },
  ]);
  assertEquals(m.get("u1"), 2);
  assertEquals(m.get("u2"), 1);
});

Deno.test("completedDayCounts: NULL and malformed dates are not counted", () => {
  const m = completedDayCounts([
    { user_id: "u1", date: null },
    { user_id: "u1", date: "garbage" },
    { user_id: "u1", date: "2026-11-01" },
  ]);
  assertEquals(m.get("u1"), 1);
});

Deno.test("mergeMonotonicTotal: the counter never decreases", () => {
  assertEquals(mergeMonotonicTotal(3, 10), 10);
  assertEquals(mergeMonotonicTotal(10, 3), 10);
  assertEquals(mergeMonotonicTotal(5, null), 5);
  assertEquals(mergeMonotonicTotal(5, undefined), 5);
  assertEquals(mergeMonotonicTotal(0, 0), 0);
});
