---
bug_id: b3d8f9
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: PRO user who burns all 3 streak freezes in week 1 gets back to 3 the following Monday — full reset, no incentive to save freezes.
concept: streak_freezes
sot_registry_entry: streak_freezes
writers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier._refillIfNewWeek, line: 247 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: calculateCurrentStreak (consumes freeze), line: 169 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: syncFreezes, line: 4117 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: streakFreezeProvider, line: 277 }
  - { file: lib/features/profile/widgets/rank_service_record_sheet.dart, method_or_widget: RankServiceRecordSheet, line: 204 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getStreakFreezesAvailable, line: 1533 }
hive_key_prefix: null
hive_key_formula: "userBox['user_progress']['streak_freezes_available']"
sync_methods:
  - SyncService.syncFreezes
restore_methods:
  - SyncService._restoreFreezes
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
  - streak_freezes_used_dates
  - streak_freezes_last_refill
contract_test_path: test/home/streak_freeze_refill_ladder_test.dart
ist_handling:
  - { file: lib/features/home/providers/home_provider.dart, line: 253, fn: _refillIfNewWeek }
provider_invalidations:
  - streakFreezeProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "true (key migrated via UserConfigMigrator v2; lives in userBox/user_progress)"
forbidden_patterns_checked:
  - { pattern: "'streak_freezes_available': maxFreezes", absent: true }
proposed_fix: |
  Replace reset-to-max with a ladder. Read currentAvailable from progress
  (default 0 for fresh users), compute newAvailable = (currentAvailable +
  1).clamp(0, maxFreezes), write that. PRO user goes 0 → 1 → 2 → 3 over
  three Mondays. Free user goes 0 → 1, capped. Idempotent guard
  (lastRefill compare) unchanged.
regression_test_planned:
  - test/home/streak_freeze_refill_ladder_test.dart
---

# Bug D.1 — Streak-freeze refill ladder

## Symptom

PRO user who burned all 3 streak freezes in week 1 was rewarded with a full reset to 3 freezes the following Monday — no incentive to save them. Founder direction (2026-05-10): freezes should ladder up over time so they feel earned.

## Root cause

`_refillIfNewWeek` (lib/features/home/providers/home_provider.dart:247–274) wrote `'streak_freezes_available': maxFreezes` on every Monday transition. The `maxFreezes` constant resolved to `1` (free) or `3` (PRO), ignoring whatever count the user had after consuming freezes during the prior week.

## Fix

Read `currentAvailable` from `UserRepository.instance.getProgress()` (default 0 for fresh users with no progress row), compute the new value as `(currentAvailable + 1).clamp(0, maxFreezes)`, write that. Free max remains 1 (no behavioral change for free since there's only one slot). PRO max remains 3 but a PRO user who burned all 3 ladders 1 → 2 → 3 over three Mondays.

Idempotent guard (lastRefill string compare) preserved unchanged. `streak_freeze_used_dates` reset to `[]` preserved unchanged. `unawaited(SyncService.instance.syncFreezes())` push preserved unchanged.

## Verification

- Source-grep contract test pins:
  - `(currentAvailable + 1).clamp(0, maxFreezes)` formula present
  - `(progress['streak_freezes_available'] as int?) ?? 0` reader present
  - `'streak_freezes_available': maxFreezes` reset-to-max pattern absent
- Pure-logic mirror `applyLadderRefill(currentAvailable, isPro)` covers the 7 boundary scenarios (free 0/1, PRO 0/1/2/3/4, mid-ladder).

## Related

- CLAUDE.md §15 "Restore-completeness sync" — `syncFreezes` + `_restoreFreezes` survive reinstall
- docs/sot_registry.yaml — `streak_freezes` writers and readers
- Test #11 Theme A added cloud columns; Test #14 corrects refill semantics
