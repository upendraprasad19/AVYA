---
bug_id: d5a1e7
date: 2026-09-26
batch: day-swapper-sync-load
status: in_progress
blast_radius: platform
symptom: |
  A day swap made with the existing `SwapService.swapDays` (lib/core/services/swap_service.dart:113)
  can silently revert on the next app launch, and a workout-to-workout swap never propagates to a
  second device at all. `swapDays` never pushes the plan backup (`user_progress.plan_json`) itself —
  the backup is only pushed by the daily `weeklyFullSync` (lib/core/services/sync_service.dart:1343,
  interval at :703) or by the specific writers listed under OI-189, and a swap is not one of them.
  On every launch, `restoreLightweightAlways` (lib/core/services/sync_service.dart:1535) runs
  `_restoreWorkoutPlan` BEFORE the daily sync check (:1095-1096), and raw-puts
  `PlanIntegrityReconciler.mergeScheduleEntry` (lib/core/services/plan_integrity_reconciler.dart:69)
  for every snapshot row. `mergeScheduleEntry` keeps a completed local row and a local row that has
  exercises; otherwise it takes the snapshot's content and keeps the local `status`. A rest row (the
  destination of a workout->rest swap) has no exercises, so the next launch refills it with the
  stale snapshot's workout while keeping `status: rest`, producing a `type: workout` + `status: rest`
  hybrid. `isRestDayConsideringLogged(type)` (lib/shared/repositories/plan_engine/plan_engine_flags.dart:499)
  decides by `type` alone, so the workout renders on both the old and new date. Workout<->workout
  swaps survive a restart (both rows keep exercises), but for the identical reason they never reach
  a second device: that device's own non-empty local rows always win the merge, so a workout-to-workout
  swap made on device A is invisible on device B even after a successful cloud push.
concept: schedule_arrangement_stamp
sot_registry_entry: scheduled_workouts_mutations (interim until Task 29 registers schedule_arrangement_stamp; Task 31 re-points this line to it — see docs/sot_registry.yaml; the merge's
  `arranged_at_ms` timestamp comparison is what this fix adds as the tie-breaker between a device's
  local schedule rows and a downloaded plan_json snapshot)
writers:
  - { file: lib/core/services/swap_service.dart, method: swapDays, line: 113 }
  - { file: lib/core/services/sync_service.dart, method: "weeklyFullSync (plan backup push)", line: 1343 }
readers:
  - { file: lib/core/services/sync_service.dart, method: "restoreLightweightAlways (runs _restoreWorkoutPlan before the daily-sync check)", line: 1535 }
  - { file: lib/core/services/sync_service.dart, method: "daily full-sync interval check", line: 1095 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: mergeScheduleEntry, line: 69 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method: isRestDayConsideringLogged, line: 499 }
hive_key_prefix: "schedule_ — the per-date scheduled-workout row every reader above reads type/status/exercises from."
hive_key_formula: "schedule_${formatDateKey(date)}"
sync_methods: [weeklyFullSync, pushWorkoutPlanForSyncDomain]
restore_methods: [restoreLightweightAlways, _restoreWorkoutPlan]
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: "must add: test/sync/restore_merge_invariants_test.dart (invariants
  I1-I8, spec §5.7) plus test/services/day_swap/day_swap_engine_atomic_write_test.dart"
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 113, fn: mondayOfIst }
  - { file: lib/core/utils/ist_date.dart, line: 76, fn: istTodayStr }
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: [day_swap_done]
  failure: [day_swap_failed, swap_merge_conflict]
cross_account_guard: n/a — the merge operates on the already-scoped current user's own schedule
  rows and plan_json backup; no cross-account read is introduced by this fix.
forbidden_patterns_checked:
  - { pattern: "General last-write-wins on updated_at_ms for every schedule row", absent: true }
  - { pattern: "A daily 7-day blind re-send safety net that could undo another device's swap", absent: true }
proposed_fix: |
  Rebuild the restore merge in three layers (spec §5.7), each with its own kill switch (CLAUDE.md
  §4.6): L1 restricts the existing refill-a-planned-row repair (the a7d3f1 fix) so it applies only
  when the local row is a workout type, its status is not `rest`, and it has no exercises — a local
  row of type `rest` or with status `rest` is kept as-is, closing the hybrid-creation path. L2 adds a
  stored `plan_bundle_cloud_fingerprint` (excluding `synced_at`) so a device skips the whole merge
  when the downloaded bundle is one it already knows about, which also removes up to 112 Hive writes
  per launch. L3 adds a per-Mon-Sun-week comparison of the newest `arranged_at_ms` on each side; the
  newer arrangement's content, status and markers win for every date in that week carrying a stamp
  on either side, and completed local rows are always kept. `WorkoutWriteService.upsertScheduled`
  gets a carry-forward rule: rewriting a date whose existing row has `arranged_at_ms` with a new entry
  that has none stamps `arranged_at_ms = now` (excluding sources `daySwap` and `restore`), so a later
  regeneration or reschedule of a swapped date counts as a newer arrangement and an old swap can never
  overwrite it. The atomic write itself (`WorkoutWriteService.swapScheduledDays`, replacing the dead
  `rescheduleDay`) also pushes the plan backup immediately after a successful swap
  (`pushWorkoutPlanForSyncDomain`), instead of waiting for the once-daily `weeklyFullSync`.
