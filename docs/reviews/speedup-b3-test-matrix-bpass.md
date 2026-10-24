---
branch: speedup-b3-test-matrix
date: 2026-10-11
reviewed_at: 2026-10-11T08:40:00+05:30
staged_against: d363553e (staged diff at review time: 12 files, platform)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind, read-only except backup/restore mutation of four named files, exhaustive command list)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# B-pass — release-cycle speedup B3 (`speedup-b3-test-matrix`): parallel whole-file test matrix (OI-275)

Reviewed diff: the staged diff against base `d363553e` (12 files, `platform`). **Result: 0 P0, 0 P1, 4 P2, 5 P3.**
The reviewer's summary: the partition and gate logic held up (the real 1,057-file tree split 265/264/264/264, disjoint and complete against
an independent `git ls-files` listing); the four P2s are test gaps proven by surviving mutants in the workflow WIRING and exit-status
propagation, which the new tests never exercised, plus one wrong doc claim. 26 mutations: 7 survived (8 counting one equivalent).
**All 9 findings were fixed in this batch** (no deferrals; the one informational item is recorded with its measurement hook), then
re-verified by mutation (see the author's Round B). Triage is the author's; the founder may re-triage any row. Numeric claims below
are the reviewer's, each re-checked by the author where the check is cheap (the doc claim in finding 4 by `git grep`, the wording in
finding 7 by reading the lib docstring, the baseline in finding 6 by re-running the read-only `gh api` script: N=20, median 13.12 min,
min 10.9, max 13.9).

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** `.github/workflows/test.yml` (`flutter test $FILES ...`, the last line of the shard step); harness `test/contracts/ci_unit_test_matrix_shape_test.dart` (`flutter() { ...; return 0; }`, `runStep`).
- **claim:** Nothing proved that a failing `flutter test` fails the shard step. The stub always returned 0 and the source check was `contains(...)`, which a longer line still satisfies. Mutant T14 (append `| tee test.log`) left all 84 tests green; GitHub's default shell is `bash -e {0}` with no pipefail, so the step would exit with `tee`'s status: a red suite gives a green shard, a green gate and a mergeable PR. Same class: `|| true`, a step-level `continue-on-error: true`, a step-level `if:` (mutant T12, `if: false` on the shard step, left 84 green: zero tests run anywhere under a green gate).
- **verification:** append ` | tee test.log` to the `flutter test` line and run the shape test: "+11: All tests passed!".
- **status:** fixed — `runStep` takes a `flutterRc`; the new test "a RED `flutter test` fails the step" runs the extracted script under `sh -e` (no pipefail, mirroring GitHub) with `flutter` returning 7 and requires a non-zero exit; "runs ONLY its own files" now pins the EXACT last line of the step instead of `contains`; a new test pins that neither job carries `continue-on-error` and that the shard job and its steps carry no `if:`. Mutants T12, T14, T14b (`|| true`), T15 (step-level `continue-on-error`), T16 (trailing command) are now RED.

