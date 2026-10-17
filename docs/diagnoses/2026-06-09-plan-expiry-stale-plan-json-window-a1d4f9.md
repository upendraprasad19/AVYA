---
bug_id: a1d4f9
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: account
symptom: >
  APK +34 obs 1/5.1/6 — Home "Start Workout" said "not scheduled", the Train
  week strip highlighted a wrong/last week as TODAY with "No workouts scheduled",
  and the plan looked expired — even though the user's plan had regenerated and
  cloud scheduled_workouts ran to 2026-07-05 (42 rows past the old end). The app
  trusted a stale plan window.
concept: plan_phase_expiry
sot_registry_entry: plan_phase_expiry
writers: >
  not_applicable (no writer change). The fix is in the READ/decision path. Cloud
  side, the plan window has two representations that drifted: user_progress
  scheduled_workouts (live, regenerated → 2026-07-05) vs the user_progress
  plan_json snapshot (stale → plan_end_date 2026-05-24, plan_generated_at
  2026-05-01). _syncWorkoutPlan rebuilds plan_json from the local plan_end_date
  MigratedKey; the push lagging (BUG-C d3a1c7 401) is the enabler of the split.
readers: >
  lib/core/services/workout_schedule_read_service.dart isPhaseExpired() — was
  `today.isAfter(getPlanEndDate())` using the stale plan_json-derived plan_end.
  Now: expired only if the stored window says so AND _scheduledWorkoutDays() has
  no real workout day on/after today (pure decision isPhaseExpiredFrom). Consumers
  of isPhaseExpired (home_screen PlanExpiredCard gate, splash autoGenerateNextPhase,
  Train week selector via BUG-B) all benefit.
hive_key_prefix: schedule_
hive_key_formula: schedule_${istDateStr(date)}
sync_methods: _syncWorkoutPlan (plan_json), _syncScheduledWorkouts (scheduled_workouts)
restore_methods: _restoreWorkoutPlan (applies plan_json window authoritatively), _restoreScheduledWorkouts (materializes per-day rows)
cloud_table: user_progress
cloud_columns: plan_json, plan_generated_at
contract_test_path: test/contracts/plan_expiry_respects_schedule_test.dart
ist_handling: >
  isPhaseExpired uses nowWall() (seam-aware) and compares DATE-only (year/month/
  day) so the last scheduled day itself is not treated as expired. Schedule keys
  are IST date strings (istDateStr).
provider_invalidations:
  - todayWorkoutProvider (home reads schedule + isPhaseExpired)
  - currentPlanProvider
telemetry_op_types: not_applicable
cross_account_guard: >
  not_applicable to the fix (reads the current user's workoutBox via _hive, which
  is user-scoped via HiveUserSession).
forbidden_patterns_checked:
  - "isPhaseExpired must not trust the stored plan_end_date alone when a real workout day is materialized today-or-later; pinned by test/contracts/plan_expiry_respects_schedule_test.dart (isPhaseExpiredFrom pure decision)."
proposed_fix: >
  Extract isPhaseExpiredFrom(today, storedEnd, scheduledWorkoutDays) — expired
  iff storedEnd non-null AND date(today) > date(storedEnd) AND no scheduled
  workout day is on/after today. isPhaseExpired() fast-paths the stored-window
  check, then scans the local schedule (_scheduledWorkoutDays, non-rest) only
  when the stored window already says expired. This treats the materialized
  schedule as authoritative over a stale plan_json-derived plan_end_date.
regression_test_planned: >
  test/contracts/plan_expiry_respects_schedule_test.dart — pure isPhaseExpiredFrom
  cases: stale end + future workout → not expired; past end + only past days →
  expired; workout today → not expired; inside window → not expired; null end →
  not expired; empty schedule + past end → expired.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "isPhaseExpired rewritten with the materialized-schedule check + pure isPhaseExpiredFrom helper; dart analyze clean; plan_expiry_respects_schedule_test green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "_scheduledWorkoutDays scans schedule_<date> rows (non-rest); a future planned day makes isPhaseExpired false" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live: scheduled_workouts max=2026-07-05 (42 rows past 05-24) vs plan_json plan_end_date=2026-05-24 — the SoT split this fix tolerates on the read side" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "BUG-C (d3a1c7) restores the daily-snapshot push so the cloud plan_json re-persists going forward; this read-side fix heals the symptom even before that lands on a device" }
impact_analysis: >
  Account blast radius — the plan-expiry decision gates Home (PlanExpiredCard),
  splash next-phase auto-generation, and the Train week strip (BUG-B). The bug
  was trusting a single stale cloud representation (plan_json plan_end_date) over
  the live materialized schedule. The fix makes the materialized schedule
  authoritative for "is the plan still active". It does NOT heal the stale local
  plan_end_date constant itself (other than via BUG-C re-persisting the cloud
  snapshot) — and if a partial/504-truncated restore left the future schedule
  rows missing locally, the user can still read expired until those rows restore
  (addressed by BUG-G restore hardening). New SoT concept plan_phase_expiry +
  debugging bug class (two cloud representations of one concept drift) added in
  the batch self-evolve step.
---

# Plan looked expired though scheduled_workouts ran a month into the future

## What happened
APK +34 obs 1/5.1/6: Home "not scheduled", Train highlighted a wrong/last week
with no workouts, plan looked expired — but the plan HAD regenerated
(scheduled_workouts → 2026-07-05).

## Root cause
A source-of-truth split: the live `scheduled_workouts` table extended to 07-05,
but the `user_progress.plan_json` snapshot the client reads the plan window from
was stale (plan_end_date 05-24, generated 05-01). `isPhaseExpired()` was
`today.isAfter(plan_end_date)` → true → false "expired". The push that would
re-persist plan_json was 401ing (BUG-C).

## Fix
`isPhaseExpired()` now treats the materialized schedule as authoritative: expired
only if the stored window says so AND no real workout day is scheduled today or
later (pure `isPhaseExpiredFrom`). Fast-pathed so the schedule scan runs only
when the stored window already says expired.

## Verification
`dart analyze` clean; `plan_expiry_respects_schedule_test.dart` (6 pure cases).
Live: scheduled_workouts max 2026-07-05 vs plan_json plan_end_date 2026-05-24.

## See also
- BUG-C (d3a1c7) — restores the daily-snapshot push so cloud plan_json re-persists.
- BUG-B — Train week selector consumes isPhaseExpired for its expired/transition state.
- BUG-G — restore hardening for the partial-restore (missing future rows) case.
