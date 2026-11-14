---
bug_id: e5c2a9
date: 2026-11-04
batch: oi456-b-count-band
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  After OI-456 piece A (rest by exercise type) the day-to-day skew was gone, but the exercise COUNT still depended on the
  clock instead of the user's level: at 30 minutes every day of a 4-day intermediate plan held 3 exercises, at 45
  minutes 4 to 5, at 90 minutes 6 to 9 (spread 3), a beginner at 60 minutes 4 to 5. The founder's decision (2026-11-03) is a
  band: beginner 5, intermediate 6, advanced 7-8, hard range 5-8, holding at 30 / 45 / 60 / 90 minutes with sets flexing
  first; decision D-A (2026-11-04, "option 2"): at 30 minutes the floor is 4 so the session stays inside its minutes.
concept: session_set_budget
sot_registry_entry: |
  session_set_budget (docs/sot_registry.yaml): the OI-456 piece B paragraph (count band, force step, countForced) and one
  additional_test, exercise_count_band_behavioral_test.dart.
related_bugs: [d3b7f1, 2d04d7]
recurrence: |
  NOT a recurrence. d3b7f1 (OI-456 piece A, the same skew family: a day's intensity chose rest and base sets) removed the
  day-to-day spread and is the batch this one builds on; its report is the baseline this change starts from. 2d04d7 (thin
  days for injured users) is the same symptom family (a day with too few exercises) with a different cause; this change
  moves its ratchet (kThinCeilings) down: 14 of 20 blocks to zero.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant (pass A seat target and seat-at-2, A2 force step, pass B grow-to-base, stats)", line: 270 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "countMax / countFloor / hardMax / maxForcedOverSeconds (new tables)", line: 380 }
readers:
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "apply reads the allocator's sets as the week-1 base; unchanged, sees the new counts", line: 83 }
  - { file: lib/shared/repositories/plan_engine/session_estimate.dart, method_or_widget: "budgetedDaySeconds (Train and Home minutes) prices whatever the stored day holds", line: 1 }
  - { file: test/plan_generator/session_set_budget_gate_test.dart, method_or_widget: "check (the time exemption now reads AllocationStats.countForced)", line: 306 }
hive_key_prefix: "schedule_<date>.exercises (workoutBox)"
hive_key_formula: "PlannedExercise list per day -> WorkoutDay.toMap -> schedule_<IST date>"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); exercise count and sets are plain list content, unchanged shape"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged)"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: generation only; existing plans on devices are not regenerated"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: pure planning code, no Hive or Supabase access."
forbidden_patterns_checked:
  - { pattern: "an exercise count that depends on the day's intensity or on how many 3-set seats fit the clock", absent: true }
proposed_fix: |
  Cause (measured): pass A seated a slot at its desired 3 sets when 3 fitted (k = desired..2), so on a short or loaded
  day the first few exercises took 3 sets each and the clock ran out: 3 exercises at 30 minutes, 4-5 at 45, and an
  overshoot of cheap isolations at 90 minutes (a 90-minute day had no ceiling).
  Fix (OI-456 piece B): the COUNT is decided first and the sets flex after it. (1) Target: a day holds at most
  SessionBudget.countMax(level) main exercises (beginner 5, intermediate 6, advanced 8), not-budgeted rows included; (2)
  pass A SEATS every slot at 2 sets while the day's seated count is under that target; (3) pass A2, the floor
  (SessionBudget.countFloor: 5 from 45 minutes, 4 from 25, 3 below), force-seats the CHEAPEST remaining slot at 2 sets
  although the clock says no, never past a session cap or a weekly top and only while the day stays within
  maxForcedOverSeconds (300) of its budget, one slot per day per round; the forced slots are named in
  AllocationStats.countForced (variant B inherits A's for copied days); (4) pass B grows every seated exercise to the base 3
  where time and the weekly top allow, then passes C and D (weekly bottom, focus) as before. A day still short is named
  in belowCount (cap_top / clock) or selectorThin; a group whose slots the count left out is labelled count_limited.
  The lead lift's boundBy is computed after the grow passes and without the reservation (every later lead is by then in
  the ledger).
