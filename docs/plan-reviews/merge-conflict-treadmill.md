---
branch: merge-conflict-treadmill
date: 2026-10-24
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/cedb32369c1c-review.md
---

# Plan-review record: landing A0 of the merge-conflict-treadmill fix (atomic read-only hook install; `git add -u -- <index>`)

This is the record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/merge-conflict-treadmill.md` (revision 7, with the A0 build notes). It covers LANDING A0 only; A1, A2, B, C
and D each get their own branch, record, B-pass and PR.

**Tier: platform, L.** `scripts/setup-hooks.sh` moves to platform in `docs/blast_radius.yaml` (it is the only writer of
the hooks every worktree runs), and the diff edits CLAUDE.md. Execution mode: inline, one worktree per landing.

## Rounds

Every round had context-blind reviewers who checked each claim against the code and the live repository state (read-only).
The plan's revision history maps each round's findings to the text change.

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1-4 | 1 → 5 | folded | landings split; hook shims dropped; A0 shrank to `git add -u`; automatic rebuild removed from Claude Code hooks (D7); A0 test redesign; A1 structural parsing |
| 5 | 6 | A0: exposure CONVERGED, ground truth HARDEN (one P1) | R5A-1: two planned mutations could not redden any test, and the post-install `cmp` had no covering test; the test and mutation table was rebuilt |
| 6 (delta, A0) | 7 | HARDEN (one P1, five P2) | the README had no test; five wording fixes in the test table; all folded |

## Ground truth verified

- The measured evidence (47 of 52 replayed main-sync merges conflicted, 46 only in shared docs/ledger/generated files) was
  replayed on a pinned commit and re-anchored on the base the A0 branch was cut from.
- Hook installation behaviour was exercised against the real five hook sources in scratch repos (dash and bash), and
  Gate 32 was run against that install (PASS, no WARN).
- Code claims (writer and reader file:line, the env scanner's treatment of every `$NAME` in `scripts/setup-hooks.sh`, the
  `install_hook "..."` call-shape parsers) were checked by the reviewers and again by the B-pass.

## Mutation proof (§4.4 rule 21)

53 mutants on the final state (46 on `scripts/setup-hooks.sh`, 7 on `scripts/pre-commit.sh`), each applied with a match
count of 1, run against its test file, and restored with the sha256 of both scripts verified equal afterwards. Every
mutant reddened at least one case.

## B-pass (2026-10-24)

`docs/reviews/cedb32369c1c-review.md` (accepted): two fresh seats, 32 findings (0 P0, 0 P1, 8 P2, 24 P3), all fixed in
the batch, none deferred. The full gate loop on the final state (base 87a0d8d1): `flutter analyze lib/` 0 warnings and
0 errors, `TZ=Asia/Kolkata flutter test --exclude-tags golden` all passed (10599 tests), `sh scripts/pre-commit.sh` rc 0.

**Rebuild and re-key.** The review was first named `df17bd0d780e`. While the branch sat staged, the library-injury-recheck
landing reached main (1f1ea306) and touched `docs/blast_radius.yaml`, `docs/diagnoses/INDEX.md` and the tuning archive.
The branch was rebuilt on 1f1ea306 (a 3-way merge of the staged tree; the only conflict was the two appends at the end
of the tuning archive, resolved by keeping main's entry then this one) rather than merged, because a merge commit of
that much unrelated platform-tier content would need a review of its own. The staged-diff hash became `cedb32369c1c`
and the review file was renamed to it; its `staged_against` line and the archive entry record the old name. The review
text was not changed. Equivalence proof: the same 15 files are staged, and `git patch-id --stable` of 12 of the 13
hashed files is equal to the reviewed diff's (including `docs/blast_radius.yaml`, which main also changed);
`docs/diagnoses/INDEX.md` adds the same lines and differs only in its context rows. After the rebuild: `sh scripts/pre-commit.sh` rc 0 with the hash
unchanged by the run, and the two new e2e files plus the blast-radius contract tests pass (74 cases). The full suite
runs in CI on the pull request.

## Hand-off to the next landing

A2 cannot merge until the installer has been run from a current primary on the VPS and on the founder's Windows clone
(the installed hooks are copies; an old `pre-commit` still uses a plain `git add`).
