---
branch: merge-train
date: 2026-11-03
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/b073e94ab265-review.md
---

# Plan-review record: landing D of the merge-conflict-treadmill fix (`land_pr.sh`, the merge train)

This is the record for the section 4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/merge-train.md` (revision 4 with an as-built section 8); its parent is `docs/plans/merge-conflict-treadmill.md`.
It covers LANDING D, the last landing: A0 (#159), A1 (#160), A2 (#167), B (#171), C1 (#176) and C2 (#190) are merged. The
board entry OI-309 closes with this landing.

**Tier: L-equivalent, platform.** The diff adds a pure library (`scripts/land_pr_lib.dart`), a CLI (`scripts/land_pr.dart`), a wrapper
(`scripts/land_pr.sh`) and a CI classifier in `scripts/safe_pr_merge_lib.dart`, five test files and a fixture, all registered platform in
`docs/blast_radius.yaml`, and edits the plans, hooks.md, the glossary, build-apk.md, the board (OI-309 moved to the closed file) and
CLAUDE.md (section 4.3 and the section 7 row). It touches no hook, no workflow and no Edge Function. It is developer tooling: nothing runs in
the app and nothing is deployed. Execution mode: inline, one worktree.

## Rounds

Every round had context-blind Sonnet reviewers who checked each claim against the code and the repository (read-only).

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1 | 1 -> 2 | reviewers HARDEN, no P0 | the written comparison of the options (merge queue unavailable for a personal-account repository, auto-merge useless without required checks, a lock unsound, a worker over other sessions' branches out of bounds); one command for the CURRENT branch only |
| 2 | 2 -> 3 | HARDEN, no P0 | the replay of the plan-review-record gate must be faithful to CI and checked by its FINAL pass line; the CI classifier built by construction on the existing judge; exit-code and `result:` protocol |
| 3 (delta) | 3 -> 4 | HARDEN on details, no P0 or P1, converged | main and PR-head re-checks in rounds, interrupt rules, scratch-clone sweep by directory name, stub protocol for the tests |

## Ground truth verified

- The replay was exercised against the real gate (`check_plan_review_record_exists.dart`) in throwaway repositories: a change without a record
  is refused, the same change with a valid record and review file passes, a main that moves between the ancestry check and the replay is
  `needs-human`, a TERM during the real replay leaves no merge.
- The CLI ran end to end against real git and a stub `gh` (the stub protocol of plan section 5), including the real sync step, signals, a closed
  stdout and a non-UTF-8 byte; the wrapper ran under `sh`, bash, with a spaced path and with SIGKILL of the CLI.
- 5 test files (lib: decisions and classifier, e2e, replay, wrapper e2e, source pins) plus the existing `safe_pr_merge_lib_test.dart`
  (byte-identical reasons); the final full run has 12925 passed.

## Mutation proof (section 4.4 rule 21)

87 mutants (library, CLI, classifier, wrapper, B-pass additions) and 3 controls (comment-only edits, all green), applied to a copy of the tree
with an exact-match assertion, compile error never counted as red, sources restored and compared. 86 red. One survivor, N09 (the
`try/catch` in the safe stdout writer turned into `rethrow`): a closed stdout reports through `stdout.done`, so no test reaches the catch; it
is defence for a detached stdout and is not claimed proven. Three mutants (N11, W05, W07) are red only by a source pin: the child-wait guard
of the uncaught-error path, the early-signal window of the wrapper (microseconds) and the bash early-reap branch (this machine's bash does not
reach it). The first discovery run had survivors C26, C35, W02, W03 and an anchor miss W04, each got a test or pin and was re-run red; the
B-pass fixes were mutated too. The re-run also found two test defects, fixed: the SIGHUP wrapper test failed when the suite was started under
`nohup` (an ignored signal cannot be trapped; the test now resets the dispositions through perl), and a `startSpawn` without `reportSpawn`
(caught by the full suite's spawn-sites guard). Self-attested.

## B-pass (2026-11-03)

`docs/reviews/b073e94ab265-review.md` (accepted): two fresh Sonnet seats (S1 library and CLI, S2 wrapper and docs), 0 P0, 0 P1, 5 P2 and the
P3s raised, merged into 12 entries, all fixed in the batch or stated as accepted residuals (R1: no lock, OI-92). Gate loop on the final tree:
whole-project `flutter analyze --no-fatal-infos` 0 warnings and 0 errors, the complete suite (`TZ=Asia/Kolkata flutter test --exclude-tags
golden`) 12925 passed, 14 skipped by their own markers, 0 failed after the spawn-guard fix (the first full run had that one failure, fixed and
re-run: guard 95/95 with the e2e file), and `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh` rc 0.

## Residual, stated

R1: there is no lock, so two runs for one PR, or two in one worktree, can interleave (OI-92 makes a shell lock unsound here); the PR head
check and `safe_pr_merge.sh` still refuse a stale head. Every test ran on this VPS's git 2.43.0; the first run on the CI runner's git 2.55.0 is
the pull request itself. The wrapper needs `sh` and is untested on Windows. One unrelated test (`test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`)
failed once under load in an earlier full run and passed alone and in the final full run. The temporary `workflow` scope of the VPS gh token
is for the founder to remove (`gh auth refresh -h github.com -r workflow`).
