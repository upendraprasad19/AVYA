---
bug_id: e4b7a9
date: 2026-11-26
batch: nutrition-history
status: fixed
tier: full
blast_radius: feature
symptom: |
  CI on PR #346 (run 45646807592, Unit Tests shard 2/4) failed test/contracts/sync_template_before_schedule_order_test.dart "weeklyFullSync Future.wait does NOT contain _syncWorkoutTemplates" (Expected false, Actual true) on a commit that touches no sync file. The same test passed on the previous CI run of the same branch and passes on the VPS.
concept: sync_template_before_schedule_order
sot_registry_entry: none (a test-harness defect; no product writer or reader changes)
writers:
  - { file: test/contracts/_sync_service_source.dart, method_or_widget: "SyncServiceSourceFacade.readAsStringSync: concatenated sync_service.dart with the part files in Directory.listSync order", line: 27 }
readers:
  - { file: test/contracts/sync_template_before_schedule_order_test.dart, method_or_widget: "the Future.wait list pattern", line: 44 }
hive_key_prefix: "none"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/sync_template_before_schedule_order_test.dart
ist_handling: ["not date-related"]
provider_invalidations: ["none"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "n/a (test code only)"
forbidden_patterns_checked:
  - { pattern: "Directory.listSync() consumed unsorted by the sync source facade", absent: true }
proposed_fix: |
  Two causes that only fail together. (1) The facade joined the part files in the order the filesystem lists them, which differs between machines and runs. (2) The test's pattern `Future.wait([ ... ], eagerError: false` used a lazy any-character list, and lib/core/services/sync/nutrition_slot_engine.dart holds four `Future.wait([` with NO eagerError: from such a wait the pattern ran on into whichever file came next and stopped at that file's first `], eagerError: false`, swallowing everything between. When the neighbour held both pushes the test saw them "in one list". Fix: the facade sorts the part files by path, and the list pattern may not run into another `Future.wait`.
regression_test_planned: |
  The test itself, now order-independent. Measured with a scratch script over 300 random orders of the 20 part files: the OLD pattern reported the false positive in 90 of 300 orders (0 in the VPS's listing order and 0 in sorted order, which is why it had not been seen here); the NEW pattern in 0 of 300, while still finding exactly 2 lists that hold the schedule push in every order (so it is not vacuous).
mutation_proof: |
  With the new pattern, a source in which `_syncWorkoutTemplates(userId)` is put into the same list as `_syncScheduledWorkouts(userId)` is still flagged (scratch check, True). The real file was not edited for this check.
impact_analysis: |
  Test code only. Every source-grep test that reads the sync source through the facade now sees one fixed order on every machine. No product code changes.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "No lib/ file changes for this fix; lib/core/services/sync/nutrition_slot_engine.dart read to count its four open-ended Future.wait lists." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Test harness only." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Test harness only." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Test harness only." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Test harness only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "Test harness only." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Test harness only." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Test harness only." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Test harness only." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Test harness only." }
  - { tier: 11, name: "External services", status: fixed_in_this_batch, evidence: "CI (GitHub Actions) is where it failed; the fix removes the dependency on the runner's directory order." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Test harness only." }
recurrence: "Recurrence of the class 'green locally is this machine's layout': a test that depends on an order or layout the VPS happens to have and a CI runner does not (see the known-flakes catalogue: a spawn test that passed here and failed on CI). Not a recurrence of a product bug."
related_bugs: []
---

# e4b7a9 - a sync source test depended on the directory listing order

## What happened
The sync source facade joined part files in filesystem order, and one test's pattern could run from an open-ended `Future.wait([` in one file into the next file.

## The fix
Sort the part files; forbid the pattern from crossing another `Future.wait`.

## Not established
- Which order the failing CI runner produced was not captured; the mechanism is shown by simulation (90 of 300 random orders fail with the old pattern), not by reproducing that runner.
- Other source-grep tests that read through the facade were not each audited for the same cross-file reach; sorting makes whatever they see the same on every machine.
