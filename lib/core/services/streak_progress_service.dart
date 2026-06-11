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

import 'error_telemetry.dart';
import 'sync_service.dart';
import 'subscription_service.dart';
import '../utils/ist_date.dart';
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
    // B1 telemetry — diagnostic event so we can post-mortem from
    // client_errors whether refill actually landed and what the count
    // bumped from/to. LOW-priority op_type (rate-limited).
    unawaited(ErrorTelemetry.logEvent(
      'streak_freeze_refill_done',
      message: 'before=$currentAvailable after=$newAvailable '
          'max=$maxFreezes monday=$thisMondayStr',
    ));
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
    // B2 telemetry — caller passes the pre-consume freeze count + the
    // list of dates the walk-back newly flagged + the walk start date.
    // Optional with safe defaults so existing callers keep compiling;
    // the canonical caller (WorkoutRepository._calculateStreak) passes
    // all three.
    int? freezesAvailableBeforeConsume,
    List<String>? newlyConsumedDates,
    String? walkStartDate,
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
        'usedDates=${usedDatesAfterConsume.length} '
        'newly=${newlyConsumedDates?.join(",") ?? "?"}');
    // B2 telemetry — record which date(s) the walk-back penalised. If
    // founder reports a spurious banner, this telemetry tells us
    // exactly which Hive row the walk-back disagreed with.
    unawaited(ErrorTelemetry.logEvent(
      'streak_freeze_consume_done',
      message: 'before=${freezesAvailableBeforeConsume ?? -1} '
          'after=$freezesAvailableAfterConsume '
          'newly=${newlyConsumedDates?.join(",") ?? ""} '
          'walk_start=${walkStartDate ?? ""}',
    ));
    return freezesAvailableAfterConsume;
  }

  /// OI-38 (audit-2026-05-17 Hermes C3) — refill orchestrator. Pre-fix the
  /// equivalent logic lived inside `StreakFreezeNotifier.build()` —
  /// write-on-read Riverpod anti-pattern. Now lives here; callers are
  /// `DayRolloverObserver._doRolloverWithRef` (every rollover) +
  /// splash post-restore (first launch). Idempotent — same Monday twice
  /// is a no-op. Returns the new available count, or null if no refill
  /// happened (already done this week).
  int? refillIfNewWeek() {
    final thisMonday = mondayOfIst(nowWall()); // seam-aware (dev / year-sim)
    final progress = UserRepository.instance.getProgress() ?? {};
    final lastRefill = progress['streak_freezes_last_refill'] as String?;
    final y = thisMonday.year.toString().padLeft(4, '0');
    final m = thisMonday.month.toString().padLeft(2, '0');
    final d = thisMonday.day.toString().padLeft(2, '0');
    final thisMondayStr = '$y-$m-$d';

    final bool willRefill =
        lastRefill == null || lastRefill.compareTo(thisMondayStr) < 0;
    // B1 telemetry — fire on every refill check so we can see from
    // client_errors whether refill was attempted, what the gate saw,
    // and which side won.
    unawaited(ErrorTelemetry.logEvent(
      'streak_freeze_refill_check',
      message: 'monday=$thisMondayStr lastRefill=${lastRefill ?? "null"} '
          'willRefill=$willRefill',
    ));

    if (!willRefill) {
      return null;
    }

    final isPro = SubscriptionService.instance.isPro();
    final maxFreezes = isPro ? 3 : 1;
    return commitRefill(maxFreezes: maxFreezes, thisMondayStr: thisMondayStr);
  }

  /// Pure, refill-aware merge of local vs cloud streak-freeze state for the
  /// restore path (`_restoreFreezes`). `streak_freeze_used_dates` is PER-WEEK
  /// (cleared on refill — see [commitRefill]), so the merge keys on last_refill:
  ///   - SAME week (equal last_refill): UNION used_dates — never lose a consume
  ///     written locally during the background-restore window (or on another
  ///     device) — and take the LOWER available (never refund a freeze).
  ///   - cloud refill STRICTLY newer: cloud is the current-week truth.
  ///   - local refill strictly newer (or cloud last_refill null): keep local;
  ///     the caller schedules a syncFreezes to push it up.
  /// Pre-fix `_restoreFreezes` lumped equal-refill into cloud-wins AND
  /// unconditionally overwrote used_dates → a same-week local consume was wiped
  /// and the freeze refunded (spurious streak break). The slow-boot flip
  /// (ADR-0014) opened the window by landing /home before restore Step C.
  /// closes-diagnose: a8f3d1.
  static FreezeMergeResult mergeFreezeProgress({
    required int localAvailable,
    required List<String> localUsed,
    required String? localLastRefill,
    required int cloudAvailable,
    required List<String> cloudUsed,
    required String? cloudLastRefill,
  }) {
    int clamp3(int v) => v.clamp(0, 3);
    List<String> sortedUnion(Iterable<String> a, Iterable<String> b) =>
        (<String>{...a, ...b}.toList())..sort();

    // Same week on both sides — the bg-restore-window / cross-device case.
    if (localLastRefill != null &&
        cloudLastRefill != null &&
        localLastRefill == cloudLastRefill) {
      final avail =
          localAvailable < cloudAvailable ? localAvailable : cloudAvailable;
      return FreezeMergeResult(
        available: clamp3(avail),
        usedDates: sortedUnion(localUsed, cloudUsed),
        lastRefill: localLastRefill,
        scheduleSyncUp: false,
      );
    }

    final bool cloudWins = localLastRefill == null ||
        (cloudLastRefill != null &&
            cloudLastRefill.compareTo(localLastRefill) > 0);
    if (cloudWins) {
      return FreezeMergeResult(
        available: clamp3(cloudAvailable),
        usedDates: cloudUsed.toList()..sort(),
        lastRefill: cloudLastRefill ?? localLastRefill,
        scheduleSyncUp: false,
      );
    }
    // Local refill strictly newer — keep local entirely; push it up to cloud.
    return FreezeMergeResult(
      available: clamp3(localAvailable),
      usedDates: localUsed.toList()..sort(),
      lastRefill: localLastRefill,
      scheduleSyncUp: true,
    );
  }
}

/// Result of [StreakProgressService.mergeFreezeProgress] (restore freeze merge).
class FreezeMergeResult {
  final int available;
  final List<String> usedDates;
  final String? lastRefill;
  final bool scheduleSyncUp;
  const FreezeMergeResult({
    required this.available,
    required this.usedDates,
    required this.lastRefill,
    required this.scheduleSyncUp,
  });
}
