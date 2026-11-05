# OI-458: the Upper day reads as leftovers (plan v2, after review #1)

Tier L (plan engine, `exercise_selector.dart`). Execution mode: INLINE (one unit, one worktree `oi458-upper-repeats`).
Rule 14: `plan_generator.dart` is NOT touched.

## Cause (measured)

`ExerciseSelector.pickV4` (`exercise_selector.dart`, the day loop after the `enable_core_list_pool` branch) fills every
day with `excludeNames: {}` for variant A and `aNames` (that day's own A) for variant B. No day sees what an earlier day
of the SAME week holds. The Upper day of the live `selectV4` splits (`MuscleSlotDay`, `split_resolver.dart:647` 4-day, `:866` 5-day
build_muscle 'Upper + Core', `:910` default 5-day; shoulders vertical_push, lats horizontal_pull, lateral delts, biceps,
triceps, core) asks the same shallow isolation pools as the Push and Pull days, and the cascade returns the
pool's first row, so it picks the same names (`queryV4` is deterministic; `_preferNovel` only sees the previous PHASE's
names). Writer: `pickV4` loop `avoidA/avoidB`. Reader: the Train week view (`WorkoutDay.exercises` of week 1 / 2).

Measured on the unchanged selector (real `PlanGenerator.generateV4`, 3 tiers x 4 goals x {4, 5} days x 3 levels = 72
plans, 60 minutes, weeks 1 and 2, `test/contracts/cross_day_variety_behavioral_test.dart`): **409 Upper-day names that
an earlier Push / Pull / Chest / Back / Shoulders + Arms day of the same week also holds, in 42 of 72 plans.**

## Fix

An `upper` day SOFT-avoids the names the earlier `push`, `pull` and `shoulders_arms` days of the plan hold (review #1:
the 5-day build_muscle split is Chest / Back / Shoulders + Arms / Legs / Upper + Core, and its Upper + Core repeats the
Shoulders + Arms biceps, triceps and delt picks), per variant (A with A, B with
B), lowercased, unioned into `avoidA` / `avoidB`. The avoid is the existing `_preferNovel` tiebreak: it prefers the
first pool row NOT in the set and falls back to `pool.first`, so it never empties a slot and never changes the pattern,
equipment, injury or exclusion filters (they run before it). Same lines in `_pickCoreList` (ship-dark, default OFF) so
turning the flag on cannot bring the repeat back. Nothing else changes: a push / pull / legs / full-body day gets the
same sets as before (frequency repeats such as 6-day Push A / Push B stay deliberate).

Not mirrored in `cascade_tracer.dart`: W3.4 and W3.5 (the other two avoid-set features) are not either, and the
scorecard counts cascade attempts, which a tiebreak inside one pool cannot move.

## Review #1 findings and how they are handled

- P1 golden: `test/fixtures/generator_golden_hashes.json` is re-recorded in the same commit (`RECORD_GENERATOR_GOLDEN=1`),
  the changed keys are named in the commit body, and the gate loop (full suite, whole-project analyze) runs on the final
  tree. The golden's flag-OFF identity role holds for the flags it guards; it now also encodes this selector change.
- P1 5-day build_muscle: `shoulders_arms` days are collected; the sweep is classified by `dayType` (not name) and
  includes the 5-day build_muscle split.
- P2 residue wording: the avoid acts inside the FIRST cascade attempt whose pool is non-empty, so a residual repeat is a
  shallow attempt pool (often attempt 1 with a sub-focus), not necessarily a shallow library. Stated, not chased: going
  to a broader attempt would change which filters apply.
- P2 `topUpDays` (injured users only) can re-add a name; its soft avoid is not widened. Stated residue.
- P2 strength goal: the soft avoid applies there too; a pattern repeated on a second day moves to a sibling when one
  exists. Decision: accepted (the Upper day is meant to be a different session); the avoid is bounded.
- P2 the beginner 4-day sweep rows have no Upper day (full-body days), so they contribute 0; coverage is stated by the
  measured plan count, not by 54.
- P2 test honesty: the plan ratchet is tightened to the measured post-fix plan count; the before figures (243 pairs) are
  recorded with the command in the diagnose doc.

## Proof

1. Real-generator sweep above: after the fix **70 pairs in 38 of 72 plans**; ratchet `pairs <= 70`, `plans <= 38`,
   `pairs < 409 / 4`. (Beginner plans of 4 days and fewer are full-body, no Upper day: they contribute 0; the 4-day lose_fat / general_fitness split has 'Upper Push' / 'Upper Pull' days that the engine types push / pull, and the 4-day strength split has no upper day: the sweep does not cover them and the avoid does nothing there by design.)
2. A non-Upper control: 6-day beginner Push A vs Push B still share 10 lifts; an avoid applied to every day would
   remove them.
3. Mutants (each confirmed applied, none a compile error, tree restored and compared with the saved patch after the
   run): guard off for A, guard off for B, every day avoids, B collects A's names, case not lowered, shoulders_arms not
   collected, pull not collected, push not collected. **Eight, all red** (the earlier plain push-only collection mutant
   was also red).
4. Re-recorded in the same commit: `test/fixtures/generator_golden_hashes.json` (326 of 999 keys changed, every one a
   4-day or 5-day plan, none 3-day or 6-day; the key list is in the commit body), and the thin-day ratchet
   `kThinCeilings['repeat bodyweight']` 4 -> 2 (it FELL: a second Upper day pins fewer repeated unsafe rows).
