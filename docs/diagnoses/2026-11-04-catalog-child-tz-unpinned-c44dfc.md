---
bug_id: c44dfc
date: 2026-11-04
batch: tz-pin-catalog (OI-459)
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  The pre-commit regression catalog (run on a merge commit) failed 6 tests on the UTC VPS while landing PR #204, and the same files passed under TZ=Asia/Kolkata. It looked like a flaky test. Reproduced 2026-11-04 without a code change: the walk passes at 06:35 UTC (UTC and IST name the same date) and fails under any caller zone whose date differs from IST, here TZ=Etc/GMT+12 (exit 1, many tests in rest_by_type, gate_input_family_e2e, the exlog sync tests and others).
concept: pre_commit_regression_catalog_child_environment
sot_registry_entry: none
writers:
  - { file: scripts/check_regression_catalog.dart, method_or_widget: "Process.run('flutter', ['test', ...chunk]) with environment: scrubbedChildEnvironment(Platform.environment) and includeParentEnvironment: false", line: 72 }
  - { file: scripts/regression_catalog_lib.dart, method_or_widget: "scrubbedChildEnvironment (passes the caller's TZ through, or none)", line: 177 }
readers:
  - { file: test/contracts/rest_by_type_behavioral_test.dart, method_or_widget: "date-boundary assertions read the process zone", line: 1 }
  - { file: test/scripts/gate_input_family_e2e_test.dart, method_or_widget: "date-sensitive e2e assertions", line: 1 }
  - { file: test/sync/exlog_push_u3_behavioral_test.dart, method_or_widget: "workout_log_id derived from a row date", line: 1 }
hive_key_prefix: none
hive_key_formula: "not applicable: no stored value changes meaning"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/regression_catalog_lib_test.dart
ist_handling:
  - { file: scripts/regression_catalog_lib.dart, line: 201, fn: catalogChildEnvironment }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: no user data."
forbidden_patterns_checked:
  - { pattern: "a wrapper-only TZ export (safe_commit.sh / land_pr.sh) as the fix", absent: true }
proposed_fix: |
  Pin the zone at the spawn site, not in the wrappers. A new pure catalogChildEnvironment in scripts/regression_catalog_lib.dart applies the canonical scrub and sets TZ=Asia/Kolkata (CI and pre-push already pin the same zone); check_regression_catalog.dart passes it to flutter test. The hook runs the walk for every way of making a merge commit (safe_commit.sh, land_pr.sh, safe_merge.sh, plain git merge), so only the spawn site covers them all. scrubbedChildEnvironment is unchanged because git_safety_hook_integration_test and test/helpers/spawn.dart share it and an existing test pins that it keeps TZ.
regression_test_planned: |
  test/scripts/regression_catalog_lib_test.dart: group "catalogChildEnvironment pins the zone (OI-459)" (unit: unset, UTC, a date-differing zone and IST all give Asia/Kolkata; the scrub still applies and PATH survives; scrubbedChildEnvironment still passes TZ through), a behavioural test that spawns a real /bin/sh -c "date +%z" with the catalog env under three parent zones and expects +0530 (skipped on Windows), and the structural pin that the gate calls catalogChildEnvironment and no longer passes the bare scrub.
mutation_proof: |
  Rule 21. Four mutants, each confirmed applied (grep -c 1), file restored in a finally, git diff --stat clean after. M1 comment out the TZ assignment: 3 red. M2 spawn site back to scrubbedChildEnvironment: 1 red (structural pin). M3 catalogChildEnvironment copies the parent instead of calling the scrub: 1 red. M4 pin set to UTC: 3 red. End to end: the real catalog run under TZ=Etc/GMT+12 exited 1 before the fix and exits 0 after (59 recent Dart tests green), with no manual TZ.
impact_analysis: |
  scripts/ only (a pre-commit gate's child process environment). No lib/ change, no writer/reader contract, no registry range moves. Effect on a user of the VPS: merge commits no longer fail the catalog in the 18:30 to 24:00 UTC window. Effect on the Windows clone: none (Dart and the tests there ignore TZ; the behavioural test is skipped).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "git diff --stat -- lib is empty; scripts/regression_catalog_lib.dart and check_regression_catalog.dart read at the cited lines." }
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
recurrence: "Same family as the memory note on CI-versus-local layout divergence (a result that depends on the machine's zone). Not a recurrence of a fixed product bug class; the earlier TZ lesson in reference_vps_quirks.md was a manual workaround, never a code fix."
related_bugs: []
---

# c44dfc - the regression catalog child ran in the caller's zone

## What happened

On a merge commit the pre-commit hook walks the regression catalog by spawning `flutter test` on the recent regression tests. The child got the caller's `TZ` or none, and the VPS is UTC while the suite assumes IST. UTC and IST name different calendar dates from 18:30 to 24:00 UTC, so date-boundary tests fail then and pass in the morning. During OI-450's landing it cost a failed landing and a wrong "load flake" guess, and the workaround was a manual `TZ=Asia/Kolkata` prefix.

## The fix

The catalog's child environment now pins `TZ=Asia/Kolkata` at the one place that spawns it, for every way of making a merge commit.

## Not covered

- Other scripts that spawn `flutter test` (`pre-push.sh` already pins its own; CI pins at workflow level). Not changed here.
- The test (f) residual that used to ride in this OI's entry is now OI-463.
