---
reviewed_at: 2026-07-08T00:00:00+05:30
staged_against: unit-c-ef-read-hardening (staged diff) vs main c467423
blast_radius: platform
reviewer: fresh-context-blind-plan-agent (adversarial B-pass on the implemented code)
lens_set: [per_site_fix_correct_not_inert, pgrst116_discrimination, minus_one_sentinel, loop_composition, ceremony_copy_no_fabrication, ci_job_soundness, unintended_files]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — Unit C: Edge-Function unchecked-read hardening

A fresh, context-blind reviewer traced all 12 implemented sites, both test changes, the CI job, the
counters, the reader (tool-loop), and the loop composition against the actual staged diff. **Overall
verdict: SHIP-WITH-FIXES — no P0/P1.** The two P2 advisories are folded below.

## Site-by-site (all 12 traced — CORRECT)
Every fix is captured AND acted on per its kind: site 1 (getProgressSummary) captures 5 errors + throws
after the Promise.all; sites 2/4 (batch) throw into the cron outer catch → `logCronEnd("failed")`; site 5
(proactive-coach) throws in `loadUserContext` before Gemini/insert/push; site 3 (`.maybeSingle`) captures +
skips on genuine error, no-row falls through to send; **sites 6/7 (`.single`) PGRST116 discrimination is the
right way round** — `snapErr && snapErr.code !== "PGRST116"` → skip, no-row (PGRST116) → send (paying/at-risk
user preserved); sites 8/9/11 convert each read to capture + `continue` (not an inert wrap) with counters in
scope; **site 10 returns `-1.0` on the error path only, `windowWeeks<=0` stays `0.0`**, and the gate
`rate < min` → highestQualified breaks keeping earned ranks; site 12 (getPromotionStatus) throws on each of 6
reads before its `?? default`. The pre-existing insert-error `continue` (now `:188`) survived; new read-error
skips are added BEFORE the insert block, so a normal iteration still reaches the insert + monotonic update.

## Cross-cutting (verified)
- Counters (`skipped++`/`errors++`) all reference in-scope `let`s; `continue`-only sites match the function's
  existing idiom.
- `tool-loop.ts:270-291` catches a thrown coach-tool per-tool, feeds Gemini `{error:"execution_failed"}`,
  continues the turn — throws narrate honestly, no turn poison.
- **ceremony_text_test.ts — all 3 updated assertions reproduced byte-for-byte from `formatPromotionCeremony`
  (no fabrication).** maxLatencyMs test now asserts 6000 (source = 6000). Correct stale-test fixes.
- Behavioral test is real (`assertRejects` for sites 1/12; `assertEquals(-1.0)`/`0.5`/`0.0` for site 10), not
  a no-op — the fake `failingSb` builder exercises each handler's error-capture path.
- No unintended files staged (10 EFs + 2 tests + 1 CI + 2 docs); no node_modules / deno.lock.
- Gate 40 closure YAML passes (12/12 closed_in_commit, `(uncommitted)` label permitted).

## P2 advisories — DISPOSITION
- **P2-1 (deno-check coverage gap) — FIXED.** The CI `deno check` step named only getProgressSummary +
  rank_engine, omitting getPromotionStatus (the most-edited file, 6 sites). getPromotionStatus carried 2
  pre-existing streak-loop type errors (`sortedDates` inferred `unknown[]` via `sb: any`). Fixed by casting
  `dateLogs` to `Array<{date:string}>` so `.map` yields `string[]`; getPromotionStatus is now type-clean and
  ADDED to the CI `deno check` list. All 3 files `deno check` green.
- **P2-2 (watch first CI run for other red tests) — ADDRESSED.** Deno was installed locally and the FULL
  suite was run: **223 passed / 0 failed** (the 4 pre-existing red tests — maxLatencyMs + 3 ceremony copy —
  are fixed). No other red test remains; the `--no-check` rationale (pre-existing cross-module type debt,
  tracked as a separate task) is sound and does not hide a problem in the new edits.

**Verdict: accepted** — no P0/P1; both P2 advisories folded (getPromotionStatus type-clean + CI-checked; full
Deno suite green locally).
