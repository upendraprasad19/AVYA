---
branch: library-injury-recheck
date: 2026-10-24
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/library-injury-recheck-bpass.md
---

# Plan-review record — injury re-check: 104 library rows gain 148 injury tags (platform, live)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`.** Confirmed on 2026-10-24 over the whole branch
(`git diff origin/main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -`). The diff
touches `lib/shared/repositories/plan_engine/**`, `lib/core/services/seed_service.dart`, the library
data and its tests, fixtures and baselines.

## Plan
`docs/plans/2026-10-23-library-injury-recheck.md` (revision 3, plus the Execution rulings table
E1 to E9 appended while building). Executed INLINE (founder, 2026-10-23). It follows the founder's
2026-10-23 rulings: reject the 13-B "kept safe for variety" principle and tag per injury, keep the
lower_back tags on Decline Sit Up and Reverse Hyper, the exercise picker, swap and add sheets stay
unfiltered, thin days get a top-up as OI-401, and "Ship, allow 4" for the pairs empty-day ceiling.

## Review rounds (context-blind Sonnet reviewers, every claim checked against code and data)

1. **Round 1:** NOT converged. 0 P0, 4 P1, 7 P2, 3 M. All applied in revision 2 and revision 3. The
   P1s: the warm-up test (`warmup_injury_filter_behavioral_test`) pins Push Up kept for shoulder and
   was not probed; the sweep's env override tripped `spawn_env_manifest_test`; the scorecard
   no-regression ceilings were not probed (they redden); and two injuries at once were unmeasured
   on the OFF path. (A P2 in the same round: Tricep Pushdown wrongly removed from the shoulder
   substitutes.)
2. **Round 2** (on the post-round-1 plan): **CONVERGED**, 0 P0, 0 P1, 9 P2, 5 M. All applied before
   execution (the pairs became 15 pairs of six injuries, the sweep three separate tests, the seed
   test a plain `test()`, the push-up warm-up positive control).

Ground truth: the plan's probes ran the full change through the real generator and the widest test
set that can read the library (6,641 passed, 12 failed before the repoints, all now green).

## Execution rulings (appended to the plan, none made in secret)
E1 table before tests as spec data; E2 personas by reach search, unreached moves on `queryV4`; E3
pairs gate as a ratchet; E4 the sorted assertion covers the table's rows; E5 pairs ceiling 4 (the
founder was asked and said ship); E6 the scorecard check compares fresh against fresh; E7 Ruling 2
reversed (Diamond and Incline Push Up tagged shoulder); E8 five sweep blocks over 3 to 6 day plans
with their own ceilings; E9 the library data classifies `account` in `docs/blast_radius.yaml`.

## B-pass
`docs/reviews/library-injury-recheck-bpass.md`: one fresh read-only Sonnet reviewer at HEAD
`07f41517`, 0 P0, 1 P1, 5 P2, all six verified by the author and accepted, none a false alarm.
The P1 was the author's own unilateral ruling (two push-up variants left shoulder-free to avoid thin
days); it is reversed and pinned by a test with a five-test mutation. The rest: the sweep now proves it
scanned something and covers all four day counts (it found 1 and 6 empty days), the baseline refresh's
absorbed older decline is attributed to `ad896b42` and filed as OI-404, the coach injury-swap planner
that ignores the tags is OI-403, and the library data now classifies `account`.

## Verification before merge
Full local `flutter test` (`TZ=Asia/Kolkata`) on the pre-fix HEAD: 10,585 passed, 24 skipped, 0 failed
(39:24); re-run on the fixed HEAD before the push. `flutter analyze lib/`: 0 errors, 0 warnings.
CI on the pull request is the full-suite gate for the merge.
