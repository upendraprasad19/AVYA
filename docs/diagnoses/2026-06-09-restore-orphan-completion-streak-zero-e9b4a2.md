---
bug_id: e9b4a2
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: account
symptom: >
  APK +34 obs 5.2 — Home showed streak "0 DAYS" though cloud
  user_progress.current_streak_days was 2 and the user had recent completions
  (last_workout_date 2026-06-06). After a reinstall the client-side streak walk
  found no completed days locally.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers: >
  lib/core/services/sync/sync_workout.dart _restoreScheduleCompletions — now
  SYNTHESIZES a completed schedule_<date> row (status='completed', type='logged',
  source='cloud_restore_completion') when the cloud workout_schedule_completions
  row has no matching local schedule entry. Previously it only updated existing
  rows and skipped missing ones. Mirrors WorkoutWriteService.markCompleted's
  no-prior-schedule synthesize branch.
readers: >
  lib/features/train/repositories/workout_repository.dart _calculateStreak (reads
  the local schedule_<date> map status=='completed'; type 'logged' is a workout
  day, so it counts) + week_selector.dart pastPhaseBlocks / hasCompletedDayInWeek
  (past-phase scroll-back reads the same completed rows).
hive_key_prefix: schedule_
hive_key_formula: schedule_${scheduled_date}
sync_methods: not_applicable (read/restore-side)
restore_methods: _restoreScheduleCompletions (sync_workout.dart)
cloud_table: workout_schedule_completions
cloud_columns: scheduled_date, workout_name, completed_at, duration_seconds
contract_test_path: test/contracts/restore_orphan_completion_test.dart
ist_handling: >
  schedule_<date> keys use the cloud scheduled_date (an IST date string); the
  streak walk compares via formatDateKey (istDateStr). No new date math here.
provider_invalidations: []
telemetry_op_types:
  failure: [restore_schedule_completions]
cross_account_guard: not_applicable (writes the current user's user-scoped workoutBox)
forbidden_patterns_checked:
  - "_restoreScheduleCompletions must not skip a cloud completion that has no local schedule row — it must synthesize a completed schedule_<date> row (source='cloud_restore_completion', type='logged'). Pinned by test/contracts/restore_orphan_completion_test.dart."
proposed_fix: >
  Add an `else if (date.isNotEmpty)` branch to _restoreScheduleCompletions that
  puts a synthesized completed row (status='completed', type='logged',
  workout_name/completed_at/duration_seconds from the cloud completion) so the
  completion survives a reinstall and the streak walk + past-phase view see it.
regression_test_planned: >
  test/contracts/restore_orphan_completion_test.dart — comment-stripped
  source-grep: _restoreScheduleCompletions synthesizes a row tagged
  cloud_restore_completion with type='logged'. Full Hive restore round-trip is
  the follow-up behavioral case (restore_completeness carries
  behavioral_test_required).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "synthesize-on-missing branch added; dart analyze clean on sync_workout.dart + the test; restore_orphan_completion_test green" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "out-of-window completions now produce local schedule_<date> status='completed' rows that the streak walk counts" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live: workout_schedule_completions has 18 rows for the account (last 2026-06-06); cloud current_streak_days=2 — the client now reconstructs that locally after a reinstall" }
impact_analysis: >
  Account blast radius — streak correctness (which gates rank progression) +
  past-phase visibility. The bug was a restore-completeness gap: completions
  outside the (possibly stale) plan_json window had no local scaffold, so the
  client-computed streak read 0 even though cloud held the right value and the
  workouts genuinely happened. Synthesizing the row closes the gap. Also part of
  the obs-1 "completed Phase 1 not visible" surface (past completed days now
  restore). Note: streak being numerically LOW (2-3) for an account with only a
  few recent completions is correct — the bug was the 0/N mismatch from missing
  local rows, not the magnitude.
---

# Streak read 0 after reinstall (out-of-window completions not restored)

## What happened
APK +34 obs 5.2: Home showed streak "0 DAYS" though cloud current_streak_days
was 2 and recent workouts existed.

## Root cause
`_restoreScheduleCompletions` only UPDATED existing local schedule_<date> rows
and SKIPPED completions with no local row. Completions outside the (stale)
plan_json window — ad-hoc/logged days, or past phases — had no scaffold from
`_restoreWorkoutPlan`, so they were dropped on reinstall. The client streak walk
reads local schedule_<date> status=='completed', so it counted nothing → 0.

## Fix
Synthesize a completed schedule row (status='completed', type='logged',
source='cloud_restore_completion') when no local entry exists, mirroring
markCompleted's no-prior-schedule branch.

## Verification
`dart analyze` clean; `restore_orphan_completion_test.dart`. Live:
workout_schedule_completions = 18 rows (last 06-06), cloud current_streak_days=2.

## See also
- `lib/core/services/workout_write_service.dart` markCompleted (the synthesize this mirrors)
- BUG-G — restore hardening (the partial/504-truncated restore that can still drop future rows)
