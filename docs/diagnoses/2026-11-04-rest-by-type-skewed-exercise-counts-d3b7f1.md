---
bug_id: d3b7f1
date: 2026-11-04
batch: exercise-count-band
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  A tester (signed up 2026-11-03: build_muscle, basic_gym, 4 days, intermediate, 55 kg, no session minutes so the
  60-minute default) got Push 4, Pull 6, Legs 4, Upper 9 exercises in week 1 (cloud user_progress.plan_json, reproduced
  exactly with the real PlanGenerator.generate and his onboarding inputs). The founder expects similar counts on every
  day. The exercises were never missing from the cloud: they live in user_progress.plan_json, scheduled_workouts has
  no exercises column (the first lookup was wrong).
concept: session_set_budget
sot_registry_entry: |
  session_set_budget (docs/sot_registry.yaml) — extends the EXISTING concept: rest by exercise archetype and baseSets in the description, the swap writer added, the periodization reader semantic updated, two additional_tests.
related_bugs: [2d04d7, 9b1e7a]
recurrence: |
  NOT a recurrence of a recorded bug. Two related entries were read: 2d04d7 (injured users' thin days; the thin-day
  top-up) is the same family of symptom (a day with too few exercises) with a different cause, and this batch moves its
  ratchet; 9b1e7a (a swap kept the outgoing exercise's UI fields) is the same writer-copies-from-the-outgoing-slot shape
  as swap_service's rest_seconds, found here as a consequence of the change and fixed in the same batch.
writers:
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "restFor / desiredFor (deleted) -> restForArchetype / baseSets", line: 374 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant (slot rest and desired sets)", line: 191 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "apply / _applyWave (stamped rest), _weekTwoGains (re-price), week-4 sets", line: 83 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay (replacement rest_seconds, rep_range)", line: 517 }
readers:
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "estimateDaySecondsFromPlanDay (prices the stored rest_seconds for Train and Home)", line: 303 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted (reads the stamped restSeconds)", line: 192 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "the active-workout rest label and timer read the stored rest", line: 440 }
hive_key_prefix: "schedule_<date>.exercises[].rest_seconds (workoutBox)"
hive_key_formula: "PlannedExercise.restSeconds -> WorkoutDay.toMap exercises[].rest_seconds -> schedule_<IST date>"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); passes rest_seconds through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged)"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none new: a swap still goes through WorkoutWriteService.upsertScheduled, which owns the invalidation"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: swapExerciseInDay writes through WorkoutWriteService.upsertScheduled (wrapUserScopedBox)."
forbidden_patterns_checked:
  - { pattern: "a rest keyed by the DAY's intensity anywhere in lib/ (restFor, desiredFor, _profileParams rest column)", absent: true }
  - { pattern: "a swap copying the outgoing slot's rest_seconds for a rep-based incoming row", absent: true }
