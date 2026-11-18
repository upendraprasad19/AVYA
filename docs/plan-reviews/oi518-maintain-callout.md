---
branch: oi518-maintain-callout
date: 2026-11-18
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/bb5a04f8a371-review.md
---

# Plan-review record: OI-518 the Weekly Report weight card treats Maintain as a hold-weight goal (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Plan: `docs/plans/oi518-maintain-callout.md`
(revision 4). Tier M (§4.12.6: the diff leaves `lib/features/{home,train,nutrition,profile}/**` for the shared rule in
`lib/features/onboarding/` and `lib/core/copy/`). Blast radius `account`, computed with
`dart run scripts/blast_radius_from_diff.dart` on the product paths. `bpass: accepted` (with `bpass_review:`) was set after the
self-initiated `/code-review` (B-pass, two fresh seats, 10 findings, all fixed or recorded) on the CI-green branch, before the merge (§4.3).
The B-pass moved the screen-to-callout wiring into `WeightProjectionLine` (a runtime-tested unit); no plan decision changed.

## Rounds

| Round | Reviewers | Findings | Plan revision after |
|---|---|---|---|
| 1 | 2 context-blind Sonnet (A: rule, copy and their tests; B: widget extraction, gates, docs) | 7 P1, 8 P2 | 2 |
| 2 | 2 fresh context-blind Sonnet (C: product-code design; D: tests, mutations, gates, docs) on revision 2 | 4 P1 (two introduced by revision 2 itself: a name shadow and a cross-screen label change), 13 P2 | 3 |
| 3 | 1 fresh context-blind Sonnet, on revision 3 | 1 P1 (a pre-existing crash edge in the date branch, found while checking a claim the plan made), 6 P2, no design finding | 4 |

Every finding of every round was applied in the plan (section 7 lists each one with its landing place); none was deferred.
Substantive plan-text errors the rounds caught: an `if` chain that would have rendered a new kind as the date sentence; a
copy that re-derived the gap from a float (now one integer helper shared by the rule and the text); `hold` colliding with the
reserved free-tier repeat-week term; revision 2's change of the chart label on one screen only (reverted to the two new lines);
and a divide by a zero rate in the date branch, reachable on a flat series with a target exactly 0.5 kg away.

## Ground truth

Reviewers read the real code for every cited file:line. The coordinator re-verified the load-bearing claims directly:
`recomp` is not healed (`fitness_goals.dart:132`); `AppColors.orange` equals `warn` and `green` equals `ok`
(`colors.dart:118-130`); the Journey ETA never fires for Maintain (`journey_timeline.dart:58-60`); the float-edge pair
66.9 / 70.0 gives 30.999999999999943 (scratch Dart run, `round()` 31 versus `truncate()` 30).

## Verdict

Converged after three rounds: round 3 found no design issue, one reachable crash edge and wording. B-pass (`/code-review`,
before the merge) is required by §4.3 at `account` and is self-initiated after the build.
