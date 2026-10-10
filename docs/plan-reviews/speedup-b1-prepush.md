---
branch: speedup-b1-prepush
date: 2026-10-10
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/speedup-b1-prepush-bpass.md
---

# Plan review — release-cycle speedup B1: pre-push branch-push skip + `safe_pr_merge.sh` (`speedup-b1-prepush`)

The plan is `docs/plans/2026-10-10-release-cycle-speedup.md` (master plan, four batches B1..B4; this record covers B1,
§2 of that plan). Founder directive 2026-10-09: "push and merge and CI is taking a lot of time everyday; plan and
implement all of these."

## Why this record exists

B1 edits `scripts/pre-push.sh`, adds `scripts/safe_pr_merge.{sh,dart}` + `safe_pr_merge_lib.dart` (pinned `platform`), and
touches `CLAUDE.md`, `docs/blast_radius.yaml`, `.github/workflows/test.yml` (comment only). Blast radius `platform`, so
CLAUDE.md §4.12 requires two context-blind plan-review rounds plus a B-pass before the merge to `main`.

## Rounds

| Round | Reviewed | Outcome |
|---|---|---|
| 1 | Master plan v1 (one 7-unit batch), fresh Sonnet reviewer with no session context, told to verify every claim against code and live state | **needs-rework.** 0 P0, 11 P1. The ones that change B1: the planned goldens-only local run was a false premise; the compensating control was voluntary and its own spec (`every job success`) could never pass because two jobs are `skipped` on a PR run; the allow-rule text was wrong (it named raw `gh pr merge`); the one-batch scope was too large (§4.12.1: split). Every claim was spot-checked by the author against the code before use (pre-push.sh stdin drain at the capture site, `ci_workflow_concurrency_test.dart:73`, repo visibility, `@Timeout` counts, ledger and registry pins). |
| 2 | Master plan v2 (four batches, round 1 applied), a SECOND fresh reviewer, same brief | **needs-rework, localized.** 0 P0, 8 P1, all spec fixes; "a third full round is not warranted unless the edits change a design". Those that change B1: goldens run NOWHERE today (pre-push passes `--exclude-tags golden`, verified at `pre-push.sh:151`), so the step would have been a NEW gate that false-reds on the Linux VPS — dropped; the real check-run job name is `Plan-review record (>=account merge-to-main)`; filter to `app.slug == github-actions` (a real PR also carries Vercel's check); fail closed on `gh`/network failure; use a pure Dart evaluator with an injected lister. All applied in plan v3. |

## Ground truth (verified against code and live state, 2026-10-10)

- `scripts/pre-push.sh`: stdin was drained with `cat > /dev/null`; the full suite runs at every tier above `feature`; analyze is unconditional and placement is pinned by `test/contracts/hook_gate_placement_test.dart`. Measured full-suite wall-clock on the founder PC: **38 min** (2026-10-10 run, 8,542 tests), matching the 39 min in OI-275.
- CI: `Unit Tests` 13.0-13.5 min is the critical path; every other job <= 4 min (`gh run view 37971525387`, `37958167385`). CI runs on the PR and again on the push to main.
- Main protection: `required_status_checks: strict:true, contexts:[]` (no required checks), `enforce_admins:true`, `required_conversation_resolution:true` (`gh api repos/upendraprasad19/AVYA/branches/main/protection`). Requiring checks was tried 2026-07-25 and blocked every direct push and `/build-apk`, so it is NOT proposed.
- On a PR run `Plan-review record (>=account merge-to-main)` and `Supabase Integration Tests` are `skipped` (run 37958167385); the `safe_pr_merge_lib.dart` job lists are asserted equal to the seven `name:` fields of test.yml by a test.
- Goldens: both CI and the pre-push suite pass `--exclude-tags golden`; the comments claiming otherwise (`dart_test.yaml`, `docs/blast_radius.yaml`) were wrong and are corrected.

## Execution evidence (post-plan, for the B-pass)

Full local suite 8,542 passed / 1 failed (a recursion-pin test that enumerates tests running the pre-push hook; fixed and re-run); `flutter analyze lib/` 0 warnings or errors; the pre-commit gate loop passes; new/changed tests: 23 + 65 + 17 + 6; mutation proof in `docs/diagnoses/2026-10-10-release-cycle-wallclock-c7a3e9.md` and the B-pass file. The B-pass (`docs/reviews/speedup-b1-prepush-bpass.md`) found 0 P0, 0 P1 and 12 P2, all fixed in this batch with their mutants re-killed.

## Convergence

**Converged for B1.** Round 2's remaining items were localized spec fixes (no design change), all applied; the B-pass then reviewed the BUILT code independently and its findings were closed with mutation evidence. Residual risk, stated plainly: a red branch can now leave the machine (it is caught by the PR CI, by `safe_pr_merge.sh` when used, and by main CI); the GitHub web-UI merge button bypasses the wrapper (founder-owned; the alternative was tried and reverted on 2026-07-25). OI-275 stays OPEN: its item D, the allow-rule `Bash(sh scripts/safe_pr_merge.sh:*)`, is a settings change that is the founder's to make.
