---
bug_id: f3b2e8
date: 2026-07-03
batch: audit-fixwave-2026-07-02
status: fixed
blast_radius: account
symptom: >
  WorkoutScheduleWriteService.pauseRange (workout_schedule_write_service.dart:120,140)
  aliased `final box = _hive.workoutBox;` then did a bare `await box.put(key, map)`
  for each paused day, with status='paused'. Its siblings markCompleted
  (:77), markSkipped (:92), redoWeek4 (:185) and copyWeek (:227) all route
  through WorkoutWriteService.upsertScheduled, which fans out
  SyncService.syncWorkoutData()+pushSnapshot(), invalidates the calendar/today/
  plan providers, and takes the per-date mutex. pauseRange did NONE of that: a
  coach "pause my plan for N days" (tool_dispatcher pausePlan → pauseRange) wrote
  local Hive only, so (a) the pause did not reach cloud that tick — lost on a
  reinstall-before-next-sync, and (b) the Train calendar / Today card stayed stale
  until a manual rebuild. Offline-first so the common case eventually reconciles
  (the paused entry rides the next workout-domain sync), but it is a window /
  staleness + provider-invalidation bug. The class header comment (:6-9) already
  CLAIMED pauseRange "calls into WorkoutWriteService for each Hive mutation" — it
  didn't, until this fix.
concept: workout_schedule_write_path
sot_registry_entry: >
  workout_schedule_service_routes_through_write_service — pauseRange now routes
  each paused day through WorkoutWriteService.upsertScheduled (source schedSwap),
  matching markCompleted/markSkipped/redoWeek4/copyWeek. It is no longer an
  exception to the "all schedule mutations route through the canonical writer"
  invariant.
writers: >
  HIVE schedule_<istDate>: pre-fix WorkoutScheduleWriteService.pauseRange did a
  bare box.put (workout_schedule_write_service.dart:140); post-fix it calls
  WorkoutWriteService.upsertScheduled(date, entry, source: schedSwap) which does
  the mutex-guarded put (workout_write_service.dart:529) + stamps source +
  updated_at_ms (:523-528). CLOUD scheduled_workouts.status: pushed by
  _syncScheduledWorkouts (sync_workout.dart:1557-1565) which passes status
  verbatim — status='paused' now reaches cloud on the fan-out.
readers: >
  workoutBox.get('schedule_<istDate>') — Train week-selector / Today card / plan
  readers (workout_schedule_read_service.dart) render status. cloud
  scheduled_workouts.status is restored back into the same keys on cross-device
  restore. paused_via / paused_at / pause_reason are local-only annotation fields
  (no cloud columns exist; no sync path ever projected them) preserved in Hive via
  upsertScheduled's `...entry` spread.
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + istDateStr(date)"
sync_methods: ["upsertScheduled -> syncWorkoutData", "_syncScheduledWorkouts"]
restore_methods: ["scheduled_workouts restore into schedule_ keys (sync_workout.dart)"]
cloud_table: scheduled_workouts
cloud_columns: ["status"]
contract_test_path: test/contracts/pause_range_routes_through_write_service_test.dart
ist_handling: >
  The schedule key uses istDateStr(date) (== formatDateKey) both in pauseRange and
  in upsertScheduled's scheduleKey(date), so routing does not change the key. The
  cloud upsert keys on user_id,scheduled_date (UNIQUE, verified live). No timestamp
  semantics changed; status='paused' is a status token, not a date.
provider_invalidations:
  - "calendar/today/plan providers via WorkoutWriteService.onInvalidate (now fired for pause; pre-fix none)"
telemetry_op_types:
  success: []
  failure: ["workout_write_service_upsert_scheduled"]
cross_account_guard: true
forbidden_patterns_checked:
  - "A schedule mutation that writes workoutBox directly (bare or ALIASED box.put) instead of routing through WorkoutWriteService.upsertScheduled, skipping the cloud fan-out + provider invalidation + per-date mutex. pauseRange used `final box = _hive.workoutBox; box.put(...)` — the alias hid it from the existing gate regex. FIXED: routes through upsertScheduled; the gate (workout_schedule_service_uses_write_service_test.dart) was broadened to resolve _hive.workoutBox aliases so a future aliased put fails."
