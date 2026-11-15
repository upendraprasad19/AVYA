# Generator Unit 2E: no week without direct arm work under 60 minutes (OI-496, founder d51)

Status: v1, 2026-11-15. Base: main after Unit 2D (PR #280). Board card t217. Tier L (plan engine), blast radius
platform. Execution: inline, one worktree (`generator-step2e`).

## 0. Scope and founder basis

**OI-496**, measured on main 0c383703 over the 2,304-plan audit (`plan_audit_dump_test.dart`):
- 71 (plan, group) zero-week pairs remain: Biceps 13, Triceps 9, Calves 49, Core 0.
- Calves: the founder accepted these under d45 / d49. Not in scope.
- Biceps / Triceps: 22 pairs in 21 plans (one plan holds both), all at 30 minutes, except 1 Biceps plan at 45.

**d51 (2026-11-15, "Swap in an arm row").** At 30-45 minutes, when a week would hold 0 Biceps or 0 Triceps but the
other week trains them:
- swap that day's last extra row of an over-served group for the arm row, at 2 sets;
- same exercise count, same time.

**Not changed:**
- 60+ minutes;
- Calves;
- every group but Biceps and Triceps;
- the selector;
- `plan_generator.dart`.

## 1. Writers and readers (measured)

**The writer** is `SessionSetAllocator._variant`, the minimum pass of Unit 2C-b, in the allowance world (under 60).
- The arm row IS in the selector's list on every residue day (`scratchpad/oi496/probe.log`). Examples:
  - bodyweight Pull + Core: Self-Resisted Bicep Curl;
  - gym Push + Core: Tricep Pushdown (Cable).
- The minimum pass never goes past the day's admitted-row target. Under 60 that target is R's row cap (d44).
- Rank 0, the 2A opener and the kept holds fill the cap, so the pass refuses.

**A second cause, found by the prototype (2 Biceps plans, strength 4-day advanced home_dumbbells 30):**
- A's d35 targets are read once, against step 1's B (`session_set_allocator.dart`, the 2C-b driver, step 2).
- B gains Biceps only later in the fixpoint, as a protective target.
- So A never learns that B trains Biceps.

**The readers:**
- the week's per-group sets: `AllocationStats.credited`, and the audit's zero-week count;
- the 2B day-floor gate's swap excuse (`day_floor_gate_lib.dart`). A day with the same row count, whose new row is a
  `minimumSeats` entry and whose dropped row's groups are still trained that week, is a swap and not a loss.

## 2. Design

- **S1. Where it runs.** Only in the allowance world (`allowance` true: lead-first, floor on, balanced week on, under
  60 resolved minutes), right after the minimum pass and before the count verdict.
- **S2. The trigger.** A target `g` in {Biceps, Triceps} that is still at 0 in the ledger and not credited by a kept
  hold.
- **S3. The arm slot.** Candidates are the non-admitted, non-reservation-blocked slots of `g` on any allocated day.
  They are tried cheapest first (2-set seconds), then by day.
- **S4. The victim, on the arm slot's day.** Walk the day's list back to front. The first row that passes all of these
  is the victim:
  - a budgeted admitted row or a kept library hold;
  - not rank 0;
  - not the day's opener (the 2A lead; on the main path, the opener of the admitted rows);
  - not a minimum seat;
  - crediting no focus group (d38);
  - every one of its groups credited by another admitted row or kept hold of the same day (the "over-served" rule).
- **S5. The swap.**
  - Free the victim: a budgeted row is un-admitted and its sets and seconds come off the ledger; a hold goes to
    `evicted` and its seconds come off.
  - Then seat the arm slot at 2 sets when all of these hold:
    - every group's session cap;
    - every other group's weekly top;
    - the day's time within the forcing bound, or no longer than before the swap (d51: same time).
  - Otherwise restore the victim and try the next one.
  - The row count is unchanged.
  - The seat is recorded in `AllocationStats.minimumSeats` with `g`.
- **S6. The fixpoint (the second cause).** Under 60, after each round, an arm group that B now credits and A does not
  joins A's targets, and the loop continues (the same 4-round bound).
  - The protect-first step and the terminal guard are unchanged. A swap that costs a protective group, or a day's
    row, still sends the plan to R verbatim.
- **S7. Kill switch.** None new (d37). It rides 2C's `disable_balanced_week`: off, the allowance world never runs.
  `SessionSetAllocator.debugArmSwap` is a test seam only (never set in lib/).
- **S8. Reach: only plans with an arm zero-week, and never at a group's cost.** `_allocateCore` runs the 2C-b
  allocation first, with no swap and no S6. It allocates again with them only when that result has an arm pair (one
  variant at 0 Biceps or 0 Triceps while the other credits it; `armPairsOf`). It keeps the re-run only when:
  - the re-run has fewer arm pairs;
  - and no group either variant credited is at 0 in it (`lostAny`, Calves included).
  Otherwise the plan is the 2C-b allocation byte for byte. The 6-day path (B = A, so no pair) and 60+ minutes never
  re-run.
  - Why (measured on prototype p1 / p3): with the swap inside every fixpoint round, two advanced bodyweight 30-minute
    plans that had NO arm zero-week on main changed trajectory. Calves left them entirely (2 -> 0 in weeks 1 and 3),
    and V-Up / Calf Raise became Pike Push Up / Skater Squat.
  - The audit's pair count hid it, because a group at 0 in every week is not a pair. The 2C-b weekly-minimum gate's
    "Calves newly at 0 at 30" caught it (143 -> 147).

## 3. Prototype measurement (2,304-plan audit, against main 0c383703)

| run | Biceps pairs | Triceps pairs | Calves pairs | plans changed | rows per day | max minutes over |
|---|---|---|---|---|---|---|
| main | 13 | 9 | 49 | - | - | - |
| S1-S5 | 2 | 0 | 47 | 21 | unchanged | +6 (within the under-60 +6 bound) |
| S1-S6 | 0 | 0 | 47 | 23 | unchanged | +6 |
| S1-S8 (built) | 0 | 0 | 49 (= main) | 21 | unchanged | +6 |

- The audit's headline table (suitability, majors at 0, lead starved, openers) is identical to main for every run.
- **S1-S8 (the built design):** 21 plans change, exactly the arm-residue plans (one plan held both a Biceps and a
  Triceps pair). Per plan-week, against main, any group, weeks 1-3: 0 newly at 0 and 34 newly trained. Calves stays
  at main's 49 (the S1-S6 "improvement" to 47 was partly plans losing Calves in every week, which is not a pair).
- S6 fixes the 2 strength 4-day advanced home_dumbbells plans, without the swap: once Biceps is a target of A, 2C-b's
  own walk (d48) moves the curl slot ahead and pass A admits it within R's row cap. Deadlift Day A: Dumbbell Rear
  Lateral Raise -> Dumbbell Alternate Bicep Curl. Shoulders stays trained on OHP Day; the protective rule would
  otherwise send the plan to R.
- Every changed day is a one-for-one swap. Examples:
  - bodyweight Pull + Core: Doorway Isometric Row (hold, Back) -> Self-Resisted Bicep Curl;
  - gym Push + Core: Cable / Machine Lateral Raise (a second Shoulders row) -> Tricep Pushdown (Cable).
- Calves 49 -> 47: a side effect of re-seating. The arm row frees time elsewhere in a fixpoint round. No new
  zero-week group appears in any plan.

## 4. Tests and gates

- **Behavioral (crafted, `session_budget_fixtures.dart`), `test/contracts/arm_swap_behavioral_test.dart`:**
  - the swap seats the arm row and drops the last over-served row, with the count unchanged;
  - never rank 0, the opener, a minimum seat or a focus row;
  - a hold victim and a budgeted victim;
  - a victim whose group no other row of the day credits is skipped;
  - refusals restore the victim (cap, top, time);
  - 60 minutes: no swap;
  - Calves / Core: no swap;
  - the S6 fixpoint case (B gains the arm group late);
  - `disable_balanced_week`: byte-identical.
- **Neighbouring gates on the built tree (bug class 2.160):**
  - `weekly_minimum_gate_test`;
  - `day_floor_gate_rep30_test` and `day_floor_gate_pairs_p1/p4`, whose pinned swap counts change and are attributed;
  - `lead_first_gate_test`, `session_set_budget_gate_test`, `balanced_week_gate_test`, `core_list_pool_gate_test`;
  - the golden: 30-minute keys only are expected to move, and are attributed;
  - the four kill-switch goldens;
  - `repeat_minutes_gate_test` (2D).
- **Mutation:** each guard in S2-S6 is mutated once and must redden a test.

## 5. Docs

- plan-engine CLAUDE.md bullet;
- plan-engine-detail.md;
- the SoT registry (`weekly_minimum` gains the swap; or a new concept `arm_swap`, per `naming_conventions.md`);
- the diagnose doc;
- the closure ledger;
- OI-496 closed (archived);
- the board card t217.

## Review log

- **Self-review, prototype (before round 1):** S8 added after the weekly-minimum gate's Calves count moved. A
  per-plan-week "newly at 0" check (any group, weeks 1-3, against main) joins the audit comparison
  (`scratchpad/oi496/newzero.py`).
