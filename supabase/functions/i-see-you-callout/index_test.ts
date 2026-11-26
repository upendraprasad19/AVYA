// i-see-you-callout calls serve() at module scope, so the handler cannot be
// imported; the shared rule is behaviourally tested in _shared/recent_prs_test.ts.
// These pins keep the wiring (L1b B1/B2/B3) from regressing.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const pr = src.slice(src.indexOf("async function checkPRAfterBadSleep"), src.indexOf("async function checkPreDawnWorkout"));

Deno.test("PR-after-bad-sleep reads ALL last-24h rows (no is_pr filter) and routes through recentLivePrs", () => {
  assert(!pr.includes('.eq("is_pr", true)'), "is_pr must not be filtered server-side (dedupe first)");
  assert(pr.includes("recentLivePrs("), "must dedupe + recency-day via recentLivePrs");
  assert(pr.includes('.is("deleted_at", null)'));
  assert(pr.includes(".limit(1000)"));
});

Deno.test("PR-after-bad-sleep never renders `weight × N reps` from the cumulative field", () => {
  assertEquals(pr.includes('.join(" × ")'), false);
  assertEquals(pr.includes("×"), false, "no weight × reps rendering at all");
  assertEquals(pr.includes("${pr.reps} reps"), false, "cumulative reps are only ever 'total reps'");
  assert(pr.includes("total reps"));
});

// PRESENCE-ONLY (coach workout parity 2, OI-492): checkFirstInStreakSaturday is not importable and
// its per-user flow has no handler seam, so streak_gate_test.ts cannot see the call site. The
// Saturday gate counts DISTINCT IST dates through readDeepStreak, never a row count on logged_at.
Deno.test("Saturday gate calls readDeepStreak and keeps no row-count gate on logged_at", () => {
  const start = src.indexOf("async function checkFirstInStreakSaturday(");
  assert(start >= 0, "checkFirstInStreakSaturday must exist");
  const rest = src.slice(start + 1);
  const m = /\n(?:async )?function /.exec(rest);
  const slice = m ? src.slice(start, start + 1 + m.index) : src.slice(start);
  assert(slice.includes("readDeepStreak(supabase, userId"), "must gate on readDeepStreak(supabase, userId");
  assertEquals(slice.includes("since28d"), false, "the 28-day ISO-timestamp window is retired");
  const headCountOnLoggedAt = /head:\s*true[\s\S]{0,200}?\.gte\("logged_at", since/.test(slice);
  assertEquals(headCountOnLoggedAt, false, "no head: true row count gated on logged_at");
});