## Finding 2 — P2 — guard_without_its_mirror (gate wiring)
- **file:line:** `test.yml` `unit-tests-gate` (`needs`, `if`, `env: SHARDS_RESULT: ${{ needs.unit-test.result }}`); test `ci_unit_test_matrix_shape_test.dart` gate group (`extraEnv: {'SHARDS_RESULT': result}`).
- **claim:** The gate behaviour test injected `SHARDS_RESULT` itself, so the YAML that feeds it was unpinned. Survivors: T1 (`SHARDS_RESULT: ${{ job.status }}`, which is always `success` at step time, so the gate can never fail), T3 (`if: false` on the gate's only step: green job, skipped step), T2 (`continue-on-error: true` on `unit-test`, which GitHub reports as `success` in `needs.*.result`). This is the exact hole the file header says the file exists to prevent.
- **verification:** change the env line to `${{ job.status }}` and run the shape test: all green.
- **status:** fixed — new test pins the exact env line, that `SHARDS_RESULT:` is assigned exactly once, and that the gate's only expressions are `!cancelled()` and `needs.unit-test.result`; the no-`continue-on-error` / no-step-`if:` test also pins the gate's single job-level `if: ${{ !cancelled() }}` at 4-space indent. Mutants T1, T2, T3 and an `always()` replacement are RED.

## Finding 3 — P2 — guard_without_its_mirror (matrix shape, silent file drop)
- **file:line:** `test.yml` `strategy.matrix`; test "the shard count is the matrix length (strategy.job-total), never a second literal".
- **claim:** That test only inspected the text of the `dart ...` invocation. Mutant T6 added `variant: [a, b]` under `matrix:`: `strategy.job-total` becomes 8, the shard list stays [1,2,3,4], shards 1-4 of 8 cover 529 of 1,057 files, so 528 files (50%) run nowhere while `Unit Tests` is green and the other 529 run twice.
- **verification:** `for i in 1 2 3 4; do dart scripts/ci_test_partition.dart $i 8 | wc -l; done` gives 133, 132, 132, 132.
- **status:** fixed — `_matrixKeys` asserts the matrix has exactly one key, `shard` (no `include`/`exclude`, no second dimension; an inline or `fromJson` matrix throws instead of passing silently), and a second test pins that the only expressions in the shard job are `matrix.shard` and `strategy.job-total`. Mutants T6 and T6b (`include:`) and an extra `github.ref_name` expression are RED.

## Finding 4 — P2 — doc claims vs reality (who reads the check name)
- **file:line:** `test.yml` header comment; `docs/architecture/hooks.md` (the B3 paragraph); `docs/naming_conventions.md` (the `Unit Tests (gate)` row); the shape test header. These contradicted the master plan (`docs/plans/2026-10-10-release-cycle-speedup.md` §4: "run-level conclusion only; no programmatic job-name consumer exists").
- **claim:** Four places said `/build-apk` Gate 3.5 and `scripts/reconcile_ci.dart` "rely on / read" the `Unit Tests` check name. They do not: Gate 3.5 does `gh run list --workflow "Test & Analyze"` on the run-level conclusion, `reconcile_ci.dart` has `_workflowName = 'Test & Analyze'`. Only `scripts/safe_pr_merge_lib.dart` reads the name. Someone could rename the gate believing the other two would flag it.
- **verification:** `git grep -n "Unit Tests" -- .claude/commands scripts/reconcile_ci.dart scripts/gh_run_lib.dart` returns nothing (re-run by the author).
- **status:** fixed — all four reworded: `safe_pr_merge_lib.dart` requires the name green; Gate 3.5 and `reconcile_ci.dart` read the run-level conclusion of `Test & Analyze`, which any red shard turns red with or without the gate.

## Finding 5 — P3 — asserted_fixture_value / guard_without_its_mirror (discovery)
- **file:line:** `scripts/ci_test_partition_lib.dart` (`followLinks`, `isTestFilePath`); tests "the REAL test/ tree" and "discoverTestFiles".
- **claim:** Two mutants survived (0 red of 103): L6 `followLinks: true` (files behind a directory link would be listed, which Flutter's `_findTests` does not) and L7 `endsWith('test.dart')` with no underscore (the same 1,057 on the real tree, so only a fixture can see it). The real-tree "complete" test compared `discoverTestFiles()` with itself; the plan promised an independent oracle.
- **verification:** change the suffix and run `dart scripts/ci_test_partition.dart 1 1 | wc -l`: 1057; the partition test: +103 passed.
- **status:** fixed — fixtures `contest.dart` / `mytest.dart` / `latest.dart` / `test.dart` (must be absent; `_test.dart` itself present) and a symlinked DIRECTORY (must not be traversed); and a real-tree test that diffs discovery against `git ls-files -z --cached --others -- test` (tracked plus untracked, ignore rules not applied), an enumerator that shares no code with the directory walk. Mutants L6 and L7 are RED, and a new mutant L9 (discovery silently drops `*_e2e_test.dart`, invisible to every other assertion) is RED only through the oracle.

## Finding 6 — P3 — misleading or dangling doc references
- **file:line:** `docs/architecture/hooks.md` cited `test.yml:120` (the deno job, now line 183+) and `test.yml:61` (the analyze step); it also cited `docs/audit/speedup-b3-test-matrix.closure.yaml`, which was not on disk; the test.yml comment gave a baseline median of 13.12 and a threshold of 9.84 that appeared nowhere else, with no file preserving the 20 run ids, so abort condition (1) could not be re-derived later.
- **verification:** `ls docs/audit/speedup-b3-test-matrix.closure.yaml`: no such file; grep for `13\.12|9\.84` under `docs`: no files.
- **status:** fixed — the two line numbers replaced by job/step names; the closure ledger now exists and carries the 20 baseline run ids with each run's wall-clock (entry BASE-1), and the workflow comment names it.

## Finding 7 — P3 — wording: "shard i % N" for 1-based shards
- **file:line:** `test.yml` header, `scripts/ci_test_partition.dart` header, `docs/architecture/hooks.md`, `docs/naming_conventions.md` (the `test shard` row), and the lib header.
- **claim:** They said "file i goes to shard `i % N`". Shards are 1-based and the rule is `(i % N) + 1` (the lib's `shardFiles` docstring was right). Cosmetic; the reviewer diffed all four shards against an independent `sed -n 'k~4p'` of the sorted union: identical.
- **status:** fixed — every place now says "the 0-based file i goes to shard `(i % N) + 1`".

## Finding 8 — P3 — missing_input (unverifiable, fails loudly)
- **file:line:** `test.yml` shard step (`FILES="$(dart ...)"`).
- **claim:** `$(...)` captures all of stdout. If the Dart CLI printed any non-path line on a fresh runner (a first-run banner, a hook line), it would become an argument to `flutter test`. Locally the CLI printed exactly 1,057 clean path lines for shards 1-4; the failure would be loud (Flutter reports the file missing), not silent. Not verifiable without a runner.
- **status:** fixed — the step now rejects any line that does not match `^test/[A-Za-z0-9_./+-]+_test\.dart$` BEFORE calling flutter, with an `::error::` naming the line. Three mutants RED: the check removed; the pattern loosened to `^test/`; the inner `|| true` dropped (which fails the step on GOOD input under `-e`, so the new positive test "a list of well-formed paths is NOT mistaken for stray output" and the existing hand-off test catch it).

## Finding 9 — P3 — informational: load skew proxies and cost
- **claim:** The re-balance trigger is a slowest/fastest ratio above 1.5x. Two weak proxies are already near it: process-spawning test files per shard 12/18/15/18 (1.5x); files declaring a `@Timeout` of 3 minutes or more 13/23/18/19 (1.77x). The abort conditions do not include runner-minute cost: 5 jobs instead of 1 means 3 extra setups per run.
- **status:** accepted, no code change required — the first matrix run logs each shard's duration and the 1.5x trigger is evaluated there (ledger entry U7-9). Runner-minute cost is not a constraint: the repository is PUBLIC (standard-runner minutes are free, master plan §0) and the extra setup runs in parallel, adding no wall-clock. Recorded in the closure ledger as `verified_clean`.

## Lenses that returned clean (reviewer's evidence, condensed)
- **Partition laws on the real tree:** 1,057 `_test.dart` files (`git ls-files -s -- test`); shards 265/264/264/264, rc 0, union 1,057, `sort | wc -l` equals `sort -u | wc -l` (disjoint), union diffs empty against `git ls-files` (complete); no symlinks, no directory named `*_test.dart/`, no path outside `[A-Za-z0-9_./+-]`; the 5 golden tests are in the list and excluded only at run time; `_findTests` read in the local SDK (3.41.4, equal to the CI pin): `endsWith('_test.dart') && isFileSync`, `followLinks:false`, matching the lib. Each list is about 14 KB, far under ARG_MAX.
- **Consumers of the old single job:** `Unit Tests` matches by exact string only (`safe_pr_merge_lib.dart:25`); the only `needs:` on `unit-test` is the gate; `check_ci_flutter_version.dart` counts 6 pins all `3.41.4` (the gate has no Flutter setup); `pre_push_matches_ci_invocation_test.dart` takes the first non-comment `flutter test` line, which is the shard line; `test.yml` is the only workflow file.
- **`evaluateCheckRuns` and shards:** a red or pending shard is refused by the "other checks" rule, a shard with only cancelled runs by the cancelled-only rule, a later success supersedes an earlier failure; `matrixJobNameTemplates` is documentation-only at runtime and says so.
- **Docs:** 18.3% = (469−383)/469 s; 13.12 × 0.75 = 9.84; job counts 9 and 11 match the workflow; no deferral euphemisms in the added lines.
- **blast_radius.yaml:** first match wins; `scripts/ci_test_partition.dart` and `_lib.dart` are `platform` and precede the `scripts/**` catch-all; `.github/workflows/test.yml` is `platform`.
- **function_exception_swallow, secrets_in_tree, unawaited_no_error_sink:** not applicable or 0 hits (no `functions.invoke`, no credential-shaped strings in the added lines, no `unawaited`; the gate passes `needs.*.result` through `env:`, not interpolated into the script).
- **missing_input:** `test/` exists with 1,057 files; the closure ledger and the plan-review record were not yet present at review time (now written); no `docs/plan-reviews/speedup-b3*` was tracked.
- **Not verified (no network or runner):** GitHub Actions behaviour (context availability, `continue-on-error` reporting in `needs.*.result`, default shell, `strategy.job-total`), the 13.12 baseline (re-derived by the author, see above), CI first-run stdout. The author separately checked the contexts against docs.github.com on 2026-10-11 (recorded in the closure ledger).

## Mutation log
### Reviewer (against the staged blobs; backups verified byte-identical before and after; no compile-error mutants)
| # | File | Mutation | Test file(s) | Red |
|---|---|---|---|---|
| L1 | ci_test_partition_lib.dart | `== shard - 1` to `== shard` | partition test (103) | 71 |
| L2 | ci_test_partition_lib.dart | `(i + 1) % total == shard - 1` | partition test | 56 |
| L3 | ci_test_partition_lib.dart | loop `length - 1` (skip last file) | partition test | 70 |
| L4 | ci_test_partition_lib.dart | drop `..sort()` | partition test | 10 |
| L5 | ci_test_partition_lib.dart | `isFileSync` to `e is! File` | partition test | 1 |
| L6 | ci_test_partition_lib.dart | `followLinks: true` | partition test | 0 — SURVIVED (finding 5) |
| L7 | ci_test_partition_lib.dart | `endsWith('test.dart')` | partition test | 0 — SURVIVED (finding 5) |
| L8 | ci_test_partition_lib.dart | safe-path regex allows space | partition test | 2 |
| C-a | ci_test_partition.dart | `unsafe.isNotEmpty && false` | partition test | 1 |
| C-b | ci_test_partition.dart | drop `shard > total` | partition test | 1 |
| T1 | test.yml | `SHARDS_RESULT: ${{ job.status }}` | shape + safe_pr + pre_push_matches + concurrency (84) | 0 — SURVIVED (finding 2) |
| T2 | test.yml | `continue-on-error: true` on `unit-test` | same four files | 0 — SURVIVED (finding 2) |
| T3 | test.yml | gate step `if: false` | shape (11) | 0 — SURVIVED (finding 2) |
| T4 | test.yml | gate `if: ${{ always() }}` | shape | 1 |
| T5 | test.yml | `shard: [1,2,3,3]` | shape | 1 |
| T6 | test.yml | add `variant: [a, b]` dimension | shape + safe_pr (76) | 0 — SURVIVED (finding 3) |
| T7 | test.yml | hard-coded `4` in the invocation | shape | 1 |
| T8 | test.yml | drop `\|\| exit 1` | shape | 0 — EQUIVALENT under `-e` (kept as the explicit form; the comment says why `test -n` is not redundant with it) |
| T9 | test.yml | `[ -n $FILES ]` unquoted | shape | 3 |
| T10 | test.yml | gate `= "failure"` | shape | 1 |
| T11 | test.yml | `fail-fast: true` | shape | 1 |
| T12 | test.yml | shard step `if: false` | same four files (84) | 0 — SURVIVED (finding 1) |
| T13 | test.yml | old `flutter test test/ ...` restored | shape + pre_push_matches (14) | 2 |
| T14 | test.yml | `flutter test ... \| tee test.log` | same four files (84) | 0 — SURVIVED (finding 1) |
| S1 | safe_pr_merge_lib.dart | `matrixJobNameTemplates = []` | safe_pr_merge_lib_test (65) | 1 |
| S2 | safe_pr_merge_lib.dart | skip "Unit Tests shard*" in the other-checks rule | safe_pr_merge_lib_test | 1 |

Surviving non-equivalent: L6, L7, T1, T2, T3, T6, T12, T14. Equivalent: T8.

### Author, Round B (after fixing every finding; each mutation confirmed APPLIED — exact single match, changed bytes — and the file restored and compared byte-identical; targeted file named per row)
| Mutation | Test file | Red |
|---|---|---|
| T1 gate env fed by `job.status` | shape | 1 |
| T2 `continue-on-error` on the shard job | shape | 1 |
| T3 gate step `if: false` | shape | 1 |
| T6 second matrix dimension | shape | 1 |
| T6b matrix `include:` entry | shape | 1 |
| T12 shard step `if: false` | shape | 1 |
| T14 `flutter test ... \| tee test.log` | shape | 2 (last-line pin, failing-flutter behaviour) |
| T14b `flutter test ... \|\| true` | shape | 2 |
| T15 step-level `continue-on-error` on the shard step | shape | 1 |
| T16 trailing command after `flutter test` | shape | 1 |
| F8a stray check removed | shape | 1 |
| F8b stray pattern loosened to `^test/` | shape | 1 |
| F8c stray `grep` loses its `\|\| true` | shape | 3 |
| F2b gate job `if` replaced by `always()` | shape | 3 |
| F3b hard-coded total next to a 4-leg matrix | shape | 1 |
| F2c extra expression (`github.ref_name`) reaches the shard script | shape | 2 |
| L6 `followLinks: true` | partition | 1 |
| L7 suffix `test.dart` | partition | 1 |
| L9 discovery drops `*_e2e_test.dart` | partition | 1 (only the git oracle) |

All eight reviewer survivors are now killed; the equivalent T8 is left as is. The shape test is 18 tests and the partition test 106 (124 together, all green).

## Founder triage notes
Triaged by the author on 2026-10-11: 9 accepted-and-fixed (one of them informational), 0 false alarms. The founder may re-triage any row.
