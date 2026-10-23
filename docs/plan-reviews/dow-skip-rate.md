---
branch: dow-skip-rate
date: 2026-10-22
blast_radius: account
review_rounds: 4
ground_truth_verified: true
verdict: converged
---

# Plan-review record: the coach stops naming a weekday the user never trains or never singled out (OI-390)

This is the record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/dow-skip-rate.md`, revision 5.

**Tier: account, M.** The classifier on the planned file set returns `account`. The work is in an ai_coach service,
so §4.12.6 makes it M. Editing the nested `lib/features/ai_coach/CLAUDE.md` does not make it L (precedent R3A-P3).
The B-pass (`/code-review`) runs before the merge. Its result is added here as `bpass_review:` when it is accepted.

## Rounds

Every round had two context-blind reviewers. They checked each claim against the code at `cbfa8884` and against
live data on `dedsavbjuwgarrhphgnl` (read-only):
- **A** checked ground truth.
- **B** checked exposure.

Each round's findings are mapped in the plan's §7.

| Round | Plan rev | A | B | Main findings |
|---|---|---|---|---|
| 1 | 1 | NOT CONVERGED (2 P1) | NOT CONVERGED (4 P1) | an east-of-IST key bug; `custom_template` days dropped; a global contrast that fires on a lapse; a recurrence of OBS-3; stale copies are 10 embeddings + 3 interactions; Home widgets unmounted |
| 2 | 2 | NOT CONVERGED (1 P1) | NOT CONVERGED (1 P1) | T3 cannot fire (4/8 = 0.5); D4(a)/(b) deferred same-class bugs (§4.2) |
| 3 | 3 | NOT CONVERGED (2 P1) | NOT CONVERGED (1 P1) | the rev-3 additions (adherence 0% on empty, `lapseFacts` parity, upendra numbers) and a growing IST tail. Split under §4.12.1 into this batch and Batch B |
| 4 | 4 | **CONVERGED** | **CONVERGED** | P2/P3 only, folded into rev 5: week key east of IST; the seeding recipe; Bug C recurrence; the `getProgressSummary` sibling; D3 vs device replay |

## Ground truth verified

The reviewers probed the walk and anchor keys in 8 zones, including DST crossings and ±1 min around IST midnight
(round 2 A, round 4 A).

They recomputed these counts from live rows, and every one holds:
- upendra's day-of-week counts (T7);
- 90-day adherence `{40, 19, 21, 47}` (T14);
- the old-code figure, 34/16.

**Live check of the new rule:** 0 accounts fire it. The old rule fires on 22.

**Stale-copy inventory:** exactly 10 embeddings and 3 interactions. No other store holds the claim.

## Splits under §4.12.1

These are recorded in the plan and in the closure ledger as `blocked_on_user`, pending the founder's go to mint the
OIs and schedule the work:
- **Batch B:** IST-throughout for workout dates.
- **`rolling-context` re-embedding** (catastrophic-tier EF).
- **`getProgressSummary` `adherence_pct`** (EF, L).
