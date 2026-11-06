---
bug_id: a7d3f1
date: 2026-06-06
batch: wls-reps-fix
status: fixed
blast_radius: account
symptom: >
  After a fresh-install restore the Train screen showed the wrong week/phase
  (Home "WK 4", Train banner "WEEK 4 OF 12", Roadmap "33% complete", "Week 6
  hasn't started yet") AND every not-yet-completed day collapsed to "REST DAY /
  No exercises scheduled" with a START button that started nothing. Observed
  live on the founder's account (d7a67a37) after reinstalling the latest APK.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers: >
  _restoreWorkoutPlan (lib/core/services/sync/sync_workout.dart) is the ONLY
  restore writer that applies the cloud plan_json snapshot (plan_start_date +
  plan_end_date + the date-keyed schedules WITH exercises). It was gated by an
  `if (current_plan != null) return` early-return, so when a plan was locally
  (re)generated before/around restore (onboarding_provider, train_provider
  _autoGeneratePlan, or the sim driver) it skipped — the snapshot never applied.
  PlanIntegrityReconciler.reconcile (lib/core/services/plan_integrity_reconciler.dart)
  is the new shared boot heal. mergeScheduleEntry is the shared completed-day-
  preserving merge used by both the restore path and the heal.
readers: >
  train_provider.dart CurrentPlanNotifier.build reads each schedule_* day's
  type + exercises[]; a type=workout day with empty exercises rendered as "REST
  DAY / 0 EX". getCurrentWeekNumber (workout_schedule_read_service.dart, clamp
  1-4 = week WITHIN the phase) was read by the Train banner (screen.dart), Home
  header (home_screen.dart) and the Roadmap (phase_roadmap_screen.dart), each
  framing it as the 12-week program week ("OF 12" / n/12 %).
hive_key_prefix: schedule_
hive_key_formula: "schedule_ plus the IST date key; plan_start_date / plan_end_date keys are re-anchored from plan_json on restore + heal"
sync_methods: syncWorkoutData
restore_methods: _restoreWorkoutPlan, _restoreScheduledWorkouts
cloud_table: user_progress
cloud_columns: plan_json
contract_test_path: test/contracts/restore_plan_json_authoritative_test.dart
ist_handling: not_applicable (schedule_* keys are already IST date-keyed at write time)
provider_invalidations: currentPlanProvider, selectedWeekProvider, calendarWeekProvider
telemetry_op_types: plan_integrity_reconciled, restore_workout_plan
cross_account_guard: yes (restore + reconcile run after HiveUserSession.openForUser; cloud read is user_id-scoped)
forbidden_patterns_checked:
  - "the blanket current_plan early-return that skipped plan_json — removed; the snapshot now always applies (the contract test pins its absence)."
  - "a planned workout day rendered without exercises — the shared mergeScheduleEntry fills exercises from plan_json while preserving a local completed status."
  - "a 1-4 phase week printed as the 12-week program week — the Roadmap now uses getProgramWeek and the banner shows WK n OF 4 plus the canonical phase name."
proposed_fix: >
  (1) _restoreWorkoutPlan ALWAYS applies plan_json plan_start_date / plan_end_date
  / schedules (completed-day-preserving merge extracted to
  PlanIntegrityReconciler.mergeScheduleEntry), removing the blanket skip. (2) A
  symptom-gated, kill-switchable PlanIntegrityReconciler re-applies the snapshot
  on the next sign-in for already-broken installs, wired beside
  PhaseProgressReconciler in restoring_screen (foreground + background). (3)
  Display made phase-relative — banner shows the canonical phase name (derived
  from current_phase) + week WITHIN the phase (OF 4); the Roadmap uses
  getProgramWeek for its 12-week counter, percent + active-phase highlight. (4)
  START WORKOUT is gated on a non-empty plan so it can never no-op. (5) Home
  workout/macro cards rebalanced 60/40 to 50/50 so the macro labels stop
  truncating.
