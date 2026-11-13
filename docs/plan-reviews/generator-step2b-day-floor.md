---
branch: generator-step2b-day-floor
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/generator-step2b-day-floor-bpass.md
---

# Plan review: generator-step2b-day-floor (Unit 2B, the 3-exercise day floor, OI-452)

- **Plan:** `docs/plans/2026-11-13-generator-step2b-day-floor.md` (v6).
- **Founder basis:**
  - OI-452's direction (2026-11-03): a hard floor of 3 exercises a day; a thin day may exceed the weekly band by a
    few sets, with its own stats.
  - Decisions d30 (no excess limit), d31 (every phase, deloads included), d32 (a day floored to its reach) and d33
    (the floor may pass the 300 s clock bound), all 2026-11-13, recorded on the step-2 board.
- **Tier and blast radius:** tier L (plan engine), blast radius platform.
- **§4.6:**
  - The new path is behind the Hive kill switch `disable_day_floor` (`PlanEngineFlags.dayFloorEnabled`, rule ON by
    default after the full ×2 review), with an optional `dayFloor` argument on `allocate`.
  - Switched off, it reproduces main 8a2e1c5a byte for byte over the injured sweep personas (fixture).
  - `plan_generator.dart` is not touched.

## Review rounds

Four rounds. Each is one fresh, context-blind Sonnet seat that read the plan, the prototype diff and main's code,
read-only (no tests run).

- **Round 1 (v1): not converged.** 3 P1:
  - the kill switch must also cover the 2A-off path, with an injured OFF proof;
  - F4's verdict claim was false;
  - the weekly-top readers need one oracle.
  The P2s led to the founder questions: the lighter phase and the clock bound.
- **Round 2 (v3, after d30-d33): not converged.** 2 P1: the reader lists were incomplete (the gate's time oracle,
  oi489, `auditPlan`). The P2 doubting the B copy was answered by measurement: no day lost a row over 34,560
  day-weeks, and 10 day-weeks have a set less.
- **Round 3 (v4): not converged.** 1 P1: `overClock` left a hole for a top-refused seat 1-300 s over the clock. It is
  redefined as "did not fit the remaining seconds". The P2s:
  - the full red-test list, plus a build rule that lists every red with its cause;
  - stale text;
  - a phase-4 gate block.
- **Round 4 (v5): converged.** 0 P0, 0 P1. Two P2s (§5's record / diagnose / SoT field; the label snapshot
  mechanism) and four P3s, all folded into v6, with no design change.

## Ground truth

- **Every measured figure** comes from scratch probes on the prototype, through a probe knob, over the real
  generator:
  - the two sweep blocks with thin days (34,560 day-weeks);
  - the whole injured grid in three worlds (46,512 runs, 418,608 day-weeks each);
  - a phase-4 pairs block.
- **Review checks:** the reviewers re-checked every file:line against main 8a2e1c5a, and the totals for internal
  consistency.
- **The build re-measures every figure** on the clean implementation.

## B-pass

Pending: `/code-review` on the built diff before the merge.
