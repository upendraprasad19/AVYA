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
  /// by +1 (clamped at [maxFreezes]), PRUNES the PERMANENT
  /// `streak_freeze_used_dates` ledger to the 365-day walk-back horizon
  /// (D1, f9d2e7 — it no longer CLEARS the ledger weekly; a day protected
  /// by a spent freeze stays protected forever), stamps
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

    // D1 (f9d2e7): the used-dates ledger is PERMANENT. Pre-fix this CLEARED
    // it to [] every week, so after a Monday refill a prior-week frozen day
    // dropped out of the ledger → the streak walk-back (which treats
    // usedDates.contains(day) as permanent protection, 5e8a1c) either
    // re-consumed that day (double-charge) or broke the streak. Now we only
    // PRUNE entries older than the 365-day walk-back horizon to bound growth.
    final prunedUsed = prunePastHorizon(
      (progress['streak_freeze_used_dates'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );

    UserRepository.instance.updateProgress({
      'streak_freezes_available': newAvailable,
      'streak_freeze_used_dates': prunedUsed,
      'streak_freezes_last_refill': thisMondayStr,
    });
    unawaited(SyncService.instance.syncFreezes());
    debugPrint(
        '[StreakProgressService] refill: $currentAvailable → $newAvailable '
        '(max=$maxFreezes, monday=$thisMondayStr, '
        'ledger=${prunedUsed.length} dates)');
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

  /// Prunes streak-freeze used-dates older than the 365-day streak walk-back
  /// horizon so the PERMANENT ledger (D1, f9d2e7) cannot grow without bound.
  /// Date strings are IST 'YYYY-MM-DD' (lexically sortable, produced by
  /// `istDateStr` == `formatDateKey`). Returns a sorted copy. Clock-aware
  /// (`nowWall()`) so it honors the dev/year-sim time seam.
  static List<String> prunePastHorizon(List<String> usedDates) {
    final cutoff = istDateStr(nowWall().subtract(const Duration(days: 365)));
    return usedDates.where((d) => d.compareTo(cutoff) >= 0).toList()..sort();
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

  // ── First-PRO grant / lapse-reset (Phase 2 Unit C) ─────────

  /// Grants 3 streak freezes on the FIRST-EVER PRO upgrade.
  ///
  /// Idempotent: if `streak_freezes_first_pro_grant_done == true`
  /// the method is a no-op, so boot-refresh of an already-PRO
  /// user (which calls `writeSubscriptionState(isPro:true)` every
  /// launch) NEVER re-triggers the grant. The migration-095 backfill
  /// pre-sets the flag for every user who was ever PRO, so the
  /// phantom-grant-on-reinstall path is also blocked.
  ///
  /// Guard: caller must verify `HiveUserSession.currentOwnerFullId
  /// != null` before calling — ensures the session box (and therefore
  /// the progress map) is open and owned by the correct user. The
  /// flag itself is the final safety net.
  void grantFirstProFreezes() {
    final progress = UserRepository.instance.getProgress() ?? {};
    final alreadyGranted =
        (progress['streak_freezes_first_pro_grant_done'] as bool?) ?? false;
    if (alreadyGranted) return; // idempotent guard

    final currentAvailable =
        (progress['streak_freezes_available'] as int?) ?? 0;
    final newAvailable = currentAvailable < 3 ? 3 : currentAvailable;

    UserRepository.instance.updateProgress({
      'streak_freezes_available': newAvailable,
      'streak_freezes_first_pro_grant_done': true,
    });
    unawaited(SyncService.instance.syncFreezes());
    debugPrint('[StreakProgressService] grantFirstProFreezes: '
        '$currentAvailable → $newAvailable (flag set)');
    unawaited(ErrorTelemetry.logEvent(
      'streak_freeze_first_pro_grant',
      message: 'before=$currentAvailable after=$newAvailable',
    ));
  }

  /// Resets `streak_freezes_available` to the free-tier cap (1) on
  /// subscription lapse. Called from `_downgradeLocally` in
  /// `SubscriptionService`.
  ///
  /// Contract: ONLY clamps `available` — does NOT touch the
  /// `streak_freezes_first_pro_grant_done` flag. Preserving the flag
  /// ensures a re-purchase after lapse does NOT re-grant 3 freezes
  /// (the weekly refill at the start of the new PRO week is the
  /// correct restore path).
  void resetToFreeCapOnLapse() {
    final progress = UserRepository.instance.getProgress() ?? {};
    final currentAvailable =
        (progress['streak_freezes_available'] as int?) ?? 1;
    final cappedAvailable = currentAvailable > 1 ? 1 : currentAvailable;
    if (cappedAvailable != currentAvailable) {
      UserRepository.instance.updateProgress({
        'streak_freezes_available': cappedAvailable,
        // flag intentionally NOT written — preserve grant history so a
        // re-purchase after lapse does NOT re-grant 3.
      });
      debugPrint('[StreakProgressService] resetToFreeCapOnLapse: '
          '$currentAvailable → $cappedAvailable');
      unawaited(ErrorTelemetry.logEvent(
        'streak_freeze_lapse_reset',
        message: 'before=$currentAvailable after=$cappedAvailable',
      ));
    }
    // B-pass Finding 4 (f9d2e7): ALWAYS push on lapse — even when local is
    // already at/below the free cap — so a stale cloud row (a higher available
    // from an unsynced mid-week PRO state) converges to the free cap and a
    // later reinstall's restore cannot re-inflate a free user back above 1.
    unawaited(SyncService.instance.syncFreezes());
  }

  /// Pure merge of local vs cloud streak-freeze state for the restore path
  /// (`_restoreFreezes`). D1 (f9d2e7): `streak_freeze_used_dates` is now a
  /// PERMANENT ledger (commitRefill prunes >365d, never clears), so used_dates
  /// is ALWAYS the UNION of both sides — neither a stale cloud snapshot nor a
  /// fresh local consume may ever drop a historically-frozen day. The weekly
  /// BUDGET (`available` / `last_refill`) still keys on last_refill:
  ///   - SAME week (equal last_refill): take the LOWER available (never refund).
  ///   - cloud refill STRICTLY newer: cloud available is the current-week truth.
  ///   - local refill strictly newer (or cloud last_refill null): keep local
  ///     available; the caller schedules a syncFreezes to push it up.
  /// Pre-D1 this treated used_dates as PER-WEEK and dropped it on the
  /// newer-refill branches; with the a8f3d1 fix (which stopped the unconditional
  /// same-week overwrite) the union is now total. The slow-boot flip (ADR-0014)
  /// opened the concurrent-consume window restore must tolerate.
  /// closes-diagnose: a8f3d1, f9d2e7.
  static FreezeMergeResult mergeFreezeProgress({
    required int localAvailable,
    required List<String> localUsed,
    required String? localLastRefill,
    required int cloudAvailable,
    required List<String> cloudUsed,
    required String? cloudLastRefill,
  }) {
    int clamp3(int v) => v.clamp(0, 3);
    // D1 (f9d2e7): PERMANENT ledger → used_dates is ALWAYS the union of both
    // sides, on EVERY branch. Pure (no clock dependency here) — growth is
    // bounded by commitRefill's weekly prune, so this stays deterministic.
    final mergedUsed = (<String>{...localUsed, ...cloudUsed}.toList())..sort();

    // Same week on both sides — take the LOWER available (never refund a freeze).
    if (localLastRefill != null &&
        cloudLastRefill != null &&
        localLastRefill == cloudLastRefill) {
      final avail =
          localAvailable < cloudAvailable ? localAvailable : cloudAvailable;
      return FreezeMergeResult(
        available: clamp3(avail),
        usedDates: mergedUsed,
        lastRefill: localLastRefill,
        scheduleSyncUp: false,
      );
    }

    // cloudWins also covers the brand-new-user case (BOTH last_refill null →
    // localLastRefill==null → true): the weekly budget defers to cloud, but
    // used_dates is still the (here empty) union. lastRefill stays null until
    // the first weekly refill stamps it. B-pass P2.
    final bool cloudWins = localLastRefill == null ||
        (cloudLastRefill != null &&
            cloudLastRefill.compareTo(localLastRefill) > 0);
    if (cloudWins) {
      return FreezeMergeResult(
        available: clamp3(cloudAvailable),
        usedDates: mergedUsed,
        lastRefill: cloudLastRefill ?? localLastRefill,
        scheduleSyncUp: false,
      );
    }
    // Local refill strictly newer — keep local available; push it up to cloud.
    return FreezeMergeResult(
      available: clamp3(localAvailable),
      usedDates: mergedUsed,
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
