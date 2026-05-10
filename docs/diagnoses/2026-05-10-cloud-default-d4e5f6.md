---
bug_id: d4e5f6
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: Cloud user_progress default for streak_freezes_available was 2 — neither matched free baseline (1) nor PRO max (3). Fresh accounts got an inconsistent middle-ground value before the client's first refill ladders them.
concept: streak_freezes
sot_registry_entry: streak_freezes
writers:
  - { file: supabase/migrations/050_streak_freezes_default_one.sql, method_or_widget: ALTER COLUMN DEFAULT, line: 14 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreFreezes default fallback, line: 4117 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: syncFreezes default fallback, line: 4228 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier.build, line: 244 }
hive_key_prefix: null
hive_key_formula: "userBox['user_progress']['streak_freezes_available']"
sync_methods:
  - SyncService.syncFreezes
restore_methods:
  - SyncService._restoreFreezes
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
contract_test_path: "n/a — migration + 2-line constants"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  Migration 050 ALTER TABLE user_progress SET DEFAULT 1 (was 2).
  Update sync_service.dart:4117 + 4228 fallbacks from 2 -> 1.
  Free baseline matches free-tier client max; PRO clients overwrite to 3
  on first refill via _refillIfNewWeek ladder (Bug D.1).
regression_test_planned: []
---

# Bug D.2 — Cloud default for streak_freezes_available

## Symptom

Migration 048 set `user_progress.streak_freezes_available` default to 2 — a conservative middle-ground that matched neither the free max (1) nor the PRO max (3). A fresh account got 2 freezes before the client's first refill ladder ran. Inconsistent UX: free users saw 2/1 (over-cap until next ladder) and PRO users saw 2/3 (one freeze "missing" until next refill).

## Root cause

Migration 048 was written before the ladder semantics decision. Default was a guess. Founder direction 2026-05-10: free baseline is 1; PRO clients overwrite via `_refillIfNewWeek` (Bug D.1) within seconds of first launch.

## Fix

1. Migration 050 ALTERs the column default to 1. Existing rows untouched (ALTER COLUMN SET DEFAULT only affects new INSERTs).
2. `sync_service.dart:4117` (`syncFreezes`) and `:4228` (`_restoreFreezes`) fallbacks bumped from 2 → 1 so a missing field on the cloud row doesn't reintroduce the 2-default in clients reading post-migration.

## Verification

- Migration applied via Supabase MCP `apply_migration`.
- 2 line edits in sync_service.dart land in the same B.1+B.2+B.3 commit window since both files are touched in this batch.

## Related

- Migration 048 (Test #11 Theme A) — original column add
- Bug D.1 (b3d8f9) — ladder refill semantics that this default supports
- Bug D.3 (c5d2a8) — pill UI exposing the new ladder
