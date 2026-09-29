# Branch lifecycle: retire deletes its own local branch (OI-138) + GitHub auto-delete

Status: DRAFT v2 for plan-review round 2 · Branch: `branch-lifecycle-cleanup` · Tier: platform (CLAUDE.md is in the diff) · Execution mode: inline (§4.12.7)

## 0. Revision history

- v1: three units — (1) retire deletes the local branch, (2) a `--sweep-branches` mode, (3) repo setting + widened §4.13.8. Round 1 returned NOT CONVERGED with two P0s against Unit 2 and one against Unit 1's tests, all reproduced by the reviewer and re-checked by the coordinator where cheap (`scripts/pre-push.sh:39-42`, `scripts/mint_oi.sh:316`, `retire_worktree_lib_test.dart:208`).
- v2 (this): §4.12.1 split. Ships Unit 1 + Unit 3-minus-widening. Unit 2 is TRACKED as **OI-273** with round 1's constraints written into it (not lost, not scheduled). The §4.13.8 "delete this session's remote branch" sentence is dropped: with GitHub auto-delete on, it authorizes nothing needed and widens a scoped authorization.

## 1. Why

`retire_worktree.dart` removes the worktree folder and never the branch (OI-138). A dead local branch also burns the worktree slug (`new-worktree.sh <slug>` refuses: branch exists, `new-worktree.sh:38`). Measured 2026-09-29: 31 local / 88 remote branches, nearly all merged; 17 local and 55 remote were deleted by hand that day (name→sha saved; all tips ancestors of `main`).

## 2. Facts verified 2026-09-29 (round 1 reproduced most in throwaway repos)

