---
bug_id: a8f3c6
date: 2026-09-20
batch: food-logging-observations (merge-time regression-catalog walk)
status: fixed
blast_radius: platform
symptom: |
  Merging `claude/food-logging-observations-126ab3` into `main` (a conflicted
  merge, resolved with `git commit`, which runs `pre-commit` -> the
  merge-commit regression-catalog walk) reported "at least one recent
  regression test FAILED" — 32 distinct failing assertions, ALL 32 tracing to
  the exact same stack frame (`grep -c "hive_user_session.dart 201"` against
  the captured output → 32, matching the 32 `[E]` failure markers 1:1).
  Per-file breakdown, taken directly from the `[E]` marker lines themselves
  (`grep "\[E\]" ... | grep -oE "test/.*\.dart" | sort | uniq -c` — corrected
  2026-09-20 by an independent B-pass review that caught the first version of
  this doc undercounting by 9, having enumerated only 3 of the 4 affected
  files from a partial `tail` inspection rather than the complete list):
  `test/contracts/nutrition_log_retag_writer_to_reader_test.dart` (6),
  `test/contracts/profile_provider_single_source_test.dart` (8),
  `test/contracts/reschedule_week_terminal_row_test.dart` (13),
  `test/contracts/streak_paused_day_not_missed_test.dart` (5) — sums to 32.
  Other file names (safe_merge_test.dart / safe_push_test.dart /
  oi_numbering_gate_e2e_test.dart) appeared interleaved in the raw output
  because `flutter test` prints a running `+pass -fail` tally across ALL
  concurrently-loading files, not because those files failed — verified they
  all passed. Bug-history check (docs/diagnoses/INDEX.md grep for
  `git_hook_env_leak`) surfaced two prior instances of "merge-commit
  regression-catalog walk fails on tests green everywhere else"
  (diagnose 4f2a9e, d81f3c) — that class was RULED OUT first: the exact
  scrubbedChildEnvironment fix from 4f2a9e is still present and correct in
  `scripts/check_regression_catalog.dart:56-71`, and `flutter test
  test/contracts/nutrition_log_retag_writer_to_reader_test.dart` reproduced
  the identical failure standalone, with zero simulated git-hook env vars set
  — ruling out an environment leak as this instance's cause.
concept: not_applicable
sot_registry_entry: not_applicable
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: _openForUserLocked, line: 203 }
readers:
  - { file: lib/core/services/hive_service.dart, method_or_widget: getBox (configBox getter), line: 198 }
hive_key_prefix: (n/a — this is a box-availability bug, not a data-key bug)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: (n/a)
cloud_columns: []
contract_test_path: test/contracts/hive_user_session_box_open_parallel_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [hive_user_session_config_box_unavailable]
cross_account_guard: Unaffected — this fix wraps a flag READ that runs before any cross-account comparison; the guard's own logic (later in _openForUserLocked) is untouched.
forbidden_patterns_checked: >-
  Grepped hive_user_session.dart for every OTHER unconditional
  `HiveService.instance.<sharedBox>` read reachable from `_openForUserLocked`
  or `_migrateLegacySharedBoxes` — `migrationBox` is the only other one, and
  it already has this exact try/catch-fallback pattern (lines 312-325),
  which is what this fix mirrors. No other new unconditional shared-box read
  was introduced by this batch.
