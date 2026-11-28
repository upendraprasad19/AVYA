---
bug_id: 9c3e7a
date: 2026-07-12
batch: coach-phase-stamp
status: fixed
blast_radius: account
symptom: >
  Two coupled coach plan-generation defects. (1) Item ② / G8: the AI-coach
  "regenerate my plan" and "switch goal" tools (both routed through the shared
  RegeneratePlanPlanner) called PlanGenerator.generate() WITHOUT a phase argument,
  so it defaulted to phase=1 — a phase-6 user asking the coach to regenerate was
  silently demoted to Foundation-level programming. (2) COACH-1 (writer/reader
  drift, self-verified 2026-07-12): the coach regen workout rows, coach regen rest
  rows, and the hotel-workout planner rows stamped `week` / `week_character` /
  `generated_via` but NOT the `phase` key that the MAIN scheduler stamps on every
  schedule_* row (workout_schedule_read_service.dart). So after any coach regen /
  switchGoal / hotel-generate, the block's rows were phase-unstamped — the
  bucketPastRows phase-identity grouping (which the reframed repeat-offer gating +
  the PhaseProgressReconciler depend on) fell back to carry-forward, and a
  fully-coach-generated history could hit the 28-day fallback and mis-count phases.
concept: coach_plan_generation_phase_stamp
sot_registry_entry: >
  Relates to the `scheduled_workouts_mutations` concept (lib/features/train/CLAUDE.md):
  "Generation now stamps 'phase' on every schedule_* row (F-B 7d2e6b)." This fix
  extends that invariant to the THREE coach-side schedule-row writers that were
  missing it (regen workout rows, regen rest rows, hotel rows). Reader unchanged:
  WorkoutScheduleReadService.bucketPastRows groups past rows by the stamped `phase`.
  Not adding a new registry concept — this closes a writer gap in an existing one.
writers:
  - "{ file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: plan (generate call — item 2), line: 189 } — threads resolvedPhase (real current_phase from the progress map) into PlanGenerator.generate(phase:), replacing the hardcoded phase=1 default."
  - "{ file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: plan (workout row map — COACH-1), line: 270 } — stamps 'phase': resolvedPhase on each workout schedule row."
  - "{ file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: _restEntry (rest row map — COACH-1), line: 344 } — stamps 'phase': phase on each rest schedule row (phase threaded in as a new param)."
  - "{ file: lib/features/ai_coach/services/hotel_workout_planner.dart, method: plan (hotel row map — COACH-1), line: 175 } — stamps 'phase': resolvedPhase on each hotel schedule row; generate() intentionally stays phase=1 (content), the row stamp is scheduling identity."
readers: >
  WorkoutScheduleReadService.bucketPastRows (workout_schedule_read_service.dart) —
  groups past schedule_* rows by their stamped `phase` (phase-identity when all
  rows stamped, else 28-day fallback), feeding pastPhaseBlocks →
  PhaseProgressReconciler (phase_progress_reconciler.dart, monotonic current_phase
  self-heal) and the reframed adherence-gated advance's repeat-content path. Prose,
  not a {file:line} contract — these readers are unchanged by this fix.
hive_key_prefix: schedule_
hive_key_formula: "schedule_<yyyy-mm-dd> — the planner emits rawSchedules maps; ToolDispatcher writes them via WorkoutScheduleService.upsertScheduled → WorkoutWriteService (schedule_<date> key). The `phase` key rides inside the row map (…entry spread), verified persisted."
sync_methods: >
  syncWorkoutData → _syncWorkoutPlan rebuilds user_progress.plan_json.schedules from
  the live schedule_* rows. The `phase` key is Hive-row-local (the cloud
  scheduled_workouts table has no phase column), so it reaches cloud only inside the
  plan_json blob and round-trips via restore.
restore_methods: >
  _restoreWorkoutPlan applies plan_json.schedules. No new cloud column, no new
  restore path — the stamp travels with the existing plan_json round-trip.
cloud_table: scheduled_workouts
cloud_columns: >
  n/a — no column added/changed. scheduled_workouts has no `phase` column (verified,
  backups/live_schema_columns.json); `phase` is Hive-row-local, cloud-carried only
  inside user_progress.plan_json.
contract_test_path: test/contracts/coach_regen_phase_stamp_behavioral_test.dart
ist_handling: >
  n/a — no new IST date key introduced; the planners use their existing date
  formatting (_fmt / ist_date) unchanged.
