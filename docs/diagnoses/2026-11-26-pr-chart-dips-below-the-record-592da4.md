---
bug_id: 592da4
date: 2026-11-26
batch: pr-step-chart
status: fixed
tier: full
blast_radius: feature
symptom: |
  Founder, web app after PR #345 (2026-11-26): the personal-record chart goes up AND down. Bench 40 kg in January, 35 kg in February, 42.5 kg in March draws 40 -> 35 -> 42.5 on the Home PR tile, the see-all row and the trend sheet, although the PR was 40 all through February. A PR only rises or holds, so its chart must be a step; the lifted weight, which does fluctuate, belongs on a second line in the full-screen sheet.
concept: exercise_pr_series
sot_registry_entry: exercise_pr_series
writers:
  - { file: lib/features/train/services/exercise_pr_series.dart, method_or_widget: "buildExercisePrSeries: one point per workout day, the day's best set (unchanged, correct)", line: 180 }
readers:
  - { file: lib/features/home/widgets/pr_snapshot.dart, method_or_widget: "prSparkValues: plotted each day's best set as the PR spark (tile :233/:269, see-all row :305/:354)", line: 208 }
  - { file: lib/features/home/widgets/pr_trend_sheet.dart, method_or_widget: "_PrTrendSheetState._chart: one line of each day's best set (spots :251)", line: 235 }
  - { file: lib/features/home/widgets/pr_trend_sheet.dart, method_or_widget: "prJourneyLine: 'now' = the last day's lift (:46)", line: 41 }
hive_key_prefix: "exlog_ (read only, unchanged)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/exercise_pr_series_writer_to_reader_test.dart
ist_handling: ["the PR step is carried on to istTodayStr(); series days are the existing IST day keys"]
provider_invalidations: ["none (display-only change)"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged: the series still comes from exercisePrSeriesProvider, which watches the auth token."
forbidden_patterns_checked:
  - { pattern: "a change to the stored series or to buildExercisePrSeries (the lifted line needs the per-day values)", absent: true }
  - { pattern: "a change to WardSpark's path when step is off (pinned by a hand-computed vertex test)", absent: true }
  - { pattern: "fl_chart's default step direction (middle, rises half-way before the PR day)", absent: true }
proposed_fix: |
  Display only, plan docs/plans/pr-step-chart.md. New pure prRunningBest (running max over the points). The tile and see-all sparks draw the running best as a step (new optional WardSpark.step, off by default, so the four other spark callers draw the same path). The sheet draws two bars: the PR as an fl_chart step line, stepDirectionForward so it rises ON the PR day (running best over the FULL series by date, carried on to today, with the PR marker) and the best set each day as a thin muted line, a tooltip with both values and a legend. The journey line's "now" is the PR itself (pr.bestValue). On a range chip the PR step's carry to today is capped at the chip's span (prTailX).
regression_test_planned: |
  test/contracts/exercise_pr_series_writer_to_reader_test.dart B11: 40 / 35 / 42.5 logged through WorkoutWriteService.logExercise; the series keeps the 35 dip, prRunningBest and prSparkValues give 40, 40, 42.5, ending at the PR. test/features/home/pr_trend_widgets_test.dart: running best, spark, journey "now", the sheet's two bars (bar 0 stepped), the legend, a PR set before the selected range holding inside it.
mutation_proof: |
  Seventeen mutants, each applied (count confirmed), run, reverted by a script; no compile errors. Against both test files under TZ=Asia/Kolkata: M1 running max -> per-day value 8 red; M2 isStepLineChart false 1; M3 prSparkValues back to p.value 2; M4 journey "now" = last lift 1; M5 PR spots from the shown window 1; M6 step direction middle 1; M7 tile spark step false 1; M8 spark corner removed 3; M9 no carry to today 1; M10 tooltip on the PR bar 1; M11 see-all spark step false 1. Against the widget file: M12 painter ignores step 1; M13 shouldRepaint ignores step 1; M14 local (non-UTC) day maths 1 under TZ=America/New_York; M15 PR dot on every spot 1; M16 legend label changed 1; M17 touch marker on the PR bar 1. After the B-pass, against both files: M9b no carry to today 2; M18 y range without the PR line 1; M19 touch-marker wiring removed 1; M20 today in UTC instead of IST 1; M21 tail not capped on a range chip 2; M22 journey "now" = running best (replaces M4) 1; M23 legend colour swapped 1; M24 lifted dots always shown 1. Two first-draft mutants (M9b, M21) did not compile and were rewritten before counting.
impact_analysis: |
  Two Home widget files. One extra pass over an exercise's points per sheet build and per spark. No write, no sync, no server reader (grep of supabase/ for the readers: none).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "pr_snapshot.dart prSparkValues; pr_trend_sheet.dart prRunningBest, _chart, prJourneyLine. Whole-project analyze: no warning or error." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "B11 writes three exlog rows through logExercise into the real workoutBox and reads the series and the running best back." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "Client display-only change; grep of supabase/functions for the readers returns nothing." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client display-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
recurrence: "Not a recurrence. No prior diagnose on the PR chart; cb1ab1 (the PR value summing sets) is a different defect. Related class: debugging 2.19 (a highest-ever concept rendered from a current-state value), here at the display layer with nothing stored. Cause: a spec gap in docs/plans/pr-strength-charts.md:13 ('the best value per workout day')."
related_bugs: [cb1ab1, 3a7b9f]
---

# 592da4 - the PR chart dips below the record

## What happened
PR #345 drew the best set of each workout day and labelled it the personal record, so a lighter session pulled the "PR" line down.

## The fix
The PR is drawn as its running best (a step in the sheet, a never-dipping spark on the tiles); the lifted weight is a second, muted line in the sheet. Data untouched.

## Not established
- Not yet seen on a device or the web app; founder check after the merge.
- The tile spark is index-spaced (points evenly spread, not by date), so gaps between logs are not to scale there; the sheet is to scale.
- On All, the sheet's PR step runs on to today: a user whose last log is long ago sees a long flat line. On a range chip the tail is capped at the chip's span.
- The old contract tests B1-B8 (and B11) assume an IST host: under TZ=Etc/GMT+12 main's own copy fails 9; CI pins IST. Not changed here.
