---
bug_id: c3f8e1
date: 2026-07-28
batch: gate-ci-env-hermetic
status: fixed
blast_radius: platform
symptom: >
  main went RED on 10dffc90. Two PRE-EXISTING gate e2e tests failed in CI while
  passing locally and through both pre-commit and pre-push: the gate they spawn
  inherited CI's real GITHUB_EVENT_PATH, whose `before` names a commit that does
  not exist in the test's throwaway repo.
concept: gate_test_environment_hermeticity
sot_registry_entry: not_applicable
writers: >
  test/scripts/plan_review_record_gate_e2e_test.dart:32 _cleanEnv;
  test/scripts/gate_input_family_e2e_test.dart:32 _cleanEnv
readers: >
  scripts/check_plan_review_record_exists.dart:264 reads GITHUB_EVENT_PATH as the
  range-base fallback — the consumer of the leaked value
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/gate_e2e_env_hermetic_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  a spawned-subprocess test helper that filters only GIT_* while the subprocess
  reads GITHUB_* ; inheriting ambient environment into a test that asserts on
  process behaviour
proposed_fix: >
  Scrub GIT_*, GITHUB_* and PUSH_BEFORE in both e2e helpers. Each test
  re-supplies via `extra:` only the keys its scenario declares, so the spawned
  gate sees a declared environment rather than an inherited one.
regression_test_planned: >
  test/contracts/gate_e2e_env_hermetic_test.dart — source-grep, PRESENCE-ONLY by
  necessity and labelled as such: the trigger is an ambient env var that only CI
  sets, and Dart cannot mutate its own process environment, so no local test can
  discriminate behaviourally. The real verification was a manual reproduction
  (below), which IS discriminating.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — test tooling only" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "GitHub Actions is the affected surface; the failing job is `Analyze & Unit Tests` on run 30331184609, and the `Plan-review record` job on that same run PASSED — the gate itself was correct throughout" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "reproduced the CI condition locally with a synthetic GITHUB_EVENT_PATH whose `before` is unreachable: the pre-fix test (taken from main via git show) FAILS exactly as CI did; with the fix, 75 tests pass under that same hostile env plus a bogus PUSH_BEFORE, and 71 under a clean env" }
impact_analysis: >
  CI-only. No product code changed and no user-facing behaviour is affected. The
  gate under test behaved CORRECTLY in both environments — it refused a range
  base it could not resolve, which is the P2-1 guard working. The defect is that
  the test handed it a base from another repository. Fix can only make the tests
  stricter about what they declare.
---

# CI's own environment leaked into a gate the test spawned

## What was wrong

`10dffc90` gave `check_plan_review_record_exists.dart` a range-base fallback
chain: `PUSH_BEFORE` → `GITHUB_EVENT_PATH` → `HEAD^1`. That is correct for the
dedicated CI job.

But **every** GitHub Actions job has `GITHUB_EVENT_PATH` set, including
`Analyze & Unit Tests`. The gate e2e suites spawn the real gate inside a
throwaway git repo, and their `_cleanEnv()` filtered only `GIT_*`. So the gate
read the real push event, whose `before` is `9d5e9d31` — a commit that exists in
`AVYA` and not in `/tmp/keystone_gate_e2e_xxxx`.

`_isCommit()` correctly returned false → `suppliedButUnresolvable` → hard fail.
Two tests that assert exit 0 got exit 1.

**The gate was never wrong.** It refused an unresolvable base, which is exactly
the P2-1 behaviour added in the same commit after round-1 review found the
silent-narrowing bug. The test simply fed it a base from a different repository.

## Why every local gate stayed green

`GITHUB_EVENT_PATH` does not exist outside Actions. The full suite passed at
pre-commit, passed again at pre-push, and passed twice more in the worktree —
all legitimately. This is `feedback_local_ci_env_divergence` in its purest form:
the variable that triggers the bug is one only CI sets.

## The recurring shape

Third instance of one class in two days, each in a different direction:

| | leak | direction |
|---|---|---|
| `feedback_mistake_git_hook_env_leak` | `GIT_DIR` from a hook | into a test's own git |
| earlier this batch | `ALLOW_RAW_GIT=1` from my command | down into a spawned hook |
| this one | `GITHUB_EVENT_PATH` from CI | into a spawned gate |

The invariant worth remembering: **a test that spawns a process must declare
that process's environment, not inherit it.** Filtering a prefix is a denylist,
and a denylist is only ever correct until the subprocess learns to read one more
variable — which is precisely what `10dffc90` taught this one to do.

## Fix

Both helpers now scrub `GIT_*`, `GITHUB_*` and `PUSH_BEFORE`. Every test already
passes the keys it wants through `extra:`, so nothing else changed.

## Verification

Reproduced before fixing, rather than assumed:

1. `git show main:test/scripts/plan_review_record_gate_e2e_test.dart` → run with a
   synthetic `GITHUB_EVENT_PATH` whose `before` is unreachable → **fails**, same
   two tests as CI.
2. Same env, fixed helpers → **75 tests pass**, exit 0, zero failures — with a
   bogus `PUSH_BEFORE=deadbeefcafe` on top.
3. Clean env → **71 tests pass**, confirming no regression to the local path.