- `retire_worktree.dart:275-282`: `git worktree remove <path>`; branch is in scope as `w.branch` (`:174`); `merged.contains(branch)` (`:254`) comes from `git branch --merged main` (`:158`).
- `parseWorktreePorcelain` strips `refs/heads/`, yields `''` for detached HEAD, drops bare records (`retire_worktree_lib.dart:197,203`).
- Worktree slug is NOT the branch name (OI-138's trap): a folder can sit on any branch. Delete must key on `w.branch`.
- `git branch -d` tests "merged into HEAD **or upstream**", not "into main". Consequences (reproduced): (a) with an in-sync upstream it deletes an UNMERGED branch; (b) run from a primary whose HEAD is not `main` it can REFUSE a genuinely merged branch. So `-d` is a second, fail-closed check; the safety guarantee is the tool's own `--merged main` predicate, which already gates retirement.
- When primary's local `main` lags `origin/main` (CLAUDE.md §4.9 post-PR-merge row) the predicate says "not merged" → the whole worktree is KEPT and no branch is touched. Fail-safe, pre-existing.
- Upstream-gone behaviour: after `git push origin --delete`, the tracking ref is removed too; `rev-parse @{u}` and `log @{u}..` exit 128; `retire_worktree.dart:234-235` sets `upstream=false`, leg 1 carries the decision, worktree stays retirable. NOT yet reproduced for GitHub-side deletion, where the tracking ref REMAINS until `fetch --prune`: there `@{u}` resolves and `log @{u}..` compares against a stale ref. Both states must be tested.
- Repo: `delete_branch_on_merge=false`, merge-commit only, `main` has `allow_deletions:false` (`gh api repos/upendraprasad19/AVYA`). Auto-delete consumers checked by round 1: `check_plan_review_record_exists.dart:596-606` reads commit objects + merge subject, not branch refs; `test.yml` triggers on push/pull_request only; nothing in `scripts/` fetches a feature branch post-merge. `oi/*` and `rescue/*` are never PR heads; dependabot recreates its own.
- Existing unit test `retire_worktree_lib_test.dart:208` pins the substring `no upstream configured`.
- Tier: the classifier gives `feature` for the tool + its test alone and `platform` only because CLAUDE.md is in the diff. `docs/blast_radius.yaml` has no `retire_worktree` entry (OI-139). OI-138's own "individually pinned above the catch-all" line is false and is corrected in its close-out. Keeping the CLAUDE.md edit is deliberate: it keeps the merge-time plan-review record required for the one tool that deletes developer work.

## 3. Design

### Unit 1 — retire deletes the local branch (closes OI-138)

Inside the `rm.exitCode == 0` branch ONLY (so a failed worktree removal can never touch a branch — structural, not a tested condition), after printing `RETIRED <name>`:
1. Skip, and say why, when: `branch` is empty; `branch == 'main'`; or the lower-cased name starts with `rescue/`, `oi/` or `dependabot/` (`  KEPT-BRANCH <b> [protected prefix]`).
2. Otherwise run `git branch -d -- <branch>` from the primary (List args, cleaned env, as `_git` already does). Success → `  BRANCH-DELETED <b>`.
3. Refusal (git's own reason, e.g. "not fully merged" when primary HEAD is not on `main`) → `  KEPT-BRANCH <b> [<git's reason>]`. NOT counted in `failed` (the worktree WAS retired); exit code unchanged. Never `-D`, never retry with force.
4. Dry-run: after `RETIRE <name> [..]` print `    branch <b> would be deleted` or `    branch <b> would be kept [protected prefix]`. It cannot predict a `-d` refusal in dry-run and says nothing about one.
5. Lib: the no-upstream reason becomes `merged + clean (no upstream configured, or it was deleted on the remote — commits reachable from main)`, which still contains the pinned substring. Pure-function change only; `classifyWorktree`'s decisions are unchanged.

### Unit 3 — repo setting + docs

- `gh api -X PATCH repos/upendraprasad19/AVYA -f delete_branch_on_merge=true`, read back with a GET, done at execution after convergence; reversible with the same call. Founder-approved.
- CLAUDE.md: §4.13.6 gains one bullet (the tool deletes the local branch with `-d`, KEPT-BRANCH on refusal; remote branches of PR merges are removed by GitHub's setting; a branch merged by any OTHER route keeps its remote branch until OI-273). §4.13.8's sequence gains one sentence saying the retire step now also removes the local branch; the authorization text is NOT widened. §7 retire row updated.
- OI-138 CLOSED with `closes-oi: OI-138`, evidence line, and the false "individually pinned" statement corrected. OI-273 (filed) carries Unit 2.

## 4. Writer / reader map

Writer of the leftover: `retire_worktree.dart:275`. Readers that depend on a free slug: `new-worktree.sh:38`. Readers of "merged": `retire_worktree.dart:158-165`, `:254`; `classifyWorktree`. Consumers of remote-branch existence after auto-delete: none in `scripts/` (round 1) — re-verify.

## 5. Risks the reviewer must attack (round 2)

1. Any way Unit 1 deletes a branch that is not safely merged or is needed: `-d` semantics from the primary in every HEAD/upstream configuration; primary on a different branch; a branch that is merged only because it was cut fresh with zero own commits (deleting it loses nothing — confirm); a branch also referenced by a tag of the same name; case variants of the protected prefixes.
2. Is the fail-closed direction really the only failure direction? Construct a case where `-d` succeeds and the branch was NOT in `--merged main` (the tool only calls `-d` after that predicate, but verify no path bypasses it, e.g. `only` slug handling, the `_protected` set, or a stale `merged` set computed once before a loop that mutates branches).
3. The upstream-gone matrix: (i) `git push origin --delete` (tracking ref removed), (ii) remote branch deleted on the bare origin with NO fetch in the clone (tracking ref stale but present — the GitHub-auto-delete shape), (iii) same then `fetch --prune`. For each: `@{u}`, `log @{u}..`, the tool's classification, and `git branch -d`.
4. GitHub auto-delete side effects the round-1 grep could have missed: `.github/workflows/*` (any `workflow_run`, `delete`-event or `branches:` filters), `scripts/safe_merge.sh`, `scripts/safe_push.sh`, `scripts/arm_ci_reconcile.sh`, `scripts/reconcile_ci.dart` (does it look a run up BY BRANCH NAME after the branch is gone?), `docs/plan-reviews/` gate, Vercel `ignoreCommand`, dependabot config. Verify with grep AND by reading `gh run list` shape for a merged-and-deleted branch if one is visible read-only.
5. Test infrastructure: the e2e file uses ONE shared `setUpAll` repo whose last test mutates it (round 1). New tests must not depend on order — each new test builds its own repo. Check the `@Timeout` budget (§4.9: 4 min today, this batch adds several git-spawning cases), grep the file for per-test `timeout:` overrides, and confirm no new test can reach real GitHub or the real repo (a bare `origin.git` under the tmp dir only; no `gh` is used in Unit 1).
6. Is the plan now converged-sized? If a Unit 1 problem needs a redesign, say which piece to cut.
7. Does dropping the §4.13.8 widening leave the founder's stated wish ("delete the branch after it is done") unmet in a way the plan does not admit? The remote half depends on the setting for PR merges only; the admission is the OI-273 pointer in §3. Say if that is honest enough.
8. Mechanical: every cited file:line.

## 6. Test plan (rule 21 + mutate-and-run) — each new test builds its own throwaway repo

`test/scripts/retire_worktree_e2e_test.dart` (real linked worktrees, real git; a helper `makeRepo()` returns a fresh repo with the two scripts copied in):
- T1 merged worktree retire deletes its branch; the slug is then reusable (`git worktree add -b <slug>` succeeds).
- T2 folder slug ≠ branch (`git worktree add -b feature/x <dir>/x`): deletes `feature/x`; an unrelated branch named `x` survives.
- T3 dry-run deletes nothing (branch and worktree both still exist).
- T4 `-d` refusal is REACHABLE: leave the primary checked out on another branch at an older commit, so `-d` refuses a merged branch → `KEPT-BRANCH` printed with git's reason, worktree still retired, exit 0, branch still exists; primary HEAD restored afterwards.
- T5 protected prefix: merged worktree on `rescue/x` (and `OI/y`, `Dependabot/z`) → worktree retired, branch KEPT with the protected message.
- T6 upstream-gone matrix (i)(ii)(iii) from §5.3 with a bare `origin.git` in tmp: the worktree still retires and its branch is deleted in all three; reason text mentions the deleted/no upstream.
- T7 `main` and a detached-HEAD worktree: neither branch deleted, no crash.
- Lib test: the reworded reason contains both `no upstream configured` and `deleted`.
Mutations to run and report in the diagnose-doc (confirm each applied; each must redden for a semantic reason, not a compile error): `-d`→`-D` (T4 must redden — and say so honestly if it does not); key on folder slug instead of `w.branch` (T2); drop the protected-prefix guard (T5); drop the `main` skip (T7); print-only dry-run mutated to actually delete (T3). Not mutation-testable, stated plainly: "branch deletion only after a successful worktree remove" is structural (inside the `rm.exitCode == 0` block); no test forces `git worktree remove` to fail. Fixture checked against the real workflow: a session branch cut from main, committed to, merged with `--no-ff` (merge commit, as PR merges here), worktree clean.

## 7. Files and process

Product: `scripts/retire_worktree.dart`, `scripts/retire_worktree_lib.dart`. Tests: `test/scripts/retire_worktree_e2e_test.dart`, `retire_worktree_lib_test.dart`. Docs: CLAUDE.md §4.13.6/§4.13.8/§7, `docs/audit/open_issues.md` (OI-138 closed, OI-273 filed), `OPEN_INDEX.md` regenerated, diagnose-doc (full template), project memory + archive line. Repo setting via `gh api` at execution.

Two context-blind plan-review rounds → `docs/plan-reviews/branch-lifecycle-cleanup.md` (`review_rounds: >=2`, `ground_truth_verified: true`, `bpass: accepted`). Full gate loop before any review round that has a diff; run the new e2e inside the FULL suite once (§4.9 `@Timeout` row).

## 8. Unit 2, not in this batch — tracked as OI-273

`--sweep-branches` (dry-run default) for merged local/remote branches that never had a worktree here. Round 1 constraints are recorded on OI-273 (gh-API transport not `git push --delete`; tip-sha-exact merged proof instead of a date guard; `gh pr list` limit/owner/fail-closed handling; e2e must isolate `gh`; `-d` is not a guard; fully-qualified refs; multi-machine gap; protected prefixes). It needs its own plan and ×2 review.

## 9. v3 amendments (from plan-review round 2 — converged; every item below was reproduced or read, then folded in)

Round 2 verdict: CONVERGED, no P0, no redesign. Amendments, all applied to Unit 1 before any code:

1. **Protect `main` and `develop` by exact, case-sensitive name** in addition to the prefixes `rescue/`, `oi/`, `dependabot/` (case-insensitive). Reproduced 2026-09-29: with the primary on another branch and a linked worktree on `main`, `git worktree remove` then `git branch -d -- main` prints `Deleted branch main`, rc=0 — the skip is the ONLY thing between Unit 1 and deleting `main`. `develop` is a CI trigger branch (`test.yml`) that does not exist today.
2. **T7 builds a fixture that can contain a worktree on `main`**: git refuses a second checkout of `main` while the primary is on it, so the test first moves the primary to another branch (restored after), then `git worktree add ../wm main`. Without that the "drop the `main` skip" mutation reddens nothing (rule 21 zero-red trap).
3. **Sanitize the KEPT-BRANCH reason.** git's refusal prints `If you are sure you want to delete it, run 'git branch -D <b>'`. Keep only git's first line, replace the rest with the fixed text `not deleted; resolve by hand`. A null `ProcessResult` (git missing) prints `KEPT-BRANCH <b> [git unavailable]`, never throws. T4 asserts stdout does not contain `-D`.
4. **Re-check ancestry immediately before `-d`**: `git merge-base --is-ancestor refs/heads/<b> main`, run with `workingDirectory` = the repo root (not the process cwd). Failure → `KEPT-BRANCH <b> [not an ancestor of main at delete time]`. This closes the reproduced race (merged set is computed once at `:158`; a branch that gains a pushed commit mid-run would otherwise pass `-d` via its in-sync upstream). Not e2e-testable (a race); stated as such in the diagnose-doc.
5. **Fix the same-name tag quirk in the merged set**: `git branch --merged main --format=%(refname)` and strip `refs/heads/` (was `%(refname:short)`, which prints `heads/T` when a tag `T` also exists, so `merged.contains('T')` was false and the worktree was silently KEPT). New test T8: tag + branch of one name → the worktree retires and the right branch is deleted, the tag survives.
6. **e2e budget**: `@Timeout(Duration(minutes: 8))`; each new test needs at most 2 spawns (fold dry-run + execute checks); every new test builds its own repo. No per-test `timeout:` override exists in the file (grepped); the plan adds none.
7. **CLAUDE.md wording is drafted literally, and does not widen authority.** §4.13.8, appended to the sequence: "`retire_worktree.dart --execute <slug>` also deletes that worktree's own merged local branch with `git branch -d`, never `-D`, and never any other branch. This describes the tool; it is not additional authority. A session runs it only with its own slug, never `--execute` without a slug, and never deletes a remote branch." §4.13.6 bullet: the local branch is deleted with `-d` only after an ancestor-of-`main` re-check; `main`, `develop`, `rescue/*`, `oi/*`, `dependabot/*` are never deleted; `KEPT-BRANCH` means a human decides; an unscoped `--execute` would delete the branch of every retirable worktree, which is why the slug is required of sessions; remote branches of GitHub-PR merges are removed by the repo setting, and any merge NOT made through a GitHub PR keeps its remote branch until OI-273. Do not oversell slug reuse: `check_plan_review_record_exists.dart:674-680` prints a stale-reuse NOTE for a branch name that already landed.
8. **Citations**: `new-worktree.sh:37` (not `:38`); bare-record drop is `retire_worktree_lib.dart:171-172` (`:197` is the `refs/heads/` strip, `:203` the detached `''`).
9. **Verified clean by round 2, recorded so nobody re-runs it**: the upstream-gone matrix. (i) `push --delete` and (iii) `fetch --prune` give `@{u}` rc=128 → `upstream=false`, retirable; (ii) remote deleted with NO fetch (the GitHub auto-delete shape) leaves the tracking ref, `@{u}` resolves, `log @{u}..` is empty → `upstream=true`, unpushed=0, retirable. `git branch -d` after the worktree is removed succeeds in all three. GitHub auto-delete side effects: none found (`test.yml` triggers only on push/pull_request; `gh run list --branch <deleted-branch>` still returns its run; the plan-review gate reads commit objects and the merge subject, not branch refs). Not verified and irrelevant today: GitHub's handling of a PR whose base is a deleted head branch (no stacked PRs exist).

## 10. Corrections after the B-pass (2026-09-29)

The plan above says two things that the B-pass showed to be false. They are left
in place above as the record of what was planned, and corrected here.

- **§4 item 4 ("Not e2e-testable (a race)") and the "no test forces `git worktree
  remove` to fail" note in the mutation paragraph.** Both are testable. A
  `reference-transaction` hook makes the race deterministic (delete of one
  candidate's branch ref triggers a commit on the next candidate and advances its
  tracking ref), and a non-root `chmod 000` on a regenerable ignored directory makes
  removal fail. Both tests now exist; mutations M9 (1 red) and M10 (6 red) are in the
  diagnose-doc. With an in-sync upstream, `git branch -d` alone deletes an unmerged
  branch, so the ancestry re-check is the guard, not defense in depth.
- **"`--execute` without a slug is refused."** The tool never refused it (an existing
  test runs it bare). Bare `--execute` deletes the branch of every retirable worktree,
  each behind the same guards. Sessions pass their own slug by rule (CLAUDE.md
  §4.13.6/§4.13.8), not by enforcement.
