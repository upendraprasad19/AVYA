---
bug_id: f3d2a7
date: 2026-10-09
batch: coach-history-correctness-sync-passes
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  A fresh install or restore wrote every exercise log from the cloud and recorded no push fingerprint, so the very next push pass re-upserted every restored log (summary and per-set rows) back to the cloud.
concept: sync_exercise_log_payload_hash_index
sot_registry_entry: sync_exercise_log_payload_hash_index
writers:
 - { file: lib/core/services/sync/sync_workout.dart, method: "_restoreExerciseLogs (writes the row, records no fingerprint)", line: 1166 }
readers:
 - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncExerciseLogs (skip decision via SyncSkipIndex)", line: 400 }
hive_key_prefix: sync_exlog_payload_hash_index
hive_key_formula: "SyncSkipDomain.exlog.indexKey (unchanged)"
sync_methods:
  - _syncExerciseLogs
restore_methods:
  - _restoreExerciseLogs
cloud_table: workout_log_exercises
cloud_columns:
  - workout_log_id
  - exercise_id
  - set_number
  - completed_at
contract_test_path: test/sync/exlog_restore_fingerprint_l1a3_behavioral_test.dart
ist_handling:
  - "no date logic added; the push bundle is the unchanged extraction of the existing day/completed_at resolution"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "recordConfirmedAll checks ownerChangedSince(userId) before it writes; commit keeps its owner checks"
forbidden_patterns_checked:
  - { pattern: "a whole-map overwrite of a sync skip index from the construction-time snapshot", absent: true }
proposed_fix: >-
  The push bundle build is extracted verbatim into _buildExlogPushBundle(userId, key, log). The restore, after its local-wins put RAN, fingerprints the bundle of the row it wrote and records all of them in one SyncSkipIndex.recordConfirmedAll (owner check first; skipped under the exlog hash-skip kill switch; never for a local row that won).
regression_test_planned: >-
  test/sync/exlog_restore_fingerprint_l1a3_behavioral_test.dart. Run: TZ=Asia/Kolkata flutter test test/sync/exlog_restore_fingerprint_l1a3_behavioral_test.dart
mutation_proof: >-
  Rule 21. Four mutants on the restore: recording dropped, recording even when a local row won, kill switch ignored: each RED in its own test (3 of 3, plus a 4th: the restore-dedupe switch ignored, RED); source restored after every run.
impact_analysis: >-
  Before: every restored exercise log was pushed straight back once. After: the push pass skips it.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "The push bundle build is extracted verbatim into _buildExlogPushBundle(userId, key, log). The restore, after its local-wins put RAN, fingerprints the bundle of " }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "the per-domain skip index in the per-user workoutBox: written by merge-of-deltas / recordConfirmedAll" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "client-side skip index only; no cloud data read or written beyond the existing upserts" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function code" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "unchanged" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "behavioral tests drive the real SyncService against SyncStubServer; no live call" }
recurrence: "recurrence of e6a2d4 restore-completeness class; the push side was already fingerprinted (OI-204)"
related_bugs: [e6a2d4, a8c4e5]
---

# restored exlog pushed back

## What was wrong

A fresh install or restore wrote every exercise log from the cloud and recorded no push fingerprint, so the very next push pass re-upserted every restored log (summary and per-set rows) back to the cloud.

## Fix

The push bundle build is extracted verbatim into _buildExlogPushBundle(userId, key, log). The restore, after its local-wins put RAN, fingerprints the bundle of the row it wrote and records all of them in one SyncSkipIndex.recordConfirmedAll (owner check first; skipped under the exlog hash-skip kill switch; never for a local row that won).

## Verification

Plan: `docs/plans/coach-history-correctness-sync-passes.md` (v3, converged in 2 review rounds). Tests and mutation proof as in the front matter.
