---
bug_id: 7ad0d2
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `streak_freezes_available` + `streak_freeze_used_dates` + `streak_freezes_last_refill` had TWO independent writers — `StreakFreezeNotifier._refillIfNewWeek` (weekly +1) and `WorkoutRepository._calculateStreak(consume:true)` (missed-day burn). Each path was a synchronous read-modify-write today, but contract drift risk was high — any future change introducing an `await` mid-flight would open a same-process race. The CROSS-DEVICE race is real now — a stale snapshot from device A could overwrite a freshly-consumed value on device B if `syncFreezes` arrived in the wrong order. (Hermes-R2 Round 2 #3 — "Refill ↔ consume race on streak freezes (lost update)", NEW CRITICAL.)
concept: streak_progress_service
sot_registry_entry: streak_progress
writers:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: commitRefill + commitConsume, line: 50 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: _calculateStreak (calls commitConsume), line: 157 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier._refillIfNewWeek (calls commitRefill), line: 270 }
hive_key_prefix: "userBox: progress.streak_freezes_*"
hive_key_formula: "userBox['progress']['streak_freezes_available', 'streak_freeze_used_dates', 'streak_freezes_last_refill']"
sync_methods: ["SyncService.syncFreezes()"]
restore_methods: []
cloud_table: user_progress
cloud_columns: [user_id, streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill, streak_progress_version]
contract_test_path: test/contracts/streak_progress_service_concurrency_test.dart
ist_handling: []
provider_invalidations: [streakFreezeProvider, streakProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: yes
forbidden_patterns_checked: ["direct_updateProgress_with_streak_freezes_available_outside_service"]
proposed_fix: Introduce `lib/core/services/streak_progress_service.dart` as the sole writer for `streak_freezes_*`. Two public methods — `commitRefill({maxFreezes, thisMondayStr})` and `commitConsume({freezesAvailableAfterConsume, usedDatesAfterConsume})` — each is a sync read-modify-write of the progress map plus fire-and-forget `unawaited(SyncService.syncFreezes())`. Route `home_provider._refillIfNewWeek` and `workout_repository._calculateStreak(consume:true)` through it. Add migration 056 with `update_streak_progress(p_user_id, p_expected_version, ...)` RPC + `streak_progress_version` BIGINT column on `user_progress` for cross-device optimistic-lock semantics (NULL return on version mismatch → caller retries).
regression_test_planned:
  - test/contracts/streak_progress_service_concurrency_test.dart (5 cases — sequential refill→consume; clamp at max; workout_repo + home_provider both route through the service; sole-writer source-grep)
---
# Audit C-15: streak freeze state had two independent writers

## Bug

Two paths read-modify-wrote the same Hive map:

1. `StreakFreezeNotifier._refillIfNewWeek` (home_provider.dart:270-300)
   — weekly +1 refill clamped at maxFreezes (1 free, 3 PRO).
2. `WorkoutRepository._calculateStreak(consume:true)` (workout_repository.dart:233)
   — walk-back consumes one freeze for each missed scheduled-workout
   day.

Each path was synchronous today (Dart's single-threaded event loop
makes each one atomic per tick). The bug class still applies:

- **Future drift risk.** Two independent writers + no enforced
  contract → easy for a future change to introduce an `await`
  mid-flight and reopen the same-process race.
- **Cross-device race today.** Device A consumes (`available=0` →
  syncFreezes at T1). Device B has a stale read (`available=1`), and
  its refill fires before T1 reaches B (`available=2` at T2). Cloud
  ends up at `2` — the consume is silently undone.

Hermes-R2 Round 2 flagged this as NEW CRITICAL.

## Cause

The Hive map was treated as shared mutable state with multiple
writers. No SoT discipline, no single owner. The cloud sync layer
(`syncFreezes` → `user_progress` upsert) has no optimistic-lock — it
projects whatever Hive currently holds.

## Fix

### Client side — single writer

New `lib/core/services/streak_progress_service.dart`:

```dart
class StreakProgressService {
  /// Refill — bumps available +1, clamps at maxFreezes, resets
  /// used_dates list, stamps last_refill.
  int commitRefill({required int maxFreezes,
                    required String thisMondayStr});

  /// Consume — persists the post-walk-back counts.
  int commitConsume({required int freezesAvailableAfterConsume,
                     required List<String> usedDatesAfterConsume});
}
```

Both are sync read-modify-write bodies that fire
`unawaited(SyncService.instance.syncFreezes())` at the end.

- `home_provider._refillIfNewWeek` now calls
  `StreakProgressService.instance.commitRefill(...)`.
- `workout_repository._calculateStreak(consume:true)` now calls
  `StreakProgressService.instance.commitConsume(...)`.

The audit's "synchronized mutex" requirement is structurally
satisfied by Dart's single-threaded event loop: each commit body
runs atomically per tick. If a future refactor introduces an `await`
inside `commitRefill` / `commitConsume`, the contract is documented
+ the regression test forces a re-think.

### Cloud side — optimistic lock

Migration 056 adds:

- `user_progress.streak_progress_version BIGINT NOT NULL DEFAULT 0`
- `update_streak_progress(p_user_id, p_expected_version,
  p_freezes_available, p_freeze_used_dates, p_freezes_last_refill)
  RETURNS BIGINT` SECURITY DEFINER + `SET search_path = public`.

The function takes `FOR UPDATE` on the user's row, compares the
version, and returns `NULL` on mismatch (caller re-reads + retries).
Insert-on-missing uses version=1.

GRANT EXECUTE to `authenticated`; REVOKE from `anon`.

Migration applied to prod 2026-05-11.

### Sole-writer source-grep guardrail

`test/contracts/streak_progress_service_concurrency_test.dart`
includes a `sole-writer contract — only StreakProgressService writes
streak_freezes_available` test. It scans every `lib/**/*.dart` for
`'streak_freezes_available':` map literals (typical write LHS),
allowlisting:

- `streak_progress_service.dart` (sole writer)
- `sync_service.dart` (restore + sync projection — reflects cloud
  state, not a state-mutation surface)
- `ai_coach_repository.dart` (AI snapshot read-then-emit)

Any new offender fails the test immediately.

## Regression tests

`test/contracts/streak_progress_service_concurrency_test.dart` — 5 cases:

1. Sequential refill → consume produces deterministic state.
2. Refill clamps at maxFreezes.
3. workout_repository routes through `commitConsume`.
4. home_provider routes through `commitRefill`.
5. Sole-writer source-grep (allowlist of 3 files; everything else
   must not write the key).

Plus updated:
- `test/contracts/streak_currentstreak_is_pure_test.dart` — pinned
  to the new commit path.
- `test/contracts/restore_completeness_writes_test.dart` — accepts
  the StreakProgressService delegation for `syncFreezes`.
- `test/home/streak_freeze_refill_ladder_test.dart` — accepts the
  ladder formula in either home_provider or the service.

Suite: 1569 pass / 0 fail / 2 skip.

## Related

- C-14 (7ad0d1 — CQRS-split `calculateCurrentStreak`; same family)
- 7ad035 (SECURITY DEFINER + search_path hardening — migration 056
  mirrors the pattern)
- CLAUDE.md §15 (Sync fan-out contract — single-writer discipline)
- Hermes-R2 Round 2 #3 (audit source — "Refill ↔ consume race on
  streak freezes (lost update) — NEW CRITICAL")
