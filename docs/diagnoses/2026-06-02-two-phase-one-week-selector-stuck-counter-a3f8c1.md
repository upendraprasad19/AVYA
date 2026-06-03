---
bug_id: a3f8c1
date: 2026-06-02
batch: apk-obs-2026-06-02
status: fixed
blast_radius: platform
symptom: >
  On the Train screen the week-selector strip showed TWO "PHASE I" sections — a
  completed "PHASE I (DONE)" with weeks W1 (Apr 27–May 3) … W4 (May 18–24) AND a
  second, current "PHASE I" with fresh weeks. Founder (upendra, PRO) completed a
  Phase 1 but never advanced: cloud user_progress.current_phase was stuck at 1
  (deployments_complete 0) while scheduled_workouts held two Phase-1 date ranges
  (min 2026-04-27, max 2026-06-14; only 4 distinct week_numbers). The strip's
  phase labels are hardcoded and never read the real current_phase, so the
  completed phase and the current one both rendered "PHASE I".
concept: phase_progress_current_phase
sot_registry_entry: phase_progress_current_phase
writers: >
  current_phase: lib/shared/repositories/user_repository.dart saveProgress
  (stamps deployments_complete = max(prior, current_phase-1), monotonic) +
  updateProgress (merge + syncProgressNow). Advance paths: splash_screen.dart
  _autoGenerateNextPhaseForPro (PRO, current_phase+1) + graduation_screen.dart
  _onPro (current_phase+1). NEW writer: lib/core/services/phase_progress_reconciler.dart
  reconcile() — monotonically advances current_phase to (completed phase blocks)+1
  on boot. schedule rows: lib/core/services/workout_schedule_read_service.dart
  generateAndSchedule (writes plan_start + schedule_* rows).
readers: >
  lib/features/train/widgets/week_selector.dart — pre-fix the forward _PhaseGroup
  labels were hardcoded "PHASE I/II/III" and _loadPastPhases numbered past phases
  from 1; post-fix WeekSelector takes currentPhase and labels the current group
  PHASE roman(currentPhase) + numbers past phases ending at currentPhase-1 (gated:
  none when current_phase==1), consuming the shared
  WorkoutScheduleReadService.pastPhaseBlocks() SoT. lib/features/train/screens/train/plan_header.dart
  already read current_phase correctly (the two readers had drifted).
hive_key_prefix: schedule_
hive_key_formula: schedule_${istDateStr(date)} (WorkoutWriteService.upsertScheduled via WorkoutScheduleService); plan window in MigratedKey plan_start_date / plan_end_date.
sync_methods: _syncScheduledWorkouts (scheduled_workouts); user_progress synced via sync_profile.dart (current_phase, deployments_complete).
restore_methods: _restoreScheduledWorkouts (cloud scheduled_workouts → schedule_* Hive); user_progress hydrated by AuthSessionBootstrapper + sync_profile.
cloud_table: scheduled_workouts (plan rows) + user_progress (current_phase, deployments_complete)
cloud_columns: >
  user_progress(current_phase int, current_week int, deployments_complete int);
  scheduled_workouts(user_id, scheduled_date, week_number, status, completed_at).
contract_test_path: test/contracts/phase_progress_reconciler_test.dart
ist_handling: >
  not_applicable to new date math — pastPhaseBlocks() buckets schedule_* by the
  rows' own istDateStr 'date' field; the reconciler reads/writes counters only.
provider_invalidations: >
  current_phase write goes through UserRepository.updateProgress → syncProgressNow;
  the Train screen rebuilds via currentPlanProvider on next mount. The reconciler
  runs in restoring_screen before /home, so currentPlanProvider reads the corrected
  counter on first build.
telemetry_op_types: >
  success: phase_progress_reconciled (emitted when the reconciler advances a stuck
  counter, with from/to/blocks); failure: recordNonFatal(reason: phase_progress_reconciler).
  Plus restoring_screen_migrator_done (migrator=phase_reconcile ms=...).
cross_account_guard: >
  preserved. The reconciler reads UserRepository.getProgress() + the user-scoped
  workoutBox (via the schedule service) for the current session only; it writes the
  current user's progress. No cross-account path.
forbidden_patterns_checked:
  - "Hardcoded forward phase label ('PHASE I'/'PHASE II'/'PHASE III') in week_selector that ignores current_phase — eliminated; labels derive from widget.currentPhase via _phaseRoman. Pinned by test/contracts/week_selector_reads_current_phase_test.dart + gate scripts/check_week_selector_phase_labels.dart."
  - "Parallel past-phase bucketing in the widget that could drift from the reconciler's count — eliminated; both consume WorkoutScheduleReadService.pastPhaseBlocks() (single SoT)."
proposed_fix: >
  Two layers. (1) DISPLAY: thread the real current_phase into WeekSelector; label
  the current group PHASE roman(currentPhase) and the two preview groups +1/+2;
  number past phases by their real number ending at currentPhase-1 and render none
  when current_phase==1 (kills the phantom duplicate). Extract the 28-day past-block
  bucketing into WorkoutScheduleReadService.pastPhaseBlocks() (a public SoT) so the
  week selector AND the reconciler share one bucketing — no writer/reader drift.
  (2) HEAL (founder choice "advance, keep progress"): PhaseProgressReconciler runs
  on boot (restoring_screen, after restore + key migrators); when current_phase <
  (completed past phase blocks)+1 it advances current_phase to that value (monotonic,
  never demotes; deployments_complete restamped by saveProgress). The in-progress
  plan stays the current phase — streak + weeks-done preserved; NO schedule-row
  rewrites, NO deletes. Idempotent (no-op once consistent → safe every boot, also
  self-heals future duplicates regardless of cause), kill-switch
  configBox['disable_phase_reconciler'], plan_start guard (skips if unknown so it
  can never over-count).