regression_test_planned: |
  test/sync/restore_merge_invariants_test.dart covers I1 (workout<->rest swap survives
  a cold restart with a stale backup, no workout on two days), I2 (reinstall after a pushed swap shows
  it, tested from both starting states per plan-time verification #1), I3 (device A's pushed swap
  appears on device B's next launch, including workout<->workout), I4 (swap then swap-back clears
  MOVED and a stale backup does not re-apply the first swap), I5 (a pushed swap survives a later
  regeneration of unrelated dates whose push failed), I6 (completed local rows never change), I7 (the
  a7d3f1 repair still refills a planned row that lost its exercises) and I8 (no merge path produces a
  type:workout + status:rest row). Each invariant runs against real Hive plus a fake downloaded bundle
  built with `SupabaseService.clientOverrideForTest` (D6/D14). Mutation proof planned: reverting L3's
  per-week `arranged_at_ms` comparison to unconditionally prefer the snapshot must redden I1 and I3;
  reverting L1's type/status guard to the pre-fix unconditional refill must redden I1 and I8.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "PlanIntegrityReconciler.mergeScheduleEntry (L1/L3), the new plan_bundle_cloud_fingerprint (L2), and WorkoutWriteService.swapScheduledDays's immediate plan push (spec §5.4, §5.7) — planned for coordinator Task 21 and Wave 0 Task 6." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "schedule_<date> rows gain a correct arranged_at_ms comparison instead of an unconditional snapshot refill; plan_bundle_cloud_fingerprint is a new stored Hive value (spec §5.7 L2)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "This bug's fix is entirely client-side restore-merge logic; no DDL is needed for it (the sync_epoch column belongs to the OI-237 fix, doc a9d3f6)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data was queried for this specific symptom; the revert is reproduced by tracing the writer/reader chain in code (spec §1.3, 'Verified chain')." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration is required to fix this bug." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function is involved in the restore-merge path." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job reads or writes the schedule rows or plan_json bundle involved here." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No new or changed query; the existing own-rows read of user_progress is unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The immediate plan push after a swap plus the per-week arrangement-stamp merge rule is what makes a workout<->workout swap actually reach a second device (spec §1.3's point 'workout<->workout swaps never reach a second device')." }
impact_analysis: |
  Severity: P1. Any user who swaps a workout with a rest day, then restarts the app before the next
  daily full sync, gets a silently-reverted swap that shows the wrong workout on both the old and new
  date, and if a sync runs during that same launch the hybrid is persisted to the cloud, corrupting
  the backup other devices restore from. A workout<->workout swap looks like it worked (it survives
  locally) but is invisible to any other device, which will surface as "my swap disappeared" reports
  once the day-swap feature ships and users rely on it across a phone and the web app. This fix is a
  precondition for shipping day-swapping at all — it is not optional or ship-dark, because the
  feature's own core promise ("a swap never reverts") depends on it.
related_bugs: [a7d3f1]
---

# A day swap can revert after a restart, or never reach a second device (day-swapper batch, spec §1.3-1.4, §5.7)

## Background

`docs/diagnoses/2026-06-06-*-a7d3f1.md` fixed an earlier restore-merge defect: a planned workout row
that lost its exercises on restore was refilled from the snapshot, keeping the local `status`. That
repair is the ONLY reason `mergeScheduleEntry` refills anything at all, and this bug is the same
mechanism firing on the wrong input — a `rest` row has no exercises by definition, so the a7d3f1
repair refills it with stale workout content too. This diagnose-doc's fix (L1) narrows the a7d3f1
repair's applicability rather than removing it, so both symptoms are covered by the regression suite
(I7 proves a7d3f1 is not regressed; I1/I8 prove this bug is fixed).

## Why this is not a recurrence

`docs/diagnoses/INDEX.md` has no prior diagnose for a day-swap engine (grepped for `swap`, `day_swap`,
`reschedule` — every hit is either the unrelated exercise-swap picker or the `rescheduleWeek` coach
tool's own move-terminal-row bug, `e8f4a3`). This is the first time the day-swap engine's own restore
interaction has been diagnosed, so it is filed as new, though it shares root-cause machinery with
a7d3f1 (noted above as `related_bugs`).

## Fix ownership in the plan

- L1/L2/L3 restore-merge rules, the hybrid normalizer and the `plan_bundle_cloud_fingerprint`: Task 21
  (coordinator, Wave 2), touching `lib/core/services/plan_integrity_reconciler.dart` and
  `lib/core/services/sync/sync_workout.dart`.
- The atomic `swapScheduledDays` write with its immediate plan push: Task 6 (coordinator, Wave 0),
  touching `lib/core/services/workout_write_service.dart` and `lib/core/services/write_result.dart`.
- The engine that calls both: Tasks 10-12 (U4), touching `lib/core/services/swap_service.dart`.

## Mutation evidence

Recorded at Task 31: each mutation, the grep that confirmed it applied, and the red count.
