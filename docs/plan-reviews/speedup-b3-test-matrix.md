---
branch: speedup-b3-test-matrix
date: 2026-10-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/speedup-b3-test-matrix-bpass.md
---

# Plan review — release-cycle speedup B3: parallel whole-file CI test matrix (`speedup-b3-test-matrix`)

The plan is `docs/plans/2026-10-10-release-cycle-speedup.md` (master plan, four batches B1..B4; this record covers B3,
§4 of that plan). Founder directive 2026-10-09: "push and merge and CI is taking a lot of time everyday; plan and
implement all of these." B1 (`speedup-b1-prepush`) merged as PR #98 (`d363553e`); this batch is built on it.

## Why this record exists

B3 rewrites the `unit-test` job of `.github/workflows/test.yml` (pinned `platform`) into a four-leg matrix plus a gate job,
adds `scripts/ci_test_partition{,_lib}.dart` (pinned `platform` in `docs/blast_radius.yaml` by this batch) and changes
`scripts/safe_pr_merge_lib.dart` (`platform`). Blast radius `platform`, so CLAUDE.md §4.12 requires two context-blind
plan-review rounds plus a B-pass before the merge to `main`. The PR touches `.github/`, so it merges with
`--allow-workflow-change` after the founder has read the workflow diff.

## Rounds

The two rounds reviewed the master plan; B3 exists as its own batch because of round 1's split. Only what the plan itself records
is attributed to a round; the abort-condition thresholds and the aggregator's `if: !cancelled()` semantics are the author's design
(plan §4), re-checked by this batch's B-pass rather than credited to a review.

| Round | Reviewed | Outcome |
|---|---|---|
| 1 | Master plan v1 (one 7-unit batch), fresh Sonnet reviewer with no session context, told to verify every claim against code and live state | **needs-rework.** 0 P0, 11 P1 (plan header: "Round 1 (11 P1) forced the split into four batches"). The test matrix became its own batch (B3) because it edits the `test.yml` jobs that B4 reshapes afterwards and B4 needs B3's `Unit Tests` aggregator (plan §1). |
| 2 | Master plan v2 (four batches, round 1 applied), a SECOND fresh reviewer, same brief | **needs-rework, localized.** 0 P0, 8 P1, all spec fixes; "a third full round is not warranted unless the edits change a design". The ones that shaped B3 (plan §4, §6): declared `@Timeout`s do not predict wall clock (per-file spans are at most about 23 s; a file declared 14 minutes is invisible in the log) and a simulated longest-processing-time packing produced 262/263/262/263 files anyway, so the partition is sorted-path round-robin with no weights parser; the path-filter hit rate was recomputed (7 of the last 40 merges touch no code path, and the docs directories they touch are read by tests), so path filters are rejected; P1-4: the aggregator named `Unit Tests` must be extensible by B4. All applied in plan v3. |

## Ground truth (verified against code and live state, 2026-10-11)

- Baseline: 20 successful PR runs of `Test & Analyze`, 2026-10-06..10 (read-only `gh api .../actions/runs/<id>/jobs`): median wall clock 13.12 min, min 10.9, max 13.9; every run had 5 jobs and the `Unit Tests` job was the critical path (median 13.03 min). The ids are in `docs/audit/speedup-b3-test-matrix.closure.yaml` (entry BASE-1), so abort condition (1), at most 9.84 min, can be re-derived.
- Test tree: 1,057 `*_test.dart` files (`git ls-files -s -- test`), shards 265/264/264/264, disjoint and complete, no path outside `[A-Za-z0-9_./+-]`, no symlinks, the 5 golden tests in the list and excluded only at run time by `--exclude-tags golden`.
- `flutter test <files>` discovery was read in the local SDK (3.41.4, equal to the CI pin): `_findTests` keeps `endsWith('_test.dart') && isFileSync` with `followLinks: false`, which the partition's discovery mirrors.
- GitHub context availability (docs.github.com, 2026-10-11): `strategy.job-total` and `matrix` are allowed in a job `name:` and in a step `run:`; `needs` is allowed in `jobs.<id>.steps.env` and in `jobs.<id>.if`; `needs.<id>.result` is one of `success | failure | cancelled | skipped`.
- Consumers of the old single job: `safe_pr_merge_lib.dart` matches `Unit Tests` by exact string; `/build-apk` Gate 3.5 and `scripts/reconcile_ci.dart` read the run-level conclusion of `Test & Analyze` (no job name); `check_ci_flutter_version.dart` counts 6 Flutter pins, all `3.41.4` (the gate job has no Flutter setup).
- Within-suite sharding (`--total-shards`) was tried and reverted on 2026-08-10 (18.3% under a 25% floor; it also broke an order-dependent test). This batch hands each job WHOLE files, so a file is never split and a shard compiles only its own files.

## Execution evidence (post-plan, after the B-pass and the first PR run)

The ENTIRE suite was run as the four CI shards, one after another, each exactly as the workflow runs it (TZ pinned to IST, golden tag excluded; the file list fed in chunks of 110 only because Windows `cmd.exe` caps a command line at 8,191 characters, which a Linux runner does not): 8,712 passed, 9 skipped, 0 failed, on the FINAL tree after every B-pass fix (1,057 files: 265 + 264 + 264 + 264). The single-job CI run at the base commit had 8,588 passed and 9 skipped; the difference, 124, is exactly B3's own tests (partition 106, shape 18). The B-pass (`docs/reviews/speedup-b3-test-matrix-bpass.md`) found 0 P0, 0 P1, 4 P2 (test gaps proven by surviving mutants, plus one wrong doc claim) and 5 P3, all fixed in this batch with every survivor re-killed by mutation. The shard seconds measured locally ran under heavy contention and are NOT a skew measurement.

**The first PR run** (run 38165332016, PR #104, head 1f976876, the merge of this branch with main after B2): all jobs green. End-to-end wall clock 4.32 min against the pre-committed limit of 9.84 (baseline median 13.12 min), 67% under the baseline; shards 3.53 / 4.03 / 4.12 / 4.17 min (skew 1.18x against 1.5x); every job started within 2 s of the run's creation. The shards ran 8,876 tests with 9 skipped, which is exactly main's single-job count on the base of the PR (8,752 passed, 9 skipped) plus this batch's own 124 tests. Conditions 1 and 2 are met; condition 3 (a PR run and a main run in flight together) did not occur and is carried in the closure ledger as U7-10 with its reopen trigger.

## Convergence

**Converged for B3.** Round 2's remaining items were localized spec fixes (no design change), all applied; the B-pass then reviewed the BUILT code independently and its findings were closed with mutation evidence. Residual risk, stated plainly: the speed-up was an estimate until the first PR run, and that run met the pre-committed abort conditions it could be judged on (wall clock 4.32 min against the 9.84 limit; every test of the single job ran and passed; skew 1.18x), recorded in the closure ledger (entry U7-9) BEFORE the merge; the queueing condition for a PR run and a main run in flight together was not observable on it and stays open as U7-10, to be checked at the first overlap, and a breach there reverts the batch. The workflow itself cannot be executed locally: its shell logic is run with `dart` and `flutter` stubbed, and its wiring is pinned by name, but GitHub's context evaluation is verified against the documentation only until the first run. OI-275 stays OPEN: its item D, the allow-rule `Bash(sh scripts/safe_pr_merge.sh:*)`, is a settings change that is the founder's to make.