proposed_fix: >
  In pauseRange, replace the per-day `await box.put(key, map)` with
  `await WorkoutWriteService.instance.upsertScheduled(date: d, entry: map,
  source: WriteSource.schedSwap)`. The `box.get(key)` read stays (the alias is
  now read-only). This fans out syncWorkoutData + pushSnapshot, invalidates the
  readers, takes the mutex, and stamps source/updated_at_ms — identical to the
  sibling mutations. Verified live that cloud scheduled_workouts has NO status
  CHECK constraint (only FK/PK/UNIQUE(user_id,scheduled_date)) so status='paused'
  upserts fine. Also broadened the source-grep gate to catch aliased
  `_hive.workoutBox` puts (F4).
regression_test_planned: >
  test/contracts/pause_range_routes_through_write_service_test.dart (behavioral):
  seed a planned day via upsertScheduled (source planGenerator), call pauseRange,
  assert status='paused' + paused_via/pause_reason preserved AND source ==
  WriteSource.schedSwap.code (upsertScheduled OVERWRITES source; a bare box.put
  would leave the seed's planGenerator — this is the assertion that FAILS on the
  pre-fix bypass). Plus a completed-day-is-not-paused case. The broadened gate
  test/contracts/workout_schedule_service_uses_write_service_test.dart flips
  fail→pass across F4→F3.
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — pauseRange routes each paused day through upsertScheduled (workout_schedule_write_service.dart:pauseRange); gate broadened (workout_schedule_service_uses_write_service_test.dart)."
  - "hive_local — status: verified — schedule_<istDate> row carries status='paused' + preserved pause annotations after the routed write (behavioral test)."
  - "postgres_schema — status: verified — live query: scheduled_workouts has NO status CHECK; only FK(template_id,user_id) + PK + UNIQUE(user_id,scheduled_date). status='paused' accepted."
  - "client_to_server_contract — status: verified — _syncScheduledWorkouts (sync_workout.dart:1557-1565) passes status verbatim → pause reaches cloud on the upsertScheduled fan-out; paused_via/at/reason are local-only (no cloud columns)."
impact_analysis: >
  Affects users who pause their plan via the AI coach. Pre-fix: pause was local
  only until an unrelated workout-domain write happened to fan out (window loss on
  reinstall; stale Train UI). Post-fix: pause syncs promptly + the calendar/today
  cards refresh immediately, matching every other schedule mutation. No data loss
  in either case (offline-first). Account-tier: one user's own schedule at a time;
  no cross-user or multi-user path. Behavior-preserving for the pause semantics
  (same status token, same key, same annotations) — only the write ROUTE changed.
---

# f3b2e8 — `pauseRange` bypassed the canonical schedule writer

See YAML frontmatter for the full diagnosis. Surfaced by the 2026-07-02
comprehensive functional audit (P1); fixed in the audit-fixwave batch, Unit 2.

## Root cause (one line)
`pauseRange` did a bare, aliased `box.put` instead of routing through
`WorkoutWriteService.upsertScheduled` like its four siblings — so a coach "pause
my plan" skipped the cloud fan-out, provider invalidation, and per-date mutex, and
the aliased `box` name hid the extra put from the source-grep gate.

## Fix
Route each paused day through `upsertScheduled(source: schedSwap)`; broaden the
gate to resolve `_hive.workoutBox` aliases so a future aliased put fails
(gates-before-refactor: F4 flips the gate fail, F3 flips it back green).

## Live-verified on test7 (2026-07-03)
Coach `pause_plan` (5 days from 2026-07-03) → APPLY/Confirm → **all 5 days flip to
`status='paused'` in cloud `scheduled_workouts`** that tick (baseline: zero paused
days), proving the `upsertScheduled` cloud fan-out fired. The Train week-list
renders paused days by their workout name — grep-confirmed there is no distinct
'paused' case in the list widget (by design; the pause surfaces on Home), so that
is not a stale-UI bug. Cleanup reverted the 5 days to baseline (rest/planned).
