---
bug_id: b7e3c1
date: 2026-11-25
batch: ci-integration-on-pr (OI-527)
status: fixed
tier: s_fix
blast_radius: platform
symptom: |
  A pull request that breaks an integration test is green on its own CI and turns `main` red after the merge: PR 328 broke test/supabase/sync_service_test.dart T4 and six consecutive `main` runs were red over 14 hours (70add5cf to 7e8bb3d2) until PR 335.
concept: ci_merge_gate_job_classification
sot_registry_entry: not_applicable
writers:
  - { file: .github/workflows/test.yml, method_or_widget: "job supabase-tests: its `if:` ran it on a push to main only", line: 657 }
readers:
  - { file: scripts/safe_pr_merge_lib.dart, method_or_widget: "_judgeCheckRuns: the job was in skippedOkJobs, so `skipped` and a missing run both passed", line: 264 }
hive_key_prefix: none
hive_key_formula: "not applicable: CI configuration"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/ci_integration_job_on_pr_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Unchanged: SupabaseTestHelper.assertDisposableTarget refuses a non-QA target (test/supabase/cleanup_target_guard_test.dart). Pull-request test code now runs with the QA account before review; same-repository authors only."
forbidden_patterns_checked:
  - { pattern: "two integration jobs at once on the one shared QA account", absent: true }
  - { pattern: "a missing check-run for the job read as fine", absent: true }
  - { pattern: "cancel-in-progress: true on the shared group", absent: true }
proposed_fix: |
  Not a flake: all six job logs show the same single failure (T4, `Bad state: No element`, line 269); 12 green runs before, 7 after.
  1. The job runs on every pull request of this repository as well as on a push to main. Dependabot and fork runs (no secrets) are skipped by the `if:`; on a pull request a missing secret fails the job.
  2. One literal concurrency group for all pull requests and main, `cancel-in-progress: false`, `queue: max`, because every step signs in as one QA account and deletes its rows.
  3. The merge wrapper gets a new class `prTimeSkippableJobs`: success or skipped pass; failure refuses; a missing run and only-cancelled runs are "not finished".
  Limits, in docs/architecture/hooks.md: the job tests the pull request's client and test code against the LIVE backend, so an additive migration must be applied before the pull request that needs it lands, and a changed Edge Function is tested against the old deployment.
regression_test_planned: |
  test/contracts/ci_integration_job_on_pr_test.dart (20 tests); test/scripts/safe_pr_merge_lib_test.dart group "jobs that run on every pull request but may skip themselves"; test/scripts/land_pr_e2e_test.dart, three OI-527 cases.
mutation_proof: |
  Rule 21, mutate / run / restore. Merge wrapper, 8 mutants, 8 red: the new class without a rule (3 red), a missing run red instead of pending (2), skipped refused (8), a running job passing (1), a failed job pending instead of red (1), the job also in skippedOkJobs (5), the job in no list (5), only-cancelled not named (1).
  Workflow, on the REAL file: `queue: max` to `queue: single` (7 red) and the Dependabot exclusion removed (red). The contract test carries 15 in-test mutants of the workflow text. First attempt at the real-file mutation failed the file at LOAD (the mutation helper threw while the group was declared), which is red for the wrong reason; the helper now returns a marker text and the rerun is red through the assertions.
  What only CI can show: that GitHub accepts `queue: max` and that the job runs and is green on this pull request (plan section 4).
impact_analysis: |
  Every pull request waits for one more job (about 3 minutes, beside the 10-minute test machines; longer when several are queued). A pull request head with no integration result cannot be merged by safe_pr_merge / land_pr.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/safe_pr_merge_lib.dart; safe_pr_merge_lib_test, land_pr_lib_test, land_pr_e2e_test green." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Not involved." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "The job deletes only the QA account's rows, as before." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration; the order rule is documented in supabase/migrations/CLAUDE.md." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "The four SUPABASE_* secrets exist (the job runs green on main); a same-repository pull request receives them." }
  - { tier: 11, name: "External services", status: verified, evidence: "GitHub Actions concurrency docs read 2026-11-25 (queue: single / max)." }
  - { tier: 12, name: "Client to server contract", status: not_applicable, evidence: "Not involved." }
---

# The integration job ran only after the merge (OI-527)

Not a recurrence of an earlier diagnose; the red runs themselves are diagnose `c7f4e2` (the T4 break), which this
change would have stopped at PR 328.
