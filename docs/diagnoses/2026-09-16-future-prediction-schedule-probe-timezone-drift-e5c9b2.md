---
bug_id: e5c9b2
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  This batch's own prior fix (`593094e3`, diagnose `9c3d7a`) added a
  schedule-row existence probe to `future-prediction/index.ts` meant to
  mirror `completionRateOverWindow`'s notion of "the last 4 weeks"
  exactly — but the probe computed its cutoff via `istDateStr(new
  Date(Date.now() - 4*7*24*3600*1000))` (IST-shifted, +5:30) while
  `completionRateOverWindow` (`_shared/rank_engine.ts`) computed its own
  cutoff via raw `new Date(...).toISOString().split('T')[0]` (no IST
  shift, UTC calendar date) for the identical instant. Both cutoffs
  derive from the same `now - 28 days` instant but extract the calendar
  date in different timezones, so whenever that instant's UTC
  time-of-day falls in [18:30, 24:00) UTC — IST has already rolled to
  the next calendar day — the probe's cutoff is one day later/narrower
  than `completionRateOverWindow`'s. A user whose only non-rest
  scheduled_workouts row in the 4-week window falls in that ~5.5-hour
  daily sliver would have the probe report `hasScheduleHistory: false`
  while `completionRateOverWindow` computes a real, non-sentinel
  adherence rate from that same row — so 9c3d7a's own guard
  (`!hasScheduleHistory || adherenceRate < 0 ? null : adherenceRate`)
  would discard a real signal and substitute the flat fallback: a
  narrower recurrence of the exact bug class 9c3d7a closed. Caught by an
  independent context-blind plan-review Round 2 (CLAUDE.md §4.12)
  dispatched specifically to check whether Round 1's own fix introduced
  a new defect — which it had. Independently re-verified against both
  files' live content (not trusted from the review's prose) before
  acting.
concept: future_prediction_streak_forecast
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covers this concept (same
  reasoning as 9c3d7a — a same-process synchronous computation, not a
  cross-layer writer/reader pair the registry exists to pin). Not adding
  one here either.
writers:
  - { file: supabase/functions/_shared/rank_engine.ts, method_or_widget: "windowSinceDateUtc — new exported helper, the single source of truth for the raw-UTC window cutoff both completionRateOverWindow and future-prediction's schedule probe now share", line: 133 }
readers:
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: "generateLocalPrediction — streakWindowSince, now computed via windowSinceDateUtc(4) instead of istDateStr(), guaranteeing agreement with completionRateOverWindow's own internal cutoff", line: 103 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — server-side Edge Function only. See 9c3d7a for the downstream cloud-write this feeds (user_daily_snapshots.snapshot_json.future_prediction.predicted_streak_weeks), unchanged by this fix."
sync_methods: []
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: supabase/functions/future-prediction/index_test.ts
ist_handling:
  - "This IS the IST-handling bug: the probe previously used istDateStr() where it needed to match completionRateOverWindow's raw-UTC convention instead. Fixed by extracting a single shared windowSinceDateUtc(windowWeeks) helper into _shared/rank_engine.ts that both completionRateOverWindow and future-prediction's probe now call, eliminating the possibility of the two computing the cutoff independently and disagreeing."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — unchanged from 9c3d7a; the probe is scoped to the single requesting user's own user_id."
forbidden_patterns_checked:
  - { pattern: "istDateStr(new Date(Date.now() - 4 \\* 7 \\* 24 \\* 3600 \\* 1000)) (the mismatched IST-shifted cutoff this fix removes from the probe)", absent: true }
proposed_fix: |
  Extract the raw-UTC window-cutoff calculation `completionRateOverWindow`
  already computed inline into a new exported pure function,
  `windowSinceDateUtc(windowWeeks): string`, in `_shared/rank_engine.ts`.
  `completionRateOverWindow` itself now calls this helper instead of
  inlining the calculation (a pure refactor — its external return
  contract, tested by test/edge_functions and
  unit_c_read_hardening_test.ts, is unchanged). future-prediction's
  schedule-existence probe now calls the SAME helper instead of
  `istDateStr()`, so the two window cutoffs can never independently
  drift again — they share one source of truth rather than two call
  sites that happen to compute the same thing today.
regression_test_planned:
  - "supabase/functions/_shared/rank_engine_test.ts — 2 new tests: windowSinceDateUtc returns a correctly-formatted raw-UTC YYYY-MM-DD cutoff, and matches the exact expression completionRateOverWindow used to inline."
  - "supabase/functions/future-prediction/index_test.ts — 1 new source-shape test asserting the probe calls windowSinceDateUtc(4), not istDateStr(), for its cutoff."
