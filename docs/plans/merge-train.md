---
plan: merge-train
revision: 4
date: 2026-11-02
base: b23e8661
blast_radius: platform
tier: L                  # CLAUDE.md gets two sentences (section 4.12.6: CLAUDE.md is L); the code is platform tooling
execution_mode: inline   # one worktree, one session
parent_plan: docs/plans/merge-conflict-treadmill.md (decision D5, landing D)
closes_oi: [OI-309]      # the last landing of the treadmill plan; closed per the option chosen in section 2
landings: [D]
---

# Landing D: the written comparison, then a landing command (`scripts/land_pr.sh`)

The treadmill plan's decision D5 says: "merge train only after a comparison". This document is that comparison (section 1),
the decision (section 2) and the design of what it chose (sections 3-7). The parent plan's wording for the bespoke case ("its
own temp worktree, pinned shas, a `GITHUB_REF` seam replay with an output check, a lock, a background run") is re-examined in
section 2: the replay with an output check survives (section 3.5, it closes the red-main class), the rest does not.

## Revision history
- **rev 3 -> rev 4 (round 3, a delta round: two seats, both HARDEN on details, no REDESIGN and no P0; seat A 5 P2 + 5 P3, seat B 1 P1 (a registration) + 4 P2 + 3 P3; every item folded in):**
  - **Mechanism:** the MERGED short-circuit checks the head branch first; the `.github/` precheck also reads the LOCAL diff each round before the push; one rule for fetch
    failures (a missing remote branch, a network failure and a timeout are different words, never "main did not move"); one rule for `gh` failures at every call site;
    `GITHUB_EVENT_PATH` is set empty (a child environment cannot unset it) and `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` are overridden for the scratch clone;
    the verdict regex is anchored; the clone path is absolute; a hung `gh` is killed at its deadline.
  - **Structured classifier result (3.7):** `classifyCheckRuns` returns the state AND the set of cancelled-only jobs, so the CLI never parses reason text.
  - **Tests:** fixed short stub kinds, the sync and push queue files, `gh` stdout dropped on a non-zero exit, `--gh` and `--record-gate` split like `safe_pr_merge.dart:31-36`, fetches
    asserted through their effects, the real-C2 row built from `copyScriptClosure`, more replay rows (a prose `bpass_review`, the `0 merge(s)` commit), nine more mutants.
  - **Registrations and closure:** the `.opencode/command/build-apk.md` mirror (a contract test compares it with the `.claude` copy), per-file blast rows, the single commit that
    carries `closes-oi: OI-309` and the board move, no closure ledger, the shell-read pin.
