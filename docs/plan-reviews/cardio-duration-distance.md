---
branch: cardio-duration-distance
date: 2026-10-22
blast_radius: account
review_rounds: 9
ground_truth_verified: true
verdict: converged
---

# Plan-review record: a cardio or distance exercise keeps its minutes and km, and every screen shows them (OI-389 Batch 1a; closes OI-380, OI-382)

This is the record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). The plan is
`docs/plans/cardio-duration-distance.md`, revision 12.

**Tier: account, L.** The classifier on the planned file set returns `account`. The diff edits
`auth_session_bootstrapper.dart` (the heal's per-set table) and `lib/features/train/CLAUDE.md`, so §4.12.6 makes it
L, which runs the same full pipeline as M. The B-pass (`/code-review`) runs before the merge. Its result is added here
as `bpass_review:` once it is accepted.

## Rounds

Every round had two context-blind reviewers. They checked each claim against the code at `cbfa8884` and against
live data on `dedsavbjuwgarrhphgnl` (read-only):
- **A** checked ground truth.
- **B** checked exposure.

Each round's findings are mapped in the plan's §8.

| Round | Plan rev | A | B | Main findings |
|---|---|---|---|---|
| 1 | 1 | NOT CONVERGED | NOT CONVERGED | 5 P1s: hint for non-library names, the LogWorkoutSheet writer, §4.6, live-step order, clamp parity |
| 2 | 2 | CONVERGED | NOT CONVERGED (4 P1) | silent refusals and raw codes; "1800 km" in StatsGrid and graduation; coach prompt routing; rollback. Split into app / cloud cap / coach tool |
| 3 | 3 | NOT CONVERGED (2 P1) | NOT CONVERGED (2 P1) | km totalled before dedup; a refused coach exercise reads "Workout logged". Split 1 → 1a (this plan) / 1b (coach paths) |
| 4 | 5 | NOT CONVERGED (1 P1) | NOT CONVERGED (1 P1) | the restore-shape lift collapses multi-set rows; the reps of a carry are erased on coach routes; a live heal with no kill switch. Lift and live heal split out (§4.12.1) |
| 5 | 6 | **CONVERGED** (P2s) | NOT CONVERGED (1 P1) | the move-merge km is invisible on a mixed shape; `editLog` bounds a total; the sheet erases an F5 total; custom cardio still `timed` |
| 6 | 7 | **CONVERGED** (P2s) | NOT CONVERGED (1 P1) | the merge's third branch deletes a km today keeps (A raised it as a P2); stale `sets_detail`; the hint is not sticky |
| 7 | 8 | **CONVERGED** (P3 only) | **CONVERGED** (one P2) | a `sets_detail`-only destination in the merge. Folded into rev 9 with every P3 |
| 8 (delta) | 10 | NOT CONVERGED (1 P1) | NOT CONVERGED (1 P1) | founder D2 change (decimal minutes, 2026-10-22): the workout card captured the MIN box with `int.tryParse`, so "12.5" saved with no minutes; the edit sheet was digits-only |
| 9 (delta) | 11 | **CONVERGED** (P3 only) | **CONVERGED** (one P2) | malformed minutes in the edit sheet must be refused, not saved as 0. Folded into rev 12 with every P3 |

Rev 9 only folds round 7's P2 and P3s; both reviewers had already converged on rev 8. Rounds 8 and 9 are delta rounds
on the founder's D2 change (decimal minutes); rev 12 only folds round 9's P2 and P3s.

**Founder decisions (2026-10-22):** plan approved; D2 changed to decimal minutes; D8 accepted; D10 order confirmed;
D9 go, minted OI-391 (Batch 2), OI-392 (Batch 3), OI-393 (d), OI-394 (e). D4 explained and awaiting a yes.

## Ground truth verified

**Live data (read-only):**
- 0 cardio or distance rows ever, and 0 rows with km.
- `workout_log_sets`: 715 rows; `duration_secs` ranges 1..60.
- `wls_duration_secs_realistic` is `0..3600 NOT VALID`; there is no km CHECK; `distance_km` is `numeric(8,3)`.
- 55 cloud summary rows have no per-set rows, and all 55 are soft-deleted. So 0 live rows are restore-shaped.
- 0 rows whose stored type differs from the library.

**Code claims** were checked by both reviewers in every round, including:
- every writer and reader file:line;
- the formatter arithmetic;
- that `reschedule_week_terminal_row_test.dart:429-503` stays green unchanged;
- that each mutation M1–M73 reddens its named test.

## Splits under §4.12.1

These are recorded in the plan and the closure ledger as `blocked_on_user`. The OIs are minted (D9, 2026-10-22) and the order is
ratified (D10, 2026-10-22); each waits on the founder action its OI names:
- **1b:** coach paths (OI-389 stays OPEN for it).
- **OI-391, Batch 2:** the cloud duration cap (needs a live migration apply).
- **OI-392, Batch 3:** the coach `logCardio` tool (needs an ai-proxy deploy).
- **OI-393 (d):** a set logged on top of a restore-shaped or F5 exlog row resets its totals. This also covers the move
  merge's mixed shape.
- **OI-394 (e):** the live exlog type heal (the cast fix plus kill switch `disable_exlog_type_heal`).
