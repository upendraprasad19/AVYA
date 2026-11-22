# Plan: make CI fail a PR whose pubspec.lock the pinned Flutter cannot honour (`oi520-enforce-lockfile`, OI-520 option a)

Version: v1 (draft diff built; not yet reviewed). Date: 2026-11-22. Branch `oi520-enforce-lockfile`, base `origin/main` `c8a19ef4`.
Decision: the founder chose option (a) of OI-520 ("Add a CI check so a bad Dependabot lock fails its PR?" "Yes, add CI check", 2026-11-22). Option (b), a Dependabot configuration that cannot regenerate the lock outside the pinned SDK, was not chosen and is not known to exist: the `.github/dependabot.yml` pub block has no key that selects a Dart version (UNVERIFIED against GitHub's documentation, which no reviewer can read offline).

**Tier:** `.github/workflows/test.yml` is `platform` (`docs/blast_radius.yaml:403`); the new test is under `test/**`; the other files are `docs/**` (`feature`, `:579`). Branch maximum `platform`, so process tier M (CLAUDE.md §4.12.6): the full ×2 plan review, the B-pass and the record. Not L. **Execution mode (§4.12.7):** inline, one worktree, one writer; every reviewer is read-only.
**Lenses in scope (`docs/audit/LENS_REGISTRY.md`):** L1 writer/reader drift (the install step and every reader of it), plus the guard-without-its-mirror and missing-input lenses of the code-review skill.

## Problem (from OI-520 and PR #314)

The three Dependabot lock commits of 2026-11-21 wrote a `pubspec.lock` that Flutter 3.41.4 (Dart 3.11.1), the version CI, Vercel and `.fvmrc` pin, cannot honour. CI stayed green on them because every one of its six `Install dependencies` steps runs a plain `flutter pub get`, which re-resolves such a lock instead of failing. PR #314 re-committed a lock the pinned SDK resolves. Nothing prevents a repeat: the Dependabot exemption of the merge gate checks the branch prefix, the commit authors and manifest-only paths (`scripts/check_plan_review_record_exists.dart:611-621`), never whether the lock honours the SDK.

## Change

1. `.github/workflows/test.yml`, job `analyze` (check name `Analyze`): the `Install dependencies` step runs `flutter pub get --enforce-lockfile` instead of `flutter pub get`, with a comment that names the failure and its fix. Nothing else in the workflow changes: the other five install steps stay plain.
2. `test/contracts/ci_lockfile_enforced_test.dart` (new): pins the SHAPE of that guard and kills eleven mutants of it in memory (flag dropped, `|| true`, an extra argument, `if:` or `continue-on-error:` on the step or on the job, a plain `pub get` step before it, the step moved after `flutter analyze`, the job renamed, `Analyze` dropped from `requiredSuccessJobs`).
3. Process documents of a platform-tier change: this plan, the plan-review record, the B-pass review, the closure ledger; OI-520 moved to `docs/audit/closed_issues.md` with `closes-oi: OI-520` in the commit.

Why the `Analyze` job: it is in `requiredSuccessJobs` (`scripts/safe_pr_merge_lib.dart:24`), so a red `Analyze` makes `safe_pr_merge.sh` refuse (`:233-241`); it has no `if:` and runs on every PR and every push to `main`; it is one of the shortest jobs (1m27s on the PR #314 run; `Audit Gates` 1m25s, `Deno` 1m29s); and it is the first job in the file. The flag is placed on the existing step, not added as a second step, because a step that follows a plain `pub get` checks a lock that was just rewritten and passes on any lock (the test pins this).

## Facts and how each was measured (reviewers re-verify every row)

| # | Fact | Measured by |
|---|---|---|
| F1 | `analyze` job: `actions/checkout`, `subosito/flutter-action` (`flutter-version: '3.41.4'`), `Install dependencies` = `flutter pub get`, `Flutter analyze`. Six install steps in the file, at lines 60, 144, 321, 436, 533, 618 on `c8a19ef4`; no `run:` precedes the first one in the job | `.github/workflows/test.yml:45-63` |
| F2 | `Analyze` is the first entry of `requiredSuccessJobs`; a required job that is not `success` makes the wrapper refuse (`evaluateCheckRuns`, `:233-241`). `main` has NO required status checks (CLAUDE.md §4.3), so a merge made in the GitHub web UI is not stopped by this guard | `scripts/safe_pr_merge_lib.dart:23-29,233-241`, CLAUDE.md |
| F3 | The exact CI command on the pinned SDK (Flutter 3.41.4), run in a scratch folder holding only `pubspec.yaml` + `pubspec.lock` at each revision: current `main` `c8a19ef4`: exit 0, lock hash `B990F94F…` before and after; pre-#314 lock (`20c0e40b`): exit 65, "Would change 31 dependencies." and "Failed to update packages.", lock hash `CED167B3…` unchanged (the flag never writes the lock); each of the three Dependabot-authored lock commits (`ddddc428`, `ffcd7aaf`, `971a67e4`): exit 65 | scratch folders, `$LASTEXITCODE`, `Get-FileHash` |
| F4 | Dependabot history: 13 PRs from the `pub` ecosystem (`dependabot/pub/*`) since 2026-05-21, none opened since 2026-08-10, none open now; three were merged on 2026-11-21 (#9, #20, #21) after a rebase on that day; the next scheduled run is Monday 2026-11-23 06:00 IST (`.github/dependabot.yml:13-19`); `open-pull-requests-limit: 5` | `gh pr list --state all --author app/dependabot`, file read |
| F5 | Readers of the install step's text: `test/scripts/ci_local_indexes_steps_test.dart:225,237` find `flutter pub get` by substring, in the `unit-test` and `audit-gates` jobs ONLY (not touched). `scripts/check_ci_flutter_version.dart` reads the `flutter-version` literals, not run strings. `scripts/vercel_build.sh:41` and `.claude/commands/build-apk.md:348` run their own plain `pub get` and are left alone (a Vercel production build or a release build must not start failing on a lock that re-resolves) | `git grep -n -E "pub get|enforce-lockfile" -- test scripts .claude/commands .github` |
| F6 | `.github/workflows/test.yml` is not a tracked context artifact of the budget gate (`scripts/check_context_artifact_budget.dart` mentions it only in a comment); no doc describes the Analyze job's install step | `grep`, `git grep` |
| F7 | The merge-to-main record gate is independent of this change: it runs only on a push to `main` (`test.yml:421-446`) and its Dependabot exemption lives in `scripts/plan_review_record_lib.dart:189,200-202` and `check_plan_review_record_exists.dart:611-621`, none of which this change touches | `git diff --stat origin/main...HEAD` |
| F8 | The local pre-push `flutter analyze --no-fatal-infos` (`scripts/pre-push.sh:139`) and every `dart run scripts/*` run a `pub get` that REWRITES a lock the pinned SDK cannot honour, so a developer meets the same drift as a dirty tree before CI does | PR #314 plan, F10 |
| F9 | The new test: 14 cases pass on the draft (the real workflow and anchors, eleven mutants killed, the comment case); `flutter analyze --no-pub` on it: no issues | `flutter test --no-pub test/contracts/ci_lockfile_enforced_test.dart` |
| F10 | `--enforce-lockfile` is also what fails a PR that edits `pubspec.yaml` without regenerating the lock (the lock "would change"): wanted, and the local pre-push analyze already regenerates it | flag semantics, F3 |
| F11 | END-TO-END proof (to be filled before the merge): a throwaway draft PR carrying this workflow and the OLD lock (`20c0e40b:pubspec.lock`), never merged, must show `Analyze` red at `Install dependencies` with the guard's message while the green PR shows it green. Evidence to cite: the two run URLs and the failing log line | `gh run view` |

## Claims the reviewers must try to break

C1. After this change a PR whose `pubspec.lock` the pinned Flutter would change fails `Analyze` at its first `run:` step with exit 65 and an unchanged lock, and `safe_pr_merge.sh` then refuses to merge it; a PR whose lock is honoured behaves exactly as before (same packages resolved, same analyze).
C2. The guard cannot be pre-empted inside the job: no step before it resolves packages (F1), and the test pins "first `run:` step", "exactly one resolving step" and the exact command.
C3. Nothing else changes: five install steps stay plain, Vercel and `/build-apk` are untouched, the Dependabot exemption and the record gate are untouched (F5, F7).
C4. The test fails when the guard is weakened in any of the eleven ways it lists, and a REAL mutation of `test.yml` (not only the in-memory ones) reddens it (Verification plan).
C5. `Analyze` stays a required merge check only while it is in `requiredSuccessJobs`; the test pins that, so the guard cannot silently become advice.
C6. The change closes OI-520's option (a) as written there: the CI step exists on the pinned SDK; it fails a lock that would change; the mutation proof is the test's mutants plus the real mutation run (CLAUDE.md §4.4 rule 24 governs new `check_*.dart` GATES, and this adds none, so no ledger row in `docs/audit/gate_test_ledger.yaml`); the Dependabot exemption still works for a manifest-only PR (F7: a Dependabot PR whose lock is honoured passes `Analyze` and the record gate is exempt as before).

## Risks stated, not hidden

R1. **Every Dependabot `pub` PR whose lock needs a newer Dart than 3.11.1 goes red from now on.** That is the purpose, but it is a recurring chore: the fix is on the PR branch, `flutter pub get` with the pinned Flutter, commit `pubspec.lock`, push (the workflow comment says so); a later Dependabot rebase can overwrite it and the lock is then regenerated again; or the Flutter pin moves everywhere in one batch (`scripts/check_ci_flutter_version.dart` pins the literals). Frequency so far: 13 PRs in six months (F4). Not a regression: the lock was already unusable, now it is visible at the PR.
R2. A merge in the GitHub web UI is not stopped (F2): `main` would run red on `Analyze`, and `scripts/reconcile_ci.dart` warns at the next session start. Branch protection with a required `Analyze` check is the founder's GitHub setting and is not part of this change; it would turn the guard from "the wrapper refuses" into "GitHub refuses".
R3. A `pub.dev` outage or a transient network error fails `Analyze` as it already would at a plain `pub get`. `--enforce-lockfile` adds no new network dependency (it resolves exactly the lock).
R4. A green CI run on this PR does NOT discriminate: with a good lock the new step and the old step both pass. The discriminating evidence is F3 (the SDK's behaviour) and F11 (a red run on a real runner). The red run uses a throwaway PR whose pre-push sweep is skipped with the sweep's own documented knob `CONTRACT_SWEEP_SKIP=1` (a warn-only advisory step, not `--no-verify`); the PR is closed unmerged and its branch deleted.
R5. Only the `Analyze` job enforces. A bad lock still lets the other required jobs run on a re-resolved lock, so a red PR can look "mostly green"; the red job's name is the signal.
R6. The `analyze` job has a 10-minute timeout (`timeout-minutes: 10`); the flag adds no work.

## Verification plan

Local: `flutter analyze --no-fatal-infos` (whole project, as pre-push) and the pre-commit gates; the new test file alone; the test's mutants (in memory) and ONE real mutation of `.github/workflows/test.yml` per mutant class run against the committed state (commit first, `git diff <file>` empty after each restore): flag removed, `|| true` appended, a plain `pub get` step inserted before it; each must redden the first case. Full suite: CI on the PR (four shards; necessary, not discriminating, R4). F11 as described. Reviewers are dispatched only after CI is green on the draft diff (§4.12.8). B-pass `/code-review` on the built diff before the merge (§4.3). Before the merge, replay CI's record gate by hand on the merge commit (`scripts/land_pr.dart:476-566`), because `land_pr.sh` exits 4 on this Windows machine; then `sh scripts/safe_pr_merge.sh <pr>`.

## Platform-tier requirements (`docs/blast_radius.yaml:25`)

- `regression_test`: `test/contracts/ci_lockfile_enforced_test.dart`; it fails when the flag is removed from the real workflow (real mutation run) and on the other ten mutants.
- `behavioral_test_path`: the guard's behaviour is the SDK's (F3, measured) and the runner's (F11, a red run on a real runner); a Dart test cannot run the runner, and one that spawns `flutter pub get` would need the network inside every shard (the pitfall row "a new test file that spawns subprocesses — or waits on a live service — goes green targeted and RED in the full suite").
- `code_review_b_pass`: `docs/reviews/oi520-enforce-lockfile-bpass.md`.
- `feature_flag`: not applicable, there is no code path to gate. Rollback: revert the one-line workflow change (the test then fails by design and is reverted with it).

## Commit and merge order

1. Draft diff (the workflow line, the test, this plan) committed on the feature branch, pushed, PR opened. `land_pr.sh --ci-only` is unavailable here (it exits 4), so `gh pr checks --watch` stands in for its CI wait. Plan review round 1 is dispatched only after CI is green on that head.
2. Fold round 1 into plan v2; round 2 on the hardened v2; fold.
3. F11: the throwaway red PR; record both run URLs here.
4. B-pass on the built diff; fold.
5. One commit with the final plan, the B-pass review `docs/reviews/oi520-enforce-lockfile-bpass.md`, the record `docs/plan-reviews/oi520-enforce-lockfile.md`, the closure ledger `docs/audit/oi520-enforce-lockfile.closure.yaml` (§4.2) and OI-520 moved to `closed_issues.md` with `closes-oi: OI-520`.
6. Push, CI green on the final head, hand replay of the record gate, `sh scripts/safe_pr_merge.sh <pr>`, read the PR state back, retire the worktree.

## Dispositions

(filled after each review round)
