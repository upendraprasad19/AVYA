---
bug_id: 4c3fc4
date: 2026-09-29
batch: branch-lifecycle-cleanup
status: fixed
blast_radius: platform
symptom: |
  Founder-observed (2026-09-29, after PR #54 merged and its worktree was
  retired): the local branch `oi-154-profile-clear-tombstone` still existed
  (and so did the remote one). `scripts/retire_worktree.dart --execute`
  removed the worktree directory but left its local branch behind, so
  branches accumulated (17 merged local branches at the audit). OI-138.
concept: worktree_retirement_branch_lifecycle
sot_registry_entry: |
  none — a dev-tooling script with no Hive/cloud writer-reader pair. The
  contract is pinned by test/scripts/retire_worktree_e2e_test.dart
  (real repos) and retire_worktree_lib_test.dart (pure predicates).
writers:
  - { file: scripts/retire_worktree.dart, method_or_widget: "_deleteBranchAfterRetire — protected-name check, ancestor-of-main re-check, git branch -d", line: 141 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "protectedBranchReason + sanitizeBranchRefusal", line: 374 }
readers:
  - { file: scripts/retire_worktree.dart, method_or_widget: "merged-set computation (git branch --merged main --format=%(refname))", line: 216 }
  - { file: scripts/retire_worktree.dart, method_or_widget: "execute loop — calls _deleteBranchAfterRetire only after git worktree remove exits 0", line: 346 }
hive_key_prefix: "n/a (dev tooling, no Hive)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a"
forbidden_patterns_checked:
  - { pattern: "git branch -D anywhere in the retire path", absent: true }
  - { pattern: "deleting a remote branch from the retire tool", absent: true }
proposed_fix: |
  After a SUCCESSFUL worktree removal only, delete that worktree's own local
  branch with `git branch -d` (never `-D`). Guards, in order: protected-name
  check (main/develop matched case-INSENSITIVELY, prefixes rescue/, oi/,
  dependabot/), `git merge-base --is-ancestor refs/heads/<b> refs/heads/main`
  re-check at delete time, then `-d` with cwd=primary. Any refusal is
  reported as `KEPT-BRANCH <b> [reason]` and left alone. The merged set is
  read with `%(refname)` filtered to refs/heads/ so a same-named tag cannot
  masquerade as the branch. The no-upstream reason now also covers "upstream
  deleted on the remote" (GitHub auto-delete shape), which stays retirable.
  Deliberate deviation from plan round 2: main/develop protection is
  case-insensitive (the fail-closed direction).
contract_test_path: test/scripts/retire_worktree_e2e_test.dart
regression_test_planned: |
  - test/scripts/retire_worktree_e2e_test.dart group "branch deletion after
    retirement (OI-138)": 9 tests (dry-run then execute + slug reuse; keys on
    branch not folder slug; -d refusal via detached primary; protected
    prefixes; main/develop; same-name tag; upstream-gone matrix; the
    ancestry re-check under a deterministic race; a failed removal never
    touches the branch).
  - test/scripts/retire_worktree_lib_test.dart: protectedBranchReason,
    sanitizeBranchRefusal, reworded no-upstream reason.
  64 tests pass in the two files (46 lib + 18 e2e).
  MUTATION RESULTS (each confirmed applied, file restored byte-identical):
    M1 -1 red, M2 -3, M3 -2, M4 -2, M6 -1, M8 -4.
    M7 (ancestry re-check replaced with always-true): ZERO red against the
    first 62 tests. I recorded that as "an untestable race", and that was
    WRONG: the B-pass showed the window can be made deterministic with a
    reference-transaction hook (when a1's branch ref is deleted, commit on
    the next candidate b1 and advance its tracking ref). `git branch -d`
    accepts a branch merged into its UPSTREAM, so with an in-sync upstream
    the re-check is the only guard against deleting an unmerged branch, not
    defense in depth. New test added. M9 (`if (anc.exitCode != 0)` ->
    `if (false)`, grep -c confirmed applied): 1 red, the new test, failing on
    `BRANCH-DELETED b1` where `KEPT-BRANCH b1 [not an ancestor ...]` is
    expected (an assertion failure, not a compile error).
    M10 (branch deletion moved ahead of, and independent of,
    `git worktree remove`): 6 red, including the new failed-removal test,
    which fails on an unexpected `KEPT-BRANCH f1 [cannot delete branch ...
    used by worktree]`. Git's own refusal of a checked-out branch absorbs
    the DATA effect, so the guard is only visible in the output line, which
    is what that test asserts.
    Structural guarantees (never -D, never a remote) are absence-of-code
    properties and are not mutation-testable.
impact_analysis: |
  Scoped to worktree retirement. The tool does NOT refuse `--execute`
  without a slug (a pre-existing test, "--execute removes ONLY the
  retirable worktrees", runs it bare and expects exit 0). A bare
  `--execute` therefore now also deletes the branch of EVERY retirable
  worktree, each still behind the protected-name, ancestor and `-d`
  guards. Sessions are told to pass their own slug in CLAUDE.md
  §4.13.6/§4.13.8; that is prose, not enforced by the tool. Remote
  branches are never touched; the GitHub delete-head-on-merge setting
  handles those separately. Branch sweep of older branches is OI-273, not
  this change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/retire_worktree.dart + retire_worktree_lib.dart; 64 tests green; mutations M1-M4, M6, M8, M9, M10 all red; M7 (zero-red against the first 62 tests) closed by the M9 test." }
  - { tier: 12, name: "Client to server contract", status: verified, evidence: "Traced retire dry-run then execute on real linked worktrees in the e2e group, including a bare origin with push --delete, stale-tracking-ref and prune shapes." }
---

## Summary

Retirement removed the worktree folder but never its branch. It now deletes
the worktree's own merged local branch with `git branch -d`, with layered
guards, and reports anything it declines to delete.

## Root Cause

Writer gap: `retire_worktree.dart` had no branch-deletion step at all; the
execute loop (`:346`) ended at `git worktree remove`. Reader: the merged set
(`:216`) was used only to classify worktrees, never to clean up branches.

## Fix

`_deleteBranchAfterRetire` (`retire_worktree.dart:141`) plus the pure
`protectedBranchReason` / `sanitizeBranchRefusal` in the lib.

## Related

OI-138 (closed here), OI-273 (older-branch sweep, open). Git semantics
relied on: `branch -d` tests merged into HEAD or upstream, so it can delete
an unmerged branch whose upstream contains it and can delete `main` when the
primary is on another branch, hence the explicit ancestor and name guards.
