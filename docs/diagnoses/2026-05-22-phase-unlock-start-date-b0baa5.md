---
bug_id: b0baa5
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 4 / Theme H)
status: shipped
symptom: |
  Founder tapped GENERATE NEXT PHASE the second time on 2026-05-21
  evening (after Theme F2 unblocked the silent gate). Plan generation
  fired, BUT: the train screen then showed a new Phase 1 starting from
  THIS Monday (May 18) — erasing the previous Phase 1 W1-W3 schedule
  entries (Apr 27 - May 17) AND populating Phase 2 W5 with "No workouts
  scheduled". Founder confused — his completed Phase 1 workouts had
  vanished from the calendar.

  Root cause: graduation_screen.dart:448 + workout_schedule_read_service.dart:399
  (autoGenerateNextPhaseIfNeeded) both passed `DateTime.now()` directly
  as startDate into generateAndSchedule. The service then applied
  `_normalizeToMonday(startDate)` at line 100, resolving to THIS week's
  Monday. For founder tapping Wed May 21, that = May 18 — the Monday
  of his current Phase 1 W4. New Phase 2 W1 entries got written under
  schedule_2026-05-18 / 19 / ... overwriting the existing Phase 1 W4
  entries. The completed-history scope shifted (week_character +
  workout_name now Phase 2's) so the train screen rendered the wrong
  current-week banner.

  Secondary issue: WorkoutWriteService.upsertScheduled at
  workout_write_service.dart:409 had no guard against overwriting an
  entry whose `status == 'completed'`. Even when the planGenerator
  path inadvertently lands on completed days (the bug above), the
  writer silently clobbered them. No telemetry. No recovery.
concept: scheduled_workouts_mutations
sot_registry_entry: workout_logs
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: upsertScheduled now refuses planGenerator overwrites of completed days + emits upsert_scheduled_skipped_completed_day telemetry, line: 409 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: nextPhaseStartDate helper — computes max(today, currentPhaseEnd + 1) Monday-normalized, line: 549 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: autoGenerateNextPhaseIfNeeded routes via nextPhaseStartDate (no raw DateTime.now), line: 379 }
readers:
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: GENERATE NEXT PHASE tap — passes nextPhaseStartDate() into generateAndSchedule, line: 415 }
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: week renderer reads schedule_* keys (no change), line: 1 }
hive_key_prefix: "schedule_"
hive_key_formula: "schedule_${istDateStr(date)}"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [date, week, day_of_week, type, workout_name, status, completed_at, week_character, source]
contract_test_path: test/contracts/phase_unlock_start_date_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 549, source: "nextPhaseStartDate uses LOCAL DateTime.now() — schedule keys downstream go through _normalizeToMonday + istDateStr separately. The 'when phase starts' logic is anchored to user perception of week boundaries (local), not IST." }
  - { file: lib/core/services/workout_write_service.dart, line: 415, source: "upsertScheduled uses istDateStr(date) for the canonical key" }
provider_invalidations:
  - currentPlanProvider
  - todayWorkoutProvider
  - calendarWeekProvider
telemetry_op_types:
  success: []
  failure: [upsert_scheduled_skipped_completed_day]
cross_account_guard: WorkoutWriteService.upsertScheduled already routes through HiveService.workoutBox which wraps via wrapUserScopedBox.
forbidden_patterns_checked:
  - "startDate: DateTime.now() passed into generateAndSchedule — clobbers current phase final week."
  - "upsertScheduled overwriting status='completed' from planGenerator — silent data loss."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "workout_schedule_read_service.dart:549 (nextPhaseStartDate helper) + :399 (autoGenerate uses it) + graduation_screen.dart:447 (uses it) + workout_write_service.dart:415 (guard)" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "schedule_* key format unchanged (istDateStr) — only the chosen DATE for new entries differs" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/phase_unlock_start_date_test.dart — pins helper presence + caller wiring + completed-day guard" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/graduation_screen.dart (user-tap path)
    - lib/core/services/workout_schedule_read_service.dart autoGenerateNextPhaseIfNeeded (splash auto path)
  callers_updated_in_this_batch:
    - lib/features/train/screens/graduation_screen.dart (startDate)
    - lib/core/services/workout_schedule_read_service.dart (autoGenerateNextPhaseIfNeeded startDate + new nextPhaseStartDate helper)
    - lib/core/services/workout_write_service.dart (upsertScheduled guard)
  callers_unchanged:
    - All other generateAndSchedule callers (e.g. onboarding initial generation) — they pass `DateTime.now()` legitimately because there's no prior phase to push past.
