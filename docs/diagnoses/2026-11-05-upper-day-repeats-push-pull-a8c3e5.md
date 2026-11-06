---
bug_id: a8c3e5
date: 2026-11-05
batch: oi458-upper-repeats
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  A tester's 4-day plan (build_muscle, basic_gym, intermediate; the same plan as OI-456) had an Upper day (day 4) that
  repeated accessories the Push or Pull day of the same week already carried: week 1 Bench Dips, Dumbbell Row,
  Self-Resisted Bicep Curl, Dumbbell Alternate Bicep Curl, Lateral Raise; week 2 Barbell Curl, Cable Rope Pushdown,
  Egyptian Lateral Raise. The day read as leftovers, not a new session. Measured over 72 real generations: 409 such
  repeated names in 42 plans (4- and 5-day splits, every tier and goal).
concept: upper_day_cross_day_variety
sot_registry_entry: |
  upper_day_cross_day_variety (docs/sot_registry.yaml) — added in this batch; behavioral test test/contracts/cross_day_variety_behavioral_test.dart.
related_bugs: [d3b7f1, e5c2a9]
recurrence: |
  NOT a recurrence of a recorded bug. The nearest entries were read: the cross-phase variety feature (W3.4, concept
  cross_phase_variety) uses the same soft `_preferNovel` mechanism for the PREVIOUS PHASE's names and never looks at
  other days of the same week, which is the gap; c3f9b2 (the universal pool's duplicate and wrong-pattern entries) is a
  different layer (attempt 5). The plan-engine CLAUDE.md already said `pickedNames` dedups only inside one variant of
  one day.
writers:
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "pickV4 day loop: avoidA / avoidB had no view of earlier days; now unions earlierPushPullA/B for an upper day", line: 645 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "_pickCoreList day loop (ship-dark enable_core_list_pool, default OFF), same union", line: 783 }
readers:
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "_selectCandidate / _preferNovel (the only reader of the avoid set; soft, bounded)", line: 1564 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "apply reads exercisesA for weeks 1 and 3, exercisesB for weeks 2 and 4 (3, 4 and 5 day plans; useB at line 79, reads at 85, 162, 194)", line: 85 }
hive_key_prefix: "schedule_<date>.exercises[] (workoutBox); plan_json.workouts[].exercises (the plan blob)"
hive_key_formula: "PlannedExercise.exerciseName -> WorkoutDay.toMap exercises[].name"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); the names pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged)"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers (wrapUserScopedBox)."
forbidden_patterns_checked:
  - { pattern: "avoid names passed to queryV4 / excludeNames / pickedNames for the cross-day avoid (it must stay soft)", absent: true }
  - { pattern: "an avoid applied to a day type other than upper", absent: true }
