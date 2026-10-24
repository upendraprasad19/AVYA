---
branch: l2-no-custom-autoadd
date: 2026-10-21
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d15cd2688bbc-review.md
---

# Plan-review record — Batch 0a: the generator never auto-adds custom exercises (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart <changed paths>` →
`platform` (`lib/shared/repositories/plan_engine/**`, docs/blast_radius.yaml:105).

## Plan
`docs/plans/2026-10-21-l2-no-custom-autoadd.md`; diagnose `d4b8e1`.

## Review rounds (context-blind Sonnet reviewers, every claim checked against code)
1. **Round 1** on the combined plan (L2 removal + repair migrator): generator removal confirmed complete
   (line citations, both call sites, no other caller, no other auto-add path, seam count 16 → 15);
   1 P0 + 6 P1 + 8 P2 — ALL in the repair half (wiring, plan_json push, repeat pins, template marker,
   Gate 49, §4.6).
2. **Round 2** on the post-round-1 plan (r2): generator removal re-confirmed (seam recount with comments
   stripped, unused-import check, `_muscleTokens`/`_buildCustomExercise` still used); 0 P0, 5 P1 + 8 P2 —
   again ALL in the repair half (restore-settled gate, WriteResult handling, active-session guard, seam
   and Gate-19 placement).

Per §4.12.1 the unit was SPLIT: this branch ships the converged generator removal (Batch 0a). The repair
(Batch 0b, `docs/plans/2026-10-21-l2-custom-repair.md`) went to round 3 (0 P0, 3 P1) and continues on its
own branch with its own record.

## B-pass
`docs/reviews/d15cd2688bbc-review.md` — 0 P0, 0 P1, 1 P2, 4 P3, all resolved in this batch,
verdict accepted.

## §4.6 feature-flag waiver
No kill switch: the removed path is the defect itself (founder decision 2026-10-21, "never auto-add
customs"); a switch would keep it reachable and §4.6 step 4 deletes the old path anyway. Revert = `git
revert` of the merge. The B-pass (Finding 1) asked that the founder accept this explicitly; asked in chat
2026-10-21. **Accepted by the founder in chat 2026-10-21** ("yes, accept the waiver — merge #138");
PR #138 merged as `c54e63ba` the same day.

## Verification
- `flutter analyze lib/`: 0 errors, 0 warnings (60 pre-existing infos elsewhere).
- New behavioural test 4/4; mutations: L2 restored → 3/4 RED, L6 replacement removed → test (4) RED.
- 11 neighbouring test files 72/72; the three path-separator fixes 30/30.
- Full local suite (Windows, TZ=Asia/Kolkata, goldens excluded): 10,048 passed; the only failures were the
  three Windows path-separator tests (now fixed) and `mint_migration_e2e_test.dart`, which was killed by
  the 50-minute local timeout (a sh-subprocess e2e that runs on Linux CI). CI on the PR is the full-suite gate.
- Gates: exercise seams, SoT parity / behavioral paths / completeness / citations, context budget,
  diagnose validator, and the full pre-commit loop on commit c6fd56e3.
