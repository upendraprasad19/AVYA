---
bug_id: d9e4b1
date: 2026-09-26
batch: ci-green-batch-a (U1 — main CI red)
status: fixed
blast_radius: feature
symptom: |
  `main` was RED for four consecutive CI runs (0c92c105 merge of
  main-sync-warning, b4a42556, fc797551, fafec56a), job "Unit Tests", one test
  of 6430: `test/scripts/discipline_hook_main_sync_e2e_test.dart: stays silent
  when there is no origin/main to read (no remote at all) [E]` —
  `Expected: <0>  Actual: <128>`. The test was introduced by 1db54e4f in the
  same batch; the last green main run (b9b38d15) predates it. It passed on
  every developer machine the batch was built on, which is why it merged.
concept: not_applicable — a test-fixture environment defect, not a Hive/cloud
  writer/reader contract.
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or cloud
  table is involved.
writers:
  - { file: test/scripts/discipline_hook_main_sync_e2e_test.dart, method_or_widget: "the `lone` fixture (git init + _commit with NO user.email/user.name; setUp gives `clone`/`other` an identity at :97-98, `lone` is built inside the test and never got one)", line: 172 }
readers:
  - { file: test/scripts/discipline_hook_main_sync_e2e_test.dart, method_or_widget: "_commit — expect(_git(['commit', …]).exitCode, 0)", line: 74 }
  - { file: test/scripts/discipline_hook_main_sync_e2e_test.dart, method_or_widget: "_cleanEnv — stripped GIT_* but inherited HOME, so the developer's ~/.gitconfig identity reached the fixture's git", line: 25 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/scripts/discipline_hook_main_sync_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user data.
forbidden_patterns_checked:
  - "fixing only the `lone` identity — rejected as incomplete: the file would still pass locally for any FUTURE identity-less fixture and fail only in CI, which is the exact shape of this bug. The environment is made hermetic so the local run is the CI run."
  - "pointing GIT_CONFIG_GLOBAL at an EMPTY file — rejected (plan-review R2 F7): on a host with a real FQDN git auto-detects an identity from the hostname and the missing user.email still commits. The file holds `[user] useConfigOnly = true`."
  - "setting the GIT_CONFIG_* vars before the GIT_* strip — rejected: the strip would remove them. They are set after it."
  - "leaving $EMAIL inherited — rejected (plan-review R1 F8): git falls back to $EMAIL for the author, so a machine that sets it would pass a commit the runner refuses."
proposed_fix: |
  test/scripts/discipline_hook_main_sync_e2e_test.dart:
  (1) the `lone` repo gets `user.email`/`user.name` exactly as setUp gives
  `clone`/`other`; (2) `_cleanEnv()` — used by every fixture git call AND the
  hook subprocess — now also removes `EMAIL` and, after the GIT_* strip, sets
  `GIT_CONFIG_GLOBAL` to a temp file containing only
  `[user] useConfigOnly = true` and `GIT_CONFIG_NOSYSTEM=1`. Neither the
  fixtures nor the hook need any global config (the hook only fetches and
  compares refs).
regression_test_planned:
  - "test/scripts/discipline_hook_main_sync_e2e_test.dart — MUTATION-PROVEN 2026-09-26 on this VPS, a machine WITH a global git identity: with (2) in place, deleting only (1)'s two `config` lines (applied: `grep` of `], lone);` config lines → 0) reddened exactly 1 of 8 tests — the `lone` test, `Expected: <0> Actual: <128>`, byte-identical to CI's failure. That the mutation reproduces CI on a machine that HAS an identity is the proof the hermetic env works. Restored → 8/8 green."
impact_analysis: |
  Test-only. No product code, no gate, no hook script changed. The one
  behavioural change is that this test file no longer reads the developer's
  global/system git config, so it now behaves the same on a laptop, the VPS
  and the CI runner.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "test file only; `flutter test test/scripts/discipline_hook_main_sync_e2e_test.dart` 8/8 green hermetically; mutation reddens exactly the failing CI test with the CI error shape." }
  - { tier: 12, name: "Client → server contract (here: CI → main)", status: verified, evidence: "CI job log for run on fafec56a read directly: 6429 passed / 1 failed, the single failure is this test at `_commit` (:74) from :176. No other failure in any of the four red runs (plan-review R1 cross-checked all four run ids)." }
---

## Summary

A test fixture committed to a throwaway git repo without an author identity.
It passed wherever a global `~/.gitconfig` identity existed — every developer
machine — and exited 128 on the CI runner, which has none. `main` stayed red
for four runs.

## Root cause

`_cleanEnv()` stripped `GIT_*` variables but not the ambient config git
reads from `HOME`, so the test's outcome depended on the machine. The
`lone` repo is built inside the test body rather than in `setUp`, and it
alone never got the `user.email`/`user.name` the setUp repos get.

## Fix

Give `lone` its identity, and make the file hermetic
(`GIT_CONFIG_GLOBAL` → a `useConfigOnly` file, `GIT_CONFIG_NOSYSTEM=1`,
`EMAIL` removed) so a local run is the CI run.

## Class, and the sweep

First recorded instance of "fixture depends on ambient global git config".
23 test files create fixture commits; the other 22 pass CI today, which is
the evidence none of them currently commits identity-less. The class is
entered in the debugging skill's bug-class table so the next fixture author
sees the hermetic pattern.

## Regression test

See `regression_test_planned` — mutation-proven, 1 red of 8, CI-identical.
