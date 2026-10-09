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
