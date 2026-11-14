# OI-166 Unit 2 (v5) — plan review round 5

**Plan reviewed:** `docs/audit/oi166-unit2-plan-v5.md` (superseded in-place by v6 after this round;
the v5 text itself is not preserved as a separate file — this record is v5's surviving account,
same pattern as round 4 recorded for v4).

**Verdicts:** design reviewer **not-converged** · ground-truth reviewer **verified** (24/24
citations confirmed, 2 trivial line-drifts, 0 wrong — the first fully clean ground-truth pass
across five rounds).

⚠ Findings marked CONFIRMED were independently re-derived by the design reviewer using its own
numbers, not taken on the plan's word — including the core arithmetic claim itself.

## The headline: the core mechanism is sound for the first time in five rounds

v5's central idea — bind the write loop's upper bound to the exact same `planEnd` local the delete
loop already reads, instead of deriving a second, independent formula — was **independently
re-derived and confirmed** by the design reviewer with two scenarios of its own:

- Unextended: `planStart=0`, `today=14`, `storedPlanEnd=27` → `writeRange=[14,27]`, 14 days,
  matches the delete bound exactly.
- `redoWeek4`-extended (round 4's exact scenario): `storedPlanEnd=34`, `today=30` →
  `writeRange=[30,34]`, 5 days — matching what `redoWeek4` actually provisioned, no over/under-write.

Both check out with no off-by-one in either direction. **The delete/write mismatch that killed v3
and v4 is genuinely closed.** This is the first round where the core idea survived adversarial
hand-checking rather than being the thing that failed.

## What kept it from converging — five completeness gaps, not mechanism flaws

1. **P0 — the "genuinely expired" case, named in v5's own intro, never revisited.** When
   `today > storedPlanEnd` with no extension, `writeRange` is correctly empty (no data loss — the
   delete range is also empty), but `current_plan` was still being unconditionally overwritten —
   reproducing round 2's P0-2 (blob claims a refresh, zero rows back it up). Directly reachable:
   `edit_profile_screen.dart:2019-2038` has no expiry check before calling
   `generateAndScheduleFromDate`.
2. **P1 — B's actual `current_plan` write site (`:388`) was never cited.** The splice design was
   described in prose but never wired to the real, unconditional
   `await workoutBox.put(_planKey, plan.toMap());`.
3. **P1 — C's `'week'` field left unfixed**, despite the codebase's own doc comment on
   `rawWeekNumberFor` calling this exact drift "the whole subject of OI-166."
4. **P2 — C's explicit-`startDate` branch not actually guarded.** Both real callers
   (`regenerate_plan_diff.dart:48`, `switch_goal_diff.dart:62`) do pass an explicit `startDate`
   through, and v5's content-flavor substitution had no `startDate == null` gate protecting that
   case from the new (today-anchored) indexing.
5. **P2 — C never reads `plan_start`.** No source for the value `regenStartWeek` depends on was
   specified.

None of the five require a new founder decision — each is a direct extension of the rule already
locked in ("bind everything to the same condition, never let two things diverge"). Round 6 closes
all five (see `docs/plan-reviews/regen-wave-unit2-round6.md`).

## Author's read

Genuinely different signal from rounds 1-4: this is the first round where "not-converged" means
"incomplete," not "wrong." Proceeding to close the five gaps in the same document (v6) rather than
re-deriving a new mechanism.