proposed_fix: |
  Three changes:

  1. NEW helper `WorkoutScheduleReadService.nextPhaseStartDate({DateTime?
     now})` at workout_schedule_read_service.dart:549. Reads
     `plan_end_date` (already stored by every generateAndSchedule call
     at line 104). Returns `_normalizeToMonday(max(today,
     planEnd + 1 day))`. Falls back to `_normalizeToMonday(today)` if
     plan_end_date is missing (defensive).

  2. graduation_screen.dart:447 + autoGenerateNextPhaseIfNeeded both
     call `nextPhaseStartDate()` instead of passing raw `DateTime.now()`.

  3. WorkoutWriteService.upsertScheduled at workout_write_service.dart:415
     adds a defensive guard: if `existingMap['status'] == 'completed'`
     AND `source == WriteSource.planGenerator`, refuse the write and
     emit `upsert_scheduled_skipped_completed_day` telemetry. Scoped to
     planGenerator only because every other source (editSheet,
     activeWorkout, swap, restore, manual, aiCoach) has a legitimate
     reason to write to a completed day.

  Onboarding (initial Phase 1 generation) is unaffected because there
  is no `plan_end_date` stored yet — nextPhaseStartDate falls back to
  Monday-normalized today, which is correct for a first-time generation.
regression_test_planned:
  - test/contracts/phase_unlock_start_date_test.dart — 6 assertions: nextPhaseStartDate method exists, reads _planEndKey, computes max via candidate.isAfter(today); both callers (graduation_screen + autoGenerateNextPhaseIfNeeded) route through it; upsertScheduled guards completed days from planGenerator with telemetry.
related_bugs:
  - 7b3eaf  # Theme F2 — gate catchError; the bug that unblocked the user's tap so this clobbering became visible
  - "Theme F (commit 6) — provider invalidations + plan_generated_at write"
---
# Body

## Why `max(today, planEnd + 1)` (not just `planEnd + 1`)

Consider a user who lets Phase 1 expire (inactivity for 8 weeks). On
unlock tap, planEnd + 1 would land 8 weeks in the past. The new phase
should start the user's CURRENT Monday, not retroactively. The max-
of-two-dates picks correctly:
- Active mid-phase user: planEnd is in future, candidate wins.
- Lapsed user: today is in future, today wins.

## Why scope completed-day refusal to planGenerator only

The guard intentionally lets other write sources through. Examples:
- `editSheet`: user is editing a completed log — legitimate mutation.
- `activeWorkout` / `aiCoach`: re-logging — legitimate.
- `schedSwap`: handled by a separate `rescheduleDay` path that
  preserves status semantics anyway.
- `restore`: cloud-restore MUST be allowed to replay history; the
  Test #12.7 fix already keeps `completed_at` stable across restore.
- `manual`: user explicitly tapped a button.

Only planGenerator has no legitimate use-case for overwriting a
completed day. It's a pure data-generation source.

## Why this wasn't caught earlier

The bug requires a specific condition: user mid-phase taps unlock on
a non-Monday. Pre-Theme-F2, the silent gate hid this — the tap
"did nothing" so no user reached the data-corruption state. Once
Theme F2 made the tap actually fire, the founder hit it immediately.

## Combined effect with the other commits this batch

- Theme F2 (commit 2) ensures the tap reaches a branch.
- Theme F1 (commit 3) ensures TOTAL SETS displays correctly on the
  graduation screen so the user actually has graduation data to trust.
- THIS (Theme H, commit 4) ensures the resulting plan generation
  doesn't corrupt history.
- Theme F (commit 6, upcoming) wires post-unlock provider
  invalidations so the train screen renders the new phase
  immediately after unlock.

The four-fix sequence covers the full "tap unlock → land on new
Phase 2 W1, with Phase 1 history intact" flow.
