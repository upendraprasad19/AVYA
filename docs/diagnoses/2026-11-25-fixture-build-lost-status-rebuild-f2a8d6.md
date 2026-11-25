---
bug_id: f2a8d6
date: 2026-11-25
batch: ci-integration-on-pr (OI-528)
status: fixed
tier: s_fix
blast_radius: platform
symptom: |
  Twice on CI a test failed once in the setup of the `SyncCli` fixture with a git "already exists" error and passed on a rerun: `git remote add origin ...: error: remote origin already exists` (PR 329, land_pr_e2e_test) and `git checkout -q -b feature: fatal: a branch named 'feature' already exists` (PR 338 run 45361275474, sync_with_main_e2e_test E7).
concept: test_spawn_helper_retries
sot_registry_entry: not_applicable
writers:
  - { file: test/helpers/spawn.dart, method_or_widget: "retryingSpawn / retryingSpawnAsync: the lost-status branch runs the child again without knowing whether the first attempt took effect", line: 352 }
readers:
  - { file: test/helpers/sync_cli_fixture.dart, method_or_widget: "SyncCli.create: a chain of non-idempotent git commands, each required to exit 0", line: 60 }
hive_key_prefix: none
hive_key_formula: "not applicable: test infrastructure"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/spawn_retry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: no account data."
forbidden_patterns_checked:
  - { pattern: "a claim about WHY the exit status is lost (OI-468: not established)", absent: true }
  - { pattern: "a retry of a single non-idempotent command treated as safe", absent: true }
proposed_fix: |
  Mechanism, MEASURED for the second sighting only: its job log carries `[spawn-retry] lost-status retry 1 of 1 merge_scope_repo: git checkout -q -b feature | exit=-523296808`. The first attempt created the branch, the harness lost its status, the OI-468 retry ran it again and the second attempt failed on its own earlier effect. The first sighting's log was not re-read for that line; it is assumed to be the same.
  No single command can be made safe (the helper cannot know whether attempt one ran, and `commit --allow-empty` would not even fail, it would commit twice). The whole build of a fresh temporary repository can be repeated. `spawn.dart` counts lost-status retries from both loops (`lostStatusRetriesSeen`), and `rebuildOnLostStatus` runs a build once more when the counter moved during it, whatever the first outcome; the second outcome is final. `SyncCli.create` builds through it (`LandFixture.create` starts with `SyncCli.create`).
  Not covered, stated in the helper: a status lost after the fixture is built, and other fixtures. No sighting of either.
regression_test_planned: |
  test/contracts/spawn_retry_test.dart, group "OI-528: the lost-status counter and the fixture rebuild" (10 tests).
mutation_proof: |
  Rule 21, mutate / run / restore, 16 mutants on spawn.dart and sync_cli_fixture.dart, 16 red, each for its own test: the sync loop not counting (2 red), the async loop not counting (1), a native-assets retry counted in either loop (1 each), never rebuilding (5), keeping a completed first build (4), rebuilding a plain failure (1), catching only Exception (1), wrapping the error (1), the rethrow site as the stack (1), a rebuild that can rebuild again (1), no line on a rebuild (5), no line for a second lost status (1), the line stating the wrong first outcome (2), a default counter that is not the helper's (1), SyncCli.create bypassing the helper (1, a presence pin).
  The real failure cannot be produced on demand (two sightings in thousands of runs); the tests drive the loops with a scripted impossible status.
impact_analysis: |
  Test helpers only. A fixture build during which a status was lost now costs one extra build and prints one `[fixture-rebuild]` line.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "test/helpers/spawn.dart and sync_cli_fixture.dart; spawn_retry_test 10 new tests green, land_pr / sync e2e 188 green." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Not involved." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client to server contract", status: not_applicable, evidence: "Not involved." }
---

# A fixture build hit by a lost exit status is rebuilt once (OI-528)

Recurrence: the lost status itself is OI-468 (diagnose of 2026-11-06, cause not established); that fix added the
retry. This is the retry's known limit for non-idempotent children, now handled one level up for `SyncCli`.
