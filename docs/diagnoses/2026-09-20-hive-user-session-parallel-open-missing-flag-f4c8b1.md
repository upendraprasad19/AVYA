---
bug_id: f4c8b1
date: 2026-09-20
batch: food-logging-observations (fix round, B-pass reviewer A finding 1)
status: fixed
blast_radius: platform
symptom: |
  Task 8 of this batch (commit 5bb7a995) changed HiveUserSession's 7
  user-scoped box opens from a sequential `for` loop to
  `Future.wait(userScopedBoxRoots.map(openOne))`. `hive_user_session.dart`
  is `platform`-tier in docs/blast_radius.yaml, whose `requires:` list
  includes `feature_flag` (root CLAUDE.md §4.6: any payment/sync/auth/AI
  prompt/plan-generator change must default the new path behind a
  kDebugMode gate, Hive flag, or RemoteConfig, with the old path preserved
  verbatim). No such gate existed — the parallel path was unconditional,
  with no way to revert to the well-understood sequential behavior without
  a code change and redeploy. Found by B-pass reviewer A (lens 3,
  blast_radius_mismatch), verified via a repo-wide grep for
  feature_flag/kDebugMode/RemoteConfig hits in the diff (zero).
concept: auth_hive_owner_agreement
sot_registry_entry: auth_hive_owner_agreement
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: _openForUserLocked, line: 157 }
readers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: ensureOpenedForCurrentSession, line: 123 }
hive_key_prefix: (n/a — this fix gates the OPEN of the 7 user-scoped boxes, not a data key)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: (n/a)
cloud_columns: []
contract_test_path: test/contracts/hive_user_session_box_open_parallel_test.dart
ist_handling: []
provider_invalidations:
  - { provider: hiveSessionOwnerProvider, added_in_this_batch: false, reason: "Unaffected — this fix wraps the box-open loop only; currentOwnerListenable is still set after either branch completes, exactly as before Task 8." }
telemetry_op_types:
  success: []
  failure: [hive_user_session_open_box_corrupt]
cross_account_guard: Unaffected — the guard runs strictly after box-open completes (either branch), on _currentOwnerHash/_currentOwnerFullId, which this fix does not touch.
forbidden_patterns_checked: []
proposed_fix: |
  Add a `disable_parallel_hive_box_open` opt-out kill-switch, read from
  `HiveService.instance.configBox`, matching this repo's established
  opt-out convention (`disable_bg_restore`, `disable_sync_debounce`,
  `disable_plan_integrity_reconciler`). When set, restore the exact
  pre-Task-8 sequential `for` loop over `userScopedBoxRoots`, calling the
  same `openOne` closure Task 8 already extracted. When unset (default),
  keep the parallel `Future.wait` path Task 8 shipped.
regression_test_planned:
  - test/contracts/hive_user_session_box_open_parallel_test.dart
impact_analysis: |
  Purely additive: an `if/else` around the existing loop body, both
  branches calling the same `openOne` closure. No behavioral change when
  the flag is unset (the default) — the parallel path Task 8 shipped is
  unchanged. When set, restores byte-identical open semantics to the code
  before Task 8 (same per-box try/catch corruption-recovery, same box
  set, same order). No new Hive keys, no sync/cloud impact, no provider
  invalidation change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/hive_user_session.dart:201-208 — flutter analyze lib/ reports 0 warnings on the file." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/hive_user_session_box_open_parallel_test.dart's new 'disable_parallel_hive_box_open restores the sequential fallback' test opens all 7 boxes with the flag set and asserts Hive.isBoxOpen(...) true for every one." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched — this fix gates a local Hive box-open path only." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire format or Edge Function contract touched." }
mutation_proven:
  mutated: "Changed the sequential fallback's loop from `for (final root in userScopedBoxRoots)` to `for (final root in userScopedBoxRoots.skip(1))`, confirmed applied by reading the file, so the fallback path would silently skip the first box."
  result: "Ran the file's test suite: RED — 'disable_parallel_hive_box_open restores the sequential fallback and still opens every box' failed with `Expected: true Actual: <false>` on the first box's Hive.isBoxOpen check, exit status 1 (2 passed, 1 failed). Reverted the mutation; re-ran the full file: GREEN, 5/5 tests passed, exit status 0."
  confirmed_applied: "Read the file (Read tool) before and after each edit to confirm the loop's iterable matched the intended mutation, not just grepped for a string."
---

## Summary

Task 8 of this batch parallelized `HiveUserSession`'s 7 user-scoped Hive box opens for
cold-start perf. `hive_user_session.dart` is a `platform`-tier path per
`docs/blast_radius.yaml`, and platform-tier changes require a `feature_flag`
(root CLAUDE.md §4.6) — none existed, so there was no way to revert to the
known-safe sequential behavior without shipping a new build.

## Root cause

Task 8's implementer (and its own task review) treated this as a pure performance
refactor with no behavioral risk, since "no box here has a documented open-order
dependency on another." That's true of the boxes' *content*, but the blast-radius
registry classifies the *file* `hive_user_session.dart` as platform-tier regardless —
it is the sole gate on cross-account Hive box ownership (`auth_hive_owner_agreement`),
and any change to it carries the registry's structural `feature_flag` requirement, not
a requirement conditioned on the reviewer's confidence in this specific change's safety.

## Fix

Added `disable_parallel_hive_box_open`, read from `HiveService.instance.configBox`,
following this repo's established opt-out kill-switch convention. When set, the
sequential pre-Task-8 loop runs (same `openOne` closure, same per-box corruption
recovery, same box order). When unset (the default), the parallel path Task 8 shipped
runs unchanged.

## Verification

- New behavioral test: with the flag set, `HiveUserSession.openForUser` still opens
  all 7 user-scoped boxes (`Hive.isBoxOpen` true for each namespaced box name).
- New source-shape test: confirms the guard (`configBox.get('disable_parallel_hive_box_open')`)
  is present in the file, so a future edit can't silently drop the escape hatch.
- Mutation proof: broke the sequential fallback (skipped the first box in the loop) —
  the new functional test caught it (`Expected: true Actual: <false>`); reverted, green again.
- `flutter analyze lib/` — 0 warnings (45 pre-existing infos, none in this file).
- Existing test `openForUser source uses Future.wait for the box-open loop` still
  passes unchanged — confirms the default (unset) path is untouched.

## Files changed

- Modified: `lib/core/services/hive_user_session.dart` (added the `disable_parallel_hive_box_open`
  guard around the existing `Future.wait`/sequential-loop choice).
- Modified: `test/contracts/hive_user_session_box_open_parallel_test.dart` (added the fallback
  functional test + the guard source-shape test).
- Created: this diagnose-doc.