contract_test_path: test/contracts/exercise_count_band_behavioral_test.dart
regression_test_planned: |
  - test/contracts/exercise_count_band_behavioral_test.dart (16 crafted fixtures + the real-generator sweep + the tester
    plan): the tables, the target by level, four heavy lifts at 30 minutes forced, the cap / weekly top never forced past, the
    15-minute forcing bound, a negative-secondsLeft day, copied days, the cheapest-first force, not-budgeted rows against the
    maximum, pass B spreading, selectorThin versus belowCount, count_limited; the sweep covers level (3) x minutes
    (15, 20, 25, 30, 31, 35, 44, 45, 60, 90, 120, 180) x days (3-6) x goal (2) x tier (2) x all four weeks: every day is
    within [floor, max] or named by the allocator, countForced only below 45 minutes, the deload keeps each variant's count.
  - test/contracts/session_set_allocator_behavioral_test.dart and rest_by_type_behavioral_test.dart repointed to the
    seat-at-2 results (REPOINTED, never loosened; the expectation changes are named in their comments).
  - test/plan_generator/session_set_budget_gate_test.dart: the time exemption subtracts the seconds of the NAMED forced
    exercises (and the guard's lead lift when both apply) and bounds the overrun at the forcing bound plus the display slack.
  MUTATION PROOF (rule 21), RE-RUN ON THE FINAL TREE (after the B-pass fixes and the last test edit): 22 mutants applied one
  at a time, each confirmed applied (anchor count 1; three anchors that no longer matched after the B-pass edit were
  re-pointed and re-run) and not a compile error, the new test file and the allocator behavioral test run against each,
  the file restored in a finally block (git status clean). Red counts: M01 floor from 45 minutes -> 4 (1), M02 floor 25-44
  -> 3 (6), M03 advanced max 9 (1), M04 beginner max 6 (3), M05 forcing bound 3000 (4), M06 force predicate uses fits (1),
  M07 force ignores the session cap (1), M08 force ignores the weekly top (1), M09 forcing bound removed (3), M10 force
  picks the first slot not the cheapest (1), M11 pass B removed (1), M12 pass A seats at 3 (5), M13 target ignores
  not-budgeted rows (2), M14 copied day drops countForced (1), M15 count_limited label removed (1), M16 belowCount cause
  inverted (5), M17 selectorThin not recorded (1), M18 copied day drops belowCount / selectorThin (1, killed only by the
  5-minute sweep), M19 hardMax 9 (1), M20 no force step (6), M21 the force prefers the lead lift removed (1). All 21 killed.
  M22 (belowCount counts a reservation-blocked slot as forceable) SURVIVES and is argued equivalent, not proven: a slot is
  reservation-blocked only while later same-group leads are unseated in pass A; by the end of pass A2 they are seated or
  guard-forced, so the group's weekly top has no room and `canForce` is false for that slot anyway. A fixture would need a
  week with room and a lead refused by the reservation alone, which pass A cannot leave behind. Three mutants survived
  the FIRST run and drove tests: M08 and M11 (fixtures (m), (l)) and M17 (fixture (n)). M19 is killed only by the
  literal pin of the constant (hardMax is behaviourally equivalent to the tables: countMax is at most 8).
  B-PASS (docs/reviews, fresh Sonnet): 0 P0, 0 P1, 2 P2, 4 P3, all closed here: the gate's countForced exemption now
  bounds the overrun by the forcing itself (min(forced seconds, 300 s) plus the guard lead plus the 2-minute display
  slack) instead of a flat 7 minutes; belowCount is read at the end of pass A2 (before the grow passes spend weekly top) and
  skips reservation-blocked slots; the force prefers the day's lead lift when the bound allows it (test (p)); the
  countMax + 1 edge is pinned by test (o); the registry semantic text was updated. The reviewer's optional day-order
  suggestion (force days with an unseated lead first) was tried and REMOVED: no fixture could kill its mutant.
impact_analysis: |
  MEASURED (test/plan_generator/rest_by_type_report.md, week 1, build_muscle): the tester persona (intermediate, basic_gym,
  4 days) holds 6 / 6 / 6 / 6 at 60 minutes (4 / 6 / 4 / 9 before piece A, 6 / 6 / 7 / 6 after it), 4 / 4 / 4 / 4 at 30,
  6 at 45 and at 90; beginner 5 / 5 / 5 / 5 (was 5 / 5 / 5 / 4), advanced 8 / 8 / 8 / 8 (was 6 / 6 / 7 / 6); full_gym
  intermediate 3, 5 and 6 days all 6. Spread 0 in every measured cell.
  THIN-DAY RATCHET (kThinCeilings, injury_floor_sweep_lib.dart): re-measured on all 20 blocks (7,200 runs). 14 fell to 0 thin days
  and 0 one-exercise days; the six `pairs` / `pairs46` blocks of home_dumbbells, basic_gym and full_gym keep a residue, all of it
  the shoulder+elbow pair (a small injured pool): pairs 10 / 22 / 14 (was 76 / 126 / 106) and pairs46 12 / 8 / 4 (was 120 /
  143 / 125); one-exercise days 0 everywhere; no empty day in any block. Seating at 2 sets leaves room for the 3rd and 4th
  exercise the 3-set seat used to starve; what is left is the pool, not the clock (the 2d04d7 residue, much reduced).
  PRODUCT CONSEQUENCES the founder should know: (1) a day now holds the level's count at every length, so a long day
  (90 minutes) no longer shows more exercises than a short one: it shows the same count at 3+ sets each, and intermediate
  at 90 minutes fills about 45 of 76 minutes; (2) seating at 2 first means accessories can take weekly top before a lead
  lift grows, so a lead lift can end at 2 sets (the allocator test 'round-robin by rank' now reads 2 / 2 where it read
  3 / 3); (3) the floor of 4 applies from 25 minutes (the founder fixed only 30); (4) at 30 minutes four heavy lifts overrun
  the budget by about 1.3 minutes (bounded by 300 s, named in countForced and in the gate's report); (5) existing plans
  on tester devices are not regenerated: only new generations and phase advances move.
  Value semantics (4.1.5.3): the meaning of 'exercises per day' changed (clock-driven -> level-driven). Swept lib/, test/,
  supabase/functions/ and docs for count literals; the tests that pinned the old counts are repointed (allocator behavioral,
  rest_by_type, injury_recheck_v14's elbow persona moved to intermediate 3-day by a reach search, the thin-day ceilings, both
  golden fixtures regenerated); no Edge Function reads a day's exercise count.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "session_budget.dart, session_set_allocator.dart; 21 of 22 mutants killed (one argued equivalent), see regression_test_planned." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "pure planning code; the stored plan shape is unchanged (a list with fewer or more exercises)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no column, migration or Edge Function touched." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the plan push carries the exercise list unchanged; no server reader depends on a day's count (grep of supabase/functions)." }
---

# Exercise counts follow the clock, not the level (OI-456 piece B)

## What the founder saw
Piece A fixed the 4 / 6 / 4 / 9 skew, but a 30-minute day still held 3 exercises and a 90-minute day up to 9.

## Cause (writers and readers by file:line)
See `writers:` / `readers:` and `proposed_fix`: pass A seated at 3 sets first, so the number of exercises was whatever
the clock left over.

## What was proven and what was not
- Proven: the measured report (spread 0 in every cell), 20 of 20 mutants killed on the final tree, the sweep over minutes
  15..180, thin days 0 in 14 of the 20 injury-sweep blocks and a small shoulder+elbow pair residue in the other six (no empty day).
- Not proven: a before/after count table for the golden hashes (the old fixture stores hashes only).
- Decisions the founder made: D-A (floor 4 at 30 minutes); OI-454 (Quads) and OI-458 stay separate.

## Process
Plan `docs/plans/2026-11-04-oi456-b-count-band.md` (v6), record `docs/plan-reviews/oi456-b-count-band.md`.
