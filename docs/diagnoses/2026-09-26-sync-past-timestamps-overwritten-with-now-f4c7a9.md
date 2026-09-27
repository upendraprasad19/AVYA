---
bug_id: f4c7a9
date: 2026-09-26
batch: day-swapper-sync-load
status: in_progress
blast_radius: platform
symptom: |
  Two workout-completion sync paths, plus 12 other sync-payload sites, fall back to `DateTime.now()`
  when a timestamp describing something that already happened is missing, so a past event gets
  re-stamped with the sync pass's own wall-clock time on every push. `markCompleted`
  (lib/core/services/workout_write_service.dart:502, :511) stamps the schedule row with
  `completed_at_ms` only; the ISO `completed_at` is written on the `wlog_<date>` row instead
  (:541). `_syncScheduleCompletions` (lib/core/services/sync/sync_workout.dart:629) sends
  `entry['completed_at'] ?? DateTime.now().toUtc().toIso8601String()`, which is "now" on every pass
  because the schedule row never carries an ISO `completed_at`. `_syncScheduledWorkouts`
  (sync_workout.dart:1707-1710) sends the raw (usually null) `completed_at`, so completed scheduled
  days show a null time in the cloud. Live evidence cited from the spec's own investigation (§1.6,
  read-only SQL, 2026-09-26): 17 of 37 completion records are stamped more than a day after the
  workout; 4 records for days older than 3 days were re-stamped within the last 3 days; 9 of 37
  completed scheduled days have a null time. This is a recurrence of `5a36ad` (2026-05-08), which
  fixed the identical "now" fallback for workout and exercise logs using `_resolveCompletedAt`
  (sync_workout.dart:532) — the two completion paths above were never moved onto that resolver. The
  plan's own re-grep (deviation D2) found the fallback recurs at 14 sites total, not the 11 the spec
  first counted: three more sit in `lib/core/services/sync/sync_restore_completeness.dart`
  (notifications push at :290/:293, notifications restore at :492), missed by a one-line grep because
  the `??` sits at a line break.
concept: sync_completion_time_resolution
sot_registry_entry: workout_completion_status (interim until Task 29 registers sync_completion_time_resolution; Task 31 re-points this line to it — see docs/sot_registry.yaml; extends the
  existing _resolveCompletedAt resolver from 5a36ad to the schedule-completion paths and 13 other
  "now"-fallback sites it never covered)
writers:
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (completed_at_ms only, no ISO completed_at, on the schedule row)", line: 502 }
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (ISO completed_at, on the wlog_<date> row)", line: 541 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncScheduleCompletions (now-fallback, the recurrence)", line: 629 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncScheduledWorkouts (sends the unresolved, usually-null completed_at)", line: 1707 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt (the existing 5a36ad resolver, not reused by the two readers above)", line: 532 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt call site #1", line: 102 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt call site #2", line: 244 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: "notifications push now-fallback", line: 290 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: "notifications restore now-fallback", line: 492 }
hive_key_prefix: "schedule_ (completed_at_ms) and wlog_ (completed_at ISO)"
hive_key_formula: "schedule_${formatDateKey(date)} and wlog_${formatDateKey(date)}"
sync_methods: [_syncScheduleCompletions, _syncScheduledWorkouts, _syncWorkoutTemplates, _syncCoachInteractions, _syncSavedMeals, _syncReadiness, syncSleepNow, _syncSleepLogs, _syncWeightLogs, _syncMeasurements]
restore_methods: [_resolveCompletedAt]
cloud_table: workout_schedule_completions
cloud_columns: [completed_at]
contract_test_path: "must add: test/sync/completion_time_resolver_extended_test.dart (extends the
  existing test/sync/completed_at_preservation_test.dart pattern from 5a36ad to the two schedule-
  completion paths) plus a G2 gate test (see scripts/check_sync_no_now_fallback.dart, must add:
  test/scripts/check_sync_no_now_fallback_test.dart)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_completed_at_fallback]
cross_account_guard: n/a — the fix corrects what timestamp value is sent for the current session's
  own rows; it introduces no cross-account read.
forbidden_patterns_checked:
  - { pattern: "Reusing _resolveCompletedAt's existing field order (created_at, completed_at, logged_at, updated_at_ms, completed_at_ms) unchanged for the schedule-completion paths", absent: true }
  - { pattern: "A completion-time resolver whose last resort is DateTime.now() rather than omitting the field", absent: true }
