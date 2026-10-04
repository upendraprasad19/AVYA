---
bug_id: 7ad0d1
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `WorkoutRepository.calculateCurrentStreak()` was documented as a "read" but had side effects — consumed streak freezes for missed days and persisted the new state to Hive + cloud on every invocation. Four read-only call sites (RankService cron / splash, streakProvider for home pill, rank_service_record_sheet display, AI snapshot) ran this method routinely. A user with 1 freeze available and 1 missed day would have that freeze burned by the first cron eval, but if the cron fired 3× in a window, race conditions could burn 3 freezes for the same day. UI rebuilds, hot reload, dev tools — every trigger of those surfaces silently mutated freeze state.
concept: streak_cqrs_split
sot_registry_entry: streak_calculation
writers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: consumeMissedDayIfFreezeAvailable + _calculateStreak(consume:true), line: 167 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: currentStreak + _calculateStreak(consume:false), line: 157 }
  - { file: lib/core/services/rank_service.dart, method_or_widget: evaluateAndPromote (READ), line: 333 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakNotifier.build (READ), line: 230 }
  - { file: lib/features/profile/widgets/rank_service_record_sheet.dart, method_or_widget: _statusTilesRow (READ), line: 201 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: completeWorkout (CONSUME — the one legitimate mutator), line: 1418 }
hive_key_prefix: "userBox: progress.streak_freezes_*"
hive_key_formula: "userBox['progress']['streak_freezes_available', 'streak_freeze_used_dates']"
sync_methods: ["SyncService.syncFreezes()"]
restore_methods: []
cloud_table: user_progress
cloud_columns: [user_id, streak_freezes_available, streak_freeze_used_dates, streak_freeze_last_refill]
contract_test_path: test/contracts/streak_currentstreak_is_pure_test.dart
ist_handling: []
provider_invalidations: [streakProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["read_only_streak_call_triggers_freeze_consume"]
proposed_fix: CQRS-split `calculateCurrentStreak` into pure `currentStreak()` and explicit `consumeMissedDayIfFreezeAvailable()`. Internal `_calculateStreak({required bool consume})` runs the same walk-back; the persist + sync block is gated on `consume: true`. Keep `calculateCurrentStreak()` as a thin @Deprecated wrapper around the consume variant for any straggler callers. Switch the 3 read-only sites to `currentStreak()` and leave `train_provider.completeWorkout` on `consumeMissedDayIfFreezeAvailable()` (canonical mutation surface).
regression_test_planned:
  - test/contracts/streak_currentstreak_is_pure_test.dart (2 cases — pure read 3× preserves freeze state; explicit consume DOES persist)
---
# Audit C-14: streak calculation was read-with-side-effects

## Bug

`WorkoutRepository.calculateCurrentStreak()` did all of:

- Walk schedule backwards from today (READ).
- For each missed-but-frozen-covered day, decrement
  `streak_freezes_available` in memory (RECOVERY — required for the
  count to be correct).
- Add the date to `streak_freeze_used_dates` in memory (BOOKKEEPING).
- **Persist the updated freeze state to Hive** (WRITE).
- **`unawaited(SyncService.instance.syncFreezes())` (CLOUD WRITE)**.

The last two are the bug. They fire on every call. Four code paths
called this routinely:

1. `RankService.evaluateAndPromote` — splash + every workout
   completion + nightly cron.
2. `home_provider.streakProvider` build — every home screen render
   + every Riverpod invalidation.
3. `rank_service_record_sheet._statusTilesRow` — bottom sheet display.
4. `train_provider.completeWorkout` — the only legitimately
   mutating site.

A user with 1 freeze available and 1 missed day saw it burn on the
FIRST evaluation that hit either path. Three rapid Riverpod
invalidations on home could in principle burn three freezes for the
same day (race-prone but not blocked by a mutex). The bug class
APK Test #15 / C-15 (parallel refill ↔ consume race) is the same
family — both stem from no clear CQRS boundary.

## Cause

CQRS discipline wasn't applied. The freeze-consumption recovery
logic was in the same method body as the read, so it shipped with
side effects baked into every reader.

## Fix

```dart
/// Pure read — does NOT mutate state.
int currentStreak() => _calculateStreak(consume: false);

/// Explicit mutating variant — same walk, persists freeze
/// consumption to Hive + cloud.
int consumeMissedDayIfFreezeAvailable() =>
    _calculateStreak(consume: true);

/// Legacy entry — thin wrapper for back-compat. @Deprecated.
int calculateCurrentStreak() => consumeMissedDayIfFreezeAvailable();

int _calculateStreak({required bool consume}) {
  // ... existing walk-back logic, simulates freeze use locally ...
  if (consume && freezeConsumedThisCalc) {
    UserRepository.instance.updateProgress({...});
    unawaited(SyncService.instance.syncFreezes());
  }
  return streak;
}
```

Call sites switched:

- `RankService.evaluateAndPromote` → `currentStreak()` (READ).
- `home_provider.StreakNotifier.build` → `currentStreak()` (READ).
- `rank_service_record_sheet._statusTilesRow` → `currentStreak()` (READ).
- `train_provider.completeWorkout` → `consumeMissedDayIfFreezeAvailable()`
  (explicit CONSUME — canonical mutation surface).

## Regression tests

`test/contracts/streak_currentstreak_is_pure_test.dart` — 2 cases:

1. **Pure read 3× preserves freeze state.** Seed user with 1
   freeze + 1 missed scheduled day. Call `currentStreak()` 3 times.
   All three return the same count (1, derived from local
   simulation), AND `progress['streak_freezes_available']` is still
   1 after, AND `streak_freeze_used_dates` is still empty.
2. **Explicit consume DOES persist.** Same setup, but call
   `consumeMissedDayIfFreezeAvailable()`. Returns 1, AND
   `freezes_available == 0` AND `used_dates` contains the missed
   day's ISO string.

Plus updated `test/widgets/home_streak_pill_source_test.dart` to
accept either `currentStreak()` or the legacy
`calculateCurrentStreak` literal (deprecation shim).

Suite: 1564 pass / 0 fail / 2 skip.

## Related

- C-15 (parallel refill ↔ consume race on streak freezes — same
  family; resolved in 7ad0d2 sibling fix via StreakProgressService).
- CLAUDE.md "Hive field-name contract" — single-reader / single-writer
  discipline.
- feedback_source_of_truth_audit.md — SoT alignment across home pill
  + rank chip.