proposed_fix: |
  Cause (measured): ExerciseSelector.pickV4 fills every day with an empty exclude set for variant A and that day's own A
  names for B, so no day sees what an earlier day of the same week holds. The Upper day (split_resolver.dart, the
  MuscleSlotDay 'Upper' / 'Upper + Core': shoulders vertical_push, lats horizontal_pull, lateral delts, biceps, triceps,
  core) asks the same shallow isolation pools as Push and Pull; queryV4 is deterministic and the cascade returns the
  pool's first row, so it picks the same names. `_preferNovel` only knew the previous PHASE's names.
  Fix: an `upper` day SOFT-avoids the names the earlier push, pull and shoulders_arms days hold, per variant, lowercased,
  unioned into avoidA / avoidB (review #1 added shoulders_arms: the 5-day build_muscle split is Chest / Back /
  Shoulders + Arms / Legs / Upper + Core). The avoid reaches only `_preferNovel` (first pool row not in the set, else
  pool.first), so it never empties a slot, never changes a pattern and never loosens an equipment, injury or exclusion
  filter. The same lines sit in `_pickCoreList` so the ship-dark flag cannot bring the repeat back. B-pass fix: the repeat
  phase's fresh fill (`buildPinnedDays` -> `fresh()`, a ONE-frame `pickV4` call) could not see the earlier days, so
  `pickV4` takes optional `earlierFeederNamesA/B` seeds and `buildPinnedDays` collects the push / pull / shoulders_arms
  frames it has already built and passes them in (empty seeds: byte-identical).
  RESIDUE, stated: 70 pairs remain in 38 of 72 plans. The avoid acts inside the first cascade attempt whose pool is
  non-empty, so a residual repeat is a shallow attempt pool (often attempt 1 with a sub-focus), not necessarily a shallow
  library; going to a broader attempt would change which filters apply, so it is not chased. topUpDays (injured users)
  does not widen its soft avoid and can re-add a name. Strength-goal 5-day Upper (intensity 'strength'): its lead
  compounds can move to a lower-ranked in-pattern sibling when Push or Pull took the top one; accepted (the filters run
  before the tiebreak, so the swap stays in-pattern, equipment-capable and injury-safe). Coverage: the sweep measures the 4-day build_muscle split and the
  5-day splits (build_muscle 'Upper + Core', strength and the default 5-day 'Upper'); the 4-day lose_fat / general_fitness
  split has 'Upper Push' / 'Upper Pull' days (engine day types push / pull, no upper day) and the 4-day strength split
  has no upper day, so the avoid does nothing there by design.
contract_test_path: test/contracts/cross_day_variety_behavioral_test.dart
regression_test_planned: |
  - test/contracts/cross_day_variety_behavioral_test.dart (5 tests): (3) the ship-dark core-list path, flag ON on the
    real library (155 pairs without the avoid, 2 with it, asserted `<= 2`); (4) an injured user (shoulder; 52 pairs
    without, 20 with, `<= 20`, and no contraindicated pick); (5) a repeat phase that fresh-fills the Upper day, on both
    the cascade and the core-list path (32 pairs without the seed, 0 with it, `== 0`). The control is now an exact count
    (10 shared lifts), so an avoid on MORE day types also reddens it. (1) the REAL generator over 3 tiers x 4 goals x
    {4, 5} days x 3 levels (72 plans, 60 minutes, weeks 1 and 2) counts Upper-day names an earlier push / pull / chest /
    back / shoulders + arms day of the week also holds: 409 pairs in 42 plans before, 70 in 38 after; ratchet pairs <= 70,
    plans <= 38, pairs < 409 / 4. Reproduce the BEFORE figure: check out the pre-fix
    exercise_selector.dart into a scratch tree and run the file. (2) control: 6-day beginner Push A vs Push B still share
    10 lifts (an avoid applied to every day removes them).
  MUTATION PROOF, B-PASS ROUND (final tree, unmutated test asserted green first): 16 mutants over the cascade guard,
  the core-list guard and collection, the fresh-fill seeds and the pinned-frame collection; 13 red. THREE survived and are
  stated: C2 (core-list B-variant guard off), F2 (fresh-fill B seed not passed) and F6 (core-list B seed ignored): a
  probe over the real library showed identical output with and without them (weeks 2 and 4 stay at 45 repeats on the
  core-list path and 0 on the fresh fill), because the Upper day's B picks do not overlap the push / pull B picks there.
  They mirror the A guards, which ARE killed; a library change that makes B overlap would need a fixture of its own.
  The A-side core seed (F5) and the core pickV4 pass-through (C5) were killed after the flag-ON repeat test was added.
  FIRST TABLE, kept for the record: 8 mutants applied one at a time, each confirmed applied (anchor
  count >= 1, file changed) and not a compile error, the tree compared with the saved patch after the run: guard off for
  variant A (red), guard off for B (red), every day avoids (red), B collects A's names (red), case not lowered (red),
  shoulders_arms not collected (red), pull not collected (red), push not collected (red). All 8 killed, with the UNMUTATED test asserted green first in the same run (an earlier table ran against a test whose pairs ratchet had not been updated, so every mutant looked red because the baseline was red; review #2 caught it, the table was re-run). An earlier plain
  "collect push only" mutant was red too. An interrupted earlier run left two mutations in the source; the tree was
  restored from the saved patch and compared byte for byte before anything else ran.
impact_analysis: |
  MEASURED, before / after, same 72 plans: 409 -> 70 repeated Upper-day names; plans with at least one repeat 42 -> 38.
  GOLDEN: test/fixtures/generator_golden_hashes.json re-recorded, 326 of 999 keys changed, every one a 4-day (86) or
  5-day (240) plan, none 3-day or 6-day (the changed-key list is in the commit body). core_list_pool_behavioral_test
  reads two keys of the same fixture and follows it.
  THIN-DAY RATCHET: kThinCeilings['repeat bodyweight'] 4 -> 2 (it FELL; no block rose, 0 empty days).
  Existing plans on tester devices are not regenerated; only new generations and phase advances carry the change.
  Value semantics (4.1.5.3): no stored value changes meaning (names, sets and reps keep their shape). Swept test/ and
  supabase/functions/ for anything pinning Upper-day contents: only the golden fixtures; no Edge Function reads exercise
  names of a day.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "exercise_selector.dart pickV4 + _pickCoreList + _feedsUpperAvoid; 8 mutants killed, see regression_test_planned." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "generation only; no Hive key or box layout changes, the stored plan keeps its shape." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no column, migration or Edge Function touched." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "the symptom was reproduced with the real PlanGenerator.generateV4 (409 repeats over 72 generated plans); no cloud read or write." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the plan push passes exercise names through untouched (user_progress.plan_json); no server reader of a day's exercise names." }