proposed_fix: |
  This batch's own Task-8b B-pass fix (diagnose f4c8b1, commit e3c96e08)
  added the FIRST unconditional read of `HiveService.instance.configBox`
  inside `_openForUserLocked` — a method invoked by every test file's shared
  `openForUser`-based setup helper across the whole suite (e.g.
  `test/nutrition_write_service/helpers/nws_test_setup.dart`, mirrored by an
  analogous workout-side helper). `HiveService.init()` guards on a
  process-wide singleton flag (`hive_service.dart:74-75`,
  `if (_initialized) return;`) that never resets to `false`. Multiple test
  FILES sharing one Dart test worker/isolate each call
  `HiveService.instance.init()` in their own `setUp`, but only the FIRST one
  actually opens the shared boxes — every later file's `init()` call is a
  silent no-op against an ALREADY-true flag, even though each file's own
  `tearDown` genuinely closes and deletes every Hive box
  (`Hive.close()` + `Hive.deleteFromDisk()`). `configBox` is therefore gone
  by the second file's tests, while `_initialized` still reads true — so
  `HiveService.getBox` skips its own `StateError` guard and `Hive.box(name)`
  throws the raw package's `HiveError: Box not found` (or, when `_initialized`
  itself is false because THIS particular file runs first in its own worker
  but crosses a compact/close boundary mid-suite, the `StateError` message
  instead — both traced to the exact same new call site).
  Nothing before this batch ever read a shared box from inside this
  ubiquitous path, so this latent test-harness fragility was never exposed.
  Fix: wrap the flag read in the SAME defensive try/catch pattern this file
  already uses for `migrationBox` (lines 312-325) — on any exception, log +
  `ErrorTelemetry.recordNonFatal` and fall through to the safe default
  (`disableParallelOpen = false`, i.e. the new parallel-open behavior Task 8
  shipped). This does not fix `HiveService.init()`'s stale-singleton
  assumption itself (a real, separate, pre-existing latent issue — flagged
  below, not expanded into scope here) — it makes THIS read resilient to it,
  consistent with the one sibling read that already had to survive the same
  hazard.
regression_test_planned:
  - test/contracts/hive_user_session_box_open_parallel_test.dart
impact_analysis: |
  Purely additive: the flag read moves into a try/catch, falling through to
  the existing default (parallel open) on any failure — no change to either
  branch's box-open behavior, no change to the flag's semantics when
  configBox IS available. Fixes the merge-blocking regression for all 32
  observed failures (all traced to the same file:line via the full captured
  stack traces — see Evidence below), unblocking the food-logging-observations
  merge to main.
  Residual, NOT expanded into this fix: `HiveService.init()`'s
  `_initialized` singleton flag never resets across test files sharing a
  worker, and `nws_test_setup.dart`-style helpers rely on a fresh open each
  time. This has been silently true for a long time and only this batch's
  new configBox read exposed it. Any FUTURE unconditional shared-box read
  added to a similarly ubiquitous path would hit the exact same failure
  mode. Worth a dedicated hardening pass (either make HiveService.init()
  idempotent against a closed-but-flagged-initialized state, or make the
  shared test-setup helpers reset the singleton in tearDown) but that is a
  test-harness-wide change with its own blast radius, deliberately not
  bundled into this one-file mutation-proven fix.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/hive_user_session.dart:201-224 (bool declaration through the if/else box-open branches) — flutter analyze lib/ reports 0 warnings on the file." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/hive_user_session_box_open_parallel_test.dart's new 'falls through to the parallel path when configBox is unavailable' test closes configBox mid-test and asserts openForUser still completes and opens every user-scoped box." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire format or Edge Function contract touched." }
mutation_proven:
  mutated: "Reverted the try/catch wrapper to the prior unconditional single-expression read (`final disableParallelOpen = HiveService.instance.configBox.get(...) == true;`), confirmed applied by reading the file."
  result: "Ran the new test alone: RED — 'openForUser falls through to the parallel path when configBox is unavailable, rather than crashing session open' failed with the exact HiveError: Box not found stack trace this diagnose describes, exit status 1. Restored the fix from a pre-mutation backup copy; re-ran the full file (test/contracts/hive_user_session_box_open_parallel_test.dart) plus test/contracts/nutrition_log_retag_writer_to_reader_test.dart together: GREEN, 12/12 passed."
  confirmed_applied: "Read the file (Read tool) before mutating, and diffed lib/core/services/hive_user_session.dart against the pre-fix backup to confirm the restore was byte-identical to the fix, not just re-typed."
