---
branch: sync-resolver
date: 2026-11-02
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/b10f3873e2a9-review.md
---

# Plan-review record: landing C2 of the merge-conflict-treadmill fix (a record-aware branch sync)

This is the record for the section 4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/sync-resolver.md` (revision 4 with an as-built section 9); its parent is `docs/plans/merge-conflict-treadmill.md`.
It covers LANDING C2 only. OI-309 stays OPEN until landing D (the merge train). A0 (#159), A1 (#160), A2 (#167), B (#171) and
C1 (#176) are merged.

**Tier: L-equivalent, platform.** The diff adds a pure library (`scripts/sync_resolver_lib.dart`), a CLI
(`scripts/sync_with_main.dart`) and a wrapper (`scripts/sync_with_main.sh`), all registered platform in `docs/blast_radius.yaml`,
eight test files and two helpers, and edits the plans, hooks.md, the glossary, the board (one progress sentence) and CLAUDE.md
(one sentence in 4.13.2 and one row in section 7). It touches no hook, no workflow and no Edge Function. It is developer tooling:
nothing runs in the app and nothing is deployed. Execution mode: inline, one worktree.

## Rounds

Every round had context-blind Sonnet reviewers who checked each claim against the code and the repository (read-only).

| Round | Plan rev | Result | Main findings |
|---|---|---|---|
| 1 | 1 -> 2 | 3 seats, all HARDEN, no P0 | a vacuous self-check replaced by three independent checks (V-a, V-b, V-c); emission rules; the alternative of resolving only records that overlap git's hunks recorded |
| 2 | 2 -> 3 | 2 seats, both HARDEN, no P0 (1 P1) | state-directory and crash-window rules, the four write rules (backup first, atomic rename), refusal mirrors, exit-code taxonomy |
| 3 (delta) | 3 -> 4 | 2 seats, both HARDEN on details, no P0 or P1, no design defect | V-c clean-output only, V-a exact for a line occurring once, the tip resolved to a SHA once, no direct-write fallback, test rows for every refusal |

## Ground truth verified

- The resolver was replayed over this repository's real merge history (`git log --merges -600`; numbers in plan section 7 and 9) and
  its output compared with the human resolution; the false-positive and survivor corners are stated in the plan.
- It was exercised against REAL git: library tests on real files, a seeded fuzz (13 tests), end-to-end CLI tests in temporary
  repositories (77 + 17 state + 26 wrapper), and source pins; 330 tests in 8 files.
- The branch was synced with origin/main (b472b496) before the final review hash; the conflicts that exist in the history are the
  append-only boards, which is what the tool resolves.

## Mutation proof (section 4.4 rule 21)

205 mutants (library 99, CLI 93, wrapper 13) and 4 controls (a comment-only edit of each file, which stayed green), each applied
with an exact-match assertion, compile error never counted as red, sources restored and compared. The discovery run found
survivors; dead or equivalent code was removed, ill-formed mutants were replaced, the rest got tests; the five final-run survivors
(MW12, MK34, MK54, MK62, MK86) each got a test and were re-run red; the 12 B-pass fixes were mutated too (B1-B12, all red).
Self-attested.

## B-pass (2026-11-02)

`docs/reviews/b10f3873e2a9-review.md` (accepted): two fresh seats (S1 library and tests, S2 CLI, wrapper, tests and docs), 0 P0,
0 P1, 9 P2, 10 P3 raised, all fixed in the batch or stated as accepted residuals in plan section 9. Gate loop on the final tree:
whole-project `flutter analyze --no-fatal-infos` 0 warnings and 0 errors, the complete suite
(`TZ=Asia/Kolkata flutter test --exclude-tags golden`) 12717 passed and 14 skipped by their own markers, 0 failed, and
`sh scripts/pre-commit.sh` rc 0 (re-run after the last sync with main).

## Residual, stated

Every test ran on this VPS's git 2.43.0; the first run on the CI runner's git 2.55.0 is the pull request itself. The wrapper needs
`sh` (Git Bash on Windows) and is untested there. A signal sent to the wrapper alone does not reach the CLI's children: a supervisor
(landing D) must signal the process group. OI-309 closes at landing D, not here.