proposed_fix: |
  A completion time gets its OWN resolver order, distinct from the general `_resolveCompletedAt`
  order: `completed_at` (ISO) -> `completed_at_ms` -> the matching `wlog_<date>` row's `completed_at`
  -> omit the field entirely. It deliberately never falls back to `updated_at_ms`, because every
  schedule row carries `updated_at_ms` from its last `upsertScheduled` (often plan generation), which
  would silently reintroduce a wrong-but-plausible timestamp instead of the real completion time
  (spec §1.6's explicit warning: "the resolver cannot be reused as-is"). `_resolveCompletedAt`'s own
  last-resort "now" becomes "omit", keeping its existing `sync_completed_at_fallback` telemetry event.
  All 14 `?? DateTime.now()` sync-payload sites (spec §5.12 table, corrected to 14 by plan deviation
  D2) are fixed with the general rule: recorded value -> derived from a `*_ms` sibling or a timestamp
  embedded in the Hive key (`coach_<ms>`, `tmpl_<ms>`) -> omit, so the database keeps its existing
  value and the column default applies on insert. New gate `scripts/check_sync_no_now_fallback.dart`
  (G2, spec §7) fails on any `?? DateTime.now()` inside sync payload code, comment-stripped; it must
  fail on today's tree (14 hits after D2) and pass once this fix lands.
regression_test_planned: |
  test/sync/completion_time_resolver_extended_test.dart proves the new completion-time order picks
  the ISO `completed_at`, then `completed_at_ms`, then the matching `wlog_<date>`'s `completed_at`,
  then omits — never `updated_at_ms` even when it is the freshest field present, reproducing the exact
  trap spec §1.6 names. A live-evidence-shaped fixture reproduces the "17 of 37 stamped >1 day late"
  and "9 of 37 null" symptom and asserts the fix stops re-stamping an old completion with the sync
  pass's own time. G2's own test mutates a fixture file to insert `?? DateTime.now()` inside the sync
  payload path and confirms the gate goes red; a second mutation restores the omit-only fallback and
  confirms it goes green again. Mutation proof planned for the resolver itself: reverting the order to
  fall back to `updated_at_ms` before omitting must redden the "never updated_at_ms" assertion.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "The completion-time resolver and all 14 now-fallback sites are Dart sync code (Tasks 14, 16-19 per the plan's task list)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "The Hive key patterns the fix reads from (coach_<ms>, tmpl_<ms>, wlog_<date>) already exist and are read as-is by the existing sync code; the fix only changes what is chosen and sent, not the Hive schema." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL is needed; the fix changes what value the client sends for an existing column." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Spec §1.6's own live, read-only SQL investigation (2026-09-26) found 17 of 37 completion records stamped more than a day late, 4 records for days older than 3 days re-stamped within the last 3 days, and 9 of 37 completed scheduled days with a null time. This drafting pass cites that evidence and did not re-query the database." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration is required for this fix; existing wrong cloud values heal on the first sync after the client update, once the new SyncSkipIndex has no stored fingerprint yet for any row (spec §5.12)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads or writes either completion-time column (plan-time verification #12: grep of supabase/functions/ and supabase/migrations/ found no server-side reader of either column)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job reads either completion-time column (plan-time verification #12)." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS policy change; the existing own-rows write is unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The sync payload itself stops sending 'now' as a stand-in for a past event across all 14 sites, which is the client-to-server contract this bug violates." }
impact_analysis: |
  Severity: P2, systemic. Every completed workout's cloud completion time is wrong today whenever the
  sync pass runs later than the workout itself (the common case), which corrupts any feature that
  reads completion timing from the cloud (analytics, the weekly-recalc / rank-engine class of
  functions, if any is later added to read it) and confuses support investigations that trust the
  cloud timestamp. Because this is a recurrence of `5a36ad`, the same class will keep resurfacing at
  new sync sites unless the new gate (G2) makes the "now"-fallback pattern structurally impossible in
  sync payload code going forward, which is why G1/G2 land before the domain fixes per CLAUDE.md
  §4.11.
recurrence: 5a36ad (2026-05-08, docs/diagnoses/2026-05-08-sync-stack-templates-streak-pill-5a36ad.md)
related_bugs: [5a36ad]
---

# Completion times are overwritten with "now" on sync (recurrence of 5a36ad, 14-instance class)

## Why this is a recurrence, precisely

`5a36ad` fixed the "now" fallback for workout and exercise logs by introducing `_resolveCompletedAt`
(`lib/core/services/sync/sync_workout.dart:532`) and a regression test,
`test/sync/completed_at_preservation_test.dart`. The two schedule-completion paths this doc covers
(`_syncScheduleCompletions`, `_syncScheduledWorkouts`) were never migrated onto that resolver — they
are a DIFFERENT pair of call sites writing the SAME class of bug the earlier fix was supposed to close
everywhere. `docs/diagnoses/INDEX.md`'s own `5a36ad` line records "completed_at was overwritten..." as
one of several fixes in that batch, confirming the class name and scope.

## Why the general resolver order cannot be reused as-is (spec §1.6)

`_resolveCompletedAt`'s order is `created_at`, `completed_at`, `logged_at`, `updated_at_ms`,
`completed_at_ms`. Every schedule row carries `updated_at_ms` from its last `upsertScheduled` — often
just plan generation — so applying the general resolver here would return the plan-generation time
instead of omitting the field, which is a plausible-looking wrong answer rather than an honest gap.
The completion-time-specific order in `proposed_fix` above deliberately excludes `updated_at_ms`.

## Fix ownership in the plan

- The completion-time resolver order and its two call sites: Task 14 (coordinator).
- Template `created_at`: Task 16. Saved-meal `created_at`: Task 17. The five health-domain sites: Task
  18. Coach, onboarding-replay and notifications sites (the D2-discovered three): Task 19.
- Gate G2 (`scripts/check_sync_no_now_fallback.dart`): Task 2 (coordinator, Wave 0, lands before any
  domain fix per CLAUDE.md §4.11).

## Mutation evidence

Recorded at Task 31: each mutation, the grep that confirmed it applied, and the red count.
