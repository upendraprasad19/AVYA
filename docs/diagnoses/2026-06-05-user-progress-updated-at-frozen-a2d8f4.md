---
bug_id: a2d8f4
date: 2026-06-05
batch: cloud-sync-fixes
status: fixed
blast_radius: feature
symptom: >
  user_progress.updated_at was frozen at the row's created_at (account creation)
  even though the row's data advanced (last_workout_date = today, total_workouts
  current). Surfaced in the live audit of the founder's account (d7a67a37):
  updated_at = 2026-05-01 while the row was current.
concept: user_progress_updated_at
sot_registry_entry: not_applicable
writers: >
  SyncService._syncUserProgress (lib/core/services/sync/sync_profile.dart:160)
  upserts user_progress but OMITTED updated_at. There is no DB trigger on the
  table, so the column never advanced.
readers: >
  No client reader currently depends on user_progress.updated_at; the
  evaluate-rank-promotions Edge Function SELECTs the table WITHOUT updated_at.
  The risk is future "changed-since" / incremental-sync / conflict logic keyed
  on the (frozen) timestamp.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: syncProfileNow
restore_methods: not_applicable
cloud_table: user_progress
cloud_columns: updated_at
contract_test_path: test/contracts/cloud_sync_fixes_2026_06_05_test.dart
ist_handling: not_applicable (updated_at is a UTC modification timestamp, not an IST date-key)
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "_syncUserProgress upsert omitting updated_at — it now stamps DateTime.now().toUtc().toIso8601String() on every push; pinned by cloud_sync_fixes_2026_06_05_test.dart."
proposed_fix: >
  Add 'updated_at': DateTime.now().toUtc().toIso8601String() to the
  _syncUserProgress upsert payload so the column reflects each write.
regression_test_planned: >
  test/contracts/cloud_sync_fixes_2026_06_05_test.dart asserts the
  _syncUserProgress region includes updated_at.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "_syncUserProgress upsert now stamps updated_at; flutter analyze clean" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live audit confirmed the frozen value (updated_at = created_at = 2026-05-01) that the fix corrects on the next push" }
impact_analysis: >
  Feature blast radius — data was correct (values current); only the modification
  timestamp was wrong, so no current reader broke. The fix prevents a latent
  incremental-sync/conflict bug. Low risk additive change.
---

# user_progress.updated_at frozen at created_at

## What happened
`user_progress.updated_at` stayed at the row's creation time despite the row's
data advancing daily.

## Root cause
`_syncUserProgress` upserts the row without `updated_at`, and there is no DB
trigger to maintain it.

## Fix
Stamp `updated_at` = `DateTime.now().toUtc().toIso8601String()` in the upsert.

## Verification
`cloud_sync_fixes_2026_06_05_test.dart` asserts the upsert includes updated_at;
analyze clean.

## See also
- `lib/core/services/sync/sync_profile.dart` `_syncUserProgress`
