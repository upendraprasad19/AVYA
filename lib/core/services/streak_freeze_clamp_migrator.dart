// Bug f8c1a5 — APK Test #16.2.
//
// One-shot Hive repair migrator. Normalises `streak_freezes_available`
// inside `userBox['progress']` to the user's tier cap, and clears
// `streak_freezes_last_refill` so the next Monday rollover/splash
// refill can run cleanly.
//
// Why this exists
// ---------------
//
// `StreakProgressService.commitRefill` clamps on write
// (`(currentAvailable + 1).clamp(0, maxFreezes)`), but the value 8
// reported by the founder cannot be produced by any in-app write
// path. The plausible upstream is:
//
//   - pre-CQRS-split code (pre-2026-05-11) where refill ran inline
//     inside the Riverpod build() without the clamp,
//   - or cloud restore (`SyncService._restoreFreezes`) pulling a
//     legacy unclamped value from the server and writing it through
//     to Hive verbatim (the same write path this migrator repairs).
//
// Layer 1 of the f8c1a5 four-layer defense (read-side clamp in
// `StreakFreezeNotifier.build`) corrects the displayed value in the
// current session.  This migrator is Layer 2 — durable on-disk
// repair so the value never drifts out of cap again. Layer 3 clamps
// inside `_restoreFreezes` itself. Layer 4 is migration 072's CHECK
// constraint server-side.
//
// Idempotent. Gated by `migrationBox['streak_freeze_clamp_v1_done']`,
// which is NEVER cleared by `clearAllData()` — mirrors the
// UserConfigMigrator + ExlogKeyMigrator pattern.
//
// Caller MUST ensure `HiveUserSession.openForUser` has run for the
// current session before invoking this. The intended call site is
// `_ensureLocalUser` in auth_provider.dart, after the existing
// `UserConfigMigrator.runIfNeeded()` invocation.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'subscription_service.dart';
import 'sync_service.dart';

class StreakFreezeClampMigrator {
  StreakFreezeClampMigrator._();

  static const String _flagKey = 'streak_freeze_clamp_v1_done';

  /// PRO tier cap. Free is 1. Used both as the cap-clamp ceiling for PRO
  /// users and as the absolute upper bound that no legitimate value can
  /// exceed regardless of tier.
  static const int _absoluteMax = 3;

  /// Runs the migration once per device-user pair. Idempotent.
  ///
  /// Returns a [StreakFreezeClampResult] describing the outcome.
  /// Failures are non-fatal — the read-side clamp keeps the display
  /// honest until the next launch where this can retry.
  static Future<StreakFreezeClampResult> runIfNeeded() async {
    final hive = HiveService.instance;
    final migBox = hive.migrationBox;
    if (migBox.get(_flagKey) == true) {
      return const StreakFreezeClampResult.noop();
    }

    try {
      final userBox = hive.userBox; // GuardedBox — caller has a session.
      final existing = userBox.get('progress');
      if (existing is! Map) {
        // No progress map yet — nothing to clamp. Mark flag so we don't
        // re-run for this device.
        await migBox.put(_flagKey, true);
        return const StreakFreezeClampResult.noop();
      }

      final map = Map<String, dynamic>.from(existing);
      final stored = (map['streak_freezes_available'] as int?) ?? 0;
      final cap =
          SubscriptionService.instance.isPro() ? _absoluteMax : 1;

      if (stored <= cap) {
        // Already in range — no repair needed. Flag and exit.
        await migBox.put(_flagKey, true);
        return StreakFreezeClampResult(
          previousAvailable: stored,
          clampedAvailable: stored,
          clearedLastRefill: false,
          repaired: false,
        );
      }

      // Repair: clamp + clear last_refill so the next rollover/splash
      // refill can run again (it was idempotency-gated when the
      // unclamped value parked itself with a recent last_refill).
      map['streak_freezes_available'] = cap;
      final hadLastRefill =
          (map['streak_freezes_last_refill'] as String?)?.isNotEmpty == true;
      map.remove('streak_freezes_last_refill');
      await userBox.put('progress', map);
      await migBox.put(_flagKey, true);

      // Best-effort cloud sync so the repaired value reaches user_progress.
      unawaited(SyncService.instance.syncFreezes());

      debugPrint(
          '[StreakFreezeClampMigrator] repaired streak_freezes_available '
          '$stored -> $cap (cap=$cap, clearedLastRefill=$hadLastRefill)');

      return StreakFreezeClampResult(
        previousAvailable: stored,
        clampedAvailable: cap,
        clearedLastRefill: hadLastRefill,
        repaired: true,
      );
    } catch (e, st) {
      debugPrint('[StreakFreezeClampMigrator] error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'streak_freeze_clamp_migrator'));
      return StreakFreezeClampResult.error(e);
    }
  }
}

class StreakFreezeClampResult {
  final int previousAvailable;
  final int clampedAvailable;
  final bool clearedLastRefill;
  final bool repaired;
  final Object? error;

  const StreakFreezeClampResult({
    required this.previousAvailable,
    required this.clampedAvailable,
    required this.clearedLastRefill,
    required this.repaired,
    this.error,
  });

  const StreakFreezeClampResult.noop()
      : previousAvailable = 0,
        clampedAvailable = 0,
        clearedLastRefill = false,
        repaired = false,
        error = null;

  const StreakFreezeClampResult.error(Object e)
      : previousAvailable = 0,
        clampedAvailable = 0,
        clearedLastRefill = false,
        repaired = false,
        error = e;

  @override
  String toString() {
    if (error != null) return 'StreakFreezeClampResult(error: $error)';
    if (!repaired) return 'StreakFreezeClampResult(noop)';
    return 'StreakFreezeClampResult($previousAvailable -> $clampedAvailable, '
        'clearedLastRefill=$clearedLastRefill)';
  }
}
