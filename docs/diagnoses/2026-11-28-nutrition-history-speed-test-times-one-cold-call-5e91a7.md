---
bug_id: 5e91a7
date: 2026-11-28
batch: oi348-landing3c
status: fixed
tier: m_fix
blast_radius: feature
symptom: |
  On the founder's Windows machine the pre-commit regression catalog failed on "730 days of four meals build well inside a frame budget" in test/contracts/nutrition_history_writer_to_reader_test.dart: 723, 530 and 667 ms against a 400 ms bound, in three merge-commit walks. The same test passes run alone. It is on origin/main, whose CI run at d2d92832 was green.
concept: nutrition_history_build_speed_bound
sot_registry_entry: none
writers:
  - { file: lib/features/nutrition/providers/nutrition_history_provider.dart, method_or_widget: "buildNutritionHistoryData (a pure builder with no cache; unchanged by this fix)", line: 65 }
readers:
  - { file: test/contracts/nutrition_history_writer_to_reader_test.dart, method_or_widget: "the speed test timed one first call", line: 569 }
hive_key_prefix: none
hive_key_formula: "not applicable: no stored value changes meaning"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/nutrition_history_writer_to_reader_test.dart
ist_handling:
  - { file: lib/features/nutrition/providers/nutrition_history_provider.dart, line: 65, fn: buildNutritionHistoryData }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: no user data."
forbidden_patterns_checked:
  - { pattern: "a single timed first call as the speed measurement", absent: true }
  - { pattern: "a hook skip as the way round the failing walk", absent: true }
proposed_fix: |
  Test only. One untimed call, then five timed calls; the fastest must be under 200 ms (was: one first call under 400 ms). Founder approved 2026-11-28 ("OK change").
regression_test_planned: |
  The rewritten test itself, in test/contracts/nutrition_history_writer_to_reader_test.dart.
mutation_proof: |
  Run on Windows 2026-11-28, each mutant confirmed applied (grep count 1), none a compile error, the provider restored byte for byte (cmp). A 250 ms busy wait on every call: red (best 267 ms). A 150 ms busy wait: green (best 167 ms), which is the stated limit of the bound and not a protection.
impact_analysis: |
  No lib/ change. Measured with a temporary print, since removed. Alone, three runs of the new test: 36, 55, 42 ms. The bound now catches less: from warm timings of 13 to 55 ms the builder must get roughly 4 to 15 times slower to fail. It no longer measures the first call at all. Under 32 busy-loop processes on 16 cores, one run that was fully under load FAILED: best of five 549 ms. So the change lowers the chance of a load failure and does not remove it. Other loaded readings (35 to 55 ms) are not counted: the load ran for a fixed time and may have ended before them. One early loaded run failed at 00:00 with its output filtered away; the cause is not known and it did not reproduce in later runs that kept their output.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Test file only; the builder it times is unchanged (read at nutrition_history_provider.dart:65, no cache)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive contract changed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No client/server contract touched." }
recurrence: "Not a recurrence of a filed bug: git grep of docs/diagnoses found no earlier entry for this test. The plan-review note docs/plan-reviews/nutrition-history.md records the 400 ms bound as set for the 4-core VPS."
related_bugs: [d0b7e4]
---

# 5e91a7 - a speed test that timed one first call

## What happened

The pre-commit hook runs the recent regression tests in one `flutter test` call on a merge commit. This test
timed a single first call, so its number carried both Dart's warm-up and whatever the other test files were doing
at that moment. It failed in three walks on a tree where it passes alone.

## The fix

Warm up once, then take the fastest of five and require under 200 ms. See impact_analysis for what this catches
less of, and for the loaded run that still failed.