impact_analysis: |
  Scope: future-prediction is client-invoked, platform-tier. This fix
  touches _shared/rank_engine.ts (a shared helper also consumed by
  evaluate-rank-promotions) but ONLY by extracting an existing inline
  expression into a named function with the identical return value for
  every input — completionRateOverWindow's own behavior and return
  contract (0.0 for zero-scheduled, -1.0 for a query error, real rate
  otherwise) is byte-identical before and after, confirmed by
  unit_c_read_hardening_test.ts staying green unmodified (3/3, incl. the
  -1.0-sentinel and 0.0-zero-scheduled cases) and by all of
  evaluate-rank-promotions' own tests staying green. The actual
  behavior change is scoped entirely to future-prediction's own probe,
  narrowing (fixing) an edge case 9c3d7a's own fix introduced rather
  than widening any existing risk.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Functions only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "supabase/functions/_shared/rank_engine.ts and supabase/functions/future-prediction/index.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3. deno check --node-modules-dir=none passed clean on both; deno test --no-check --allow-all --node-modules-dir=none across supabase/functions/_shared/rank_engine_test.ts (11), supabase/functions/future-prediction/ (13), and supabase/functions/_shared/tools/__tests__/unit_c_read_hardening_test.ts (5) all passed — 29/29." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "predicted_streak_weeks's type/range is unchanged — only the correctness of which value gets computed in one narrow boundary case changes." }
---

## Summary

A Round 2 CLAUDE.md §4.12 context-blind plan-review pass — dispatched
explicitly to check whether Round 1's own P1 fix (`9c3d7a`) introduced a
new defect, per §4.12 point 1's "the corrections themselves can introduce
new defects" — found exactly that: the fix's own schedule-existence probe
used a different date-cutoff timezone convention than the shared helper
it was written to agree with. Independently re-verified by reading both
`future-prediction/index.ts`'s probe and `_shared/rank_engine.ts`'s
`completionRateOverWindow` fresh, confirming the IST-shift-vs-raw-UTC
mismatch is real before acting on it.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "windowSinceDateUtc", "IST",
"UTC boundary" in this concept area. This is a direct recurrence of the
SAME general defect class as `9c3d7a` (an overloaded/ambiguous
computation collapsing two states that should be distinguished) — but a
different specific mechanism (timezone-cutoff mismatch between two
callers, not a return-value sentinel collapse). Also matches this
repo's general `feedback_ist_sweep_gap.md` class ("sweeps miss sites on
the first pass") in spirit: 9c3d7a's own fix, written specifically to
be IST-consistent by using `istDateStr()`, was IST-consistent with the
WRONG reference point — the file's own `since90` pattern (a
single-query, single-file convention with nothing to disagree with) —
rather than with the cross-function convention it actually needed to
match.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer (mismatched pair, pre-fix):** `future-prediction/index.ts`'s
`streakWindowSince` (then `istDateStr(new Date(Date.now() -
4*7*24*3600*1000))`, IST-shifted) vs. `_shared/rank_engine.ts`'s
`completionRateOverWindow` internal `sinceIso` (`new
Date(Date.now() - windowWeeks*7*24*3600*1000).toISOString()`, raw UTC,
unchanged prior to this fix) — two independent computations of "the
same" cutoff that silently disagreed near the IST/UTC calendar
boundary.

**Reader:** `future-prediction/index.ts`'s `predictedStreak` guard
(`!hasScheduleHistory || adherenceRate < 0 ? null : adherenceRate`) —
consumes both values as if they described the same window, which they
did not for roughly 5.5 hours of every UTC day.

## Fix

Extracted the raw-UTC cutoff calculation into a single exported
function, `windowSinceDateUtc(windowWeeks)`, in `_shared/rank_engine.ts`.
`completionRateOverWindow` now calls it instead of inlining the
expression (pure refactor, zero behavior change — proven by the
existing `unit_c_read_hardening_test.ts` suite staying green unmodified).
`future-prediction`'s probe now calls the same function instead of
`istDateStr()`, so the two window cutoffs are structurally guaranteed to
agree — not just today, but for any future edit to either call site.

## Verification

`deno test --no-check --allow-all --node-modules-dir=none` across
`supabase/functions/_shared/rank_engine_test.ts` (11 tests, incl. 2 new),
`supabase/functions/future-prediction/` (13 tests, incl. 1 new), and
`supabase/functions/_shared/tools/__tests__/unit_c_read_hardening_test.ts`
(5 tests, unmodified) — 29/29 passed. `deno check --node-modules-dir=none`
on both changed files — clean.

**Mutated and run** (rule 21), two separate mutations:
1. Reverted `future-prediction`'s probe from `windowSinceDateUtc(4)` back
   to `istDateStr(new Date())` — reddened exactly 1 of 13
   `future-prediction` tests (the new source-shape test asserting
   `windowSinceDateUtc(4)` is used), the other 12 stayed green. Reverted;
   re-ran green (13/13).
2. Added an off-by-one-day error inside `windowSinceDateUtc` itself
   (`+ 86400000`) — reddened exactly 2 of 11 `rank_engine_test.ts` tests
   (both new `windowSinceDateUtc` tests), while `completionRateOverWindow`'s
   own pre-existing behavioral tests in `unit_c_read_hardening_test.ts`
   (3 of them, incl. the -1.0-sentinel and 0.0-zero-scheduled cases)
   stayed green — confirming the refactor correctly preserved
   `completionRateOverWindow`'s external behavior while the new tests
   correctly detect a defect in the shared helper itself. Reverted; re-ran
   green (11/11 + 5/5).

## Related

Direct follow-on to `9c3d7a` (future-prediction's streak-weeks
zero-schedule collapse) — this is a defect in that fix's own
implementation, found by the very next review round per CLAUDE.md
§4.12's explicit purpose ("the corrections themselves can introduce new
defects"). Also related: `a1f7d3` (proactive-coach-promotion's
model_used mislabel), found by the same Round 2 review pass.
