# CI sweep split: run the plan-generator sweeps only when they can change, and spread them when they run

- Date: 2026-11-24. Branch / worktree: `ci-sweep-split`. Founder decision (2026-11-24): option A plus option B, one plan.
- Tier: L (CI workflow + CI scripts). Blast radius is computed at execution with `dart run scripts/blast_radius_from_diff.dart <paths>`; expected `platform`.
- Execution mode (CLAUDE.md §4.12.7): **inline**, one session, this worktree. Not switched mid-batch.
- Lenses in scope (docs/audit/LENS_REGISTRY.md): L8 (contract test coverage gap), L18 (skipped test classification).
- Supersedes nothing. Extends `docs/plans/2026-10-10-release-cycle-speedup.md` §4 (B3) and revisits its §8 "path filters rejected" for ONE narrow case (§2 below).

## 1. Measured ground truth (2026-11-24; every number re-derivable)

1. CI wall clock. Baseline before B3: 13.12 min median, one job. B3 target: <= 9.84 min. Last 12 green runs of `Test & Analyze`: 14.7 to 26.5 min, most near 21 (`gh run list --workflow test.yml --limit 40`).
2. Where the time goes. Per-file span (first to last reporter line naming the file) from the four shard logs of three runs:

   | run | total span | `test/plan_generator/` | share | shard test-phase ends (s) |
   |---|---|---|---|---|
   | 45340748319 (PR) | 5749 s | 3939 s | 69% | 858 / 756 / 1225 / 1209 |
   | 45318405229 (PR) | 4905 s | 3239 s | 66% | 641 / 794 / 784 / 1190 |
   | 45343469169 (main) | 4202 s | 2780 s | 66% | 628 / 737 / 809 / 801 |

   In run 45340748319 the top 20 files are 3514 s of 5749 s, and 859 of 1072 files span <= 1 s. Spans come from an interleaved log (two files run at once per runner), so they are approximate; the ranking is stable across the three runs.