regression_test_planned: >
  test/contracts/phase_progress_reconciler_test.dart (behavioral): seed a stuck
  fixture (current_phase=1 + one completed past phase block before plan_start) →
  reconcile() advances to 2 + deployments_complete 1; a consistent fixture is a
  no-op; never demotes; current_phase==1 with no past blocks is a no-op (free user).
  test/contracts/week_selector_reads_current_phase_test.dart (comment-stripped
  source-grep): WeekSelector ctor takes currentPhase; forward labels use
  _phaseRoman(widget.currentPhase); no hardcoded forward 'PHASE I' literal; the
  build passes plan.phase. Gate scripts/check_week_selector_phase_labels.dart pins
  the same at pre-commit/CI.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "week_selector.dart reads currentPhase + shared pastPhaseBlocks(); PhaseProgressReconciler added + wired in restoring_screen; flutter analyze clean on the changed files (only pre-existing infos remain)" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "reconciler reads schedule_* + writes user_progress current_phase via UserRepository.updateProgress; behavioral test seeds Hive + asserts the advance + monotonicity" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "live: user_progress has current_phase/current_week/deployments_complete (int); the heal writes counters only, no schema change" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live query 2026-06-02: upendra current_phase=1, deployments_complete=0, two scheduled_workouts Phase-1 ranges (Apr 27–May 24 + to Jun 14) — the stuck state the reconciler heals to current_phase=2 on next boot" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "reconciler advance → updateProgress → syncProgressNow pushes current_phase/deployments_complete to cloud user_progress; Train header + week selector both then read current_phase=2 consistently" }
impact_analysis: >
  Platform blast radius — the display half hits EVERY user who advances past Phase 1
  (the hardcoded labels never reflected current_phase, so a Phase-2 user's current
  block rendered "PHASE I" and any past block also rendered "PHASE I"). The data
  half (stuck counter + duplicate Phase-1 plan) was observed on the founder's real
  PRO account; exact regeneration trigger is unknown (a month of heavy testing —
  re-onboard / expiry / restore), so rather than chase the single trigger the
  reconciler makes the invariant self-correcting on every boot (current_phase >=
  completed-blocks+1) and is monotonic, so it can only ever advance a stuck user,
  never demote. Free users (always Phase 1, zero completed blocks) are a guaranteed
  no-op. The fix preserves the in-progress plan + streak ("advance, keep progress")
  and never deletes or rewrites schedule rows. The phase_progress_reconciled
  telemetry gives prod observability into how often a stuck state is healed (and
  thus whether a generation-path bug is still creating duplicates). Found via the
  founder's APK observation + live user_progress / scheduled_workouts queries.
---

# Two "PHASE I" — hardcoded week-selector labels + a stuck current_phase counter

## What happened
The Train week-selector rendered a completed "PHASE I (DONE)" (Apr 27–May 24)
next to a current "PHASE I". The founder (PRO) had completed a Phase 1 but
`current_phase` was stuck at 1, and a second Phase-1 plan had been generated.

## Root cause (two stacked faults)
1. **Display (generalizable):** `week_selector.dart` hardcoded `PHASE I/II/III`
   for the forward groups and `_loadPastPhases` numbered past phases from 1 —
   neither read the real `current_phase`. `plan_header.dart` *did* read it, so
   the two readers had drifted (the recurring writer/reader-drift class).
2. **Data/logic:** completing Phase 1 never advanced `current_phase` (it stayed
   1, with a duplicate Phase-1 plan generated). Exact trigger unknown (heavy
   testing).

## Fix
- **Display:** thread `current_phase` into `WeekSelector`; label the current
  group `PHASE roman(currentPhase)`, previews `+1/+2`, past phases numbered to
  `currentPhase-1` (none on Phase 1). Both the selector and the reconciler read
  one shared `WorkoutScheduleReadService.pastPhaseBlocks()` (no parallel
  bucketing → no drift).
- **Heal ("advance, keep progress"):** `PhaseProgressReconciler.reconcile()` on
  boot advances `current_phase` to `(completed past phase blocks)+1` —
  monotonic, idempotent, kill-switched, plan_start-guarded. The in-progress plan
  stays current; streak/weeks-done preserved; nothing deleted.

## Verification
- `flutter analyze` clean on the changed files.
- `phase_progress_reconciler_test.dart` (behavioral: advance / no-op / monotonic /
  free-user no-op) + `week_selector_reads_current_phase_test.dart` (source-grep) +
  gate `check_week_selector_phase_labels.dart`.
- Live: upendra reconciles 1→2 on next boot → Train shows "Phase 2, week 3" with
  "Phase 1 (DONE)" to the left, no duplicate.

## See also
- `lib/features/train/widgets/week_selector.dart`, `lib/core/services/phase_progress_reconciler.dart`
- `lib/core/services/workout_schedule_read_service.dart` (`pastPhaseBlocks`)
- `feedback_writer_reader_field_drift_recurring.md`, `feedback_monotonic_field_recompute_demotion.md`
