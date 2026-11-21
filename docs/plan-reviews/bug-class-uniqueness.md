---
branch: bug-class-uniqueness
date: 2026-10-25
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0dde3b7f58f6-review.md
---

# Plan-review record: landing B of the merge-conflict-treadmill fix (bug-class uniqueness gate + renumber of nine ids)

This is the record for the section 4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/bug-class-uniqueness.md` (rev 3 with build notes); its parent is `docs/plans/merge-conflict-treadmill.md`
(section 7). It covers LANDING B only (closes OI-167; OI-309 stays open for C and D). A0 (#159), A1 (#160) and A2 (#167)
are merged. C and D each get their own branch, record, B-pass and PR.

**Tier: M, platform.** The diff adds one gate and its parser under `scripts/`, three test files, edits two skill documents
and nine citing documents, and adds two platform globs to `docs/blast_radius.yaml`. It touches no hook, no workflow and no
Edge Function. Execution mode: inline, one worktree.

## Rounds

Every round had context-blind reviewers who checked each claim against the code and the repository (read-only).

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1 | 1 -> 2 | 3 reviewers, all HARDEN | the census missed the skill's own two files (10 more citation lines, four of them red flags); the 16-character title rule needed a measured base (1 of 131 pairs differs); the tie-break between the two classes of a pair needed a stated rule; the gate had to land with the renumber in one commit |
| 2 | 3 | 2 reviewers, both CONVERGED, no P0/P1 | mechanical corrections folded in place (citation line numbers, legacy-map date rules, the lookalike rule for indented headings) |

## Ground truth verified

- On the base files (b0735bb1) the real gate reports exactly the nine duplicate ids (18 lines) plus the one 2.93 title
  mismatch, next free id 2.123; on the renumbered tree it prints PASS with headings=131 rows=131 and `--next` prints 2.134.
- The 18 repointed citation lines (8 outside documents in 7 files, 6 in SKILL.md, 4 in bug-classes.md) were each read in
  context by the B-pass; no citation of a moved class by its old id remains outside the dated historical carve-outs.
- `origin/main` (38f8a064) differs from the base only in `docs/audit/open_issues.md`; `git merge-tree` of the branch with
  it is clean and no new bug-class id appeared on main. The live session `sync-storm-first-sweep` holds 2.123 and 2.124,
  and the moved classes start at 2.125, so neither side renumbers.

## Rationale for three process choices

- **Commit type `feat(gates)`, not `fix`.** The commit adds a gate; the defect it closes (OI-167) is recorded in the diagnose
  doc `docs/diagnoses/2026-10-25-bug-class-number-collisions-d5b8e3.md` (validated) and cited with `closes-diagnose` anyway.
- **No section 4.2 closure ledger.** One defect (OI-167) in one mechanism (the same number chosen by eye); the nine ids are
  instances of it and close in the same commit. Every B-pass finding was fixed in the batch; nothing is deferred.
- **No section 4.11 soak.** The gate has no environmental input (two markdown files), was baselined by running it on the
  base files before the renumber (it found exactly the nine), and cannot land first because a gate-first commit fails its
  own pre-commit.

## Mutation proof (section 4.4 rule 21)

72 mutants of the parser, the gate wiring, the root resolution, the renumber outcome and the citations, each applied with
an exact-one-match assertion before the write, the three test files run, the sources restored and their sha256 re-checked
(RESTORE-CHECK OK). All 72 reddened at least one test on the final code (two needed a fix first: M06 a harness compile
error, M09 a title-less CRLF heading assertion). The table is in `docs/audit/gate_test_ledger.yaml`.

## B-pass (2026-10-25)

`docs/reviews/0dde3b7f58f6-review.md` (accepted): two fresh seats, 17 findings (0 P0, 0 P1, 2 P2, 15 P3), all fixed in
the batch. The gate loop on the final tree: `flutter analyze --no-fatal-infos` over the whole project 0 errors and 0
warnings, the complete suite (`TZ=Asia/Kolkata flutter test --exclude-tags golden`) 11342 passed and 11 skipped by their
own markers, 0 failed, and `sh scripts/pre-commit.sh` rc 0 with the staged-diff hash unchanged by the run.

## Residual, stated

CI runs the gate through the existing Audit Gates loop on the PR merge ref; the first CI run of the gate and of the three
test files on the runner (git 2.55.0, not this VPS's 2.43.0) is the proof that remains and happens on the pull request.
Two PRs that mint the same next id and are both green before either merges turn the main push CI red; the session that
merges second renumbers (landing D narrows the window).