3. The heavy files (run 45340748319 / 45343469169, seconds): `titration_plateau_gate_test.dart` 587 / 367 (ONE `test()`, `@Timeout` 40 min); `day_floor_gate_pairs_p1_test.dart` 471 / 272; `day_floor_gate_pairs_p4_test.dart` 353 / 263; `day_floor_gate_rep30_test.dart` 248 / 226; `goal_training_gate_test.dart` 223 (4 tests). The same file varies up to 1.6x between runners.
4. Job setup is about 1 minute per shard (job 11.6 min vs. test phase 628 s, run 45343469169 shard 1).
5. The repository is PUBLIC (`gh repo view --json visibility`), so extra parallel jobs cost no Actions minutes.
6. Import closure. The transitive `import` / `export` / `part` closure of the 40 `test/plan_generator/**/*_test.dart` files is 287 files: 235 of the 669 `lib/**.dart` files (106 in `lib/core/services`, 33 `lib/shared/repositories`, 23 `lib/features/ai_coach`, 20 `lib/core/utils`), 9 `test/helpers/*` libs, `scripts/migration_ledger_hash_lib.dart`. Every one of the 37 timed sweep files has the same 235-file `lib/` closure (it is `plan_generator.dart`'s own).
6a. As of this SHA the closure contains ONE conditional import (`lib/core/services/razorpay_web_checkout.dart`) and one file with `part` directives; no closure file builds an `assets/` path by interpolation. `lib/` closure files name two assets by literal, both in `lib/core/services/seed_service.dart`: `assets/data/exercise_library.json` and `assets/data/food_database.json`.
7. Non-Dart inputs named by string literal in the non-`lib/` closure files: `assets/data/exercise_library.json`, `scripts/data/library_batch_c2_removals.json`, six `test/fixtures/*` files, two `test/plan_generator/*_report.md`, `lib/features/profile/screens/edit_profile_screen.dart` (read as text).
8. Replay of a prototype scope rule over the last 80 first-parent merges on `main`: 50 would run the sweeps, 30 would skip (about 43 / 37 after removing two prototype over-triggers: all of `assets/`, all of `.github/`). First triggering path: `lib/core/services` 22, `lib/core/constants` 8, `lib/shared/repositories` 6, `pubspec.lock` 4, `test.yml` 3.
9. Pins on the current shape: 18 files under `test/` name `workflows/test.yml`; `scripts/safe_pr_merge_lib.dart:23-50` (`requiredSuccessJobs`, `matrixJobNameTemplates`); `scripts/check_ci_flutter_version.dart`; `test/contracts/ci_unit_test_matrix_shape_test.dart`; `test/scripts/ci_test_partition_test.dart`; `test/scripts/pre_push_matches_ci_invocation_test.dart`.

## 2. Why the October rejection of path filters does not cover this

October rejected a docs-only skip of the WHOLE suite because tests read the docs directories and no per-file mapping existed. This plan skips ONLY `test/plan_generator/**`, on pull requests only, and derives the mapping from those files' own imports at run time. Every other test file still runs on every PR. Every push to `main` / `develop` runs everything.

## 3. Design

### U1. Scope decision: `scripts/ci_sweep_scope.dart` + `scripts/ci_sweep_scope_lib.dart`

Pure Dart, no package imports (it runs as plain `dart scripts/ci_sweep_scope.dart`, like the partition CLI, before `flutter pub get`).

- Sweep set: every `*_test.dart` under `test/plan_generator/` (directory rule, no list).
- Parser: STATEMENT-based and quote-aware (reads each directive up to its `;`): 38 directives in `lib/` and `test/helpers/` span several lines. `show` / `hide` / `as` are ignored (superset). `part of <library name>` without a URI is ignored.
- Closure: transitive `import` / `export` / `part` / `part of` closure of the sweep set over files in the checkout. `package:icanbefitter/x` resolves to `lib/x`; a relative URI resolves against the importing file; `dart:` and other `package:` URIs are leaves.
- A conditional import (`import 'a.dart' if (x) 'b.dart'`) follows EVERY branch (the default URI and each alternative): a superset, so it is safe. (Round 1: treating it as a fail-safe `run=true` would have made the rule always run, because §1.6a's file is in the closure.)
- Declared non-Dart inputs: a `const` list of files and directories in the lib (§1.7's list, with `test/fixtures/` as a directory, plus `assets/data/exercise_library.json`).
- Declared NON-inputs: a second `const` list of `(path, reason)` for a path literal found in a closure file that the sweeps provably never read. Its only entry is `assets/data/food_database.json`. Round 2 verified the reason: the sweeps read the exercise library straight from disk (`test/helpers/injury_floor_sweep_lib.dart:117` and about 15 sweep tests), and nothing under `test/helpers` or `test/plan_generator` uses `SeedService`, `rootBundle` or the food box; `seed_service.dart:353,381` is in the closure but never executed by a sweep.
- Always-run paths: `pubspec.yaml`, `pubspec.lock`, `dart_test.yaml`, `analysis_options.yaml`, `.github/workflows/test.yml`, `scripts/ci_sweep_scope*`, `scripts/ci_test_partition*`, anything under `test/plan_generator/`.
- Input: the changed paths, one per line on stdin. Output: exactly one line `run=true` or `run=false`, then reason lines on stderr.
- `run=true` when any changed path is in the closure, in a declared input, or an always-run path.
- Fail-safe direction is ALWAYS `run=true`: empty stdin; a changed `.dart` path under `lib/` or `test/` that no longer exists (deleted or renamed away); a relative or `package:icanbefitter/` URI the resolver cannot map to an existing file inside the closure walk; any exception (exit 0 with `run=true`, plus a `::warning::`).
- The workflow computes the changed paths only on `pull_request`, as `git diff --no-renames --name-only HEAD^1 HEAD` on the merge ref (`--no-renames` so a rename prints the OLD path too, which then hits the deleted-path fail-safe) (`fetch-depth: 2`). If `HEAD` does not have exactly two parents, or the event is not `pull_request`, the step does not call the script and runs the sweeps.

### U2. Partition: `scripts/ci_test_partition.dart <shard> <total> --set core|sweep`

- `core` = every test file NOT in the sweep set, sorted-path round-robin exactly as today.
- `sweep` = the sweep set, packed by longest-processing-time-first over a committed table `scripts/data/ci_sweep_durations.json` (seconds per file, from the runs in §1; a file absent from the table takes the table's median; a duration must be > 0; ties break by path). A table entry naming a file that no longer exists is a `::warning::` in the CLI and a failure only in the unit test, so a rename cannot turn every sweep leg red for a bookkeeping reason.
- The two-argument form without `--set` is removed (an unknown or missing `--set` is a usage error, exit 64), so no caller can silently get the old all-files list.
- By-product, not a new mode: `flutter test $(dart scripts/ci_test_partition.dart 1 1 --set core)` is a local run without the sweeps. `scripts/run_full_suite.sh` is NOT changed (it stays CI's full invocation).

### U3. Workflow `.github/workflows/test.yml`

- `unit-test`: matrix of 4, `--set core`, name unchanged (`Unit Tests shard n/N`).
- Job count: 4 core + 5 sweep = 9 matrix legs (today 4), so a PR run is 14 jobs and a `main` run 16 (the PR set plus `Plan-review record` and `Supabase Integration Tests`). Round 2: with 3 core legs a skipping PR would land at 9 to 11.5 min against an 11.5 min limit, a coin flip; 4 legs give about 7 to 8.5 min. The GitHub Free limit of 20 concurrent jobs is INFERRED from GitHub's published limits, not measured here; abort condition 5 measures the queue.
- New `sweep-test`: matrix of 5, name `Unit Tests sweep shard n/N`, `fail-fast: false`, `timeout-minutes: 30`, checkout `fetch-depth: 2`, same Flutter pin and `TZ`. Steps: checkout, Flutter setup, `pub get`, the strict index build (both UNCONDITIONAL: `test/scripts/ci_local_indexes_steps_test.dart:85-96` derives "a job that names `ci_test_partition.dart`" and requires the index build before it with no `if:`), the **scope step** (writes `run` to `$GITHUB_OUTPUT`), then the `flutter test $FILES --exclude-tags golden --reporter expanded` step with the same empty-list and stray-line guards as today, carrying the ONLY `if:` in the job (`steps.scope.outputs.run != 'false'`, so a missing output runs the tests).
- The scope step's shell is itself fail-safe, not only the script: `RUN=true` is the initial value, the whole decision runs inside `{ ...; } || RUN=true`, and ONE `echo "run=$RUN" >> "$GITHUB_OUTPUT"` is the last line. A failing `git`, a failing `dart`, a missing parent or any other non-zero status therefore runs the sweeps instead of turning the leg red. On a push event nothing writes `false`, so a push to `main` can never be green with the sweeps skipped.
- The scope decision is a STEP inside each sweep shard, not a separate job with `needs` / `if:`. A shard that is out of scope ends `success` after about two minutes with a `::notice::` and a job-summary line `sweeps skipped: no changed path is in the plan-generator closure`. Reason: a job-level `if:` produces `skipped`, which `safe_pr_merge_lib.dart` does not accept for `Unit Tests` and which has already cost this workflow one silent-pass incident (the `supabase-tests` comment at test.yml:494-502). With a step, the gate job's rule stays "every leg `success`".
- `unit-tests-gate` (`Unit Tests`): `needs: [unit-test, sweep-test]`, fails unless both results are `success`.
- `scripts/safe_pr_merge_lib.dart` `matrixJobNameTemplates` gains the sweep template.
- **"Green because skipped" is made visible where a reader decides on it.** `scripts/land_pr_lib.dart` needs ONE NEW `gh` call for this (`scripts/land_pr.dart:444` fetches only `commits/<sha>/check-runs`, which carry job conclusions, not step conclusions): the jobs of the workflow run, with their steps. It prints `sweeps: ran`, `sweeps: skipped (out of scope)` or `sweeps: unknown` on a line BEFORE `result:` (`parseResultWord`, `land_pr_lib.dart:57-72`, accepts the result only as the LAST non-empty line). A failed or unparseable call prints `sweeps: unknown` and never changes the result word or exit code. The fake `gh` in `test/helpers/land_pr_fixture.dart:108` exits 99 on an unknown argv, so it gains a fixture kind for the new call and every `land_pr` e2e test is re-run. CLAUDE.md §4.12.8 and §4.3 are reworded in this batch: on a PR, `ci-green` means "every test whose inputs the PR changed", and the full suite is what `main` runs. CLAUDE.md §4.4 rule 20 gains the sentence that a sweep red on `main` after an out-of-scope PR is a scope miss (P0 as before; the fix adds the missing input). No force switch is added: a PR that is out of scope has, by construction, nothing for the sweeps to say, and a scope miss is not something a reviewer would know to force.
- Commit order on the branch: B first (U2, U3 without the scope step, U4), then A (U1 and the scope step) as its own commit, so A can be reverted alone.

### U4. Split the heavy sweep files: DROPPED at execution (2026-11-24), `verified_clean`

Measured before touching a file: packed longest-first into 5 legs, the committed table (`scripts/data/ci_sweep_durations.json`, per-file median of the three runs in §1.2) gives leg loads of 649 / 651 / 644 / 644 / 651 s. The heaviest file (367 s median, 587 s on the slowest runner) is below one leg's load, so a split would not shorten any leg; it would only add harness setup and move about a dozen cited file names. This is the plan's own drop rule ((b) below). No sweep file is split or renamed. The original text is kept for the record:


- `titration_plateau_gate_test.dart` (one test, loops over 3 goals): body moves to `test/helpers/titration_plateau_gate_lib.dart`; three files, one goal each.
- `day_floor_gate_pairs_p1_test.dart`, `..._p4_test.dart`, `day_floor_gate_rep30_test.dart` (one test per tier, 4 tiers): two files each, two tiers each; each `_expected` row moves with its tier.
- `goal_training_gate_test.dart` (4 tests): split only if the measurement below shows no shared state between its tests.
- Before any split, per file: (a) confirm no test depends on state a previous test in the same file created (the 2026-08-10 revert cause); (b) measure the fixed cost of `SweepHarness.install()` so a split that adds more setup than it parallelises is dropped; (c) `grep -rn "<old file name>"` over `test/ docs/ scripts/ .claude/ lib/` and repoint every citation (CLAUDE.md §4.9 "moving code breaks source-grep contracts"). Mandatory repoints found in round 1: `docs/sot_registry.yaml` (Gate 42 resolves cited test paths on disk) and `lib/shared/repositories/plan_engine/CLAUDE.md`.
- `test/plan_generator/injury_sweep_b_singles_test.dart:20-31` says the letters in the injury-sweep names are a CI sort key for the round-robin deal. Under the weighted sweep partition that comment is false: it is rewritten (the names stay; nothing is renamed there), and its block map at `:56-66`, which reads sibling sweep files as text, is left untouched because no injury-sweep file is split.
- Proof of equivalence: every expected tuple and assertion is moved verbatim; the count of `test(` executions before and after is equal (reporter `+N`), on the same SHA.

### U5. Tests and repoints

New, each mutated once per CLAUDE.md §4.4 rule 21 (mutation named, reddened-test count recorded):
- `test/scripts/ci_sweep_scope_test.dart`: (1) EXHAUSTIVE: for every file in the real closure, a one-path change yields `run=true`; (2) a change to a file outside the closure (a real one, e.g. a nutrition screen) yields `run=false`; (3) each fail-safe branch; (4) DERIVED CHECK over EVERY closure file, `lib/` included: each string literal that looks like a repo path (`^(assets|test|scripts|lib|docs|backups|supabase)/`) is in the closure, the declared-inputs list or the declared-non-inputs list, so a new asset or fixture read reddens the test until someone classifies it; (4a) a conditional import, including one spread over several lines, contributes all of its branches; (4b) the not-two-parents and non-PR branches of the workflow step run the sweeps; (5) the replay count on a pinned commit range.
- `test/scripts/ci_test_partition_test.dart`: `core` and `sweep` are disjoint and their union is the full file list for every shard count; LPT determinism; a table entry naming a missing file fails; removed two-argument form exits 64.
- `test/contracts/ci_unit_test_matrix_shape_test.dart`: both matrices, `pub get` and the index build with no `if:`, the single `if:` on the test step, the gate's two-result rule, and the scope step's exact shell block EXECUTED with a failing `git`, a failing `dart` and a one-parent `HEAD` (each must write `run=true`).
- Explicit step before editing: `grep -rn "ci_test_partition\|Unit Tests shard\|workflows/test.yml" test scripts docs .claude lib` and classify EVERY hit as repoint / unaffected, recorded in the closure ledger. Round 1 named, beyond the list below: `hook_gate_placement_test.dart`, `gate_wiring_args_required_test.dart`, `land_pr_lib_test.dart`, `ci_reconcile_state_lib_test.dart`, `gate_input_family_e2e_test.dart`, `test/helpers/land_pr_fixture.dart`, `scripts/check_plan_review_record_exists.dart`, `scripts/run_full_suite.sh`, `docs/blast_radius.yaml:383-388`, `docs/architecture/hooks.md:174`.
- `test/scripts/land_pr_lib_test.dart`: the three `sweeps:` lines, and that none of them changes the result word or exit code.
- Doc ripple for the reworded "CI green" meaning (round 2; no test greps these sentences): `CLAUDE.md:42,138,217`, `docs/architecture/process-invariants-detail.md:89,307,314`, `docs/architecture/hooks.md:143,367,371`, `.claude/skills/code-review/SKILL.md:211`, `docs/adr/0013-blast-radius-tiered-gating.md`, the header comments of `scripts/land_pr.dart:10-15` and `scripts/land_pr.sh:13-18`, `scripts/pre-push.sh:56`; then `dart run scripts/check_context_artifact_budget.dart` and `--record` if intended.
- Repoint (not loosen): `safe_pr_merge_lib_test.dart`, `pre_push_matches_ci_invocation_test.dart`, `ci_local_indexes_steps_test.dart`, `ci_workflow_concurrency_test.dart`, `check_ci_flutter_version.dart`, `docs/blast_radius.yaml` (the two new scripts at `platform`), `dart_test.yaml` comment, `docs/architecture/hooks.md`, the `test.yml` header comments.

## 4. Known residual risks (named, not hidden)

1. A sweep input reached by a COMPUTED path (string interpolation) or a runtime plugin is invisible to both the import walk and the literal scan. Net under it: every `main` push runs the sweeps, and `/build-apk` requires a green `main`.
2. A scope miss shows as a red `main` after the merge, not on the PR (founder accepted 2026-11-24). Each such miss gets a diagnose doc and the missing input added to the declared list in the same fix.
3. About 55% of PRs still run the sweeps (§1.8). U2 + U4 are what shorten those.

## 5. Pre-committed abort conditions (written before the first run; any one reverts the batch)

Baseline, measured 2026-11-24: **20.95 min** median end-to-end wall clock of the last 20 green PR runs (min 16.9, max 26.5; run ids 45346045498 45345918116 45340748319 45329544020 45329322740 45323573052 45318405229 45316339438 45310790809 45309492414 45219287552 45213692484 45213388336 45146559383 45060634211 45058334654 45007589041 45005323510 44998296576 44993118794).
1. A PR that skips the sweeps takes more than **11.5 min** (median of its first 3 runs; expected 8 to 9.5).
2. A PR that runs the sweeps takes more than **16.8 min** (median of its first 3 runs; expected about 12 to 14).
3. Any test red in the new layout that is green in the old layout on the same SHA.
4. Sweep shard skew (slowest / fastest test phase, MEDIAN of 3 runs, because one file already varies 1.6x between runners) above 1.6x after one re-pack of the table.
5. Median queue delay (`started_at - created_at`) of the 9 matrix legs over the first 5 runs is above 120 s (today's figure is recorded with the baseline).

## 6. Out of scope

- Reducing the plan generator's import closure (touches plan-engine code; needs an explicit founder instruction).
- Running `Supabase Integration Tests` on pull requests (separate defect: one shared live test account, needs a concurrency group; an OI is minted at execution).
- Local hooks, `run_full_suite.sh`, pre-push.

## 6a. Review round 1 (2026-11-24, context-blind, Sonnet): 0 P0, 3 P1, 5 P2, all adopted above

- P1-1 the conditional `pub get` / index build broke an existing pin: both are unconditional again, only the test step has an `if:`.
- P1-2 the literal scan skipped `lib/`: it now covers every closure file; `food_database.json` is classified explicitly.
- P1-3 a skipped sweep looked like a pass to `land_pr`: `sweeps:` line and the CLAUDE.md rewording.
- P2: `--no-renames`; the wider repoint list; `sot_registry.yaml` and the plan-engine CLAUDE.md; a numeric queue condition; the merge-ref semantics are as assumed.
- Own finding while verifying P3: a conditional import IS in the closure, so the original fail-safe would have disabled option A entirely; now all branches are followed.
- NOT adopted: splitting into three plans. The P1s were all in U1; U1 is now its own commit, revertible alone, and the founder asked for A plus B together. If round 2 raises new material issues in U1, U1 is cut from this batch and B ships alone.

## 6b. Review round 2 (2026-11-24, context-blind, Sonnet, on the post-round-1 text): converged, 0 P0, 0 P1, 5 P2, 4 P3, all adopted above

- 4 core legs and absolute minute limits (the 3-leg limits were inside the noise); condition 4 on a 3-run median.
- `land_pr` needs a new API call, the `sweeps:` line goes before `result:`, the fake `gh` needs a fixture.
- The scope step's shell wrapper is fail-safe, and the test executes that block.
- Statement-based import parser; the full doc-ripple list; table validation; `food_database.json` confirmed a non-input.

## 7. Closure

Six units (U1 to U5 plus the docs ripple), so `docs/audit/ci-sweep-split.closure.yaml` with a `terminal_state:` per unit (CLAUDE.md §4.2), plus the plan-review record `docs/plan-reviews/ci-sweep-split.md` and a B-pass before the merge.