---

# The Upper day repeated its week's Push and Pull accessories (OI-458)

## What the founder saw
The tester plan of OI-456: the 4-day Upper day reused Bench Dips, Dumbbell Row, two curls and Lateral Raise from Push and
Pull, so the day read as leftovers.

## Cause (writers and readers by file:line)
See `writers:` / `readers:` and `proposed_fix`. One sentence: `pickV4` gave every day an empty view of the week, so the
Upper day's shallow isolation pools returned the same first rows as Push and Pull.

## What was proven and what was not
- Proven: 409 repeats in 42 of 72 generated plans before, 70 in 38 after; the 5-day build_muscle split needed
  shoulders_arms (review #1).
- Measured, not fixed: the 70 residual pairs (shallow attempt pools); topUpDays for injured users.
- NOT done: a device check of the Upper day (the founder's next build).

## Process
Plan `docs/plans/2026-11-05-oi458-upper-day-variety.md`, record `docs/plan-reviews/oi458-upper-repeats.md`.

## Golden keys re-recorded (326 of 999; 86 four-day, 240 five-day, none 3-day or 6-day)

`test/fixtures/generator_golden_hashes.json`, re-recorded with `RECORD_GENERATOR_GOLDEN=1`. The keys whose hash changed:

```
cross|full_gym|build_muscle|4d|intermediate|p2
cross|home_dumbbells|build_muscle|4d|intermediate|p2
exclusion|barbell|basic_gym|build_muscle|4d|intermediate|p1
exclusion|barbell|full_gym|build_muscle|4d|intermediate|p1
exclusion|pull-up bar|basic_gym|build_muscle|4d|intermediate|p1
exclusion|pull-up bar|full_gym|build_muscle|4d|intermediate|p1
grid|basic_gym|build_muscle|4d|advanced|p1
grid|basic_gym|build_muscle|4d|advanced|p2
grid|basic_gym|build_muscle|4d|advanced|p3
grid|basic_gym|build_muscle|4d|advanced|p4
grid|basic_gym|build_muscle|4d|advanced|p5
grid|basic_gym|build_muscle|4d|beginner|p3
grid|basic_gym|build_muscle|4d|beginner|p4
grid|basic_gym|build_muscle|4d|beginner|p5
grid|basic_gym|build_muscle|4d|intermediate|p1
grid|basic_gym|build_muscle|4d|intermediate|p2
grid|basic_gym|build_muscle|4d|intermediate|p3
grid|basic_gym|build_muscle|4d|intermediate|p4
grid|basic_gym|build_muscle|4d|intermediate|p5
grid|basic_gym|build_muscle|5d|advanced|p1
grid|basic_gym|build_muscle|5d|advanced|p2
grid|basic_gym|build_muscle|5d|advanced|p3
grid|basic_gym|build_muscle|5d|advanced|p4
grid|basic_gym|build_muscle|5d|advanced|p5
grid|basic_gym|build_muscle|5d|beginner|p1
grid|basic_gym|build_muscle|5d|beginner|p2
grid|basic_gym|build_muscle|5d|beginner|p3
grid|basic_gym|build_muscle|5d|beginner|p4
grid|basic_gym|build_muscle|5d|beginner|p5
grid|basic_gym|build_muscle|5d|intermediate|p1
grid|basic_gym|build_muscle|5d|intermediate|p2
grid|basic_gym|build_muscle|5d|intermediate|p3
grid|basic_gym|build_muscle|5d|intermediate|p4
grid|basic_gym|build_muscle|5d|intermediate|p5
grid|basic_gym|general_fitness|5d|advanced|p1
grid|basic_gym|general_fitness|5d|advanced|p2
grid|basic_gym|general_fitness|5d|advanced|p3
grid|basic_gym|general_fitness|5d|advanced|p4
grid|basic_gym|general_fitness|5d|advanced|p5
grid|basic_gym|general_fitness|5d|beginner|p1
grid|basic_gym|general_fitness|5d|beginner|p2
grid|basic_gym|general_fitness|5d|beginner|p3
grid|basic_gym|general_fitness|5d|beginner|p4
grid|basic_gym|general_fitness|5d|beginner|p5
grid|basic_gym|general_fitness|5d|intermediate|p1
grid|basic_gym|general_fitness|5d|intermediate|p2
grid|basic_gym|general_fitness|5d|intermediate|p3
grid|basic_gym|general_fitness|5d|intermediate|p4
grid|basic_gym|general_fitness|5d|intermediate|p5
grid|basic_gym|lose_fat|5d|advanced|p1
grid|basic_gym|lose_fat|5d|advanced|p2
grid|basic_gym|lose_fat|5d|advanced|p3
grid|basic_gym|lose_fat|5d|advanced|p4
grid|basic_gym|lose_fat|5d|advanced|p5
grid|basic_gym|lose_fat|5d|beginner|p1
grid|basic_gym|lose_fat|5d|beginner|p2
grid|basic_gym|lose_fat|5d|beginner|p3
grid|basic_gym|lose_fat|5d|beginner|p4
grid|basic_gym|lose_fat|5d|beginner|p5
grid|basic_gym|lose_fat|5d|intermediate|p1
grid|basic_gym|lose_fat|5d|intermediate|p2
grid|basic_gym|lose_fat|5d|intermediate|p3
grid|basic_gym|lose_fat|5d|intermediate|p4
grid|basic_gym|lose_fat|5d|intermediate|p5
grid|basic_gym|strength|5d|advanced|p1
grid|basic_gym|strength|5d|advanced|p2
grid|basic_gym|strength|5d|advanced|p3
grid|basic_gym|strength|5d|advanced|p4
grid|basic_gym|strength|5d|advanced|p5
grid|basic_gym|strength|5d|beginner|p1
grid|basic_gym|strength|5d|beginner|p2
grid|basic_gym|strength|5d|beginner|p3
grid|basic_gym|strength|5d|beginner|p4
grid|basic_gym|strength|5d|beginner|p5
grid|basic_gym|strength|5d|intermediate|p1
grid|basic_gym|strength|5d|intermediate|p2
grid|basic_gym|strength|5d|intermediate|p3
grid|basic_gym|strength|5d|intermediate|p4
grid|basic_gym|strength|5d|intermediate|p5
grid|bodyweight|build_muscle|4d|advanced|p1
grid|bodyweight|build_muscle|4d|advanced|p2
grid|bodyweight|build_muscle|4d|advanced|p3
grid|bodyweight|build_muscle|4d|advanced|p4
grid|bodyweight|build_muscle|4d|advanced|p5
grid|bodyweight|build_muscle|4d|beginner|p3
grid|bodyweight|build_muscle|4d|beginner|p4
grid|bodyweight|build_muscle|4d|beginner|p5
grid|bodyweight|build_muscle|4d|intermediate|p1
grid|bodyweight|build_muscle|4d|intermediate|p2
grid|bodyweight|build_muscle|4d|intermediate|p3
grid|bodyweight|build_muscle|4d|intermediate|p4
grid|bodyweight|build_muscle|4d|intermediate|p5
grid|bodyweight|build_muscle|5d|advanced|p1
grid|bodyweight|build_muscle|5d|advanced|p2
grid|bodyweight|build_muscle|5d|advanced|p3
grid|bodyweight|build_muscle|5d|advanced|p4
grid|bodyweight|build_muscle|5d|advanced|p5
grid|bodyweight|build_muscle|5d|beginner|p1
grid|bodyweight|build_muscle|5d|beginner|p2
grid|bodyweight|build_muscle|5d|beginner|p3
grid|bodyweight|build_muscle|5d|beginner|p4
grid|bodyweight|build_muscle|5d|beginner|p5
grid|bodyweight|build_muscle|5d|intermediate|p1
grid|bodyweight|build_muscle|5d|intermediate|p2
grid|bodyweight|build_muscle|5d|intermediate|p3
grid|bodyweight|build_muscle|5d|intermediate|p4
grid|bodyweight|build_muscle|5d|intermediate|p5
grid|bodyweight|general_fitness|5d|advanced|p1
grid|bodyweight|general_fitness|5d|advanced|p2
grid|bodyweight|general_fitness|5d|advanced|p3
grid|bodyweight|general_fitness|5d|advanced|p4
grid|bodyweight|general_fitness|5d|advanced|p5
grid|bodyweight|general_fitness|5d|beginner|p1
grid|bodyweight|general_fitness|5d|beginner|p2
grid|bodyweight|general_fitness|5d|beginner|p3
grid|bodyweight|general_fitness|5d|beginner|p4
grid|bodyweight|general_fitness|5d|beginner|p5
grid|bodyweight|general_fitness|5d|intermediate|p1
grid|bodyweight|general_fitness|5d|intermediate|p2
grid|bodyweight|general_fitness|5d|intermediate|p3
grid|bodyweight|general_fitness|5d|intermediate|p4
grid|bodyweight|general_fitness|5d|intermediate|p5
grid|bodyweight|lose_fat|5d|advanced|p1
grid|bodyweight|lose_fat|5d|advanced|p2
grid|bodyweight|lose_fat|5d|advanced|p3
grid|bodyweight|lose_fat|5d|advanced|p4
grid|bodyweight|lose_fat|5d|advanced|p5
grid|bodyweight|lose_fat|5d|beginner|p1
grid|bodyweight|lose_fat|5d|beginner|p2
grid|bodyweight|lose_fat|5d|beginner|p3
grid|bodyweight|lose_fat|5d|beginner|p4
grid|bodyweight|lose_fat|5d|beginner|p5
grid|bodyweight|lose_fat|5d|intermediate|p1
grid|bodyweight|lose_fat|5d|intermediate|p2
grid|bodyweight|lose_fat|5d|intermediate|p3
grid|bodyweight|lose_fat|5d|intermediate|p4
grid|bodyweight|lose_fat|5d|intermediate|p5
grid|bodyweight|strength|5d|advanced|p1
grid|bodyweight|strength|5d|advanced|p2
grid|bodyweight|strength|5d|advanced|p3
grid|bodyweight|strength|5d|advanced|p4
grid|bodyweight|strength|5d|advanced|p5
grid|bodyweight|strength|5d|beginner|p1
grid|bodyweight|strength|5d|beginner|p2
grid|bodyweight|strength|5d|beginner|p3
grid|bodyweight|strength|5d|beginner|p4
grid|bodyweight|strength|5d|beginner|p5
grid|bodyweight|strength|5d|intermediate|p1
grid|bodyweight|strength|5d|intermediate|p2
grid|bodyweight|strength|5d|intermediate|p3
grid|bodyweight|strength|5d|intermediate|p4
grid|bodyweight|strength|5d|intermediate|p5
grid|full_gym|build_muscle|4d|advanced|p1
grid|full_gym|build_muscle|4d|advanced|p2
grid|full_gym|build_muscle|4d|advanced|p3
grid|full_gym|build_muscle|4d|advanced|p4
grid|full_gym|build_muscle|4d|advanced|p5
grid|full_gym|build_muscle|4d|beginner|p3
grid|full_gym|build_muscle|4d|beginner|p4
grid|full_gym|build_muscle|4d|beginner|p5
grid|full_gym|build_muscle|4d|intermediate|p1
grid|full_gym|build_muscle|4d|intermediate|p2
grid|full_gym|build_muscle|4d|intermediate|p3
grid|full_gym|build_muscle|4d|intermediate|p4
grid|full_gym|build_muscle|4d|intermediate|p5
grid|full_gym|build_muscle|5d|advanced|p1
grid|full_gym|build_muscle|5d|advanced|p2
grid|full_gym|build_muscle|5d|advanced|p3
grid|full_gym|build_muscle|5d|advanced|p4
grid|full_gym|build_muscle|5d|advanced|p5
grid|full_gym|build_muscle|5d|beginner|p1
grid|full_gym|build_muscle|5d|beginner|p2
grid|full_gym|build_muscle|5d|beginner|p3
grid|full_gym|build_muscle|5d|beginner|p4
grid|full_gym|build_muscle|5d|beginner|p5
grid|full_gym|build_muscle|5d|intermediate|p1
grid|full_gym|build_muscle|5d|intermediate|p2
grid|full_gym|build_muscle|5d|intermediate|p3
grid|full_gym|build_muscle|5d|intermediate|p4
grid|full_gym|build_muscle|5d|intermediate|p5
grid|full_gym|general_fitness|5d|advanced|p1
grid|full_gym|general_fitness|5d|advanced|p2
grid|full_gym|general_fitness|5d|advanced|p3
grid|full_gym|general_fitness|5d|advanced|p4
grid|full_gym|general_fitness|5d|advanced|p5
grid|full_gym|general_fitness|5d|beginner|p1
grid|full_gym|general_fitness|5d|beginner|p2
grid|full_gym|general_fitness|5d|beginner|p3
grid|full_gym|general_fitness|5d|beginner|p4
grid|full_gym|general_fitness|5d|beginner|p5
grid|full_gym|general_fitness|5d|intermediate|p1
grid|full_gym|general_fitness|5d|intermediate|p2
grid|full_gym|general_fitness|5d|intermediate|p3
grid|full_gym|general_fitness|5d|intermediate|p4
grid|full_gym|general_fitness|5d|intermediate|p5
grid|full_gym|lose_fat|5d|advanced|p1
grid|full_gym|lose_fat|5d|advanced|p2
grid|full_gym|lose_fat|5d|advanced|p3
grid|full_gym|lose_fat|5d|advanced|p4
grid|full_gym|lose_fat|5d|advanced|p5
grid|full_gym|lose_fat|5d|beginner|p1
grid|full_gym|lose_fat|5d|beginner|p2
grid|full_gym|lose_fat|5d|beginner|p3
grid|full_gym|lose_fat|5d|beginner|p4
grid|full_gym|lose_fat|5d|beginner|p5
grid|full_gym|lose_fat|5d|intermediate|p1
grid|full_gym|lose_fat|5d|intermediate|p2
grid|full_gym|lose_fat|5d|intermediate|p3
grid|full_gym|lose_fat|5d|intermediate|p4
grid|full_gym|lose_fat|5d|intermediate|p5
grid|full_gym|strength|5d|advanced|p1
grid|full_gym|strength|5d|advanced|p2
grid|full_gym|strength|5d|advanced|p3
grid|full_gym|strength|5d|advanced|p4
grid|full_gym|strength|5d|advanced|p5
grid|full_gym|strength|5d|beginner|p1
grid|full_gym|strength|5d|beginner|p2
grid|full_gym|strength|5d|beginner|p3
grid|full_gym|strength|5d|beginner|p4
grid|full_gym|strength|5d|beginner|p5
grid|full_gym|strength|5d|intermediate|p1
grid|full_gym|strength|5d|intermediate|p2
grid|full_gym|strength|5d|intermediate|p3
grid|full_gym|strength|5d|intermediate|p4
grid|full_gym|strength|5d|intermediate|p5
grid|home_dumbbells|build_muscle|4d|advanced|p1
grid|home_dumbbells|build_muscle|4d|advanced|p2
grid|home_dumbbells|build_muscle|4d|advanced|p3
grid|home_dumbbells|build_muscle|4d|advanced|p4
grid|home_dumbbells|build_muscle|4d|advanced|p5
grid|home_dumbbells|build_muscle|4d|beginner|p3
grid|home_dumbbells|build_muscle|4d|beginner|p4
grid|home_dumbbells|build_muscle|4d|beginner|p5
grid|home_dumbbells|build_muscle|4d|intermediate|p1
grid|home_dumbbells|build_muscle|4d|intermediate|p2
grid|home_dumbbells|build_muscle|4d|intermediate|p3
grid|home_dumbbells|build_muscle|4d|intermediate|p4
grid|home_dumbbells|build_muscle|4d|intermediate|p5
grid|home_dumbbells|build_muscle|5d|advanced|p1
grid|home_dumbbells|build_muscle|5d|advanced|p2
grid|home_dumbbells|build_muscle|5d|advanced|p3
grid|home_dumbbells|build_muscle|5d|advanced|p4
grid|home_dumbbells|build_muscle|5d|advanced|p5
grid|home_dumbbells|build_muscle|5d|beginner|p1
grid|home_dumbbells|build_muscle|5d|beginner|p2
grid|home_dumbbells|build_muscle|5d|beginner|p3
grid|home_dumbbells|build_muscle|5d|beginner|p4
grid|home_dumbbells|build_muscle|5d|beginner|p5
grid|home_dumbbells|build_muscle|5d|intermediate|p1
grid|home_dumbbells|build_muscle|5d|intermediate|p2
grid|home_dumbbells|build_muscle|5d|intermediate|p3
grid|home_dumbbells|build_muscle|5d|intermediate|p4
grid|home_dumbbells|build_muscle|5d|intermediate|p5
grid|home_dumbbells|general_fitness|5d|advanced|p1
grid|home_dumbbells|general_fitness|5d|advanced|p2
grid|home_dumbbells|general_fitness|5d|advanced|p3
grid|home_dumbbells|general_fitness|5d|advanced|p4
grid|home_dumbbells|general_fitness|5d|advanced|p5
grid|home_dumbbells|general_fitness|5d|beginner|p1
grid|home_dumbbells|general_fitness|5d|beginner|p2
grid|home_dumbbells|general_fitness|5d|beginner|p3
grid|home_dumbbells|general_fitness|5d|beginner|p4
grid|home_dumbbells|general_fitness|5d|beginner|p5
grid|home_dumbbells|general_fitness|5d|intermediate|p1
grid|home_dumbbells|general_fitness|5d|intermediate|p2
grid|home_dumbbells|general_fitness|5d|intermediate|p3
grid|home_dumbbells|general_fitness|5d|intermediate|p4
grid|home_dumbbells|general_fitness|5d|intermediate|p5
grid|home_dumbbells|lose_fat|5d|advanced|p1
grid|home_dumbbells|lose_fat|5d|advanced|p2
grid|home_dumbbells|lose_fat|5d|advanced|p3
grid|home_dumbbells|lose_fat|5d|advanced|p4
grid|home_dumbbells|lose_fat|5d|advanced|p5
grid|home_dumbbells|lose_fat|5d|beginner|p1
grid|home_dumbbells|lose_fat|5d|beginner|p2
grid|home_dumbbells|lose_fat|5d|beginner|p3
grid|home_dumbbells|lose_fat|5d|beginner|p4
grid|home_dumbbells|lose_fat|5d|beginner|p5
grid|home_dumbbells|lose_fat|5d|intermediate|p1
grid|home_dumbbells|lose_fat|5d|intermediate|p2
grid|home_dumbbells|lose_fat|5d|intermediate|p3
grid|home_dumbbells|lose_fat|5d|intermediate|p4
grid|home_dumbbells|lose_fat|5d|intermediate|p5
grid|home_dumbbells|strength|5d|advanced|p1
grid|home_dumbbells|strength|5d|advanced|p2
grid|home_dumbbells|strength|5d|advanced|p3
grid|home_dumbbells|strength|5d|advanced|p4
grid|home_dumbbells|strength|5d|advanced|p5
grid|home_dumbbells|strength|5d|beginner|p1
grid|home_dumbbells|strength|5d|beginner|p2
grid|home_dumbbells|strength|5d|beginner|p3
grid|home_dumbbells|strength|5d|beginner|p4
grid|home_dumbbells|strength|5d|beginner|p5
grid|home_dumbbells|strength|5d|intermediate|p1
grid|home_dumbbells|strength|5d|intermediate|p2
grid|home_dumbbells|strength|5d|intermediate|p3
grid|home_dumbbells|strength|5d|intermediate|p4
grid|home_dumbbells|strength|5d|intermediate|p5
injury|knee|basic_gym|build_muscle|4d|intermediate|p1
injury|knee|basic_gym|build_muscle|4d|intermediate|p2
injury|knee|bodyweight|build_muscle|4d|intermediate|p1
injury|knee|bodyweight|build_muscle|4d|intermediate|p2
injury|knee|full_gym|build_muscle|4d|intermediate|p1
injury|knee|full_gym|build_muscle|4d|intermediate|p2
injury|knee|home_dumbbells|build_muscle|4d|intermediate|p1
injury|knee|home_dumbbells|build_muscle|4d|intermediate|p2
injury|lower_back|basic_gym|build_muscle|4d|intermediate|p1
injury|lower_back|basic_gym|build_muscle|4d|intermediate|p2
injury|lower_back|bodyweight|build_muscle|4d|intermediate|p1
injury|lower_back|bodyweight|build_muscle|4d|intermediate|p2
injury|lower_back|full_gym|build_muscle|4d|intermediate|p1
injury|lower_back|full_gym|build_muscle|4d|intermediate|p2
injury|lower_back|home_dumbbells|build_muscle|4d|intermediate|p1
injury|lower_back|home_dumbbells|build_muscle|4d|intermediate|p2
injury|shoulder|basic_gym|build_muscle|4d|intermediate|p1
injury|shoulder|basic_gym|build_muscle|4d|intermediate|p2
injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1
injury|shoulder|bodyweight|build_muscle|4d|intermediate|p2
injury|shoulder|full_gym|build_muscle|4d|intermediate|p1
injury|shoulder|full_gym|build_muscle|4d|intermediate|p2
injury|shoulder|home_dumbbells|build_muscle|4d|intermediate|p1
injury|shoulder|home_dumbbells|build_muscle|4d|intermediate|p2
owned|bodyweight|build_muscle|4d|beginner|p3
owned|home_dumbbells|build_muscle|4d|intermediate|p1
owned|home_dumbbells|build_muscle|4d|intermediate|p3
pins|full_gym|build_muscle|4d|intermediate|p2
```