provider_invalidations: >
  n/a — the planners produce preview + rawSchedules data only; provider invalidation
  happens on the downstream write path (ToolDispatcher → WorkoutWriteService),
  unchanged by this fix.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a to change — the planners read userBox('profile'/'progress') via
  HiveService.instance (user-scoped box, wrapUserScopedBox guarded); no new box
  access. resolvedPhase reads the same user-scoped progress map RankService uses.
forbidden_patterns_checked: []
proposed_fix: >
  Read the real current_phase once from the Hive progress map
  (`(progress['current_phase'] as int?) ?? 1` — the same source graduation / splash
  / RankService use) at the top of each planner's plan() method as `resolvedPhase`,
  then (item ②) pass it into PlanGenerator.generate(phase:) for the regen path
  (hotel keeps generate phase=1 — a hotel plan is a foundation bodyweight
  substitute, not a progression cycle), and (COACH-1) stamp 'phase': resolvedPhase
  on all three schedule-row writers (regen workout rows, regen rest rows, hotel
  rows). Content difficulty (generate phase) and scheduling identity (row phase
  stamp) are decoupled — hotel's row stamp is the user's real phase even though its
  content is phase-1.
regression_test_planned: >
  test/contracts/coach_regen_phase_stamp_behavioral_test.dart — seeds the real
  exercise library + a phase-6 user (current_phase:6), calls
  RegeneratePlanPlanner.plan() and HotelWorkoutPlanner.plan(), and asserts every
  emitted schedule row carries phase==6 (both workout and rest rows), which proves
  BOTH fixes: resolvedPhase==6 flowed into generate() AND onto the rows (one
  variable feeds both). FAILS pre-fix (generate defaulted phase=1; rows had no
  `phase` key → null ≠ 6). Green.
touched_layers_checked:
  - "tier: 1_client_code, status: fixed_in_this_batch — regenerate_plan_planner.dart + hotel_workout_planner.dart edited; flutter analyze clean on both."
  - "tier: 2_hive_local_state, status: fixed_in_this_batch — behavioral test asserts every emitted schedule row carries phase==6 (Hive row shape); coach_regen_phase_stamp_behavioral_test.dart green."
  - "tier: 12_client_server_contract, status: verified — phase is Hive-row-local; cloud scheduled_workouts has no phase column (backups/live_schema_columns.json), so no cloud-contract change; the stamp round-trips only via user_progress.plan_json.schedules."
impact_analysis: >
  Blast radius account (lib/features/ai_coach/**). Behavior change: coach regen /
  switchGoal now produce phase-N (not phase-1) content for phase≥2 users — verified
  safe by the Round-4 coach audit (PlanGenerator.generate is stateless; phase≥2 only
  widens effectiveLevel + seeds ProgressionResolver + auto-derives weakMuscles, all
  graceful on sparse history). The regression test covers the zero-history phase-6
  case. The phase row-stamp is purely additive (a new key on rows that had none) —
  no existing reader breaks (bucketPastRows already prefers a stamped phase, else
  carry-forward). Hotel generate stays phase=1 (content) so hotel plans remain the
  same easy bodyweight substitute; only their scheduling identity is corrected.
  Downstream: this stamp is a prerequisite the reframed repeat-offer gating (Batch 8)
  and PhaseProgressReconciler rely on, so landing it in Batch 1 de-risks those.
---

# Coach plan-generation phase demotion + missing phase row-stamp (9c3e7a)

## What happened
The AI-coach plan-generation tools produced phase-1 (Foundation) content for
already-advanced users and emitted schedule rows without the `phase` key that the
main scheduler stamps. Item ② (demotion) and COACH-1 (writer/reader drift) share a
root — the planners never read the user's real `current_phase`.

## Root cause
`RegeneratePlanPlanner.plan()` and `HotelWorkoutPlanner.plan()` read the profile map
(goal/equipment/days/experience) but never the progress map (`current_phase`). The
`generate()` call omitted `phase` (defaulted 1), and the schedule-row maps omitted
`phase`. The main scheduler (`workout_schedule_read_service.dart`) stamps `phase` on
every row; the three coach-side writers did not — the recurring writer/reader-drift
class (lib/CLAUDE.md).

## Fix
Read `current_phase` once as `resolvedPhase`; thread it into `generate(phase:)` for
the regen path and stamp it on all three schedule-row writers. Hotel `generate` stays
phase=1 (content is a foundation bodyweight substitute) while its rows carry the real
phase (scheduling identity). See `proposed_fix` above.

## Related
Surfaced by the workout-generator-overhaul Round-4 AI-coach integration audit
(COACH-1) + self-verified via grep of the row-writers. Prerequisite for the reframed
adherence-gated advance (Batch 8) + PhaseProgressReconciler correctness.
closes-diagnose: 9c3e7a
