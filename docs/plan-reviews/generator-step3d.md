---
branch: generator-step3d
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step3d-bpass.md
---

# Plan review: generator-step3d (Unit 3D-b, "Keep training Phase 1" is the Monday-aligned hold week, OI-175)

- **Plan:** `docs/plans/2026-11-16-generator-step3d-hold-weeks.md`. Sections 2.1, 2.2 and 2.4 form the client flip;
  rev 5, plus the round 4 folds below.
- **Founder basis:**
  - d57 (2026-11-15): switch "Keep training Phase 1" to the Monday-aligned holdWeek, delete the old redoWeek4 in the
    same batch, and make the NOW marker follow the 4-week cycle past week 4. Device check at the end.
  - d80 (2026-11-16): hold weeks keep Peak, Peak, Peak, Deload. Only the "you are here" marker changes.
  - OI-125: selectable past hold weeks stay a separate feature.
- **Tier and blast radius:** tier L (Train UI, the schedule writer), blast radius platform. This commit REMOVES the
  ship-dark flag `enable_hold_weeks` (§4.12.4), so it is not the ship-dark tier: it carries the full review rounds
  and `bpass: accepted`. The server half (FOB-4) landed first as Unit 3D-a (`docs/plan-reviews/generator-step3d-a.md`).

## Review rounds

Fresh, context-blind Sonnet seats (two per round), each verifying claims against the code and live state.

- **Rounds 1-3 (the combined 3D plan).** Not converged; each round surfaced new P1s:
  - round 1: the double tap, the completed target day, the outcome enum, the read cost, the marker state and its
    lit rule;
  - round 2: the covered rule, the failed write, the stamp-word claims;
  - round 3: the completed-row keep without `ifUnchangedFrom`, the refresh after the write, the time-of-day
    `plan_end`, the lifted-deload word.

  Under §4.12.1 the plan split into 3D-a (server, first) and 3D-b (this client flip).
- **Round 4 (3D-b only, on rev 5).** Converged with no P0 or P1. The P2 / P3 findings below were folded into the
  build:
  - **F1:** `keepTrainingPhase1` refreshes through the container captured before the await (the screen can be
    popped mid-write).
  - **F2:** the graduation refresh also invalidates `todayWorkoutProvider`; Home's today card watches only the auth
    token.
  - **F3:** `_nextHoldOrdinal` stays a thin wrapper, so the oi189 slice keeps its end marker; ONE push, pinned.
  - **F4:** the split is consistent. FOB-4's code is 3D-a's; FOB-4-deploy is `blocked_on_user`.
  - **F5:** the static test hook is reset in `tearDown`.
  - **F6:** line drift and unused `plan_engine_flags` imports (analyze clean).
  - **F7:** Z-string `plan_end` tests for both sides of the Sunday.
  - **F8:** the final `lib/` grep shows history notes only.
  - **F9:** a non-completed target row takes the source copy.

## Build findings (beyond the plan)

- **Orphan rows join a later hold.** The plan said a crash-partial hold's orphan rows "stay in Hive, invisible to
  every hold reader". The new behavioural test proved that false: once a later hold moves `plan_end` past them, they
  are covered and join that hold's dates, so H1's week start read the orphan Monday.
  - **Fix:** `holdWeek` clears hold-stamped rows in the gap after `plan_end` and before the new hold's Monday before
    it writes. A planned row is deleted (the `sweepNonCompletedRowsPastPlanEnd` rule); a completed row keeps its
    content without the hold stamps.
  - **Tests:** the two "crash-partial ... a week LATER" and orphan tests in `hold_week_d57_behavioral_test.dart`.
- **Read cost.** One `holdWeeks()` call on a 3,007-key box takes 1.09 ms on this VPS, under the plan's 5 ms
  threshold, so no memo was added.

## B-pass

Accepted: `docs/reviews/generator-step3d-bpass.md`. Two fresh Sonnet seats ran on the committed head 543fa294 (CI
green). Seat A covered the services and ran tests and mutants; seat B covered the UI, the callers and the records,
and was read-only.

There were 10 findings: 0 P0/P1, 5 P2, 5 P3. All were accepted; the material ones:
- **A failed hold now puts its rows back (A-F2).** Four raw `is_hold` readers skip the covered rule; the cloud half
  of the local delete is OI-174's.
- **Five untested caller arms now have tests (B-F1).**
- **The orphan gap's lower bound is pinned (A-F1).**
- **The records match the code:** OI-60 is archived, and OI-188 and OI-166 are corrected.

Ten mutants were run on the fixes; all are red. See diagnose `d3b7e5`, B-pass section.
