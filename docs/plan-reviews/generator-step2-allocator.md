---
branch: generator-step2-allocator
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step2-allocator-bpass.md
---

# Plan review — generator-step2-allocator (Unit 2A: the lead-first set allocator, OI-486)

Plan: `docs/plans/2026-11-12-generator-step2-allocator.md` (v8). Founder basis: the generator overhaul's step 2, decisions
d26 (the full fix with its measured costs), d27 (focus exercises exempt from the cap), d28 (d26 kept after its overrun was
corrected; the session-budget gate's limit raised only for days it does not already excuse, to exact seconds, with a
ratchet) and d29 (the priority-1 opener clause dropped). Tier L (plan engine), blast radius platform. §4.6: the new path
is behind the Hive kill switch `disable_lead_first` (`PlanEngineFlags.leadFirstEnabled`, the rule ON by default after the
full x2 review; switched off, it reproduces main's output byte for byte, pinned by a golden fixture), with optional `leadFirst` arguments on `allocate` and `apply`; `plan_generator.dart`
is not touched.

## Review rounds

Seven rounds, each one fresh context-blind Sonnet seat reading the plan, the prototype diff and the audit dumps.

- Rounds 1-3: 2 P1 each (the cap's costs, "never worse than main" overstated, the sequencer change R4's unstated cost,
  the physique focus halved). Two went to the founder (d26, d27); R4 was removed and the lead became the sequencer's own
  opener (the remove-the-mechanism rule).
- Rounds 4-6: 0 P1 (6, 3 and 4 P2): the overrun restated against the gate's limit (d28), the priority-1 clause (d29), one
  lead definition, the gate's own accounting, mutants, test files, the exact sweep ratchet.
- Round 7: converged, 0 P1, 2 P2, 6 P3, no design finding. P2-1 the whole-engine assertion test lost its hold exception
  (0 rows in every grid); P2-2 the cap alone with the opener as the lead measured (c6665). The P3s were text and five
  added mutants.

Every finding was folded into the next version; section 13 of the plan logs each round.

## Ground truth

Every number in the plan was taken from a full 2,304-plan audit run of the prototype (`plan_audit_dump_test.dart`, phases
1-3, no focus and both focus values, plus phases 4-5) against main's run on the same grid. The chosen rule is z7051:

- starved-lead plans 1,084 -> 47 (the 57 residue flags are all holds, named);
- suitable 513 -> 789;
- days with an exercise at the lead + 2 or more: 2,676 -> 58 in week 1;
- zero cells 0, days below the floor 0, first exercise changed on 0 days;
- costs stated: 12,090 days lose an exercise, total minutes -0.32%, Calves -3,374 sets.

The build re-measures every figure on the clean implementation, and the B-pass reads the built diff.

## B-pass

Accepted 2026-11-13 (`docs/reviews/generator-step2-allocator-bpass.md`). Three fresh Sonnet seats reviewed commit
e2486ce8 after CI went green on it.

Result: 0 P0, 0 P1, 3 P2, 11 P3. Every finding is fixed in the review commit or verified clean with evidence:
- B's `leadSeats` now cover the days B copies from A.
- The v14 pin's cause was traced (the Glutes session cap).
- The count-forced excuse is pinned to exact days and seconds in four sweeps.
- Three fallback / week-2 mirrors got fixtures (M16, M5, M9), and each mutant reddens.
