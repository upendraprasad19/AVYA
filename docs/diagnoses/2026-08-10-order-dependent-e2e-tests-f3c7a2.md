---
bug_id: f3c7a2
date: 2026-08-10
batch: order-dep-test
status: fixed
blast_radius: feature
symptom: >-
  Three tests in worktree_config_integrity_e2e_test.dart pass when the whole file
  runs but FAIL when run individually — `--plain-name "warn-only"` gives 1 failed,
  the full file gives 6 passed. Worse, one of them ("PASS again after the
  documented repair") passes VACUOUSLY in isolation: it asserts a repair against a
  repo that was never corrupted. Surfaced as a red CI job when a 3-shard matrix
  split the file across runners.
concept: test_isolation_intra_file
sot_registry_entry: not_applicable
writers:
  - "test/scripts/worktree_config_integrity_e2e_test.dart:157 — the ONLY writer of
     `core.worktree` in the file (test index 2, 'FAIL when core.worktree is injected')"
readers:
  - "test/scripts/worktree_config_integrity_e2e_test.dart:172 — 'the corruption is
     observable as wrong toplevel resolution' (its own comment said 'still set from
     the previous test')"
  - "test/scripts/worktree_config_integrity_e2e_test.dart:181 — '--warn-only exits 0
     while corrupt BUT still reports the violation' (the one CI caught)"
  - "test/scripts/worktree_config_integrity_e2e_test.dart:195 — 'PASS again after the
     documented repair' (unsets a key the test never set)"
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/worktree_config_integrity_e2e_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Grepped test/ for other files whose assertions depend on a previous test's side
  effect. Two candidates hand-checked (test/scripts/safe_merge_test.dart:150,185 and
  test/contracts/repository_pattern_test.dart:35) are defensively self-healing — each
  re-establishes its own precondition. Known exposure is this one file. Stated as a
  known-exposure figure, NOT a census: the sharded run sampled ONE partition, so
  "only one test broke" describes where N=3's cut lines happened to fall, not the
  population.
proposed_fix: >-
  Each dependent test establishes its own precondition (`git config core.worktree`)
  instead of inheriting it. The repair test sets the key FIRST and then unsets it, so
  "unset restores health" is asserted against a repo that was actually corrupted.
regression_test_planned: >-
  The file itself is the regression test, and the discriminating check is running each
  test STANDALONE — which is what nothing did before. Verified after the fix:
  `--plain-name` for all three now passes individually, and the whole file is still
  6/6. Before the fix, "warn-only" standalone was 1 FAILED.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "3 tests made self-sufficient; `flutter test --plain-name` passes for each of the three individually (was 1 FAILED for 'warn-only'), and the full file remains 6/6." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive involvement; the fixture is a scratch git repo." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "No client/server surface — this exercises scripts/check_worktree_config_integrity.dart against a temp repo." }
impact_analysis: >-
  Two distinct harms, and the second is worse than the red build. (1) A developer
  debugging the worktree-integrity gate by name got a FALSE RED on correct code —
  the test failed for reasons unrelated to the gate. (2) The repair test passed
  VACUOUSLY whenever it ran without its predecessor, asserting that unsetting an
  unset key restores health. That is exactly the Gate-44 class rule 24 exists to
  make impossible — a test that passes whether or not the thing works — living
  inside the test file for the gate added to close a P0. It went unnoticed because
  the whole file always ran together locally and in CI; only sharding, which split
  the file, exposed it. Latent since 2026-08-09.
related_bugs:
  - "a4f7c2 — the core.worktree corruption this test file was written to gate. The
     order dependency was introduced with that file and shipped with it."
recurrence: >-
  Not a recurrence of a product bug class, but it IS the third instance this session
  of `feedback_green_check_input_set_width`: a green check whose input set was
  narrower than the thing it certified. Here the certification is "the gate works"
  and the input set was "the whole file, in declaration order" — so the suite could
  never observe that three of its tests carried no precondition of their own. The
  general lesson: a test suite that is only ever run as a whole has never had its
  per-test isolation tested, and "all tests passed" does not distinguish a test that
  passed from one that could not have failed.
---

# Order-dependent e2e tests in the worktree-integrity gate

## What happened

`worktree_config_integrity_e2e_test.dart` has six tests. Index 2 injects
`core.worktree` into a scratch repo. Indices 3, 4 and 5 all *read* that state
without setting it — index 3's own comment said so out loud: "core.worktree is
still set from the previous test."

That is invisible while the file always runs whole, in declaration order. It
stopped being invisible when a 3-shard CI matrix split the file: `_shardSuite`
slices WITHIN a suite, so shard 2 received indices 4 and 5 — the readers —
without index 2, the writer. Shard 2 went red on
`Expected: contains 'FAIL' / Actual: ''`.

## Why it is a real defect independent of sharding

Sharding was reverted, and the defect stayed. On `main`, today:

```
flutter test <file> --plain-name "warn-only"   ->  1 FAILED
flutter test <file>                            ->  6 passed
```

So anyone debugging this gate by name got a false red on correct code.

## The worse half

Index 5 asserts "PASS again after the documented repair (unset restores
health)". Run without its predecessor it unsets a key that was never set, then
asserts the gate is green — and passes. **Vacuously.**

That is the Gate-44 class: a test that passes whether or not the thing under
test works. It was living inside the test file for the gate written to close a
P0, and rule 24 exists precisely to make that class impossible.

## Fix

Each dependent test establishes its own precondition. Index 5 sets the key
first, *then* unsets it, so the repair is asserted against a repo that was
actually corrupted.

## The transferable part

A suite that is only ever run as a whole has never had its per-test isolation
tested. "All tests passed" does not distinguish a test that passed from one that
*could not have failed* — and running a single test by name is the cheapest
check that tells them apart.