regression_test_planned: >
  test/contracts/restore_plan_json_authoritative_test.dart (mergeScheduleEntry +
  needsHeal + restore/heal wiring) and
  test/contracts/phase_relative_week_label_test.dart (phaseNameFor /
  programWeekFor + banner / roadmap / START-gate wiring).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "restore applies plan_json authoritatively; PlanIntegrityReconciler added + wired in restoring_screen fg+bg; phase-relative banner/roadmap; START gated; 50/50 home cards; flutter analyze clean on changed files except pre-existing infos" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "schedule_* planned days rehydrate exercises from plan_json; plan_start_date/plan_end_date re-anchored; 19 contract assertions green (restore_plan_json_authoritative + phase_relative_week_label)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live query user_progress(d7a67a37): plan_json.plan_start_date=2026-05-18, schedules schedule_2026-06-06 = Legs B + 8 exercises (data present + recoverable); scheduled_workouts has no exercises/name column" }
impact_analysis: >
  Account blast radius — any user reinstalling while a plan already exists
  locally lost their planned-day exercises (only completed days survive via the
  separate log tables) and saw an inflated week number computed off a stale
  plan_start. The restore now applies the cloud plan_json snapshot
  unconditionally (completed-day-safe), the symptom-gated boot heal repairs an
  already-broken install on the next sign-in, and the display reads are
  phase-relative so the labels cannot drift from current_phase. NOTE: the
  founder's account additionally carries inconsistent year-sim/clock-seam data
  (plan.phase=4 vs current_phase=2; updated_at May 1 vs synced Jun 5) flagged
  for a separate cleanup — the fixes here are correct for clean accounts and
  make the labels honest regardless of that pollution.
---

# Fresh-install restore skipped plan_json → wrong week/phase + rest-day collapse

## What happened
The founder reinstalled the latest APK and restored from Supabase. The Train,
Home and Roadmap screens then disagreed about the current week/phase, and most
days showed "REST DAY / No exercises scheduled" with a START button that did
nothing ("in the current week i cant start the workout").

## Root cause
`_restoreWorkoutPlan` is the only restore step that applies the cloud
`plan_json` snapshot — the correct `plan_start_date` AND the date-keyed
`schedules` map that carries each planned day's `workout_name` + `exercises[]`.
It early-returned whenever a local `current_plan` already existed. On a reinstall
a plan can be locally (re)generated before/around restore, so the snapshot was
never applied. The exercise-less `scheduled_workouts` restore (the cloud table
has **no** exercises/name column) then populated the days, so every
not-yet-completed day came back content-less, and the week number was computed
off a stale `plan_start_date`. One skip → both the numbering chaos and the
rest-day collapse.

Verified against live cloud data: `user_progress(d7a67a37).plan_json` holds
`plan_start_date = 2026-05-18` and `schedules['schedule_2026-06-06'] = "Legs B"`
with 8 exercises — the data was present and recoverable, the restore mangled it.

## Fix
`_restoreWorkoutPlan` now always applies the snapshot (completed-day-preserving
merge shared with the new `PlanIntegrityReconciler`). The reconciler is
symptom-gated (no network unless a current-window planned workout day lost its
exercises), kill-switchable, and wired beside `PhaseProgressReconciler` in
`restoring_screen` so an already-broken install self-repairs on the next
sign-in. Display reads are phase-relative: the banner shows the canonical phase
name + `WK n OF 4`; the Roadmap uses `getProgramWeek`. START is gated on a
non-empty plan, and the Home workout/macro cards are 50/50.

## Verification
- `test/contracts/restore_plan_json_authoritative_test.dart` (12) +
  `test/contracts/phase_relative_week_label_test.dart` (7) — all green.
- `flutter analyze` clean on the changed files (only pre-existing infos remain).
- Live `user_progress` query confirmed the data is intact in `plan_json`.

## See also
- lib/core/services/plan_integrity_reconciler.dart (shared merge + boot heal)
- lib/core/services/sync/sync_workout.dart (`_restoreWorkoutPlan`)
- diagnose 2026-06-02-two-phase-one-week-selector-stuck-counter-a3f8c1 (the
  PhaseProgressReconciler this heal sits beside)
- diagnose 2026-05-10-restore-overwrite-d9b2c5 (the completed-day merge rule)
