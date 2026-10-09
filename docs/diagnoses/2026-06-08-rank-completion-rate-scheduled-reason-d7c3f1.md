---
bug_id: d7c3f1
date: 2026-06-08
batch: regression-prevention-wi1-2026-06-08
status: fixed
blast_radius: account
symptom: >
  The nightly evaluate-rank-promotions cron's completionRateOverWindow
  (_shared/rank_engine.ts) SELECTed scheduled_workouts.reason — a column that
  exists only in the client's local Hive model, never in the cloud table.
  PostgREST 42703 -> the function caught the error and returned 0.0, so the
  workout-completion-rate input to rank qualification was silently 0 for every
  user since 2026-05-01. Surfaced 2026-06-08 by the WI-1 server-seam extension of
  the schema-column gate.
concept: rank_monotonic_current_code
sot_registry_entry: rank_monotonic_current_code
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 309 }
readers:
  - { file: supabase/functions/_shared/rank_engine.ts, line: 132 }
  - { file: lib/features/train/repositories/workout_repository.dart, line: 347 }
hive_key_prefix: schedule_
hive_key_formula: "schedule_<istDateStr(date)>"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [id, user_id, template_id, scheduled_date, week_number, day_of_week, status, completed_at, created_at]
contract_test_path: scripts/check_schema_column_refs.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [rank_engine_completion_rate_query]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "rank_engine select of scheduled_workouts.reason (absent column)", absent: true }
proposed_fix: >
  The cloud scheduled_workouts table has no `reason` column — it only ever existed
  in the client's local Hive model. Pre-onboarding placeholder days are written
  with BOTH status='rest' and reason='pre_onboarding'
  (workout_schedule_read_service.dart:303-309), and both the client and server
  completion-rate calcs skip status==='rest' FIRST, so the reason check is
  redundant. Fix: drop `reason` from the server SELECT and remove the redundant
  filter line. Behavior-preserving (pre-onboarding still excluded via the rest
  check); completionRate now computes correctly instead of always 0.
  evaluate-rank-promotions redeployed to v9 (founder-authorized 2026-06-08).
regression_test_planned:
  - scripts/check_schema_column_refs.dart
touched_layers_checked:
  - { tier: 1, layer: edge_function_code, status: fixed_in_this_batch, evidence: "rank_engine.ts completionRateOverWindow now SELECTs 'status, scheduled_date' only; redundant reason filter removed" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "evaluate-rank-promotions redeployed v9 ACTIVE (HTTP 201); smoke HTTP 401 = module booted (cron-auth gate reached)" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "information_schema confirms scheduled_workouts has no reason column (id,user_id,template_id,scheduled_date,week_number,day_of_week,status,completed_at,created_at)" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "extended check_schema_column_refs.dart green post-fix (751 refs, 0 drift)" }
impact_analysis: >
  Account blast radius — one of several rank-qualification inputs (completion rate)
  was silently 0 for all users since 2026-05-01, potentially under-promoting on that
  dimension. Other inputs (streak, total workouts, weeks, deployments) were
  unaffected, so promotions continued. No data loss. Same client/cloud writer/reader
  drift class as b4e2a9 — server code mirrored client logic that reads a field
  present only in the client's local store.
related_bugs: [b4e2a9, e2a4f7, b9f4d2]
recurrence: >
  Cloud-contract wrong/missing-column class. The server mirrored the client's
  completionRateOverWindow (workout_repository.dart:347, comment in rank_engine.ts
  even says "matches the client's semantics") including a `reason` read that only
  ever resolved against the client's local Hive map — the cloud scheduled_workouts
  table was never given the column. Invisible to the lib/-only gate; caught by the
  WI-1 server-seam extension.
---

# rank completion-rate: SELECT of nonexistent scheduled_workouts.reason returns 0% for everyone

See frontmatter for the structured diagnosis. The `reason === 'pre_onboarding'`
skip is redundant because pre-onboarding days are written with `status='rest'`
([workout_schedule_read_service.dart:303-309](../../lib/core/services/workout_schedule_read_service.dart))
and the `status === 'rest'` check already excludes them on both client and server.
Dropping the `reason` SELECT + filter is therefore behavior-preserving and stops
the 42703. Found by the WI-1 server-seam extension of
`scripts/check_schema_column_refs.dart`.