proposed_fix: |
  Cause (measured, not assumed): the 4-day split gives each day an intensity (_get4DayV4 in split_resolver.dart:581-647:
  strength, hypertrophy, strength, endurance). SessionBudget.restFor turned that into ONE rest for every exercise of the
  day (150 / 75 / 38 s) and desiredFor into 4 / 3 / 2 sets, so the same 60-minute clock fitted 4 exercises on a 150 s
  day and 9 on a 38 s day. An independent time model (a reviewer's, rebuilt from the constants) reproduced the old
  scheme as 4 / 7 / 4 / 9 against the observed 4 / 6 / 4 / 9.
  Fix (OI-456 piece A): the rest follows the EXERCISE: SessionBudget.restForArchetype (heavy compound H 150, other
  compound M 120, isolation I 75, timed / calisthenics B 60, unknown 60). Every day starts every exercise at
  baseSets 3. The allocator, _weekTwoGains and the _applyWave stamp all use that one function. Week 4 is
  min(sets, max(2, floor(0.6 x sets))) (founder: floor of 2, never raise a row). A plan-day swap re-derives a
  rep-based row's rest from the INCOMING exercise (resolved logging type) and carries rep_range, because every slot of
  a day used to share one rest and no longer does (the defect this change itself would have created).
  Piece B (the 5-8 count band, the 30-minute question) is NOT in this batch: three plan-review rounds on it found 6, 6
  and 4 P1 design holes, so per CLAUDE.md 4.12.1 it was split and is parked with its findings
  (docs/plans/2026-11-04-oi456-b-count-band.md). OI-456 stays OPEN for it.
contract_test_path: test/contracts/rest_by_type_behavioral_test.dart
regression_test_planned: |
  - test/contracts/rest_by_type_behavioral_test.dart (8 tests): (a) every budgeted rep-based exercise carries its
    archetype rest in all four weeks; (b) the same list on a strength / hypertrophy / strength / endurance day is
    identical in the allocator output and in weeks 1 and 3 (week 2 excluded on purpose: _weekTwoGains is day-order
    dependent); (c) deload 1..5 sets -> 1,2,2,2,3; (d) week-2 gains priced at the archetype rest; (e) a rep-based custom
    priced and stamped at its archetype rest; (e2) the same custom's week-2 extra set; a real-generator sweep of 1,000+
    stored rests against the literal table; (f) the tester persona measured.
  - test/contracts/swap_exercise_rest_follows_incoming_archetype_test.dart (4 tests).
  - session_budget_test.dart pins the literal table H 150 / M 120 / I 75 / B 60 / unknown 60 and baseSets 3.
  MUTATION PROOF (rule 21): 17 mutants applied one at a time, each confirmed applied (anchor count 1, file changed) and
  not a compile error, the five relevant files run against each, the tree restored after each (diff unchanged):
  M01 allocator fixed 75 s (8 red), M02 intensity-keyed desired (11), M03 _applyWave fixed 75 s (8), M04 H/M swapped
  (12), M05 unknown default 75 (2), M06 deload floor 1 (4), M07 deload floor 3 (3), M08 no min(ex.sets) (2), M09
  _weekTwoGains reads ex.restSeconds (2), M10 allocator custom at fixed 75 s (1), M11 _weekTwoGains custom at
  ex.restSeconds (FIRST RUN SURVIVED: 0 red; the fixture put a timed filler before the custom so the filler took the
  spare time first; fixed by test (e2) with the custom first, then 1 red), M12 stamp only for budgeted rows (5), M13
  swap keeps the outgoing rest (3), M14 swap applies archetype rest to timed rows (1), M15 swap does not store rep_range
  (2), M16 baseSets 4 (20), M17 isolation rest 60 (6). All 17 killed.
  EXISTING GATES VERIFIED (not new proof): session_set_budget_gate_test.dart (1,728 real runs: weekly top, lighter
  phase, session caps, time within minutes + 2, display equals the oracle) is unchanged and green.
impact_analysis: |
  MEASURED (test/plan_generator/rest_by_type_report.md, week 1, build_muscle): the tester persona (intermediate,
  basic_gym, 4 days, 60 min) is now 6 / 6 / 7 / 6 (spread 1; was 4 / 6 / 4 / 9). Other cells: intermediate 4-day 30 min
  3 / 3 / 3 / 3, 45 min 4 / 5 / 5 / 5, 90 min 7 / 6 / 8 / 9 (spread 3); beginner 60 min 5 / 5 / 5 / 4; advanced 60 min
  6 / 6 / 7 / 6; full_gym intermediate 3-day 6 / 7 / 7, 5-day 6 / 5 / 7 / 7 / 6, 6-day 6 / 6 / 7 / 6 / 6 / 7. So the
  intensity-driven spread is gone, and days at 30 and 45 minutes (and some beginner days) still sit under 5: that is
  piece B, not a regression.
  THIN-DAY RATCHET (kThinCeilings, injury_floor_sweep_lib.dart): re-measured on all 20 blocks. 19 fell (for example
  pairs46 bodyweight 84 -> 54, pairs basic_gym 152 -> 126, repeat bodyweight 82 -> 34; one-exercise days never rose).
  ONE ROSE, a recorded decision: pairs bodyweight, days under 3 exercises 30 -> 32 (knee+elbow 10, lower_back+elbow 4,
  wrist+elbow 8, elbow+hip 10). Likely cause, NOT measured: a former endurance day (2 sets) now starts at 3, so a small
  injured bodyweight pool spends its weekly band sooner. Accepted as part of the change: no empty day appears in any
  block (the hard zero holds).
  PRODUCT CONSEQUENCES the founder should know: (1) strength-goal users go from 4 to 3 base sets on strength days (the
  weekly band still tops them up); (2) the week-4 deload is milder: 3 sets -> 2 (was 3 -> 1) and a day whose
  exercises are all 2 sets gets NO set cut, so a 30-45 minute user's deload week keeps its sets and relies on the
  rep and load cut; (3) existing plans on tester devices are not regenerated: only new generations and phase
  advances carry the new rests.
  A PIN THAT HAD TO CHANGE, and what it weakened: plateau_rotation_behavioral_test.dart asserted the TOTAL exercise
  count equal ON vs OFF (rotation is a swap, not an add). It failed at 104 vs 100 over the 16 days of the fixture
  (advanced, full_gym, 4 days, phase 2, 60 min). Probed, not assumed: the rotated-in compounds are cheaper than the
  heavy ones they replace (Barbell Bench Press 150 s -> Push Up 120 s, Front Squat 150 s -> Goblet Squat 120 s), so the
  session budget seats one more accessory on those 4 days; at 180 minutes the totals still differ (126 vs 122), so it is
  not only the clock but the muscles the swapped-in rows credit. The old equality held only because every compound of a
  day cost the same. Rotation itself only widens the selector's avoid set (plateauAvoidNames), so it cannot add a slot.
  The assertion is now per day: the count never FALLS and rises by at most 1. WEAKER: this no longer catches a rotation
  that appends exactly one row per day (indistinguishable from the budget's extra seat). Residue stated, not hidden.
  Left alone, by decision: swap_sheets.dart (a live-session swap builds an in-memory active-workout row from the rest
  the user just typed into the custom-exercise form; it never writes the generated plan) and template_service.dart:340
  (user-built templates, rest absent only).
  Value semantics (4.1.5.3): the stored rest_seconds changes meaning (strength day 150 / endurance 38 became 60-150 per
  exercise). Swept lib/, test/, supabase/functions/ and docs: the readers are display and sync pass-throughs
  (session_estimate.dart, day_detail_sheet.dart, train_provider.dart, sync_workout.dart); the ai-proxy snapshot excludes
  rest_seconds (snapshot_keys_test.dart); no Edge Function reads it. Golden fixture generator_golden_hashes.json was
  regenerated wholesale (every hash moves; a before/after count table was not built because the old fixture holds only
  hashes: the measured report above is the evidence).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "session_budget.dart, session_set_allocator.dart, periodization_engine.dart, swap_service.dart; 17 mutants killed, see regression_test_planned." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "swap regression test reads the schedule_<date> row back from workoutBox after swapExerciseInDay; stored rest_seconds / rep_range asserted." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no column, migration or Edge Function touched; plan_json carries rest_seconds as before." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "user_progress.plan_json for the tester read-only on 2026-11-03 (4 / 6 / 4 / 9 in week 1); no cloud write." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the plan push passes rest_seconds through untouched (sync_workout.dart 2176, 2740); snapshot_keys_test.dart pins that the AI snapshot excludes it." }
---

# Exercise counts skewed 4 / 6 / 4 / 9 because rest followed the day's intensity (OI-456 piece A)

## What the founder saw
A friend's first plan: Push 4, Pull 6, Legs 4, Upper 9 exercises on a 60-minute clock. Not a sync problem: the plan is
in `user_progress.plan_json`; `scheduled_workouts` holds only date and status rows.

## Cause (writers and readers by file:line)
See `writers:` / `readers:` and `proposed_fix`. One sentence: the day's intensity (set in `_get4DayV4`) chose ONE rest
and ONE base set count for every exercise of the day, so the clock fitted a different number of exercises per day.

## What was proven and what was not
- Proven: the old model reproduces 4 / 6 / 4 / 9 (4 / 7 / 4 / 9 in an independent reviewer's rebuild); the new scheme
  measures 6 / 6 / 7 / 6 for the same persona; 17 of 17 mutants killed after one fixture fix.
- NOT proven: why bodyweight injury pairs gained 2 thin days (30 -> 32); the cause above is a hypothesis.
- NOT done here (piece B): a 5-8 band at every length and level, the 30-minute floor decision (D-A), the per-level
  count targets. The measured numbers that piece B starts from are in `test/plan_generator/rest_by_type_report.md`.

## Process
Plan `docs/plans/2026-11-04-oi456-a-rest-by-type.md`, record `docs/plan-reviews/exercise-count-band.md`.
