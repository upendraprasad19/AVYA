---
branch: branch-lifecycle-cleanup
plan: docs/superpowers/specs/2026-09-29-branch-lifecycle-cleanup-design.md
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0f5002adfd8c-review.md
---

# Plan Review — branch lifecycle cleanup (OI-138)

- **Batch:** make `scripts/retire_worktree.dart --execute` delete the retired worktree's own
  merged local branch (OI-138), plus the CLAUDE.md wording (§4.13.6 / §4.13.8 / §7) and the OI
  board entries. The GitHub "delete head branches on merge" repo setting is applied AFTER the
  merge and CI-green, as a separate live action, and read back.
- **Branch:** `branch-lifecycle-cleanup` (off `0cd18178`).
- **Blast radius:** `platform` — computed by `blast_radius_from_diff.dart` on the real staged
  set (the file existed when classified). By path alone the change is `feature`
  (`scripts/**`); `platform` comes from `CLAUDE.md` being in the diff. The path-tier gap is
  OI-139, already open.

## Rounds

1. **Round 1 (context-blind, ground-truth against code and live git).** Found P0s in the
   originally bundled Unit 2 (a bulk sweep of older branches, local and remote). Split per
   §4.12.1: the sweep was filed as **OI-273** with the reviewer's seven constraints and the
   converged piece, Unit 1 (this batch), went to round 2. Round 1 also established, by
   reproduction, that `git branch -d` tests "merged into HEAD **or upstream**" (so it can delete
   an unmerged branch and can delete `main` when the primary is on another branch), and that
   `%(refname:short)` prints `heads/T` when a same-named tag exists.
2. **Round 2 (on the hardened Unit 1 plan).** Converged. Corrections carried in: key on the
   branch git reports, never the folder slug; protected names and prefixes; the ancestor-of-main
   re-check; `-d` run with `cwd` = primary; never `-D`, never a remote branch; a `-d` refusal
   reported as `KEPT-BRANCH`, exit 0, the worktree still retired. One deliberate deviation from
   round 2, recorded in the diagnose-doc: `main`/`develop` are matched case-insensitively (the
   fail-closed direction).

## Ground truth verified (not taken from prose)

- Every `git branch -d` semantic above was reproduced in scratch repos, including the
  upstream-gone matrix (`push --delete`, remote deleted with no fetch, `fetch --prune`).
- The e2e fixture builds the real workflow's shape (a session branch cut from main, committed
  to, merged with `--no-ff`, worktree clean) and each test runs on its own repository.
- Full suite `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`: 7071 passed, 0 failed,
  run before the B-pass; `flutter analyze lib/`: 0 warnings, 0 errors. The pre-commit gate loop
  passed on the staged set.

## B-pass

`docs/reviews/0f5002adfd8c-review.md`: 5 findings, all accepted and closed in this batch, two
by new mutation-proven tests (the ancestry re-check under a deterministic race, M9 1 red; a
failed worktree removal never touches the branch, M10 6 red). The first version of the plan
called the re-check untestable; the reviewer disproved that, and the corrections are recorded
in the diagnose-doc (`docs/diagnoses/2026-09-29-retire-worktree-deletes-branch-4c3fc4.md`) and
spec §10.

## Platform-tier `feature_flag` — explicit position

`docs/blast_radius.yaml` lists `feature_flag` among the platform `requires:`, and nothing
enforces it. This change ships **without a kill switch**, deliberately:

- It cannot delete an unmerged branch: the merged-set predicate, the ancestor-of-main re-check
  and `git branch -d` must all agree, and `main`, `develop`, `rescue/*`, `oi/*` and
  `dependabot/*` are never deleted (case-insensitively).
- It never uses `-D` and never touches a remote branch.
- It is operator-invoked (not a hook or a cron), dry-run is the default, and a deleted merged
  branch is recoverable from the reflog and from `main` itself.
- A switch would only give an operator a way to go back to leaving dead branches behind.

**Founder decision left open (not made here):** `retire_worktree.dart` does not refuse a bare
`--execute` (a pre-existing test runs it bare). A bare `--execute` now also deletes the branch of
every retirable worktree, each behind the same guards. Sessions pass their own slug by rule
(CLAUDE.md §4.13.6/§4.13.8), which is prose, not enforcement.

## Authorization scope

CLAUDE.md §4.13.8's added sentence describes the tool; it is not additional authority. The
standing authorization still covers only retiring the worktree THIS session just finished. It is
deliberately not widened to sweeping other branches, deleting remote branches or an unscoped
`--execute`.
