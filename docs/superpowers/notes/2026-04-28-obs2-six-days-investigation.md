# OBS-2 Investigation — 6-vs-5-Days Mismatch (APK Test #5 Plan B-5)

**Date:** 2026-04-28
**Source observation:** Spec §2 OBS-2.

## Repro context (per OBS-2)
User selected 6 days/week on Edit Profile, saved, schedule strip
showed only 5 workout days that week.

## Code path traced

1. `edit_profile_screen.dart::_save` →
   `WorkoutScheduleService.instance.generateAndScheduleFromDate(...)` at line 1630.
2. `WorkoutScheduleService.generateAndScheduleFromDate` (line 281) →
   `PlanGenerator.instance.generate(...)` (line 301) which delegates to
   `PlanGenerator.generateV4(...)` (verified in `plan_generator.dart:30-44`).
3. `plan_engine/plan_generator.dart::generateV4` →
   `SplitResolver.selectV4(goal, daysPerWeek, experienceLevel)` →
   for `daysPerWeek=6` returns `_get6DayV4(goal)` (verified at
   `split_resolver.dart:402-403`).
4. `_get6DayV4` for `build_muscle` returns a list of **6** `MuscleSlotDay`
   entries: Push A, Pull A, Legs A, Push B, Pull B, Legs B (verified at
   `split_resolver.dart:935+`, lines 939, 950, ... — each `MuscleSlotDay(...)`
   is a top-level entry in the returned list).
5. Schedule writer (`workout_schedule_service.dart:361-411`):
   - Outer: `for (int week = 0; week < 4; week++)` — 4 weeks
   - Inner: `for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++)` — Mon-Sun
   - Guards: skip dates before today, skip already-completed dates.
   - Write condition (line 393-394):
     `if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length)` →
     writes a `schedule_<date>` row, then increments `workoutDayIndex`.
6. `_getDayPattern(6)` returns `[0, 1, 2, 3, 4, 5]` — Mon, Tue, Wed, Thu,
   Fri, Sat (6 entries, `workout_schedule_service.dart:1299-1300`).

### Walk for daysPerWeek=6, week=0
- dayOfWeek=0 (Mon): pattern contains 0, idx=0 < 6 → write workoutDays[0],
  idx→1
- dayOfWeek=1 (Tue): pattern contains 1, idx=1 < 6 → write workoutDays[1],
  idx→2
- dayOfWeek=2 (Wed): pattern contains 2, idx=2 < 6 → write workoutDays[2],
  idx→3
- dayOfWeek=3 (Thu): pattern contains 3, idx=3 < 6 → write workoutDays[3],
  idx→4
- dayOfWeek=4 (Fri): pattern contains 4, idx=4 < 6 → write workoutDays[4],
  idx→5
- dayOfWeek=5 (Sat): pattern contains 5, idx=5 < 6 → write workoutDays[5],
  idx→6
- dayOfWeek=6 (Sun): pattern does NOT contain 6 → skip → no row written

Net per week: **6 schedule rows + 1 unfilled Sunday** (correct).

## Findings

The 6-day schedule production code path is **correct**. Loop bounds, day
pattern, MuscleSlotDay count, and write condition all align — for a clean
state, `daysPerWeek=6` produces exactly 6 schedule rows per week.

The most plausible explanation for OBS-2 is therefore **NOT** a bug in
the service layer. Possibilities, ordered by likelihood:

1. **User dismissed the reschedule dialog.** Pre-B-2, `planChanged` did
   include `daysPerWeek`, so the dialog would have fired on a 5→6 change.
   But if the user tapped "Keep Current Plan" (the dialog's left action),
   the old 5-day schedule would persist verbatim. The schedule strip
   would then show 5 days because the old 5-day plan was preserved.
2. **User edited 6 in the field but didn't tap SAVE.** No regen runs,
   no dialog fires, schedule remains the pre-edit 5-day shape.
3. **State mismatch from a prior abandoned save.** If the previous save
   wrote `_daysPerWeek=6` to Hive but the user then dismissed the dialog,
   the profile would say 6 but the schedule would still be 5 — a
   persistent drift. B-2 makes the trigger reliable BUT does not retroactively
   reconcile already-drifted state.

## Branch chosen

**Branch A.** The service-layer code path is sound; OBS-2 is the same
class of bug as OBS-1 — a reschedule trigger UX issue, already addressed
by B-2's reliability improvement. No service-layer fix is required for
B-6.

## Implication for Plan B

- Task B-6 is a **no-op**.
- Recommended follow-up (out of scope for B-6 per spec §4.4): consider
  silent auto-regen on plan-driving field change instead of showing a
  dismissible dialog. Tracked in spec §4.4 as a deferred UX brainstorm.
- Drift-reconciliation (case 3 above) — if a user is already in a
  drifted state, B-2 won't fix them on next save unless they touch a
  plan-driving field again. Could add a one-time "your saved profile
  says X but your schedule shows Y — reschedule?" check on app launch,
  but that's also out of scope.
