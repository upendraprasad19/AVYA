// C-15 (audit-2026-05-11) — single-writer service for the
// `streak_freezes_*` fields in `user_progress`.
//
// Pre-fix, two paths mutated the same Hive map without any single
// owner:
//
//   1. `StreakFreezeNotifier._refillIfNewWeek` — weekly +1 refill.
//   2. `WorkoutRepository._calculateStreak(consume: true)` — consume
//      one freeze for a missed day.
//
// Each path was a synchronous read-modify-write of the same
// `streak_freezes_*` keys (Dart's single-threaded event loop makes
// each one atomic on its own tick), but with TWO independent writers
// the contract drift risk was high — easy for a future change to
// introduce an `await` mid-flight and reopen the race. The
// CROSS-DEVICE race is real today: stale snapshots from device A can
// overwrite freshly-consumed values on device B if `syncFreezes`
// arrives in the wrong order.
//
// This service is the sole writer. Both refill and consume route
// through `commitRefill` / `commitConsume`. The cross-device safety
// net is migration 056's `update_streak_progress(p_user_id,
// p_expected_version, ...)` RPC with optimistic-lock semantics.
//
// The methods are sync because the underlying Hive write is sync;
// `unawaited(SyncService.instance.syncFreezes())` keeps the cloud
// fan-out fire-and-forget (matches the existing CLAUDE.md §15
// fire-and-forget pattern).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_service.dart';
import '../../shared/repositories/user_repository.dart';

/// Sole writer for `user_progress.streak_freezes_available`,
/// `streak_freeze_used_dates`, `streak_freezes_last_refill`.
///
/// Read access via `UserRepository.instance.getProgress()` is fine —
/// the contract is only that WRITES go through this service.
class StreakProgressService {
  StreakProgressService._();
  static final StreakProgressService instance = StreakProgressService._();

  /// Weekly refill (called from `StreakFreezeNotifier._refillIfNewWeek`).
  ///
  /// Reads the current progress map, bumps `streak_freezes_available`
  /// by +1 (clamped at [maxFreezes]), resets the weekly
  /// `streak_freeze_used_dates` list, stamps
  /// `streak_freezes_last_refill = thisMondayStr`. Idempotent —
  /// callers must pre-check `lastRefill < thisMondayStr` before
  /// invoking.
  ///
  /// Returns the new `streak_freezes_available` value.
  int commitRefill({
    required int maxFreezes,
    required String thisMondayStr,
  }) {
    final progress = UserRepository.instance.getProgress() ?? {};
    final currentAvailable =
        (progress['streak_freezes_available'] as int?) ?? 0;
    final newAvailable = (currentAvailable + 1).clamp(0, maxFreezes);

    UserRepository.instance.updateProgress({
      'streak_freezes_available': newAvailable,
      'streak_freeze_used_dates': <String>[],
      'streak_freezes_last_refill': thisMondayStr,
    });
    unawaited(SyncService.instance.syncFreezes());
    debugPrint(
        '[StreakProgressService] refill: $currentAvailable → $newAvailable '
        '(max=$maxFreezes, monday=$thisMondayStr)');
    return newAvailable;
  }

  /// Commit freezes-consumed state. Called from
  /// `WorkoutRepository._calculateStreak(consume: true)` after the
  /// walk-back has identified which dates need to consume.
  ///
  /// Persists the new `streak_freezes_available` + appended
  /// `streak_freeze_used_dates` + the legacy
  /// `streak_freeze_just_used` / `streak_freeze_remaining_after_use`
  /// flags consumed by the streak badge UI.
  ///
  /// Returns the new `streak_freezes_available` after consumption
  /// (same as the [freezesAvailableAfterConsume] argument; returned
  /// for caller symmetry with `commitRefill`).
  int commitConsume({
    required int freezesAvailableAfterConsume,
    required List<String> usedDatesAfterConsume,
  }) {
    UserRepository.instance.updateProgress({
      'streak_freezes_available': freezesAvailableAfterConsume,
      'streak_freeze_used_dates': usedDatesAfterConsume,
      'streak_freeze_just_used': true,
      'streak_freeze_remaining_after_use': freezesAvailableAfterConsume,
    });
    unawaited(SyncService.instance.syncFreezes());
    debugPrint(
        '[StreakProgressService] consume: available=$freezesAvailableAfterConsume '
        'usedDates=${usedDatesAfterConsume.length}');
    return freezesAvailableAfterConsume;
  }
}
