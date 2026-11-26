---
bug_id: 9c3d7a
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  `future-prediction`'s new real-trend-math path (this same batch, Task 10)
  computed `predicted_streak_weeks` by passing `completionRateOverWindow`'s
  return value straight into `predictStreakWeeks`, treating anything
  `>= 0` as a real adherence rate. `completionRateOverWindow` returns
  `0.0` in TWO distinct cases it does not itself distinguish: a genuine
  0%-completion week AND a brand-new user with zero `scheduled_workouts`
  rows in the trailing 4-week window (only a query ERROR gets the
  separate `-1.0` sentinel). `future-prediction`'s most common invocation
  is `trigger === "onboarding"` — exactly the moment a user has no
  schedule history yet — so the spec's intended "fewer than 4 weeks of
  schedule history: fall back to the flat heuristic" behaviour silently
  never fired for that case; `predictStreakWeeks(0.0, streakFallback)`
  computed `0`, and every new user's 90-day forecast card showed
  "0 weeks" instead of the intended flat fallback (8 or 10, by
  `days_per_week`). Caught by an independent context-blind plan-review
  round dispatched per CLAUDE.md §4.12 on this batch's implementation,
  verified against the live file content before acting on it (subagent
  claims are not self-verifying).
concept: future_prediction_streak_forecast
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covers this concept, and none
  is being added: this is a same-process synchronous computation inside
  `generateLocalPrediction` (probe query -> guard -> predictStreakWeeks
  call), not a cross-layer writer/reader pair the registry exists to pin
  — same reasoning as the sibling `proactive-coach-promotion` fix in this
  batch (see `docs/diagnoses/2026-09-16-proactive-coach-promotion-no-fallback-b7c9e2.md`).
writers:
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: "generateLocalPrediction — scheduleProbeRows / hasScheduleHistory guard, distinguishes 'no schedule history' from a real adherence rate before calling predictStreakWeeks", line: 104 }
readers:
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: "generateLocalPrediction — predictedStreak computation, consumes hasScheduleHistory alongside completionRateOverWindow's return value", line: 109 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — server-side Edge Function only. The resulting predicted_streak_weeks is written into user_daily_snapshots.snapshot_json.future_prediction (cloud-only); the client-side prediction card reads it down unmodified by this fix."
sync_methods: []
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: supabase/functions/future-prediction/index_test.ts
ist_handling:
  - "The new schedule-existence probe's window cutoff uses istDateStr(new Date(Date.now() - 4*7*24*3600*1000)), matching the file's existing since90 pattern (line 50) rather than raw UTC date construction — required by scripts/check_local_date_key_drift.dart."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — the new probe query is scoped to the single requesting user's own user_id (the same userId generateLocalPrediction already receives), identical scoping to every other query in this function."
forbidden_patterns_checked:
  - { pattern: "predictStreakWeeks(adherenceRate < 0 ? null : adherenceRate (the pre-fix guard that collapses 'no schedule' into 'real 0% adherence')", absent: true }
proposed_fix: |
  Add a lightweight existence probe (same table, same 4-week window,
  same non-rest exclusion completionRateOverWindow applies internally)
  to compute hasScheduleHistory, and require it alongside the existing
  `adherenceRate < 0` error-sentinel check before trusting
  completionRateOverWindow's return value as a real adherence rate.
  Deliberately does NOT change completionRateOverWindow's own return
  contract (0.0 for "no data" vs -1.0 for "query error") since that
  shared helper (_shared/rank_engine.ts) is also consumed by
  evaluate-rank-promotions, where 0.0-for-zero-scheduled is the correct,
  already-relied-upon behaviour (a user with a genuinely empty schedule
  fails the rank-promotion completion-rate gate, which is the intended
  effect there). The fix belongs at future-prediction's own call site,
  not in the shared helper.
regression_test_planned:
  - "supabase/functions/future-prediction/index_test.ts — strengthened the existing 'generateLocalPrediction falls back to the static formulas when there is no history at all' test (previously asserted only predicted_weight_kg/source/call-count) with a new assertion: predicted_streak_weeks equals the days_per_week=4 streakFallback (10), not 0."
