---
bug_id: c6a2e8
date: 2026-11-15
batch: generator-step2e
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 2, Unit 2E (OI-496, founder d51).
  - Under 60 minutes, some plans held 0 Biceps or 0 Triceps in one variant's weeks while the other variant trained them.
  - Measured on main 0c383703 over the 2,304-plan audit: 22 (plan, group) pairs in 21 plans, Biceps 13 and
    Triceps 9, all at 30 minutes except one Biceps plan at 45.
  - The arm row was in the selector's list on every residue day; the allocator never seated it.
concept: weekly_minimum
sot_registry_entry: weekly_minimum
contract_test_path: test/contracts/arm_swap_behavioral_test.dart
related_bugs: [e9b3d7, b3f1d8, d4a7e2]
recurrence: |
  Not a recurrence. It closes the residue Unit 2C-b's weekly minimum (e9b3d7) left under its own row cap (d44).
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grepped for "zero week", "Biceps", "Triceps", "minimumSeats",
  "row cap" and "arm". Hits:
  - e9b3d7 (the weekly minimum and the allowance);
  - b3f1d8 (the day floor, whose gate reads minimumSeats as a swap's excuse);
  - d4a7e2 (the lead-first allocator: the opener a swap never evicts).
  None of them seats a target past R's row cap.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateCore: the 2C-b allocation first; the arm re-run only on an arm pair, kept only with fewer pairs and no group lost (S8)", line: 287 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateLeadFirst fixpoint: an arm group B credits and A does not joins A's targets (S6)", line: 529 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: the arm swap after the minimum pass (S2-S5)", line: 1431 }
readers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "AllocationStats.credited / minimumSeats (the swap's seat is a minimum seat)", line: 68 }
  - { file: test/helpers/day_floor_gate_lib.dart, method_or_widget: "the day-floor gate's swap excuse (same rows, the new row a minimumSeats entry, the dropped row's groups still trained)", line: 150 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_weekTwoGains follows PopulatedDay.allowance (unchanged)", line: 175 }
hive_key_prefix: null
hive_key_formula: null
sync_methods:
  - "none: generation only; plan_json carries the swapped row like any row"
restore_methods:
  - "none"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched", line: 1 }
provider_invalidations:
  - "none: generation only"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a: pure allocation, no storage"
forbidden_patterns_checked:
  - { pattern: "a change to any plan without an arm pair (the gate: 21 changed plans of 1,152, each with an arm pair)", absent: true }
  - { pattern: "a group trained in a plan-week (1-3) at 0 after the swap (the gate, every group)", absent: true }
  - { pattern: "a day with a different exercise count (the gate, all four weeks)", absent: true }
  - { pattern: "a change at 60+ minutes or on the 6-day path (behavioral sweep; the golden and the kill-switch goldens are unchanged)", absent: true }
  - { pattern: "plan_generator.dart or exercise_selector.dart changed", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-15-generator-step2e-arm-swap.md.
  - S2-S5: after the minimum pass, in the allowance world only, an arm target still at 0 takes its cheapest slot by
    swapping out the day's last over-served row (budgeted or a kept hold; never rank 0, the opener, a minimum seat or
    a focus row), at 2 sets, within caps and tops, and no longer than the day was.
  - S6: an arm group B gains late in the fixpoint becomes a target of A.
  - S8: the 2C-b allocation runs first. The arm re-run happens only on an arm pair and is kept only with fewer pairs
    and no group lost.
regression_test_planned: |
  test/contracts/arm_swap_behavioral_test.dart (crafted; round 1 added the opener, S8-reject, arm-slot order, restore
  and empty-group cases); test/plan_generator/weekly_minimum_gate_test.dart (the 2E block: 1,152 plans, seam on
  against off, the 34 newly-trained plan-weeks pinned; the 2C-b pins updated for the closed pairs).
impact_analysis: |
  Platform tier (plan engine). 21 of 2,304 audit plans change, all at 30 / 45 minutes, each by one row per affected day
  (a second row of an over-served group gives way to the arm row). Calves stays at main's 49 pairs (d45 / d49). No
  60+ minute plan, 6-day plan or plan without an arm pair changes. Kill switch: 2C's disable_balanced_week (d37).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "session_set_allocator only; flutter analyze clean; tests and mutations below" }
  - { layer: hive_local_state, status: not_applicable, evidence: "no Hive key; generation only" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration; plan_json rows are ordinary exercises" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the golden (60-minute personas) is unchanged" }
---

# Unit 2E: no week without direct arm work under 60 minutes (OI-496)

## Root cause

Two causes, both in `SessionSetAllocator`:

1. **The row cap.** Under 60 minutes, 2C-b's re-runs hold each day at R's rows (d44). On every residue day, rank 0,
   the 2A opener and the kept holds (spent first) fill that cap, so the minimum pass, which never passes the day's
   admitted-row target, refuses the arm slot.
2. **A's targets were read too early.** A's d35 targets are read against step 1's B. In 2 plans (strength 4-day
   advanced home_dumbbells, 30 minutes, phases 2 and 3) B gains Biceps only later, as a protective target, so A never
   learns that B trains it.

