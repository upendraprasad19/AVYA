---
bug_id: b2f7c4
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  `future-prediction`'s new real-trend-math path (this same batch, Task 10,
  `trend.ts`) computed `predictWeight`/`predictLift` via unbounded
  least-squares linear regression with no sanity clamp on the output. A
  plausible, real-world-shaped short history extrapolates to a physically
  impossible 90-day forecast: 5 weigh-ins dipping 70->65kg over 14 days
  (a normal bad-week/illness dip) forecasts **32.2kg**; 2 PRs declining
  100->80kg over 8 days forecasts **-145kg**, a negative lift weight. This
  is a regression from BOTH things this path replaced: the removed Gemini
  prompt explicitly instructed "be realistic and conservative," and the
  still-present per-field static-formula fallback
  (`weightFallback = current + (target-current)*0.3`) can never leave the
  current<->target range by construction. The new regression path had no
  equivalent guard in either direction. Caught by the self-triggered
  `/code-review` B-pass (CLAUDE.md §4.3) required before this branch's
  merge, run on a non-Opus model per founder instruction
  (`docs/reviews/247d945d1ba0-review.md`, Finding 2). Independently
  re-verified before acting: ran the real in-tree `predictWeight`/
  `predictLift` against the review's exact fixtures via
  `deno test --no-check --allow-all --node-modules-dir=none`, reproducing
  32.2kg and -145kg exactly before writing any fix.
concept: future_prediction_streak_forecast
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covers this concept, and none
  is being added: predictWeight/predictLift are pure, same-process
  functions (no cross-layer writer/reader pair the registry exists to
  pin) — same reasoning as the two prior diagnose-docs on this same
  function in this same batch (9c3d7a, e5c9b2).
writers:
  - { file: supabase/functions/future-prediction/trend.ts, method_or_widget: "predictWeight — clamps the regression forecast to [lastWeight*0.7, lastWeight*1.3] before rounding", line: 44 }
  - { file: supabase/functions/future-prediction/trend.ts, method_or_widget: "predictLift — clamps the regression forecast to [0, lastLift*2.0] before rounding", line: 57 }
readers:
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: "generateLocalPrediction — consumes predictWeight/predictLift's return values directly into predicted_weight_kg / predicted_lifts.{squat,bench,deadlift}_kg", line: 128 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — server-side Edge Function only. The clamped values are written into user_daily_snapshots.snapshot_json.future_prediction (cloud-only); no Hive field changes."
sync_methods: []
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: supabase/functions/future-prediction/index_test.ts
ist_handling:
  - "Not applicable — trend.ts's clamp is a pure numeric bound, no date-key or clock involvement beyond the pre-existing DAY_MS span computation this fix does not touch."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — predictWeight/predictLift are pure functions over rows already scoped to the single requesting user by their caller; this fix changes only the numeric bound on their return value."
forbidden_patterns_checked:
  - { pattern: "return forecast === null ? fallback : Math.round(forecast * 10) / 10; (the pre-fix unclamped predictWeight return)", absent: true }
  - { pattern: "return forecast === null ? fallback : Math.round(forecast); (the pre-fix unclamped predictLift return)", absent: true }
