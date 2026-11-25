---
bug_id: e5b9d1
date: 2026-11-25
batch: oi348-walk-rest (A22 device walk, AAB +50)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  Weekly Report, Weight Trend card (founder walk 2026-11-25, Upendra's real data, 3M window, 27 weigh-ins): the two date labels at the right end of the x axis were drawn on top of each other ("13/11" and "25/11" interleaved into "1 32/51/11 1"), and the left axis printed "74" twice. The x labels sit every round(n / 5) points (step 5 for 27 points) and the chart library adds one more label at the LAST point; point 25 and point 26 are one slot apart, so the two labels overlap. The left axis has the same shape: the library also labels the axis minimum, 73.5 (lowest weigh-in - 1), which toStringAsFixed(0) printed as "74" beside the real tick at 74. Reproduced exactly by a widget test over the same 27 weigh-ins before the fix (overlapping rectangles; left labels [74, 74, 76, 78, 80]).
concept: weekly_report_weight_chart_axis
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: "weightTrendTitlesData: bottomTitles interval and getTitlesWidget; leftTitles getTitlesWidget", line: 37 }
readers:
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: "_buildLineChart passes titlesData: weightTrendTitlesData(entries) to the LineChart", line: 853 }
hive_key_prefix: none
hive_key_formula: "not applicable: display only; the weigh-ins are read through NutritionRepository.getWeightEntries and nothing is written"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/profile/weight_trend_axis_labels_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: a pure render of the entries the screen already holds."
forbidden_patterns_checked:
  - { pattern: "two axis labels of the Weight Trend card drawn over each other, or the same left number printed twice", absent: true }
proposed_fix: |
  Extract the card's titles into the top-level weightTrendTitlesData (so a test can render the real function; the rules were first moved verbatim and the new test failed on them). Bottom: the label of a step point is dropped when the last point is less than half a step after it (the newest date wins; a last point that lands on a step is untouched). Left: only ticks that are a multiple of the applied interval are drawn (the library's forced minimum and maximum are not), and a tick step under 1 kg prints one decimal so two ticks cannot read the same whole number.
regression_test_planned: |
  test/profile/weight_trend_axis_labels_test.dart: a real LineChart over Upendra's 27 weigh-ins: no two date labels overlap, 25/11 and 29/8 are drawn, the in-between 18/9, 25/9, 1/10, 22/10 stay; the mirror (26 weigh-ins, the last point on a step) draws all six labels; the left labels are distinct and the real ticks 74/76/78/80 stay; a 0.2 kg range (0.5 kg ticks) prints distinct left labels.
mutation_proof: |
  Rule 21, backup/mutate/run/restore (files compared by hash after). Fixed code: 5 of 5 pass. Pre-fix rules (moved verbatim): the overlap test and the distinct-left-labels test FAIL (rectangles 532.5-582.5 and 544-594; labels [74, 74, 76, 78, 80]). MD1 close-to-last rule removed: 1 test RED. MD2 forced-minimum rule removed: 1 RED. MD3 decimals under 1 kg removed: 1 RED (after the narrow fixture was tightened from 0.8 kg to 0.2 kg: the first fixture left MD3 green, so it was not proof). MD4 the newest date dropped: 2 RED.
impact_analysis: |
  Display only, one card. The chart's data, ranges and tooltips are untouched. The home WeightTrendChart (shared/widgets) is a different widget with a date-proportional axis and is not changed. A series whose last point sits on a step still shows every label it showed before.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "weightTrendTitlesData extracted and fixed; weight_trend_axis_labels_test 5/5 green; flutter analyze, the god-screen / hive-first / cqrs / date-key gates pass." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Nothing stored or read differently." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Upendra's 26 weight_logs rows plus the 2026-11-25 79.0 entry read from the cloud on 2026-11-25 are the test fixture (27 points)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Not a recurrence: grepped docs/diagnoses for the axis, labels and bottomTitles; the three weight-chart diagnoses (e1c6a9 lone dot, b3f7a2 All chip, w7r4c3 invalidate race) are about the data and the window, not the labels. The step line dates from 2026-03-31 (git blame), so it is not from the OI-518 callout work."
related_bugs: [e1c6a9, b3f7a2]
---

# e5b9d1 - Weekly Report weight chart: axis labels printed on top of each other

## What happened
The Weight Trend card places an x label every `round(n / 5)` points and the chart library adds a label at the last point. With 27 weigh-ins the step is 5, so the labels at points 25 (13/11) and 26 (25/11) are one slot apart and overlap. The left axis forced a label at the non-integer minimum and printed it rounded beside the real tick (74 twice).

## Fix
`weightTrendTitlesData` drops the step label that sits within half a step of the last point, draws only real ticks on the left, and prints one decimal when the tick step is under 1 kg. Tests render the real function in a real `LineChart`.
