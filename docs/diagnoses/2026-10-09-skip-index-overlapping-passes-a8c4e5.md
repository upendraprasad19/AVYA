---
bug_id: a8c4e5
date: 2026-10-09
batch: coach-history-correctness-sync-passes
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  Two overlapping sync passes over one domain each constructed a SyncSkipIndex from the stored map and each committed the WHOLE map, so the later commit erased the earlier pass's confirmations; those rows were re-pushed next pass (all 17 domains).
concept: sync_exercise_log_payload_hash_index
sot_registry_entry: sync_exercise_log_payload_hash_index
writers:
 - { file: lib/core/services/sync/sync_skip_index.dart, method: "SyncSkipIndex.commit (whole-map put of the construction-time snapshot)", line: 270 }
readers:
 - { file: lib/core/services/sync/sync_skip_index.dart, method_or_widget: "SyncSkipIndex.pushIfChanged (reads _stored)", line: 215 }
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
contract_test_path: test/sync/sync_skip_index_overlap_commit_test.dart
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
  SyncSkipIndex tracks this pass's own deltas (_confirmed fingerprints, _forgotten keys; skipped keys are in neither). commit re-reads the stored map, applies the deltas, prunes non-live keys and writes only when the result differs, with no await between the re-read and the put.
regression_test_planned: >-
  test/sync/sync_skip_index_overlap_commit_test.dart. Run: TZ=Asia/Kolkata flutter test test/sync/sync_skip_index_overlap_commit_test.dart
mutation_proof: >-
  Rule 21. Mutant: commit merges into the construction-time snapshot (Map.from(_stored)) instead of the fresh re-read: 2 of 4 tests RED (overlap, forgotten/concurrent-confirm); restored and green.
impact_analysis: >-
  Before: overlapping passes lost each other's skip confirmations and re-pushed unchanged rows. After: each pass contributes only its own changes.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "SyncSkipIndex tracks this pass's own deltas (_confirmed fingerprints, _forgotten keys; skipped keys are in neither). commit re-reads the stored map, applies the" }
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
recurrence: "recurrence of the writer/reader drift class (a snapshot-vs-store split); prior fix OI-204 / diagnose d3f8a6"
related_bugs: [e6a2d4, d3f8a6]
---

# skip index overlapping passes

## What was wrong

Two overlapping sync passes over one domain each constructed a SyncSkipIndex from the stored map and each committed the WHOLE map, so the later commit erased the earlier pass's confirmations; those rows were re-pushed next pass (all 17 domains).

## Fix

SyncSkipIndex tracks this pass's own deltas (_confirmed fingerprints, _forgotten keys; skipped keys are in neither). commit re-reads the stored map, applies the deltas, prunes non-live keys and writes only when the result differs, with no await between the re-read and the put.

## Verification

Plan: `docs/plans/coach-history-correctness-sync-passes.md` (v3, converged in 2 review rounds). Tests and mutation proof as in the front matter.