proposed_fix: |
  Clamp both forecasts to the widest swing from the LAST OBSERVED value in
  the input rows (not the fallback, and not a hardcoded absolute number) —
  mirrors the review's own suggested-fix shape. predictWeight clamps to
  +/-30% of the last observed weight (a 30% body-weight swing in 90 days
  is already an extreme upper bound on physiological plausibility, chosen
  because no existing DB CHECK constraint or codebase convention defines
  a "realistic weight_kg" bound to reuse — confirmed by grepping
  supabase/migrations/*.sql for weight_kg CHECK constraints: none exist,
  only reps/set_number/duration bounds on workout_log_exercises/sets).
  predictLift clamps to [0, 2x last observed lift] — floor of 0 eliminates
  the negative-weight defect directly; ceiling of 2x is generous enough
  not to suppress legitimate large novice gains while still bounding a
  runaway extrapolation. Neither bound derives from a magic constant
  pulled from nowhere — both are expressed as a factor of the caller's own
  last-observed data point, so the clamp scales correctly regardless of
  the user's starting weight/lift.
regression_test_planned:
  - "supabase/functions/future-prediction/index_test.ts — 2 new tests using the review's exact fixtures: predictWeight's 70->65kg/14-day dip now returns 45.5 (was 32.2 unclamped); predictLift's 100->80kg/8-day decline now returns 0, never negative (was -145 unclamped)."
impact_analysis: |
  Scope: future-prediction (platform-tier). This fix changes ONLY the
  numeric bound on predictWeight/predictLift's return value when the
  regression path is taken (>=5 weight rows spanning >=14 days, or >=2
  lift rows spanning >=7 days) AND the unclamped forecast would have
  exceeded the bound — every other case (insufficient history, forecast
  already within bounds) is byte-identical to before, confirmed by the
  pre-existing tests ("sufficient history uses the regression" /
  "predictLift: 2 PRs...uses the regression") passing unmodified against
  the clamped code. Note (B-pass Finding 1, same review round, separately
  tracked): future-prediction currently has no confirmed live caller in
  the shipped app (no client call site, no cron schedule, not in
  CRON_REGISTRY.md) — this fix hardens shipped code regardless of current
  reachability, since a review lens found it and CLAUDE.md §4.2 requires
  fixing every surfaced bug in the batch, and any future wiring-up of this
  path would otherwise surface the defect immediately.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Function only; no lib/ files touched by this fix." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "supabase/functions/future-prediction/trend.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3. deno check --node-modules-dir=none passed clean; deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/ passed 15/15." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "user_daily_snapshots.snapshot_json.future_prediction.predicted_weight_kg/predicted_lifts's type (number) is unchanged — only the range of values the regression path can produce is now bounded, not the field's shape." }
---

## Summary

The self-triggered `/code-review` B-pass required before this branch's merge
(CLAUDE.md §4.3, dispatched on a non-Opus model per standing founder
instruction) found that this batch's new `trend.ts` regression math has no
sanity bounds, and demonstrated it with two fixtures that extrapolate to a
physically impossible 90-day forecast. Independently re-verified by running
the real in-tree functions against the exact fixtures before writing any
fix, reproducing both cited values (32.2kg, -145kg) precisely.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "unbounded", "forecast", "realistic".
This function's concept (`future_prediction_streak_forecast`) already has 2
prior bugs in this same batch (`9c3d7a`, `e5c9b2`) — both about
`predictStreakWeeks`'s adherence-rate INPUT being miscomputed, not about
`predictWeight`/`predictLift`'s OUTPUT being unbounded. This is the 3rd
distinct defect in the same concept within one batch, but a different root
cause each time (input miscollapse x2, now unbounded output) — not a
recurrence of either prior bug. The broader "unbounded" class in the index
(`unbounded_postgrest_reads_in_cron`, workout rep-count CHECK constraints)
is about row-count/input bounds, not a computed-value output bound — related
in spirit (an external/derived number needs a sanity ceiling) but a
different mechanism.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `supabase/functions/future-prediction/trend.ts`'s
`predictWeight`/`predictLift` (this same batch, Task 10) — both return
`linearRegressionForecast`'s raw output (rounded) with no clamp, unlike the
static-formula fallback they replace (inherently bounded by construction)
and unlike the removed Gemini prompt (explicitly instructed to stay
realistic).

**Reader:** `future-prediction/index.ts`'s `generateLocalPrediction`
(`:128` area) consumes both return values directly into
`predicted_weight_kg` / `predicted_lifts.{squat,bench,deadlift}_kg` with no
downstream sanity check of its own — whatever `trend.ts` returns is written
verbatim into `user_daily_snapshots.snapshot_json.future_prediction`.

## Fix

Clamped both forecasts to a factor of the last OBSERVED value in the input
rows: `predictWeight` to `[lastWeight*0.7, lastWeight*1.3]`, `predictLift`
to `[0, lastLift*2.0]`. Both factors are named constants
(`WEIGHT_MIN_FACTOR`/`WEIGHT_MAX_FACTOR`/`LIFT_MAX_FACTOR`) rather than
inline magic numbers. No existing DB CHECK constraint defines a "realistic
weight_kg" bound to reuse (confirmed via
`grep -n "weight_kg.*CHECK\|CHECK.*weight_kg" supabase/migrations/*.sql` —
only rep/set-number/duration bounds exist on `workout_log_exercises`/
`workout_log_sets`), so the bound is expressed relative to the caller's own
data rather than an invented absolute number.

## Verification

`deno test --no-check --allow-all --node-modules-dir=none
supabase/functions/future-prediction/` — 15/15 passed (13 pre-existing +
2 new). `deno check --node-modules-dir=none
supabase/functions/future-prediction/index.ts` — clean.

**Mutated and run** (rule 21): reverted both clamps back to the raw
`Math.round(forecast * 10) / 10` / `Math.round(forecast)` returns —
reddened exactly 2 of 15 tests (the 2 new ones), with the failure output
showing the mutation reproduces the review's exact unclamped values
(`-145` actual vs `0` expected for the lift case). The other 13 stayed
green, including the two PRE-EXISTING "uses the regression, not the
fallback" tests, confirming the clamp does not disturb the in-bounds
case. Reverted the mutation; re-ran green (15/15). `deno check` on the
mutated (temporarily unclamped) file also stayed clean throughout — the
mutation reddened tests via a real assertion failure, not a compile
error (CLAUDE.md §4.4 rule 21's compile-error trap).

## Related

Finding 2 of the B-pass review `docs/reviews/247d945d1ba0-review.md`
(dispatched per CLAUDE.md §4.3 before this branch's merge). Finding 1 of
the same review (future-prediction's live-caller reachability) is a
separate, non-code product-scope question, tracked and surfaced to the
founder independently rather than folded into this fix. Sibling fixes in
the same batch on the same function: `9c3d7a`, `e5c9b2` (both
`predicted_streak_weeks` input-collapse bugs, distinct root cause from
this one).