## Fix

See `proposed_fix` above and the plan's section 2 (S1-S8).

## Measured on the built tree

The audit comparison against main (2,304 plans; scripts in `scratchpad/oi496/`):

| | main | built |
|---|---|---|
| Biceps / Triceps / Calves zero-week pairs | 13 / 9 / 49 | 0 / 0 / 49 |
| plans changed | - | 21 (exactly the arm-residue plans) |
| plan-weeks newly at 0 (any group, weeks 1-3) | - | 0 |
| plan-weeks newly trained | - | 34 |
| rows per day | - | unchanged |
| displayed minutes past the session | +6 | +6 |
| audit headline table | - | identical |

**Why S8 exists.** The first prototype (the swap inside every fixpoint round) changed 23 plans. In two advanced
bodyweight 30-minute plans with no arm pair at all, the trajectory changed and Calves left the plan in weeks 1 and 3.
- The audit's pair count read this as an improvement (Calves 49 -> 47), because a group at 0 in every week is not a
  pair.
- The 2C-b gate's "Calves newly at 0 at 30" count caught it (143 -> 147).
- The per-plan-week "newly at 0" check is now in the 2E gate.

## Neighbouring pins re-recorded (found by the PR's first CI run, attributed with the test seam off)

- `test/contracts/session_allowance_behavioral_test.dart`, the 220-plan seeded sweep. Its digest changed because one
  plan changed, and that plan had an arm pair with the seam off. The test now allocates each plan with the seam off
  too, requires an arm pair for every changed plan, pins that count (1), and re-records the digest. Every invariant in
  the sweep (time, rows equal to R) still holds.
