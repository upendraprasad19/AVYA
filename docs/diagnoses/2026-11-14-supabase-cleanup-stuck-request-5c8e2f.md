---
bug_id: 5c8e2f
date: 2026-11-14
batch: sync-test-flake (test-only; no lib/ change)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  `test/supabase/sync_service_test.dart` Profile Sync T1/T2 failed with "Test timed out after 30 seconds" on the CI `Supabase Integration Tests` job of the main pushes of PR #260 (2026-11-13, T2) and PR #264 (2026-11-14, run 43552703702, T1), green on re-run. About 2 of the last ~40 main runs. Supabase edge logs for the PR #264 run: first cleanup DELETE (user_daily_snapshots) served 03:39:45.56, the second (ai_coach_interactions) only at 03:40:11.40, zero requests from anyone in between; the 30 s test timeout fired at 03:40:15.56 inside the cleanup loop, so T1's body never ran. A healthy test takes ~3 s (12 sequential round trips, ~0.25 s each). No cron job overlapped (jrd_vacuum_daily 03:40:06-12 touches another table; none at 05:02). Not established: which network layer held the request.
concept: supabase_integration_test_cleanup
sot_registry_entry: not_applicable
writers:
  - { file: test/supabase/supabase_test_helper.dart, method_or_widget: "SupabaseTestHelper.cleanup() / _realDeleteRows: 12 sequential DELETEs with no per-request bound, called from every test's setUp (billed to the 30 s test timeout)", line: 297 }
readers:
  - { file: test/supabase/sync_service_test.dart, method_or_widget: "setUp -> SupabaseTestHelper.cleanup() before every test", line: 85 }
  - { file: test/supabase/auth_restore_test.dart, method_or_widget: "same setUp cleanup", line: 1 }
hive_key_prefix: none
hive_key_formula: "not applicable: no stored value changes meaning"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/supabase/cleanup_call_timeout_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: assertDisposableTarget and qaUserIds are untouched and still run before the first delete."
forbidden_patterns_checked:
  - { pattern: "an unbounded network call inside a test's setUp", absent: true }
proposed_fix: |
  Test-only. cleanup() bounds each table delete with `.timeout(deleteCallTimeout)` (8 s) and retries it once on TimeoutException (the stuck socket stays busy, a retry opens a fresh connection); a second timeout is rethrown loudly (the old blanket `catch (_)` would have turned it into leftover rows and a misleading assertion failure later). Ordinary delete errors (missing table) are still skipped. Cleanup stays SEQUENTIAL: its own comment says FK order matters, and parallel deletes would swallow FK errors. `@Timeout(90s)` backstop on both live test files. New seams: deleteCallTimeout, debugSetSignedInIdForTests (the guard still applies).
regression_test_planned: |
  test/supabase/cleanup_call_timeout_test.dart (credential-free, runs in the Unit Tests job): hang once -> 13 calls and cleanup completes; hang twice -> TimeoutException after exactly 2 calls; ordinary error -> 12 calls, no retry, no throw.
mutation_proof: |
  Rule 21, backup/mutate/run/restore. M1 drop `.timeout(...)` (grep -c 1): 2 tests RED. M2 replace the timeout rethrow with a swallow (grep -c 1): 1 test RED. M3 retry removed, `if (attempt >= 2) rethrow` to `rethrow` (grep -c 1): 2 tests RED. Residual: the fix makes the test tolerate a stall; it does not remove it. The CI runner/edge layer that dropped the request was not identified.
impact_analysis: |
  Test helper + two test annotations. No production behavior, no registry range moves.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "lib/ diff empty; helper read at the cited lines; new test passes, existing cleanup_target_guard_test passes (17/17 together)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Not involved." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "cron.job_run_details for 03:38:30-03:41:30 on 2026-11-14 and 05:01:30-05:04:00 on 2026-11-13: only jrd_vacuum_daily (other table) and referral_conversions_hourly; ruled out as the cause." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: verified, evidence: "Supabase API edge logs for 03:39:40-03:40:20 UTC show the 26 s gap with no requests from anyone; GitHub Actions run 43552703702 job log shows the T1 timeout." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Same known-flakes catalogue entry (CI Supabase Integration Tests 30 s timeout); first diagnose for it. Not a recurrence of a fixed bug class."
related_bugs: []
---

# 5c8e2f - one stuck cleanup DELETE ate the whole test budget

## What happened
`setUp` runs `cleanup()`: 12 sequential DELETEs. Nothing bounds a single request, and `setUp` counts toward the test's 30 s. When one request is held ~26 s somewhere between the runner and the Supabase edge, the test times out in `setUp` and the error blames T1 or T2. Edge logs show nothing else running; the DB was idle.

## Fix
See `proposed_fix`. Per-call 8 s bound, one retry on a fresh connection, loud failure on a second timeout, 90 s file backstop.
