---
bug_id: d4a7c1
date: 2026-09-27
batch: reuse-audit-fixes (unit 2a — template-stable-identity, OI-252) — surfaced while merging
status: fixed
blast_radius: feature
symptom: |
  Merging `template-stable-identity` into `main` triggered the pre-merge-commit
  hook's `check_regression_catalog.dart` gate (a merge-only gate that runs the
  Dart regression tests cited by diagnose-docs from the last 30 days). It ran
  `test/contracts/alert_cron_job_silent_test.dart` and
  `test/contracts/alert_sql_job_failures_test.dart` — both merged in moments
  earlier from `main`'s own `ops-alerting-b2a` batch (`64aec6b2`) — and both
  failed their "alerts/_thresholds.yaml entry agrees with the SQL it documents"
  test, e.g.:
    Expected: 'migrations\146_alert_cron_job_silent.sql'
      Actual: '146_alert_cron_job_silent.sql'
  This blocked the merge commit. Initially suspected as a consequence of the
  same-session migration-number collision (OI-255, migrations 145/146 minted
  independently by both `main` and this branch) — ruled out by tracing the
  actual resolution logic: `numberedMigrations()` matches by SCANNING every
  migration's SQL content for the job name substring (`cron.schedule('$job',
  ...)`), not by bare numeric prefix, so a sibling file sharing the same
  number but with unrelated content (this branch's `146_workout_templates_...`)
  never matches and is silently skipped. The real cause is unrelated: pure
  Windows path-separator handling.
concept: alert-contract-test-infra
sot_registry_entry: not_applicable — test-infrastructure fix, not a writer/reader contract
writers:
  - { file: test/helpers/cron_job_body_reader.dart, method_or_widget: "numberedMigrations() — Directory('supabase/migrations').listSync(), which on Windows yields File.path values using '\\' as the separator between the directory and filename segments (Dart's Directory API returns OS-native paths)", line: 22 }
readers:
  - { file: test/contracts/alert_cron_job_silent_test.dart, method_or_widget: "'alerts/_thresholds.yaml entry agrees with the SQL it documents' — job.file.split('/').last", line: 151 }
  - { file: test/contracts/alert_sql_job_failures_test.dart, method_or_widget: "'alerts/_thresholds.yaml entry agrees with the SQL it documents' — job.file.split('/').last", line: 101 }
hive_key_prefix: not_applicable — no Hive involvement
hive_key_formula: not_applicable — no Hive involvement
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: "test/contracts/alert_cron_job_silent_test.dart and test/contracts/alert_sql_job_failures_test.dart (both pre-existing, this fix repairs their own assertion rather than adding a new test)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no per-user data path touched; this is a test-helper path-string bug
forbidden_patterns_checked:
  - "using package:path's p.basename() instead of a RegExp split — considered, but the repo's own established convention (scripts/check_migrations_applied.dart:46) already uses split(RegExp(r'[/\\]')).last with no package:path dependency in that file; matched the existing pattern rather than introducing a new one for two lines."
proposed_fix: |
  Changed both assertions from `job.file.split('/').last` to
  `job.file.split(RegExp(r'[/\\]')).last`, matching the platform-safe pattern
  already used by `scripts/check_migrations_applied.dart:46`
  (`entity.path.split(RegExp(r'[/\\]')).last`). No production code touched —
  this is a test-assertion-only fix; the SQL/YAML content both tests validate
  was already correct.
regression_test_planned:
  - "test/contracts/alert_cron_job_silent_test.dart and test/contracts/alert_sql_job_failures_test.dart themselves are the regression tests for this fix — both independently FAILED before it (observed expected/actual mismatch quoted in symptom above) and PASS after (flutter test on both files together: 15/15 green, 'All tests passed!'). No new test file needed; this repairs the assertion in the two existing tests whose job is exactly to catch this class of drift."
impact_analysis: |
  Windows-local `flutter test` runs (and this repo's own pre-merge-commit
  regression-catalog gate, which runs on this machine) can now actually
  execute these two alert contract tests to a real pass/fail verdict instead
  of a platform-artifact false failure. No behavior change to the SQL, the
  YAML thresholds, or any runtime code — both migrations' content was already
  correct; only the TEST's own path comparison was wrong. Linux CI was never
  affected (native '/' separator throughout), which is also why this shipped
  clean through the originating batch's two plan-review rounds, its B-pass,
  and CI.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "test/contracts/alert_cron_job_silent_test.dart:151 and test/contracts/alert_sql_job_failures_test.dart:101 edited. Re-ran both files directly: pre-fix, 2 failures with the exact expected/actual mismatch quoted in symptom; post-fix, flutter test on both files together --reporter expanded -> All tests passed! (15/15)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Test-infra fix only; no Hive read/write involved." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched -- the SQL these tests validate was already live and correct on both sides of the migration-number collision (OI-255)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No new migration; this fix is entirely in test/contracts/." }
---

## Summary

A Windows-only path-separator bug in two brand-new alert contract tests
(merged from `main`'s `ops-alerting-b2a` batch moments before this merge)
was blocking the merge via `check_regression_catalog.dart`. Traced to
`job.file.split('/').last` not accounting for the backslash
`Directory.listSync()` returns on Windows; fixed by switching both to the
repo's established `split(RegExp(r'[/\\]'))` pattern. No production code or
SQL was wrong — this was a test-assertion bug only, invisible on Linux CI.
