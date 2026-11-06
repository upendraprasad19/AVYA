---
branch: local-indexes
date: 2026-10-24
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/8f8019f81b15-review.md
---

# Plan-review record: landing A2 of the merge-conflict-treadmill fix (OPEN_INDEX.md and diagnoses/INDEX.md become local build products)

This is the record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/merge-conflict-treadmill.md` (revision 7, section 6, with the A2 build notes and the B-pass fixes). It covers
LANDING A2 only; A0 (#159) and A1 (#160) are merged, and B, C and D each get their own branch, record, B-pass and PR.

**Tier: platform, L.** The diff edits `scripts/pre-commit.sh`, `scripts/pre-merge-commit.sh`, `.github/workflows/test.yml`,
`scripts/discipline_hook.dart` and CLAUDE.md, adds a gate, and removes Gate 25. Execution mode: inline, one worktree per
landing.

## Rounds

Every round had context-blind reviewers who checked each claim against the code and the live repository state (read-only).
The plan's revision history maps each round's findings to the text change.

| Round | Plan rev | Result | Main findings (A2 only) |
|---|---|---|---|
| 1-4 | 1 → 5 | folded | landings split (A into A1 and A2); hook shims dropped; automatic rebuild removed from Claude Code hooks (D7) |
| 5 | 6 | A2: exposure CONVERGED, ground truth HARDEN (one P1) | R5C-1: the stamp digest needs a shared library, so the builders DO gain an import and every fixture copy list must change (`pre_merge_commit_e2e_test.dart` copied five files); the nudge uses `Directory.current`, spawns nothing and emits once; `pre-merge-commit` keeps its build |
| 6 | 7 | A2: both reviewers CONVERGED, no P0/P1 | mechanical text corrections folded in place: one closure helper for fixtures (R6C-1), the untracked branch of `pre-merge-commit` keyed on `git check-ignore -q` with no backup (R6C-2, R6C-4, R6D-4), a failed WRITE of a regenerable output is exit 3 and a warning (R6D-3), the nudge's not-installed warning keys on an A2-only literal (R6D-1); three planned build lines dropped |

## Ground truth verified

- The real orchestrator builds both indexes strictly from the real diagnose docs (674) and the real OI board (265 open
  issues) on the tree rebuilt on origin/main `c0565234`, rc 0; the output differs from the previously committed indexes only
  by the stamp line, one header sentence, the Re-run lines and the new eeca32 row.
- The real `pre-commit` and `pre-merge-commit` hooks were run in scratch repos for every index state (tracked, ignored,
  neither; old and new scripts), and, after the B-pass, the FROZEN A0 hooks (`test/scripts/fixtures/pre_a2_hooks/`) were run
  against an A2 tree, which is what the B-pass found the earlier fixtures could not see.
- The CI steps' own `run:` string is executed in a test against a bad board and a dateless doc; the first run of the strict
  step on the runner (git 2.55.0, not this VPS's 2.43.0) is the proof that remains and happens on the pull request.
- Writer and reader file:line for every changed contract were checked by the reviewers and again by the B-pass; the SoT
  concept `local_generated_indexes` resolves (Gate 42 strict).

## Mutation proof (§4.4 rule 21)

First round: 116 mutants on the sources and hooks (99 reddened a test, 17 survived; every survivor got a test or a code
change and the 20 re-runs all reddened), 10 CI-step mutants (10 killed), 14 mutants on the new gate (14 killed, ledger
evidence). B-pass round: the reviewers' own 41 mutants (19 red, 22 survived: 21 real holes and 1 equivalent), then 43
author mutants against the final tests (42 red outright; PC-1 reddened exactly the two tests written for it). Every mutant
was applied with an anchor count of 1 asserted before the file was opened for write, analyzed clean, run, and restored with
sha256 equal.

## B-pass (2026-10-24)

`docs/reviews/8f8019f81b15-review.md` (accepted): two fresh seats, 18 findings (0 P0, 1 P1, 8 P2, 9 P3), all fixed in the
batch, none deferred. The P1 was an analyzer warning in a new test that no `lib/`-only loop could see (it would have aborted
`pre-push` and turned the CI `Analyze` job red); one P2 falsified a claim of the batch's own diagnose doc (an OLD installed
hook BLOCKS a merge commit in a fresh worktree of an A2 tree) and is fixed in the tree itself, so no old hook needs the
reinstall to stay safe. The gate loop: `flutter analyze --no-fatal-infos` over the whole project 0 errors and 0 warnings (the infos are
pre-existing), `sh scripts/pre-commit.sh` rc 0 with the staged-diff hash unchanged by the run, the 14 A2 test files
(319 tests) and 147 doc, registry and payment-adjacent test files (1545 tests) all passed on the final tree (base
`c0565234`). The complete suite (`TZ=Asia/Kolkata flutter test --exclude-tags golden`, golden excluded as on every VPS
run) passed locally, 11003 passed and 10 skipped by their own skip markers, on the state before the last rebuild
(base `70f1237c`); the complete suite for the final tree runs in CI on the pull request.

## Rebuilds on a moved main

While the branch sat staged and then committed, main moved three times: PR #164 (thin-day-topup, `70f1237c`) touched nine of the
staged files, PR #165 (payment-hardening, `f58db308`) eight, and PR #166 (session-set-budget, `c0565234`, 31 commits) ten, in each
case among them OPEN_INDEX.md (a modify/delete conflict by design) and `docs/sot_registry.yaml`; the first two also touched
`docs/diagnoses/INDEX.md`. The branch was rebuilt on each new origin/main instead of merging main into it: a merge commit trips
the catastrophic review gate when main gains catastrophic content (payment-hardening is that), and it would put main's work
into this PR's diff. The staged tree was carried with a three-way `git merge-tree` over an unreferenced synthetic commit (the
third time over the committed tip), and the only conflicts were the index deletions and, once, the registry (every entry
from both sides kept). Each time the same 80 files are staged. On the last rebuild every diff is identical to the reviewed one
by per-file `git patch-id --stable` except `docs/audit/OPEN_INDEX.md` (still deleted, now deleting main's newer content); on
the first rebuild four lines were edited (two code comments and two numbers in the diagnose doc), later ones only numbers in the
diagnose doc. The strict build of the real tree passed on each (669, 674 and 674 diagnose docs, including every new doc of the
other batches). The review file was re-keyed `80a750831480` -> `fbad7f170797` -> `f3e9a074d6e6` -> `8f8019f81b15`; only its
`staged_against` line changed.

## Hand-off

The merge needs `--allow-workflow-change` (the diff edits `.github/workflows/test.yml`), which the founder authorized in chat ("Go commit push PR merge"). The push needed the `workflow` scope on the VPS token, which the founder granted. After
the merge, the roll-out runs once per machine: in the primary `git checkout -- docs/diagnoses/INDEX.md
docs/audit/OPEN_INDEX.md` if either is dirty, `git fetch origin main && git merge --ff-only origin/main`,
`dart run scripts/build_local_indexes.dart --lenient`, `sh scripts/setup-hooks.sh`; the founder repeats it on the Windows
clone. A branch cut before this change that edited either index meets one modify/delete conflict on its next sync
(`git rm --cached` both paths, then run the builder).