- **rev 2 -> rev 3 (round 2: two seats, both HARDEN, no REDESIGN; seat A 4 P1 + 8 P2 + 2 P3, seat B 2 P1 + 10 P2 + 7 P3; every item folded in):**
  - **Replay simplified and made faithful (3.5):** main is already an ancestor of HEAD at that point, so the merge commit is `commit-tree HEAD^{tree} -p main -p HEAD`
    (no `merge-tree`, no git 2.38, no conflict branch); it is built inside the scratch clone from named refs, with an explicit author and committer identity;
    `--packages` dropped (the gate chain imports only `dart:` and relative files); the verdict requires the final `PASS: every landing in` line (the gate prints two
    vacuous PASS lines) and `1 merge(s)`; stale scratch directories are swept.
  - **Classifier by construction (3.7):** `evaluateCheckRuns` is refactored to tag every refusal reason red or pending and `classifyCheckRuns` reads the tags,
    so the `skippedOk`-concluding-`neutral` hole and any future drift cannot exist; a required job whose runs stay cancelled-only for three polls is red.
  - **Fetches use explicit refspecs** and the branch tip is re-fetched every round; gh calls have a deadline; ten consecutive gh failures end in `error`; children run
    with stdin closed and `GIT_TERMINAL_PROMPT=0`.
  - **Protocol:** child output is passed through with a `<name>> ` prefix on every line so exactly one stdout line starts with `result:`; the wrapper prints
    `result: error` only for a CLI status above 7; a signal during the merge re-reads the PR state; a `.github/` PR is refused up front; an already MERGED PR is
    reported `merged`; children inherit the parent environment (C2's rule; the earlier "explicit environment" claim was wrong).
  - **Tests:** the stub protocol is rewritten so the round-loop rows can run (real merge and real push stubs, a dynamic head sha, queues keyed by kind, per-call
    hooks, a defined exhausted-queue rule); the replay fixture uses `copyScriptClosure` and `git add -f` (the shared fixture excludes `/scripts/` and
    `/docs/blast_radius.yaml`); two unreachable rows dropped; missing mutants added.
  - **Closure and registrations:** an option-to-landing table for OI-309 (section 2) and the mechanics of closing it; CLAUDE.md placement; context-budget re-record
    method; no `// Gate:` header; file-level `@Timeout`; line citations corrected; a rollback line.
- **rev 1 -> rev 2 (round 1: two seats, both HARDEN, no REDESIGN; seat A 1 P0 + 4 P1 + 8 P2 + 3 P3, seat B 2 P1 + 10 P2 + 3 P3):**
  - **The lock is gone** (both seats, P0/P1): the stale-reclaim of rev 1 section 3.3 is the decide-then-act design that
    `scripts/_git_lock.sh:78-117` records as refuted four times (OI-92, "no automatic reclaim"), and its claim shape (`mkdir`, then
    write the owner) is the refuted one; seat A also showed the round loop already makes two unserialized landers converge, so the
    lock only saved a wasted CI run (section 1 row, section 7 R1; the sibling landing C2 reached the same answer, `sync-resolver.md` D10).
  - **Merge mapping fixed:** `safe_pr_merge`'s exit 2 means UNVERIFIED, not refused: its own word `merge-unverified`; before the merge the
    PR head must equal the local HEAD that was synced and waited on; a PR that reads MERGED after any exit counts as merged.
  - **New pre-merge step (section 3.5):** the replay of CI's plan-review-record gate on the merge commit GitHub will create, with an
    output check (fail closed). `safe_pr_merge` treats that job as push-only (`safe_pr_merge_lib.dart:35-38`), so a one-step landing command
    would otherwise be exactly how a record with a bad `bpass_review` line reaches main (the red mains of #119 and #124).
  - **CI classification** derives `red` from the same latest-run-per-job view as `evaluateCheckRuns` (a failed attempt followed by a rerun is
    not red), treats `startup_failure`/`stale`/`skipped` required jobs as red, and lives in `safe_pr_merge_lib.dart` next to the judge it must agree with.
  - **Specified what was open:** the signal rule, where the remote tip comes from (`git fetch origin <branch>`), draft and `--untracked-files=no`,
    `gh repo view`, one table of CLI-only seams, the stub protocol for the tests, the `protectedBranchReason` path, the registrations.
  - **Numbers:** merge volume restated as merge commits per day (sync merges included).

## 1. Comparison (what each option does for OI-309's remaining pain)

What is left after A0, A1, A2, B, C1 and C2 (parent plan section 8): a branch that is behind `origin/main` must be synced, pushed,
re-tested by CI and merged BEFORE main moves again. The sync is mostly automatic (C2 resolves 53 of the 93 conflicts that A1 and A2
left; 40 need a human). What remains is five steps run by hand with 10-25 minutes of CI in between, in which another PR can merge and
invalidate the sync, and a final merge that does not look at the plan-review record.

| Option | Verified facts (2026-11-02) | Verdict |
|---|---|---|
| **GitHub merge queue** | Not offered for this account type. GitHub's merge queue is for repositories owned by an organization (public) or on Enterprise Cloud; this repository is owned by a personal account (`gh api repos/upendraprasad19/AVYA` -> `owner.type: User`, `private: false`; `rulesets` empty). It would also need a `merge_group` trigger in `.github/workflows/test.yml` (a workflow change; the VPS token lacks the `workflow` scope except for the temporary grant) and it would bypass `scripts/safe_pr_merge.sh`, the control that makes a merge depend on CI. The availability statement rests on GitHub's merge-queue GA announcement (2023-07-12) and a third-party FAQ; it is not verifiable from the tree. | Rejected: not available for this account type, and it would replace the one merge control relied on. |
| **GitHub auto-merge** | `allow_auto_merge: false`; `main` protection reads `required_status_checks: {strict: true, checks: []}` (no contexts), so auto-merge would merge at once, before CI. Requiring the five jobs is a repository-settings change that also blocks the founder's web-UI merges. | Rejected: wrong semantics without required checks; a settings change outside this batch. |
| **Do nothing after C2** | Merge commits on `main` per day fell from 8-20 (2026-10-20..24, sync merges included) to 1-7 (2026-10-26..11-02): the pain was the hand-resolved syncs. | Rejected as the whole answer: the five-step loop is the part that is forgotten or mis-ordered, and its last step (`safe_pr_merge`) skips the plan-review record by design. |
| **Bespoke multi-PR train** (parent wording) | A worktree per queued PR, pushes to branches the train does not own, a replay harness; crosses the section 4.13 worktree rule and the outward-facing-action rule. | Rejected: cost and blast radius far above the remaining benefit. |
| **A lock around the landing** | Needs mutual exclusion from `mkdir`/`mv`/`kill -0`; `scripts/_git_lock.sh:78-117` records that every automatic-reclaim design of that shape was broken in review (OI-92). What it buys: two sessions landing at once do not both wait for CI. What it does not buy: correctness, because the round loop (section 3.4) re-checks main and the PR head before the merge; and a hand or web-UI merge bypasses any lock anyway (R1). | Rejected: the riskiest part for a saving of one wasted CI run. |
| **A landing command for the CURRENT branch, no lock (chosen)** | `sh scripts/land_pr.sh <pr>` in the branch's own worktree: sync (C2 `--commit`), push (`safe_push.sh`), wait for CI on the pushed head, re-check that main and the PR head did not move (else another round), replay the plan-review-record gate on the merge commit, merge (`safe_pr_merge.sh`). | Chosen: it removes the mis-ordering and the missing record check, writes nothing outside its own branch, and adds no mutual-exclusion machinery. |

## 2. Decision

**D8:** build `scripts/land_pr.sh` (CLI `scripts/land_pr.dart`, pure lib `scripts/land_pr_lib.dart`, the CI classifier added to
`scripts/safe_pr_merge_lib.dart`). It drives only the branch of the worktree it runs in, only through the sanctioned wrappers
(`sync_with_main.sh`, `safe_push.sh`, `safe_pr_merge.sh`), and reads GitHub through `gh` read calls. It never runs a raw `git commit`,
`git push` or `gh pr merge`. OI-309 closes at this landing. Its options, each with the landing that answers it:

| OI-309 option | Answered by |
|---|---|
| (a) stop tracking generated indexes | A2 (#167, local build products) |
| (b) one file per entry | not built as proposed: B (#171, bug-class uniqueness gate) removes the max+1 collision and C2 merges the shared files by record, which is what (b) was for |
| (c) allocator or title-keyed class ids | B (#171) |
| (d) pre-push policy for a pure sync | OI-275 (2026-10-10): a BRANCH push no longer runs the local full suite (CLAUDE.md section 0); C1 (#176) stopped the review gate re-grading a sync |
| (e) merge queue or auto-merge | this landing, section 1 (not available; `land_pr` is the replacement) |
| (f) `rerere` and `merge=union` | not built: `union` cannot refuse a number collision and `rerere` records only a human's earlier resolution; C2's resolver covers the append-only files with a collision check |
| the open question on the founder's no-verify approval for a sync push | moot: a branch push runs no local suite and a sync through `sync_with_main.sh` needs no bypass; the approval is not extended or relied on |

Closing it: the commit that lands this change carries `closes-oi: OI-309`, the entry is moved from `docs/audit/open_issues.md` to `docs/audit/closed_issues.md`
with its Status CLOSED and a resolution paragraph, and the board keeps 0 CLOSED entries (`check_closes_oi_performed` and its mirror `check_closes_oi_cited` read this).

Invoking the command on a branch is the instruction to push that branch's unpushed commits and to merge the PR (section 4.3: a person
or the agent under a standing go asks for it); it prints the commits it is about to push first. Not built: a queue over other
sessions' branches, a lock, a daemon (a supervisor signals the wrapper's process group, as C2 documents), an inferred
`--allow-workflow-change`.

## 3. Design

### 3.1 Command and protocol

`sh scripts/land_pr.sh <pr> [--allow-workflow-change]`. The wrapper (C2's shape) finds Dart next to its own path, runs the CLI, forwards
TERM/INT/HUP to it, never forwards a test seam, and prints `result: error` itself ONLY when the CLI's status is above 7 or a signal killed it
(the CLI prints its own line as its last write, immediately before `exit`, so a normal exit never gets a second line). The argument order is
`<pr> [--allow-workflow-change]` and no other (the merge wrapper accepts only that order; a reversed order is `refused`). Child output (the three wrappers) is
passed through line by line with a `<name>> ` prefix (`sync> `, `push> `, `merge> `, `gate> `), so exactly ONE stdout line begins with `result:`: the CLI's own, and it is
the last. The CLI reads no environment variable; children INHERIT the parent environment (C2's rule: its pin forbids `includeParentEnvironment: false`); the gate child
also gets `PUSH_BEFORE`, `GITHUB_REF`, `GITHUB_REPOSITORY_OWNER` and `GITHUB_EVENT_PATH` set to the empty string (a child environment can add or override a variable but not unset it; the gate ignores an empty value and reads the event file only when `PUSH_BEFORE` is empty, which it never is here);
the scratch clone's git calls also get `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` overridden to the clone's own paths (an inherited value from a git hook would otherwise point them at the real repository); every git child gets `GIT_TERMINAL_PROMPT=0`; every child has stdin
closed. `gh` calls have a deadline (`--gh-timeout-ms`, default 60 s); ten consecutive failed `gh` reads while waiting for CI end in exit 4 (`error`, "gh keeps failing").

| exit | `result:` | meaning |
|---|---|---|
| 0 | `merged` | the PR reads MERGED (`gh pr view`), including a PR that was already MERGED when the command started |
| 1 | `needs-human` | the sync stopped with paths for a person (`pending`) or `--commit` failed (`commit-failed`); or main moved in three rounds; or the PR head is no longer the commit that was synced and tested |
| 2 | `refused` | a precondition failed and nothing had been changed yet; a `refused` from the sync in a LATER round says what the earlier rounds already did (pushed commits) |
| 3 | `ci-failed` / `ci-timeout` | a job is red (or a required job stayed cancelled-only for three polls), or the jobs are unfinished or missing after `--ci-timeout-ms` |
| 4 | `error` | internal error; a child status above its documented range; an unknown or missing `result:` word from the sync; a failed or unverified push (`safe_push` 1 or 2); a TERM/INT/HUP (section 3.6) |
| 5 | `record-failed` | the replay of the plan-review-record gate did not print its PASS line |
| 6 | `merge-refused` | `safe_pr_merge.sh` exited 1 and the PR is not MERGED |
| 7 | `merge-unverified` | `safe_pr_merge.sh` exited 2 or any other status (usage, or the merge ran and its state could not be confirmed) and the PR is not MERGED after a re-read |
| 0 | `ci-green` | added 2026-11-11 (`docs/plans/review-ci-suite-lock.md`): with `--ci-only` (review CI, CLAUDE.md §4.12.8) CI is green on the pushed head and the run stopped before the main-moved check, the record replay and the merge; exit 0 is shared with `merged`, so read the word |

A wrapper child status above 7 or a signal is `result: error`, exit 4.

### 3.2 Preconditions (nothing is changed before they all hold)

1. Not detached; the branch is not protected (`protectedBranchReason` from `scripts/retire_worktree_lib.dart`, as `sync_with_main.dart` does).
2. The tree is clean for TRACKED files (`git status --porcelain --untracked-files=no`, C2's rule) and no merge, rebase, cherry-pick,
   revert, bisect or sequencer is in progress (each path resolved with `git rev-parse --git-path`, C2's list including `sequencer`).
3. `gh repo view --json nameWithOwner`, then `gh pr view <pr> --json state,isDraft,headRefName,headRefOid,baseRefName,isCrossRepository`:
   `headRefName` must equal the current branch and the PR must not be a fork (else `refused`, the observed value in the message); then state MERGED ->
   `result: merged` (exit 0, "already merged", nothing else runs); otherwise OPEN, not a draft, base `main`. (Items 1-2 run first, so a dirty tracked file or a sequencer
   refuses even a PR that is already merged: harmless, and stated.) Any `gh` failure here is `refused` with its stderr.
4. `gh api repos/<repo>/pulls/<pr>/files --paginate` through `parseChangedFiles` and `evaluateChangedFiles` with the `--allow-workflow-change` flag as given:
   a PR that edits `.github/` without the flag is refused here, before any push or CI wait (the merge wrapper would refuse it only at the very end).
5. The remote branch tip: `git ls-remote --heads origin <branch>` (bounded by `--fetch-timeout-ms`, killed at the deadline): a failure or timeout is `refused` ("could not read the remote
   branch"); EMPTY output (the branch is absent on the remote while the PR is OPEN) is `refused` with that observed state (never read as "everything is unpushed"). Otherwise
   `git fetch origin +refs/heads/<branch>:refs/remotes/origin/<branch>` (explicit refspec, same bound; a failure is `refused`), and the fetched tip must be an ancestor of HEAD (a tip that
   is not is `refused`: the command never force-pushes). The local commits not on the remote tip are printed (count and up to 20 subjects) as the commits that will be pushed.

### 3.3 No lock

Two landings at once are safe by construction: each re-checks, before merging, that `origin/main` is an ancestor of its HEAD and that
the PR head is its HEAD (3.4 steps 4-5); the second to finish finds main moved, goes round again and syncs on top of the first. The only
cost is a wasted CI wait. This matches `scripts/_git_lock.sh` (OI-92: no automatic reclaim) and the sync landing's D10 (no lock).

### 3.4 The round loop (at most 3 rounds)

Round r (1..3):

1. `sync_with_main.sh --commit` from the current directory (its wrapper finds its own Dart); the last stdout line decides:
   `up-to-date`, `fast-forwarded`, `committed` -> continue; `pending`, `commit-failed` (and `ready`, which `--commit` never prints) ->
   exit 1; `refused` -> exit 2 with the sync's message; `error`, an unknown word or no `result:` line -> exit 4. `--commit` of a
   conflicted merge runs the full pre-commit loop (minutes): unbounded, like C2's own note for a supervisor.
2. Re-read the remote tip as in 3.2 item 5 (every round; the push of round 1 moved it; a failure now is exit 4 `error`, never "unchanged"); run the LOCAL `.github/` check
   (`git diff --name-only refs/remotes/origin/main...HEAD` through `evaluateChangedFiles` with the flag as given: the commits about to be pushed can add `.github/` edits that the
   remote file list of 3.2 item 4 does not show; a refusal here is `refused`, exit 2, and says what earlier rounds already did); if HEAD is not the remote tip,
   `safe_push.sh origin <branch>`; exit 0 continues, 1 or 2 -> exit 4.
3. Wait for CI on HEAD: every `--poll-ms` (default 30 s) read `repos/<repo>/commits/<sha>/check-runs` through `gh api --paginate`, with `<sha>` =
   `git rev-parse HEAD`; `classifyCheckRuns` (3.7) says `green`, `red` or `pending`; green continues, red -> exit 3 `ci-failed`, the `--ci-timeout-ms`
   deadline (default 60 min) -> exit 3 `ci-timeout` naming the jobs still missing or unfinished. A `gh` failure, an unparseable reply
   (a `FormatException` from `parseCheckRuns`) or no runs yet is `pending`, never green (ten failures in a row: exit 4, 3.1).
4. `git fetch origin +refs/heads/main:refs/remotes/origin/main` (bounded as above; this fetch also feeds the replay). If `origin/main` is not an ancestor of HEAD, main moved while
   CI ran (a failure or timeout of this fetch is exit 4 `error`, never "main did not move"): next round; after round 3, exit 1 with "main moved three times while this branch waited for CI; run the command again". Worst case: three CI waits
   (3 x `--ci-timeout-ms`) plus the sync and push phases.
5. `gh pr view <pr> --json headRefOid`: it must equal `git rev-parse HEAD`; otherwise someone pushed to the PR branch while the command waited
   (the merge wrapper would pin the new head but that head was never synced here): exit 1 naming both shas. A `gh` failure is retried once, then exit 4: an unreadable head never reads as equal.
6. The record replay (3.5); a failure is exit 5.
7. `safe_pr_merge.sh <pr> [--allow-workflow-change]`, output passed through; then `gh pr view <pr> --json state`: MERGED -> `result: merged`
   (even after a non-zero exit); else the wrapper's exit 1 -> exit 6, anything else -> exit 7 (the state read is retried once; an unreadable state is exit 7, never 6). The exit-6 message names the case where
   `main`'s protection (`strict: true` is recorded, not verified as enforced) refuses a head that is behind main: sync and run again.

### 3.5 The record replay (closes the red-main class)

`safe_pr_merge` does not run the plan-review-record job (push-only), so before step 7 the CLI replays it. Step 4 has just shown that
`origin/main` is an ancestor of HEAD, so the merge commit GitHub will create has HEAD's tree. In a scratch clone
(`git clone --local --no-checkout <absolute git-common-dir> <absolute git-common-dir>/land_pr_replay-<pid>-<epoch>`, created fresh, deleted in a `finally`, never pushed to; a
start-of-run sweep removes only entries with the `land_pr_replay-` prefix older than a day, which a SIGKILL leaves behind; every git call there runs with
`-c core.hooksPath=<an empty directory>`): fetch `refs/remotes/origin/main` and `HEAD` of the current repository into named refs (`refs/replay/main`,
`refs/replay/head`); `git commit-tree <head>^{tree} -p <main> -p <head>` with `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`,
`GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` set explicitly and the message `Merge pull request #<pr> from <owner>/<branch>`; check it out detached; run the Dart
that is running this CLI (`Platform.resolvedExecutable`) on the clone's `scripts/check_plan_review_record_exists.dart`, cwd the clone, with `PUSH_BEFORE=<main sha>`,
`GITHUB_REF=refs/heads/main` and `GITHUB_REPOSITORY_OWNER=<owner>` (the CI job's inputs, `.github/workflows/test.yml:437-439`) and never `--warn-only`.
The verdict is the pure `replayVerdict(exitCode, stdout)`: PASS only when the exit code is 0 AND stdout contains a line that starts with
`[plan-review-record] PASS: every landing in` and matches `\s1 merge\(s\)` (a test pins the gate's exact count text, so a wording change in the gate fails a test and not every landing) (the gate also prints `PASS: not landing on main` and `PASS: nothing landed in ...`, which prove
nothing); every other outcome (a FAIL, a SKIP, a missing gate script, a failed clone or fetch) is `record-failed` (fail closed), with the gate's output printed. The
replay grades only this PR's merge commit: a failure caused by another landing appears in CI on main (R6).

### 3.6 Signals

The CLI never kills a child it started, except a `git fetch`/`ls-remote` or a read-only `gh` call at its own deadline (a half-finished merge, commit or push is worse than a late exit). On TERM/INT/HUP it records the
signal, starts no further phase, waits for the running child, deletes the replay clone and exits with `result: error`, exit 4, and a
message saying which phase was running; when that phase was the merge it first re-reads the PR state and prints `merged` (exit 0) if the PR reads MERGED. The wrapper forwards the signal to the CLI only; a supervisor that must stop the children too
signals the wrapper's process group (C2's note). No `exit()` is called before the clone is deleted.

### 3.7 `classifyCheckRuns` (in `safe_pr_merge_lib.dart`, appended at the END of the file)

`evaluateCheckRuns` is refactored so that its single pass tags every refusal reason as `red` (a job's latest run COMPLETED with a conclusion the judge refuses:
a required job that is not `success`, a `skippedOk` job that is not `success|skipped`, any other job outside `success|skipped|neutral`, which includes `failure`,
`timed_out`, `action_required`, `startup_failure`, `stale`) or `pending` (a job not completed, missing, with only cancelled runs, or `runs == null`); `evaluateCheckRuns`
returns the same `MergeDecision` as before (the whole existing test file is the regression). `CiJudgement classifyCheckRuns(runs)` returns `({CiState state, Set<String> cancelledOnly})`: `state` is `green` when there is no reason, `red` when
any reason is red (fail early), else `pending` (agreement with the judge holds by construction); `cancelledOnly` is the names of the jobs (required or not: `evaluateCheckRuns` reports both) whose
only runs are cancelled, so the CLI never parses reason text. The CLI adds one rule on top: a job in `cancelledOnly` on three
consecutive polls (a timed-out job is reported as cancelled, `safe_pr_merge_lib.dart:228-231`) makes the poll red. A fixture set pins the partition: all green; a required
job red; a shard red; failed then rerun in progress; failed then green; cancelled then green; a pending job; red AND pending together; no runs; only third-party runs; a
`skipped` required job; a `skippedOk` job concluding `neutral` and `timed_out`; `startup_failure`; `null`.

### 3.8 Seams (CLI only; the wrapper never forwards them)

| flag | default | use |
|---|---|---|
| `--gh "<cmd>"` | `gh` | a fake `gh` (a path without spaces), as `safe_pr_merge.dart` |
| `--scripts-dir <dir>` | the directory of the CLI | where `sync_with_main.sh`, `safe_push.sh`, `safe_pr_merge.sh` are found |
| `--poll-ms <n>` | 30000 | CI poll interval |
| `--ci-timeout-ms <n>` | 3600000 | CI wait deadline |
| `--fetch-timeout-ms <n>` | 120000 | each `git fetch` |
| `--gh-timeout-ms <n>` | 60000 | each `gh` call |
| `--record-gate "<cmd>"` | the replay of 3.5 | replaces the replay with a stub (a path without spaces) that prints gate lines and exits; `replayVerdict` still judges its output |

## 4. Writers and readers (section 4.1)

- **Writer** of the `result:` line: `scripts/land_pr.dart` (the wrapper for exits the CLI cannot make); **readers:** the caller and `test/scripts/land_pr_*`.
- **Reader of C2's `result:` word:** `land_pr_lib.dart` `parseResultWord`; **writer:** `sync_with_main.dart:114` and its wrapper. A source pin
  reads the word list in `sync_with_main.dart:14` and fails if a word is added there that the lib does not map (an unknown word is exit 4, never "continue").
- **Reader of `safe_pr_merge`'s status:** `land_pr_lib.dart` `mergeOutcome`; **writer:** `safe_pr_merge.dart` (exit 0 merged, 1 refused, 2 usage or UNVERIFIED:
  the header comment at lines 16-17 and the unverified branch at 166-174); pinned by CONTENT (the comment text and the `exit(2)` branch), not by line number.
- **Judge of green:** `evaluateCheckRuns`; `classifyCheckRuns` is its sibling and is tested against it (3.7). The merge wrapper stays the authority.

## 5. Tests (rule 21; each row names its mutant)

**Spawn hygiene:** every spawn goes through `test/helpers/spawn.dart` (`test/contracts/spawn_sites_guard_test.dart` G1 bans raw `Process.*` in
tests); the CLI reads no environment variable and its children inherit the parent environment plus the named additions of 3.1 (`spawn_env_manifest_test.dart`); `land_pr_lib.dart` has no
`File` or `Process` (`check_gate_existssync_file_vs_dir.dart` guards `*_lib.dart`).

**Stub protocol:** a stub directory holds shell scripts, the stub generator pins the kind mapping. `gh` answers by a fixed short KIND derived from its argv: `repo` (`repo view`), `pr-pre`
(`pr view --json state,isDraft,headRefName,headRefOid,baseRefName,isCrossRepository`), `pr-head` (`pr view --json headRefOid`), `pr-state` (`pr view --json state`), `pr-files` (`api .../pulls/<pr>/files`),
`check-runs` (`api .../commits/<sha>/check-runs`); an argv that matches none exits 99 (a changed field list in the CLI fails loudly). Replies come from files `<dir>/q/<kind>.<n>` (n = the call number of that kind):
line 1 is `exit=<status>`, then optional `stderr:` lines, then the body; as in `safe_pr_merge.dart:41-44`, stdout is DROPPED when the status is non-zero. The body may contain the token `@HEAD@`, replaced at run time
with `git -C <repo> rev-parse HEAD` (so `headRefOid` and the check-runs sha equal the real HEAD); an exhausted queue REPEATS its last file; an executable `<dir>/pre_<kind>.<n>` runs before the reply (it pushes a commit
to the bare origin, which is how "main moved during CI" happens). Check-runs bodies carry `app.slug: github-actions` and a correct `total_count` (built from `test/scripts/fixtures/safe_pr_merge_pr96_check_runs.json` the way
`safe_pr_merge_e2e_test.dart:36-60` does). The stub `sync_with_main.sh` reads `q/sync.<n>` (a `result:` word, an exit status and `merge|ff|none`: `merge` really runs `git merge --no-ff --no-edit refs/remotes/origin/main`, `ff` a
fast-forward) and the stub `safe_push.sh` reads `q/push.<n>` (an exit status) and really pushes the branch to the bare origin when it is 0; the stub `safe_pr_merge.sh` reads `q/merge.<n>`; all append `<seq> <name> <argv>` to ONE
shared log. `git fetch` and `ls-remote` are real git and leave no log line: the tests assert them through their effects (a `pre_check-runs.<n>` push moves main, so round 2 happens only if the explicit main refspec updated
`refs/remotes/origin/main`; the `origin/<branch>` tip is read back after a push round). The CLI splits `--gh` and `--record-gate` exactly like `safe_pr_merge.dart:31-36` (`split(RegExp(r'\s+'))`: first token the executable,
the rest leading arguments); the stub path has no spaces (the helper creates one). Temporary repositories: a bare `origin.git`, `main` and a feature branch (clone helper from `sync_cli_fixture.dart`). Every test file starts with
`@Timeout(...)` and `library;` (CLAUDE.md section 4.9). `land_pr.sh` reads no unassigned shell variable (`spawn_env_manifest_test.dart` arm 4 scans `scripts/*.sh`); copy `sync_with_main.sh`'s structure. The CLI's own non-result
prints never start with `result:` (a pin).

**Library** (`land_pr_lib_test.dart`): `parseResultWord` (last line only, `result:` prefix, trailing space, CRLF, an earlier `result:` line, empty,
two words); `mergeOutcome` (every status x MERGED/not MERGED); `replayVerdict` (exit 0 + PASS, exit 0 without PASS, PASS with exit 1, empty); `roundDecision`
(main moved at round 1/2/3 boundary); the preconditions as pure functions (protected branch names, state-file list); `classifyCheckRuns` over the
fixture set (all green; a required job red; a shard red; failed then rerun in progress; failed then green; cancelled-then-green; a pending job; no runs;
only third-party runs; a `skipped` required job; `startup_failure`; `timed_out`; `null`) with the agreement property against `evaluateCheckRuns`.

**CLI e2e** (`land_pr_e2e_test.dart`): the happy path asserting the ORDER and argv of every stub call (sync `--commit`, [push], check-runs polls, fetch,
head check, record gate, merge) so a CLI that does nothing fails; push needed / not needed; the `--commit` flag present on EVERY sync call; sync `pending`,
`commit-failed`, `refused`, `error`, unknown word, no word -> 1/1/2/4/4/4 with no push; CI red -> 3; failed-then-rerun is NOT red; CI pending until the
deadline -> `ci-timeout` (short deadline); a `gh` failure while waiting keeps waiting; main moved during CI -> round 2 then merged; main moved twice
-> merged in round 3; moved in round 3 -> exit 1 with the exact message (the boundary pair); PR head moved during the wait -> exit 1; record gate failing ->
5 and no merge call; merge stub exit 1 -> 6, exit 2 -> 7, exit 2 but PR MERGED -> 0, exit 0 but not MERGED -> 7; `--allow-workflow-change` absent from the merge argv
by default and present when given; an already MERGED PR -> `merged` with no other call; a PR editing `.github/` without the flag -> refused before any push, accepted with it; the reversed argument order refused; each precondition refusal (protected branch, detached, dirty tracked file, an untracked file is NOT a refusal, pending merge,
sequencer, closed PR, draft, base not main, fork PR, `headRefName` mismatch, remote tip not an ancestor) leaving HEAD, index and
the stub log untouched; unpushed commits listed before the push; a path with a space in the repository; TERM while a stub child runs (synchronised by a ready file the stub creates, as `sync_with_main_wrapper_e2e_test.dart` does) -> the child
finishes, exit 4; TERM during a real replay with a slow gate copy -> the scratch clone is gone and `result: error`; a real-C2 row: `--scripts-dir` holds `copyScriptClosure(sync_with_main.dart)`, the real `sync_with_main.sh` and `_dart_bin.sh`, with ONLY `safe_push.sh`, `safe_pr_merge.sh` and `gh` overlaid by stubs, so the REAL sync drives a clean divergence to `committed` (a conflicted `--commit` path would need `scripts/safe_commit.sh` from the cwd and is not exercised) and the command pushes (stub) and merges (stub).

**Replay** (`land_pr_replay_test.dart`): a temporary repository whose tracked files include the gate's script closure (`copyScriptClosure` from `test/helpers/script_closure_fixture.dart`, which
follows the transitive imports) and `docs/blast_radius.yaml`, added with `git add -f` because `ScopeRepo` excludes `/scripts/` and that file (`test/helpers/merge_scope_repo.dart:61`); the gate reads the
registry with `git show <rev>:docs/blast_radius.yaml`. Rows: a >=account branch with no record -> `record-failed`; with a valid record and review file -> PASS; a docs-only branch -> PASS; a record present whose `bpass_review` line is prose without `verdict: accepted` (the #119/#124 class) -> `record-failed`; a replay whose
HEAD equals main (a deduplicated single-parent commit: the gate prints a PASS with `0 merge(s)`) -> `record-failed`, killing a verdict that accepts any `PASS:` line; a wrong merge-commit subject (owner or branch) -> `record-failed`; the replay run with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and `GITHUB_EVENT_PATH` set in the inherited environment leaves the real repository untouched; the registry missing from the repository (the gate's SKIP) -> `record-failed`; the identity: no `user.name` anywhere
in the environment still builds the commit; the real repository untouched (HEAD, index, refs) and the scratch clone absent afterwards; a leftover `land_pr_replay-*` older than a day is swept and a fresh one is not.

**Wrapper** (`land_pr_wrapper_e2e_test.dart`): argument refusals (none, two PRs, unknown flag, non-numeric PR), `--allow-workflow-change` forwarded, no `dart`
on PATH, a child status above 7, a signal.

**Source pins** (`land_pr_source_pins_test.dart`): the wrapper forwards none of the seams; the CLI contains no git `commit`, `push` or `merge` argv (`merge-base`, `commit-tree` and `rev-parse` are allowed and tested for) and no `gh pr merge`; every C2 word is mapped; the exit table agrees across the wrapper header, the CLI header,
hooks.md and this plan; the merge wrapper's exit-code comments still say what `mergeOutcome` assumes (pinned by content); `classifyCheckRuns` sits after `evaluateCheckRuns` and `evaluateCheckRuns` returns the same decisions as before; the new scripts carry no `// Gate:` header.

**Mutation** (rule 21): one mutant per row (including: merge before CI, push skipped, `--commit` dropped in round 2, ancestor check inverted, 3-round bound off by one,
head check dropped, record gate output check dropped, `merged` accepted without the state read, merge exit 2 mapped to 6, `--allow-workflow-change` dropped,
branch-name check dropped, `classifyCheckRuns` precedence swapped, signal handler removed, the remote-tip ancestor check inverted, `--paginate` dropped, CI polled for a sha other than HEAD, the round counter reset, the wrong refspec on the main fetch, the vacuous-PASS lines accepted, the cancelled-only rule dropped, the `.github/` precheck dropped (remote list and local diff separately), the replay commit's parents swapped or built from main's tree, `PUSH_BEFORE` omitted or wrong, `GITHUB_EVENT_PATH` left inherited, the ten-failure counter not reset on success or off by one, each precondition arm removed (draft, base, fork, each state file, `--untracked-files=no`), the stale sweep deleting a fresh clone, the replay clone's cleanup removed, stdin left open, the MERGED short-circuit before the head-branch check, an unreadable state read as exit 6) plus 3 controls (comment-only edits); each applied with an exact-match
assertion, compile error not counted as red, sources restored and re-hashed, the table re-run on the final tree. Self-attested.

## 6. Process

- Registrations: three `docs/blast_radius.yaml` rows `scripts/land_pr.sh`, `scripts/land_pr.dart`, `scripts/land_pr_lib.dart` (platform, one exact file each as the file's convention is; inserted ABOVE the broad `scripts/**` row, which is `feature`; `safe_pr_merge_lib.dart` is already platform), the glossary row
  ("land_pr"), `docs/architecture/hooks.md` section, `docs/plans/merge-conflict-treadmill.md` (D built; section 7 wording replaced), `docs/audit/open_issues.md` and
  `closed_issues.md` (OI-309 closed and archived), CLAUDE.md (section 4.3, in the `safe_pr_merge` bullet: one sentence naming the command and saying that invoking it counts as the ask to push the branch and merge the PR; section 7: one row), `backups/context_artifact_sizes.json`
  re-recorded after the CLAUDE.md and board edits (`--record` from a tree whose local indexes are built, then check that the JSON diff touches only the intended keys), `.claude/commands/build-apk.md` step 6 AND its mirror `.opencode/command/build-apk.md` in the same commit (`test/contracts/build_apk_bump_flow_test.dart:90-118` compares the bodies and regex-matches every `scripts/<x>` named in Gate 2, so `scripts/land_pr.sh` must exist; the mention is only for the case where the branch is behind main: that flow is "ONE commit, touch nothing else"), `docs/architecture/hooks.md` (a section with the exit table and a rollback line: nothing calls the command, so rollback is a revert). The new scripts carry no `// Gate: N` header (C2's rule). A settings allow-rule
  `Bash(sh scripts/land_pr.sh:*)` is the founder's to add; this landing does not edit settings. No new `check_*.dart`, so no gate ledger entry.
- **Closure sequence:** the `closes-oi: OI-309` trailer and the board move (the entry from `open_issues.md` to `closed_issues.md`, Status CLOSED with a resolution paragraph in the format of the OI-410 move, commit `b6c4fe49`)
  go in ONE commit (the code commit); no other commit message quotes the phrase (`feedback_quoting_a_trailer_phrase_in_a_commit_body_is_a_citation`: grep every message before the push). `OPEN_INDEX.md` is untracked, so no
  index edit. No closure ledger: one unit (section 4.2 answered by the B-pass fixing every finding in the batch).
- Build step: `gh pr view <pr> --json state,isDraft,headRefName,headRefOid,baseRefName,isCrossRepository` was run on this VPS (gh 2.45.0) and returns all six fields (checked 2026-11-02 on PR #190).
- Gate loop before any review that has a diff: whole-project `flutter analyze --no-fatal-infos`, full `TZ=Asia/Kolkata flutter test --exclude-tags golden`,
  `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh`; then the B-pass (two Sonnet seats), `docs/reviews/<hash>-review.md` (staged explicitly), and the record
  `docs/plan-reviews/merge-train.md`.
- Branch `merge-train`; commit via `scripts/safe_commit.sh`, push via `safe_push.sh`, merge via `safe_pr_merge.sh` (the command cannot land its own first version).

## 7. Residuals

- **R1** No mutual exclusion (two landings at once, or two runs in one worktree): they may waste a CI wait; a hand or web-UI merge can move main during it (the loop re-checks and re-syncs, at most 3 rounds). Founder decision 2026-11-03 (OI-449, option b): accepted, no lock will be added; a crash-stuck lock is the worse failure.
- **R2** Between the last ancestor check and the merge, main can still move (GitHub merges the PR head into main as it stands): the result is then untested on the very
  latest main, as today. Only a real merge queue closes this; none is available (section 1).
- **R3** The sync with `--commit` and the push are unbounded phases; only the CI wait and each fetch have deadlines. A supervisor signals the process group.
- **R4** Windows: needs `sh` (Git Bash) like C2; untested there.
- **R5** A CI run that never starts (a conflicted PR, a disabled workflow) shows as `pending` and ends as `ci-timeout` after 60 minutes; the message names the jobs missing.
- **R6** The replay judges only the plan-review-record gate on THIS PR's merge commit; the other main-only gates are not replayed, and a failure caused by another landing appears only in CI on main.
- **R7** The unpushed commits are pushed on the strength of the invocation; the list is printed, not confirmed.

## 8. As built (2026-11-02)

- **Files:** `scripts/land_pr.sh` (wrapper), `scripts/land_pr.dart` (CLI), `scripts/land_pr_lib.dart` (pure decisions, no `File`/`Process`), the classifier added to
  `scripts/safe_pr_merge_lib.dart` (`classifyCheckRuns`, `CiState`, `CiJudgement`; `evaluateCheckRuns` is now a thin reader of the same private pass `_judgeCheckRuns`, with byte-identical
  reasons: the existing test files and a new byte-for-byte test are the regression), `test/helpers/land_pr_fixture.dart`, five test files, and the registrations of section 6.
- **Where it differs from the plan text:** `classifyCheckRuns` sits right after `evaluateCheckRuns` (not at the very end of the file; no line citation depends on it); the replay clone is made from
  the git common dir under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE` and the clone's later git calls use `--git-dir`/`--work-tree` options plus `GIT_INDEX_FILE`; only `scripts/` is checked
  out in the scratch clone (the gate reads everything else through `git show`); `staleReplayDir` parses the epoch from the directory NAME (no mtime), so the sweep is a pure function; the
  `git push` of the loop is `safe_push.sh origin <branch>`; a `gh` or git child that is killed at its deadline can leave a grandchild holding its pipes, so the CLI stops waiting for the pipes 2 s after
  the child exits.
- **Tests:** `land_pr_lib_test.dart` (the pure decisions and the classifier against the judge), `land_pr_e2e_test.dart` (the CLI against real git, the stub protocol of section 5, the real sync row, signals),
  `land_pr_replay_test.dart` (the real gate in throwaway repositories, a TERM during the real replay), `land_pr_wrapper_e2e_test.dart`, `land_pr_source_pins_test.dart` (the totals are in the commit message).
- **Mutation evidence (rule 21):** see `docs/plan-reviews/merge-train.md`; the table is the one of section 5 plus the B-pass additions, applied to a copy of the tree, a compile error never counted as red,
  controls Z01-Z03 (comment-only edits) green.
- **B-pass changes (2026-11-02, two Sonnet seats, no P0/P1):** origin/main is read ONCE after the fetch of each round (`rev-parse`), the ancestry check, `PUSH_BEFORE` and the merge-commit parent use that sha, and the scratch clone re-checks it (a main that moved meanwhile is `needs-human`); an interrupt is checked before the head check, the replay, the push and the merge starts (a TERM during a `gh` read no longer reaches the merge); child output is decoded with `allowMalformed`; our own stdout/stderr writes cannot fail the run, the final flush has a 2 s bound (a broken stdout never completes it), and an uncaught async error waits for a running child; every message is one `land_pr:` line; the wrapper sets its trap before the CLI starts, remembers an early signal, rejects `--allow-workflow-change <pr>` with its own message and, under bash (which reaps early), asks `wait` a second time. Residual R1 now also names two runs in ONE worktree (no lock, OI-92).
