---
branch: oi348-walk-rest
date: 2026-11-28
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi348-walk-rest-bpass.md
---

# Plan-review record — OI-348 walk, the non-referral items

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform tier, so it carries a
B-pass. Not catastrophic, so no Hermes.

Scope: the 22 Nov walk of AAB +50, every item except the referral one (another session's): weekly-report chart
date labels, an Edit Profile save whose screen closed, and refusing duplicate custom-exercise names (founder:
"Refuse any duplicate"; one exception approved 26 Nov for a community row no picker can show). Reviews added the
body-fat result, its refusal messages, the coach swap list and the swap and injury-planner target rule.

## Departure from §4.12.1
No separate plan document was written, and both rounds reviewed the BUILT diff, not a plan before execution.
They were run as the two independent reviews after the founder approved the full review.

## Rounds
- **Round 1** (two context-blind Sonnet seats, mechanism and tests/registry/docs, on `d0c813c2`): the findings
  included untested restore paths, a chart label overlap, a provider call through a dead `ref`, a coach message
  wrong for built-in names, a name guard blind to repeated spaces, and weak closed-screen tests; the same round
  led to the closed-screen body-fat fix. All folded in `ff457c3e`.
- **Round 2** (fresh seat, post-round-1 diff, `efc5c123`): NOT converged. A reopened form could write the old
  body fat over the new result; the refusal messages never showed (older); a founder call on community rows with
  no equipment; test and search gaps. All folded in `584c8b82`.
- **Convergence:** round 2's folds were reviewed by the B-pass. Its seats on later fix commits each looked only at
  the previous fixes; the last one (`9208c360..3727bccd`) found nothing above P3.

## Ground truth
Findings were checked against the code by the coordinating session before they were folded. One reviewer claim
class (line cites) was also re-checked by a sweep and the registry parity gate.

## B-pass
Accepted: `docs/reviews/oi348-walk-rest-bpass.md` (five seats, 19 findings: 16 fixed, 2 unchanged with a reason,
1 older equipment gap added to OI-403).

## Merge commits made without the local hook
Three conflicted merges of `main` (`c398b7c9`, `9a4d3135`, `b8e970e6`) were committed with the pre-commit hook
skipped, each approved by the founder in chat; the reason is in each commit body. CI ran the full suite on the
pushed heads and was green on `b8e970e6` and every head after it.
