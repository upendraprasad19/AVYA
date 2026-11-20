---
branch: oi518-maintain-followon
date: 2026-11-19
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d1c2e67887b1-review.md
---

# Plan-review record: OI-518 follow-on, three founder decisions on the Maintain callout (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Plan: `docs/plans/oi518-maintain-followon.md`
(revision 4). Tier M (§4.12.6: the diff leaves `lib/features/{home,train,nutrition,profile}/**` for the shared rule in
`lib/features/onboarding/target_weight_check.dart`). Blast radius `account`. `bpass` is set to `accepted` (with `bpass_review:`) after the
self-initiated `/code-review` (B-pass) on the CI-green branch, before the merge (§4.3).

## Rounds

| Round | Reviewers | Findings | Plan revision after |
|---|---|---|---|
| 1 | 2 context-blind Sonnet (A: rule, copy and their tests; B: widget, IST handling, test restructuring, docs) | 4 P1, 3 P2 (A); 3 P1, 5 P2 (B) | 2 |
| 2 | 2 fresh context-blind Sonnet (C: product-code design; D: tests, mutations, gates, docs) on revision 2 | 3 P1, 4 P2 (C); 3 P1, 6 P2 (D) | 3 |
| 3 | 1 fresh context-blind Sonnet, on revision 3 | 3 P1 (test-row gaps), 7 P2, no design finding | 4 |

Every finding of every round was applied in the plan (section 7 lists each one with its landing place); none was deferred. The
substantive plan-text errors the rounds caught: the existing behavioural tests that would all have turned stale under a far-future
injected clock; a const `_Fixture` that could not take a clock; "today" derived in two places; a mutant set that left the double IST
shift, the local-midnight difference (equivalent in three zones, now killed under a fourth) and a Build-only exemption alive.

## Ground truth

Reviewers read the real code for every cited file:line. The coordinator re-verified by scratch Dart runs on 2026-11-19: `tryParse`
accepts `20261118`, `2026-11-18T10:00:00` and rolls `2026-02-31` to March 3; the local-midnight day difference across the US DST
change is 8 under Asia/Kolkata and 7 under America/New_York.

## Verdict

Converged after three rounds: round 3 found no design issue, only missing test rows and wording. B-pass (`/code-review`, before the
merge) is required by §4.3 at `account` and is self-initiated after the build.
