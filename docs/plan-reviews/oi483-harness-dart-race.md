---
branch: oi483-harness-dart-race
date: 2026-11-07
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi483-harness-dart-race-bpass.md
---

# Plan-review record: OI-483, the `dart run` native-assets race at the harness hooks, the launchers and the Dart spawns (platform)

**Tier `platform`, L:** the nine harness commands in `.claude/settings.json`, the shared helper `scripts/_dart_bin.sh`, the launchers `land_pr.sh`, `sync_with_main.sh`, `safe_pr_merge.sh` and `safe_merge.sh`, and seven Dart spawn sites. Founder scope call on 2026-11-07: "B", all sites stay in OI-483.

Plan: `docs/plans/2026-11-07-oi483-harness-dart-race.md`. Diagnose: `docs/diagnoses/2026-11-07-harness-launcher-dart-race-e4c1b7.md`. Execution mode: inline, one worktree; subagents only reviewed.

## What this branch is

A lost race exits 254 before `main`, which the harness reads as allow, so `git_safety_hook.dart` could let a raw commit through. The branch contains the race everywhere OI-468 and OI-482 had not: the harness commands behind a probe that cannot change the outcome, the launchers through `run_dart_cli`, which forwards signals and never retries after one, and the Dart spawns through `scripts/dart_race_retry_lib.dart`, with a sweep test over `scripts/`.

## Rounds

- **Round 1:** two fresh Sonnet readers on v1. Mechanism lens: no P0, 1 P1. Tests and pins lens: 4 P1. Led to v2.
- **Round 2:** two fresh Sonnet readers on v2. Mechanism lens: no P0, 1 P1. Tests lens: 2 P1, no design change. Led to v3.
- **Round 3:** one narrow Sonnet reader on the v3 delta. No P0, 1 P1 and 4 P2, all mechanical test-spec items: `mechanical_only`. Led to v4, the plan built.

## Ground truth

Every harness command string was run for real before review, under dash and bash, against a throwaway repo. Measured facts the plan rests on: dart walks UP to find the package, so the replay clone reads the primary's yaml; `dart run` does not heal an empty yaml; a FIFO as the yaml holds a real dart inside its read, then a real 254. The design note's contrary claim was false and is corrected at the top of the note.

## B-pass

`docs/reviews/oi483-harness-dart-race-bpass.md`: five fresh seats, 25 findings (5 P2, 20 P3), 0 false alarms. It changed the code: the probe went through three measured forms, and the rejected ones are permanent mutants. Mutation before it: 54 of 54 reddened. Open founder check: B1 in the closure ledger, the Windows clone.
