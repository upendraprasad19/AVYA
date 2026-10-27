---
branch: tuning-entry-in-review
date: 2026-10-24
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/bdba2d338b41-review.md
---

# Plan-review record: landing A1 of the merge-conflict-treadmill fix (the tuning entry moves inside the review file; the archive is frozen)

This is the record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/merge-conflict-treadmill.md` (revision 7), section 5. It covers LANDING A1 only. A1 is independent of A0.

**Tier: platform, L.** The diff edits CLAUDE.md, the code-review skill and the gate `scripts/check_skill_tuning_history.dart`
with its pure predicate. Execution mode: inline, one worktree per landing.

## Rounds

Every round had context-blind reviewers who checked each claim against the code and the live repository state (read-only).
The plan's revision history maps each round's findings to the text change.

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1-4 | 1 → 5 | folded | landing A split into A1 and A2; A1 structural parsing instead of regexes over prose |
| 5 | 6 | A1: both reviewers CONVERGED | spec pins folded: tier normalization, the scanner state machine (fence before comment), the flipped tests |
| 6 | 7 | A1 unchanged | the round concerned A2; A1 text was not touched |

## Ground truth verified

- The conflict evidence (35 of 52 replayed main-sync merges conflicted in the tuning archive) was replayed on a pinned
  commit and re-anchored on the base this branch was cut from.
- The reviewer measured the friction of the new rule against history: of 176 existing reviews with a legacy entry naming
  them, 0 would fail date equality and 2 (1.1 percent) would fail tier equality; 0 of 338 reviews trip the scanner.
- Every reader and writer of the tuning entry was listed (the gate, the SKILL.md template, docs/reviews/README.md,
  `scripts/batch_close_lib.dart`, CLAUDE.md section 5.1) and checked for contradiction.

## Mutation proof (§4.4 rule 21)

44 mutants (20 from the build, 24 added for the B-pass findings), each applied with a match count of 1, run against both
test files and restored byte-identical (sha256 of both scripts verified equal afterwards). Every one reddened at least one
case. One mutant survived once (a BOM in front of the `reviewed_at:` key) and was pinned.

## B-pass (2026-10-24)

`docs/reviews/bdba2d338b41-review.md` (accepted): one fresh seat, 7 findings (0 P0, 0 P1, 2 P2, 5 P3), all fixed in the batch, none
deferred. The gate loop on the final state: `flutter analyze lib/` 0 warnings and 0 errors; `sh scripts/pre-commit.sh` rc 0;
the full suite ran once after the last code edit: 10620 passed, 1 failed. The failure was a broken-pipe race while the
harness wrote the payload to a stub hook that never reads its stdin (`test/scripts/claude_hooks_cwd_independent_test.dart`,
mutant M9; a file this batch does not touch). It passes alone 3 of 3 and is fixed on its own branch
`hook-test-stdin-epipe` (PR #158; a deterministic regression test, red without the fix).

## Hand-off

None for the next landing. A1 changes how a review records its tuning entry; the archive stays readable and frozen.
