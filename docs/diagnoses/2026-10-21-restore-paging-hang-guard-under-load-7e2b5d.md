---
bug_id: 7e2b5d
date: 2026-10-21
batch: build-pin-and-test-closeout
status: fixed
blast_radius: feature
related_bugs: []
recurrence: >
  Not a recurrence of a recorded class. It is a sibling of CLAUDE.md §4.9's row "a new test file
  that spawns subprocesses, or waits on a live service, goes green targeted and RED in the full
  suite" (a per-call timeout too tight for a loaded run). Here the slow part is the test's own
  stub, not a subprocess.
symptom: >
  The merge regression-catalog walk (scripts/pre-commit.sh at a merge commit, swap-move-design
  merging origin/main d483a800) failed one of 1,668 tests:
  test/sync/restore_legacy_paging_behavioral_test.dart "the 50,000-row ceiling is announced, not
  silent / a table that fills the ceiling emits ONE restore_row_ceiling_hit naming only the
  table", with `TimeoutException after 0:02:00.000000: Future not completed`. Alone the test takes
  about 11 s (the whole file 40 s, 40/40 green), and the retried merge commit passed the walk.
  Another session's full `flutter test` was running on the same machine during the failed walk.
concept: >
  `_within` (the test's per-call hang guard) wrapped each restore call in a 2-minute
  `.timeout`, under a per-test `@Timeout(Duration(minutes: 5))` on `library;`. The 50,000-row
  tests are slow by construction: the shared stub `_pagedAnswer` (test/helpers/sync_stub_server.dart:204-233)
  re-filters and re-sorts all 50,000 rows for each of the 50 page requests. At about 11 s alone,
  2 minutes was about 11x headroom, and CPU contention from a second full suite used it up. The
  guard's job is to turn a HANG into a fast, named failure (its comment); it was never meant to
  bound speed.
sot_registry_entry: not_applicable
sot_registry_note: >
  Test-only timing constant. No writer/reader pair, Hive key or cloud column; the production
  restore code (`sync_service.dart:3095`, `sync/sync_nutrition.dart:636`) is untouched.
writers:
  - { file: test/sync/restore_legacy_paging_behavioral_test.dart, method_or_widget: "_within -- the per-call hang guard (was 2 min, now 8)", line: 60 }
readers:
  - { file: test/sync/restore_legacy_paging_behavioral_test.dart, method_or_widget: "the 50,000-row ceiling test that timed out", line: 677 }
  - { file: test/sync/restore_legacy_paging_behavioral_test.dart, method_or_widget: "the nutrition 50,000-row ceiling test (same exposure)", line: 502 }
hive_key_prefix: null
hive_key_formula: "not_applicable -- no Hive key involved."
sync_methods: not_applicable — only the test's guard changes.
restore_methods: not_applicable — the restore code under test is unchanged.
cloud_table: none
cloud_columns: []
contract_test_path: test/sync/restore_legacy_paging_behavioral_test.dart
ist_handling:
  - { file: test/sync/restore_legacy_paging_behavioral_test.dart, line: 60, fn: "not_applicable -- a timeout duration, no date." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — every assertion in the file is unchanged; only how long a call may run before
  it is treated as a hang changes.
forbidden_patterns_checked: >
  - Did not add retry-on-timeout (it would hide a real hang) and did not loosen any assertion.
  - Did not make the 50,000 ceiling injectable: it is a constant in production sync code, and
    changing that is a platform-tier change for a test's sake.
  - Did not memoise the stub's sorted pages: a cache would have to be keyed on list identity and
    reset on `pagedTables.clear()` or reassignment (done in setUp by
    body_measurement_push_merge_safe_test.dart:64 and measurement_batch_push_test.dart:44), and
    `reshuffleTies` depends on the stub's request counter (sync_stub_server.dart:158,205). That is
    a new source of shared test-infra bugs for the 10 files that import the stub.
proposed_fix: >
  Raise `_within` to 8 minutes and the per-test `@Timeout` to 10, so a real hang still fails at the
  guard with its own message. The loaded run time was never measured beyond "over 2 minutes" (the
  guard fired at 120 s); 11 s is the UNLOADED time. So this is a 4x widening of the bound that
  failed, not a measured headroom. Other files in test/ already declare 8 to 14 minutes. The comment
  records this.
regression_test_planned:
  - test/sync/restore_legacy_paging_behavioral_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "test/sync/restore_legacy_paging_behavioral_test.dart _within 2 -> 8 min, per-test @Timeout 5 -> 10 min; file 40/40 green alone; guard proven live by mutation (1 ms -> both 50,000-row ceiling tests red with the guard's TimeoutException)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive change." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "Stubbed server; no DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "None." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "None." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "None." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "None." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "None." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "None." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "None." }
impact_analysis: >
  Product impact zero. Process impact: a load-only failure in the merge regression-catalog walk
  blocks a merge commit and invites "retry until green", which trains people to ignore the walk.
  The guard is now 4x the bound that failed under load.
mutation_evidence: >
  The claim is "guard live, bound under the per-test timeout" (8 < 10 min). Set `_within` to
  `Duration(milliseconds: 1)` (confirmed applied by `git diff -U0`: the 2-minute line replaced),
  then ran the file filtered to "fills the ceiling". Both 50,000-row ceiling tests failed with
  `TimeoutException after 0:00:00.001000` (the guard, not the per-test timeout). Restored from a
  file backup. That the 8-minute guard sits under the per-test timeout was checked by reading
  line 1 (`@Timeout(Duration(minutes: 10))`) against the guard.
---

# 7e2b5d — the restore-paging hang guard was too tight for a loaded machine

## What happened
At a merge commit the pre-commit hook re-runs recent regression tests. One 50,000-row restore test
hit its own 2-minute hang guard while another session's full suite was loading the machine. Alone
it takes about 11 s. The retried commit passed.

## Fix
The guard is now 8 minutes, under a 10-minute per-test timeout (4x the bound that failed), so a real hang still fails
fast with the guard's message. The cost itself, the stub re-sorting 50,000 rows per page, is left
as it is, for the reasons in `forbidden_patterns_checked`.
