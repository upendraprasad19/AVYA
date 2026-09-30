---
bug_id: d4e7c2
date: 2026-09-30
batch: sync-aab-build-check-408772
status: fixed
blast_radius: feature
related_bugs: [OI-268]
recurrence: >
  SAME CLASS as OI-268 (2026-09-29, `scripts/contract_sweep.dart` setting `TZ=Asia/Kolkata` for a
  Windows child process, which the Windows CRT parses as UTC): a test that is CORRECT on Linux
  (GitHub Actions CI) and WRONG on Windows (this dev machine), because it hardcodes a
  platform-specific assumption that only one of the two OSes actually holds. There the
  assumption was "an IANA timezone string works everywhere"; here it is "a file path uses `/`
  everywhere". Both classes are invisible to CI by construction — CI is Linux, so a Windows-only
  defect never reddens the pipeline that gates `main`.
symptom: >
  `sh scripts/safe_push.sh origin claude/sync-aab-build-check-408772` failed twice with
  `Some tests failed` / `error: failed to push some refs`, despite the exact same push having
  succeeded through pre-commit and merge-commit gates moments earlier. `git ls-remote` confirmed
  the branch never advanced on `origin` both times (the exit-code-lies trap: the wrapper shell
  reported exit 0 for itself while the underlying `git push` failed). The failing test surfaced
  only in a FULL-suite run (`flutter test test/ --exclude-tags golden`, ~7300 tests, matching
  `pre-push.sh`'s exact invocation) — not in the smaller 132-test regression-catalog subset
  `scripts/check_regression_catalog.dart` re-runs on every merge commit, because this test file
  was not cited by any diagnose-doc in the last 30 days at the time it was introduced.

  `test/scripts/check_applied_migrations_ledger_e2e_test.dart`'s
  `the grandfather PIN map is wired into the binary: 057 with an unpinned file FAILS` test threw
  `Bad state: No element` from `Iterable.firstWhere` at its own line 147 — reproduced in
  ISOLATION (`flutter test <file> --plain-name "the grandfather PIN map"`), ruling out
  full-suite concurrency/flakiness as the cause before looking further.
concept: >
  The test's `setUp()` correctly copies the 5 "grandfathered" migration files (057/069/070/108/123)
  from the real `supabase/migrations/` directory into a fresh temp directory, using
  `f.uri.pathSegments.last.startsWith('${id}_')` to match filenames — a URI-based check that is
  path-separator-agnostic and works identically on Windows and Linux. All 5 copies succeed
  (verified directly: `copied: 5`).

  The test body then tries to locate that copied 057 file with a DIFFERENT, inconsistent check:
  `f.path.contains('/057_')` — `File.path` on Windows returns a BACKSLASH-separated path
  (`C:\...\supabase\migrations\057_...sql`), so a literal forward-slash substring can never match.
  `Iterable.firstWhere` with no match and no `orElse` throws `Bad state: No element`. On Linux
  (GitHub Actions), `.path` returns forward slashes, so the identical line has always passed
  there — this defect was invisible to CI from the moment the test was written and would remain
  so indefinitely on that platform.

  This is the exact shape OI-268 already named for a different mechanism: a Windows/Linux
  divergence in a test's OWN plumbing, not in the code under test, surfacing only on a local
  Windows dev machine's full-suite run.
sot_registry_entry: not_applicable
sot_registry_note: >
  Pure test-infrastructure defect (a self-check inside a test file) — no writer/reader pair, no
  Hive key, no cloud column.
writers:
  - { file: test/scripts/check_applied_migrations_ledger_e2e_test.dart, method_or_widget: "setUp() — the grandfathered-file copy loop, uses the CORRECT uri.pathSegments check", line: 67 }
readers:
  - { file: test/scripts/check_applied_migrations_ledger_e2e_test.dart, method_or_widget: "the grandfather PIN map is wired into the binary -- test body, used the INCORRECT f.path.contains('/057_') check before this fix", line: 147 }
hive_key_prefix: null
hive_key_formula: "not_applicable -- no Hive involvement."
sync_methods: not_applicable — test-only code, no cloud fan-out.
restore_methods: not_applicable — nothing is restored.
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/check_applied_migrations_ledger_e2e_test.dart
ist_handling:
  - { file: test/scripts/check_applied_migrations_ledger_e2e_test.dart, line: 147, fn: "not_applicable -- no date/timestamp involved, purely a filesystem path separator issue." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — this fix only corrects a path-matching predicate inside a test's own body; it
  does not change what the gate under test (`check_applied_migrations_ledger.dart`) actually
  verifies or its pass/fail behavior for any real migration.
forbidden_patterns_checked: >
  - Fixed to match the EXISTING correct pattern already used two lines away in the same file's
    `setUp()` (`f.uri.pathSegments.last.startsWith('${id}_')`), rather than inventing a new
    pattern — `uri.pathSegments` is guaranteed forward-slash-normalized regardless of platform,
    per Dart's `Uri` contract, so this is the platform-agnostic idiom this codebase already
    established for exactly this class of check.
  - Did not touch the copy loop itself (already correct) or the gate script under test
    (`scripts/check_applied_migrations_ledger.dart`) — the defect was isolated entirely to the
    TEST's own verification line, confirmed by reproducing it with a standalone script that
    copied the exact same setUp logic and printed intermediate state (`copied: 5`,
    `057 found in tmp: 0` using the broken check).
proposed_fix: >
  Change line 147 from `f.path.contains('/057_')` to `f.uri.pathSegments.last.startsWith('057_')`.
regression_test_planned:
  - test/scripts/check_applied_migrations_ledger_e2e_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "test/scripts/check_applied_migrations_ledger_e2e_test.dart:147 fixed and mutation-proven (9/9 green; reverting the fix reproduces the exact original failure)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration file changed -- migration 057 itself is untouched; only a TEST's reference to its own copied fixture." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret material in this test." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service call." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact ZERO — `scripts/check_applied_migrations_ledger.dart` itself (the real gate under
  test) was never broken; only this ONE test's OWN internal verification step was. CI impact ZERO
  — GitHub Actions runs on Linux, where `.path` already uses forward slashes, so this test has
  been silently green in CI since it was introduced and would have stayed that way indefinitely.

  Operational impact was real and immediate for this session: it blocked `safe_push.sh`'s full
  pre-push suite (the ONLY gate that runs this test locally, since `pre-commit.sh` skips
  `flutter test` by design per ADR-0018, and the regression-catalog's 132-test subset does not
  cite this file) on a completely unrelated branch (`claude/sync-aab-build-check-408772`, a
  Razorpay/Vercel batch) purely because that branch happened to be the first Windows-local push
  to run the full suite after this test was merged in via `origin/main`.

  WHY IT WAS NOT CAUGHT SOONER: the test was authored and merged entirely on `origin/main`
  (migration-ledger-integrity batch, PRs #57/#59/#60), reviewed and CI-green there — CI cannot see
  a Windows-only defect by construction. It surfaced here only because this session's full-suite
  push is one of the few points where a Windows dev machine actually exercises the complete test
  tree against fresh `origin/main` content.
mutation_evidence: >
  Rule 21 mutate-it-and-run-it. Reverted the fix to the original
  `f.path.contains('/057_')` form, confirmed applied via `grep -c` (1 match of the broken form,
  0 of the fixed form), re-ran the specific test: reproduced the EXACT original failure
  (`Bad state: No element` at the same line). Restored the fix, re-ran the whole file: 9/9 green.
  Root cause was additionally confirmed via a standalone throwaway script replicating the exact
  `setUp()` copy logic plus both verification forms side-by-side: the URI-based copy succeeded
  (`copied: 5`) while the forward-slash `.path.contains()` check found 0 matches for the very
  files that had just been copied — isolating the defect to the single mismatched predicate
  before any code was changed.
---

# d4e7c2 — a Windows-only `.path` forward-slash check in a test's own verification step

## What happened

`test/scripts/check_applied_migrations_ledger_e2e_test.dart`'s
`the grandfather PIN map is wired into the binary: 057 with an unpinned file FAILS` test threw
`Bad state: No element` when run on this Windows dev machine, in both the full test suite and in
isolation — but has been green in CI (Linux) since it was merged via `origin/main`.

## Why the copy succeeded but the lookup failed

The test's `setUp()` copies migration files from the real repo into a temp directory using
`f.uri.pathSegments.last.startsWith('${id}_')` — a check on URI path segments, which Dart always
normalizes to forward slashes regardless of the host OS. This copy step works identically on
Windows and Linux, and was confirmed working via a standalone reproduction (`copied: 5`).

The test body then re-locates that copied file with `f.path.contains('/057_')` — `File.path`
returns the OS-native path representation, which on Windows uses backslashes
(`C:\...\supabase\migrations\057_...sql`). A literal `/057_` substring check can never match a
backslash-separated path, so `firstWhere` finds no element and throws.

## The fix

Changed the lookup to use the same platform-agnostic idiom the copy loop already uses two lines
above it: `f.uri.pathSegments.last.startsWith('057_')`. No behavior changes for Linux/CI, where
the old check already worked by coincidence of using the same separator; on Windows the test now
finds the file it just copied, exactly as intended.