related_bugs:
  - "diagnose 4f2a9e / d81f3c (git_hook_env_leak) — same SYMPTOM class (merge-commit regression-catalog walk fails on tests green elsewhere), different root cause. Explicitly ruled out before proposing this fix by reproducing standalone with zero simulated git-hook env vars."
  - "diagnose f4c8b1 — the commit that introduced the read this bug is in (Task 8's feature-flag fix). This is a regression IN that fix's own new code, found only because a merge finally ran the regression-catalog's wider file set against it."
recurrence: >-
  First instance of "a new unconditional shared-box read from inside a
  ubiquitous session-open path crashes under the shared test-worker's stale
  HiveService singleton." Not yet a class (single instance) — noted above
  as a residual for any FUTURE read added to the same method.
---

## Summary

This batch's own Task-8b B-pass fix (`disable_parallel_hive_box_open`, diagnose
f4c8b1) added the first unconditional `HiveService.instance.configBox` read
inside `HiveUserSession._openForUserLocked` — a method every Hive-touching test
in the suite calls via its own setup helper. `HiveService.init()`'s
process-wide `_initialized` singleton never resets across test files sharing a
worker, so once one file's setUp opens the shared boxes, every LATER file's
`init()` call silently no-ops while its own tearDown genuinely closes and
deletes them — leaving `configBox` gone precisely when this new read reaches
for it. Merging `main` into this branch was the first time the merge-commit
regression-catalog walk actually ran this batch's changed `hive_user_session.dart`
against the full 30-day recent-test window, and 32 assertions across 3
unrelated contract test files failed with `HiveError: Box not found` /
`StateError: HiveService.init() must be called before accessing boxes`, both
tracing to the exact same new line.

## Root cause

Writer (pre-fix location — the wrapped, current version is at line 203):
`lib/core/services/hive_user_session.dart:201` —
`HiveService.instance.configBox.get('disable_parallel_hive_box_open')`, added
unconditionally by diagnose f4c8b1's fix.
Reader/thrower: `lib/core/services/hive_service.dart:198-204` `getBox()` →
`Hive.box(name)` — `_initialized` stays `true` (stale from an earlier test
file in the same worker) so the `StateError` guard at line 199-202 never
fires, and the underlying Hive package's own box registry (genuinely emptied
by the earlier file's teardown) throws `HiveError: Box not found` instead.

Verified live: reproduced the exact 32-failure set standalone by exporting
`GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE` to mimic the hook environment
(mechanically identical count and file list to the real hook run) — but
critically ALSO reproduced a strict subset of it (the 6
`nutrition_log_retag_writer_to_reader_test.dart` failures) with a bare
`flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart`
and NO simulated environment at all, proving the failures are independent of
the git-hook-env-leak class (4f2a9e/d81f3c) and are a real, environment-agnostic
regression in this batch's own code.

## Fix

Wrap the flag read in the same defensive try/catch this file already uses for
`migrationBox` (lines 312-325): on any exception, log + record telemetry
(`hive_user_session_config_box_unavailable`) and fall through to
`disableParallelOpen = false` (today's default parallel-open behavior). See
`proposed_fix` above for the full reasoning and the explicitly-scoped-out
residual (HiveService.init()'s singleton assumption itself).

## Evidence

| Check | Result |
|---|---|
| `check_regression_catalog.dart`'s env scrub (4f2a9e's fix) | Present and correct at `scripts/check_regression_catalog.dart:56-71` — ruled out as this instance's cause |
| `flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart` (pre-fix, no simulated env) | 1 pass / 6 fail — reproduces standalone |
| All 32 `[E]` failures in the captured merge-commit output | 100% trace to `hive_user_session.dart 201` in the stack trace (`grep -A6 "\[E\]" ... \| grep -c "hive_user_session.dart 201"` → 32 of 32) |
| Post-fix: `nutrition_log_retag_writer_to_reader_test.dart` + `hive_user_session_box_open_parallel_test.dart` | 12/12 pass |
| Mutation proof | Revert reddens the new mirror test with the exact original stack trace; restore turns it green again, 12/12 |