impact_analysis: |
  Scope: future-prediction is client-invoked (not cron-dispatched), fired
  at both the onboarding trigger (every new user, the common case this
  bug affected) and the monthly trigger (an established user, who by
  then almost always has real schedule history — the bug's practical
  blast radius is concentrated at onboarding). Confirmed via direct read
  of _shared/rank_engine.ts:123-182 that completionRateOverWindow's
  0.0-vs--1.0 return contract is exactly as described above (the shared
  helper's own inline comment at :156-164 documents the -1.0 sentinel
  choice explicitly, for the SAME reason cited here: 0.0 is a legitimate
  value a bare `< gate.completionRateMinimum` or `< 0` comparison could
  silently misread). No other field of the prediction response
  (predicted_weight_kg, predicted_lifts, predicted_bf_pct) is affected —
  each already has its own independent per-field fallback gate in
  predictWeight/predictLift (trend.ts), unrelated to this adherence-rate
  code path.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Function only; the client-side prediction card renders whatever predicted_streak_weeks it is given, unmodified by this fix." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "supabase/functions/future-prediction/index.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3. deno check --node-modules-dir=none passed clean; deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/ passed 12/12." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "user_daily_snapshots.snapshot_json.future_prediction.predicted_streak_weeks's type (number) and range (0-13) are unchanged — only which value is computed for the zero-schedule-history case changes, not the field's shape." }
---

## Summary

An independent, context-blind plan-review round (CLAUDE.md §4.12, dispatched
against this batch's `future-prediction` Task 10 implementation, run on a
non-Opus model per founder instruction) flagged that `predicted_streak_weeks`
silently defaults to 0 for a brand-new user instead of falling back to the
flat heuristic the spec calls for. The claim was independently re-verified
against the live file content (not trusted from the review's prose) before
any fix was written, per this repo's standing rule that subagent numeric/
technical claims are unverified until self-confirmed.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "completionRateOverWindow", "sentinel",
"-1.0". One related (not identical) prior bug on the same function:
`d7c3f1` (2026-06-08) — `completionRateOverWindow` selected a
`scheduled_workouts.reason` column that never existed in the cloud schema,
a schema-drift bug, unrelated to this batch's 0.0-vs-error-sentinel
collapse. Not a recurrence of that bug; this is a new, distinct defect
class (the "bad news vs no news" collapse
`memory/feedback_bad_news_vs_no_news.md` documents generally — an external
read has three real states here, "real 0%", "no data", and "query error",
and the return contract only distinguishes two of them).

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `completionRateOverWindow` (`supabase/functions/_shared/rank_engine.ts:123-182`,
unchanged by this fix) returns `0.0` both when `scheduled === 0` (line 181,
no non-rest scheduled_workouts rows in the window) and when there is a real
non-rest schedule with zero completions — it only distinguishes a genuine
query failure via the separate `-1.0` sentinel (line 166).

**Reader:** `future-prediction/index.ts`'s pre-fix `predictedStreak`
computation (`adherenceRate < 0 ? null : adherenceRate`) treated every
non-negative return value, including the "no schedule at all" 0.0, as a
real adherence rate to feed `predictStreakWeeks`.

The gap is the same shape as `feedback_bad_news_vs_no_news.md`'s named
class: an overloaded return value collapsing "no data" into "real, bad
data" at the READER, not a writer/reader field-name drift.

## Fix

Added a schedule-row existence probe at the `future-prediction` call site
(not inside the shared helper — `evaluate-rank-promotions` relies on
`completionRateOverWindow`'s existing 0.0-for-zero-scheduled behaviour and
must not be disturbed) that mirrors the exact non-rest exclusion
`completionRateOverWindow` applies internally, over the same 4-week
window. `predictStreakWeeks` now receives `null` (triggering the flat
fallback) whenever either the probe finds no non-rest scheduled rows, or
`completionRateOverWindow` itself returned the `-1.0` error sentinel.

## Verification

`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
— 12/12 passed. `deno check --node-modules-dir=none supabase/functions/future-prediction/index.ts`
— clean.

**Mutated and run** (rule 21): reverted the guard from
`!hasScheduleHistory || adherenceRate < 0 ? null : adherenceRate` back to
the pre-fix `adherenceRate < 0 ? null : adherenceRate` — reddened exactly
1 of 12 tests (the strengthened "falls back... with no history at all"
test's new `predicted_streak_weeks` assertion, actual `0` vs expected
`10`), the other 11 stayed green. The file still type-checked and ran
(confirmed via a full test run, not a compile failure) — red for the
right reason. Reverted the mutation; re-ran green (12/12).

## Related

Sibling fix in the same batch: `proactive-coach-promotion`
(`docs/diagnoses/2026-09-16-proactive-coach-promotion-no-fallback-b7c9e2.md`)
— the other genuine bug this batch's Gemini-removal work surfaced, also
found and fixed as part of the same `cron-ai-removal` branch. The other 8
functions in this batch (7 cron + `future-prediction`'s Gemini-removal
half, Task 9) are `refactor:`/`feat:` commits — nothing was broken in
them individually.