- `test/plan_generator/repeat_minutes_gate_test.dart` (Unit 2D's gate). Three blocks lost reach:
  - 30->45 bodyweight: 41 -> 39 gained, 128 -> 126 rows;
  - 30->60 bodyweight: 350 -> 348 rows;
  - 30->60 home_dumbbells: 305 -> 304 rows.
  Phase 1 at 30 minutes now holds the arm row, so the repeat pins it and has one fewer isolation left to append. With
  the seam off the three blocks measured exactly the 2D values. There were 0 invariant failures either way.
- I had run 14 neighbouring gates locally, but not these two (bug class 2.162's last point).

## Mutations

Each mutant was applied once (the runner refuses a pattern that does not occur exactly once). It was run against
`arm_swap_behavioral_test.dart` + `weekly_minimum_behavioral_test.dart`, and the survivors against the 2E block of
`weekly_minimum_gate_test.dart`. The files were restored and sha-checked (`scratchpad/oi496/mut/`).

| id | mutation | red |
|---|---|---|
| E1 | `armPairsOf` counts groups at 0 in BOTH variants | 4 |
| E5 | rank 0 may be a victim | 1 |
| E6 | the opener may be a victim | 2 |
| E8 / E8b | a focus row (budgeted / hold) may be a victim | 1 / 1 |
| E9 / E9b | the over-served rule dropped (budgeted / hold) | 1 / 1 |
| E10 | victims walked front to back | 1 |
| E11 / E11b | no time check / the strict forcing bound only | 3 / 1 |
| E12 / E13 / E13b | no session cap / no other-group top / the target's own top checked | 1 / 1 / 1 |
| E14b | a failed hold attempt not restored | 2 |
| E15 | S6 off (no arm targets for A in the fixpoint) | gate: 19 changed, 2 pairs left |
| E16 | Calves and Core join the arm groups | 1 |
| E18 | the re-run at 60+ and on the 6-day path | 3 |
| E19 | the swap's seat not recorded in `minimumSeats` | 3 |
| E2, E3, E4 | S8: re-run every plan / no loss check / accept equal pairs (each alone) | 0 (gate) |
| E2+E3+E4 | all three together | gate: 23 changed, 4 plan-weeks newly at 0 (the p3 prototype) |

**Survivors, stated:**
- **E2 / E3 / E4.** Any one of S8's three conditions keeps the grid's two bad trajectories out:
  - without the pair check, a no-pair plan's re-run cannot have FEWER pairs than 0;
  - without the strict fewer-pairs rule, the pair check still skips them;
  - without the loss check, those plans never re-run.
  The triple mutant reproduces the prototype's losses. All three are kept as stated defence in depth.
- **E17** (`allowance &&` dropped from the swap's guard). Equivalent by construction: the re-run happens only under 60,
  where `runA` / `runB` always pass `allowance: under60`.
- **E21** (a target credited by a kept hold). Equivalent on the grid: targets come from `credited`, which already
  counts kept holds; only a hold a later round keeps after an earlier round evicted it could reach it.
- **E7** (a minimum seat as victim). Masked by the over-served rule: a minimum seat was seated for a group the day did
  not credit, so it is the day's only credit for that group, unless the seat credits several groups.
- **E14** (a failed BUDGETED attempt not restored). Not reached: no measured or crafted plan had a budgeted attempt
  fail and a later one succeed. The hold half (E14b) is red.
- **E20** (`nonBudgeted` not decremented after a hold eviction). It is read only by the count verdict (`rowsOf`), which
  would read one row high on a day already below the count floor. Not reached.
- **E22** (a reservation-blocked slot as the arm slot). Not reached on the grid or the fixtures.

## Round 1 fixes and their mutations (2026-11-15)

Fixes (plan review log, round 1): the victim guard's opener uses `lead[]`'s rule (A1); a swap that would change the
day's opener is refused (`keepsOpener`, d48's mirror); S8 keeps the re-run only with the first run's allowance stamp
(B5); a taken budgeted victim leaves `floorSeats` / `countForced` and gets a `why` (A5 / B6); a failed trial resets
the day's spent seconds exactly (A7). The 2E gate block is unchanged on the fixed tree (21 changed, pairs 21 -> 0,
0 newly at 0, 34 newly trained, +6), and the 2C-b ON digest is unchanged (794121ba...).

Method: a 4,158-case probe sweep (day orders x arm row x B list x minutes x level x custom) and a second 1,026-case
sweep (custom fillers; budgeted victims cheaper than the arm row), each run on the fixed tree, with the seam off, and
under every mutant; then `arm_swap_behavioral_test.dart` under every mutant. Files restored and cmp-checked
(`scratchpad/step2e/r1mut/`).

| id | mutation | probe | red in the test file |
|---|---|---|---|
| A1 | the old `opener[d] ?? ...` | 120 plans | 1 (refused opener) |
| KO | `keepsOpener` always true | 54 plans | 1 (compound chin-up) |
| A1+KO | the round-0 code | 54 plans | 1 |
| A5 | the budgeted victim's `_dropSeat` removed | 162 orphan seats | 1 (orphan sweep) |
| FT / TIE / COST | first candidate only / day order reversed / cost order reversed | 0 | 1 / 1 / 1 |
| RSTH | a failed hold trial not restored | 0 | 3 |
| KEEP / RESTORE | S8 always keeps the re-run / the stats not restored on a reject | 3 plans | 1 / 1 |
| EMPTY / EMPTYh | an empty-group row skipped (budgeted / hold) | 0 / 6 plans | 1 / 1 |

**Survivors, stated:**
- **B5 and LOST** (the stamp clause, the loss clause, each alone): every reject the probes reach is also refused by
  another clause (the KEEP mutant reddens; each single clause does not), like E2-E4 above. Defence in depth.
- **A7** (no exact reset): equivalent in every case measured; the residue it removes is about 1e-13 s.
- **KOv** (the victim not excluded from `keepsOpener`'s list): equivalent by construction, since the victim is never
  the opener (it is skipped before) and `openerOf` keeps the first of tied rows.
- **WHY** (the victim's `why` not set): no `belowFloor` label changed in either probe.
- **RSTB** (a failed budgeted trial not restored): not reached in 5,184 probe cases (E14 above).
- **S6**: not reached by a crafted case in the probes; the gate keeps it red (E15: 19 changed, 2 pairs left).
- The hold `_dropSeat` call was removed as dead code: holds are never in `floorSeats` or `countForced`.
- The reviewer's evict-the-real-lead case (A1's stated risk) was not reached in the probes: when B credits the arm
  group, 2C-b's walk seats the arm slot early. The fixed rule is the one `lead[]` uses, pinned by the refused-opener
  test.
