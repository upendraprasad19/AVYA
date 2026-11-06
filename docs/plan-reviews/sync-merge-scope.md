---
branch: sync-merge-scope
date: 2026-10-25
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ee891702469b-review.md
---

# Plan-review record: landing C1 of the merge-conflict-treadmill fix (a branch sync is graded by what the merge adds beyond main)

This is the record for the section 4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/sync-merge-scope.md` (revision 4 with an as-built section); its parent is `docs/plans/merge-conflict-treadmill.md`
(section 7). It covers LANDING C1 only (closes OI-413; OI-309 stays open for C2, the record-aware resolver, and D, the merge
train; OI-337 stays open for the blast-radius classifier script). A0 (#159), A1 (#160), A2 (#167) and B (#171) are merged.

**Tier: M, platform.** The diff changes one platform gate (`scripts/check_code_review_pass_exists.dart`), adds its pure lib
`scripts/merge_scope_lib.dart` (registered platform in `docs/blast_radius.yaml`), five test files and a fixture, and edits
registries, the board, the ledger and documents. It touches no hook, no workflow and no Edge Function. Execution mode: inline,
one worktree.

## Rounds

Every round had context-blind reviewers who checked each claim against the code and the repository (read-only).

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1 | 1 -> 2 | 3 reviewers, all HARDEN | the name-keyed `remerge UNION overlap` rule missed content that git relocates by rename (P0/P1), replaced by an entry comparison; `git write-tree` (index.lock) and `git merge-tree` (git 2.38) dropped; OI-413 and the rejected stand-down cited |
| 2 | 2 -> 3 | 2 reviewers, both HARDEN, no P0/P1 | the spine test replaced by a comparison with the tip of origin/main (an interior or reverted MERGE_HEAD exempted what main no longer holds); the staged list and the scope list cross-checked; `dotAll` for this gate's glob engine |
| 3 (delta) | 3 -> 4 | 2 reviewers: one CONVERGED on the rule, one HARDEN on the test plan only (1 P1: no end-to-end test of the fail-closed path) | G11-G14 and G1b added; exact-reason assertions; byte-string set logic; S18-S20; a one-mutant-per-row table |

## Ground truth verified

- Measured on this repository's history (git, base `d1292a79`): of 46 `Merge branch 'main'` syncs the full staged diff reaches
  `catastrophic` in 8 and `platform` in 24 (38.0 paths on average); graded by the rule it reaches `platform` in 12 and
  `catastrophic` in none (5.3 paths). Over the wider 124 syncs, 23 reach `catastrophic` by the full diff and none by the rule. Four
  independent re-runs agreed; the B-pass seat S2 reproduced the populations from git.
- The rule was exercised against REAL git: 23 scenarios (hand resolution, renames, directory renames, a clean combination,
  `-X theirs`, an old and a moved tip, a hostile repo-local config, a gitlink, a linked worktree), a seeded fuzz of 80 syncs with three
  oracles computed without the lib, and the REAL gate spawned in temp repositories (29 tests: exit codes and the exact NOTE).
- The branch was synced with origin/main (f683076f) before the final review hash; the only conflicts were the append-only OI boards.

## Rationale for three process choices

- **Commit type `feat(gates)`, not `fix`.** The commit changes a gate; the defect it closes (OI-413, five recorded trips) is
  recorded in the diagnose doc `docs/diagnoses/2026-10-25-branch-sync-review-gate-d1264d.md` (FULL template, recurrence class,
  validated) and cited with `closes-diagnose` anyway.
- **No section 4.2 closure ledger.** One defect (OI-413) in one mechanism; every B-pass finding was fixed in the batch and nothing is
  deferred.
- **No runtime flag and no section 4.11 soak.** The gate has a narrow trigger (a pending merge), fails closed on every failed
  precondition, and rolls back by a revert; it was baselined by running the rule over 46 and then 124 historical syncs before any code was written.

## Mutation proof (section 4.4 rule 21)

79 mutants of the lib and the gate (every row of the plan's table except 6a, which has no code to mutate, plus the B-pass additions),
each applied with an exact-one-match assertion before the write, `dart analyze` required clean (a compile error is not red), the five
test files run, the sources restored and their sha256 re-checked (RESTORE-CHECK OK). The whole table ran on the FINAL tree, after the
last edit of code and tests: 79 of 79 red. An earlier run had one survivor (a hex check that accepts a leading dash), closed by a
test. The table is in `docs/audit/gate_test_ledger.yaml`.

## B-pass (2026-10-25)

`docs/reviews/ee891702469b-review.md` (accepted): two fresh seats, 16 findings (0 P0, 0 P1, 8 P2, 8 P3), all fixed in the batch. The
gate loop on the final tree: `flutter analyze --no-fatal-infos` over the whole project 0 errors and 0 warnings, the complete suite
(`TZ=Asia/Kolkata flutter test --exclude-tags golden`) 11538 passed and 11 skipped by their own markers, 0 failed, and
`sh scripts/pre-commit.sh` rc 0 with the staged-diff hash unchanged by the run.

## Residual, stated

Every test ran on this VPS's git 2.43.0; the first run on the CI runner's git 2.55.0 is the pull request itself. The NOTE is on
stdout, names the first 20 graded paths and is not stored (the pre-commit loop discards a gate's output), so a reviewer reads it by
re-running the gate while the merge is pending; a FAIL lists every graded path. Only `refs/remotes/origin/main` is the reference
(a sync from another remote or branch is graded in full), a squash merge has no MERGE_HEAD and is graded in full, and CI's keystone
gate is unchanged.
