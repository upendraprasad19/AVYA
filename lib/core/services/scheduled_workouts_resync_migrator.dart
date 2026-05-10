// APK Test #14 / Bug B.3 — One-shot resync migrator.
//
// A subset of users (founder included) currently has Hive
// `schedule_<date>` rows with `status='completed'` while the cloud
// `scheduled_workouts` row stays at `status='planned'`. Root cause was
// Bug B.1 (`_syncScheduledWorkouts` 23503-fired silently on every
// FK-violating push) + Bug B.2 (`_restoreScheduledWorkouts` then
// overwrote the local 'completed' on next restore).
//
// Once Bug B.1 + B.2 ship, future writes stay consistent. But existing
// divergence won't self-heal — the local 'completed' rows have been
// sitting unsynced for days. This migrator scans local Hive on first
// cold-start after upgrade and re-triggers `syncWorkoutData()` once,
// gated by `userBox['apk_test_14_completion_resync_done']`.
//
// Idempotent: runs once per user (flag is in user-scoped userBox).
// Safe to call on every launch — flag short-circuits all but the
// first run.
//
// Diagnose: docs/diagnoses/2026-05-10-resync-migrator-e3f7a8.md

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class ScheduledWorkoutsResyncMigrator {
  ScheduledWorkoutsResyncMigrator._();

  /// Hive flag key in `userBox`. Per-user — different users on the
  /// same device get separate gates. Bumping this key (e.g. v2)
  /// re-triggers the migration on devices that already ran v1.
  static const String _flagKey = 'apk_test_14_completion_resync_done';

  /// Runs once per user. Subsequent calls short-circuit on the flag.
  ///
  /// Strategy:
  ///   1. Iterate `workoutBox.keys` looking for `schedule_<date>`
  ///      entries with `status == 'completed'` AND `completed_at != null`.
  ///   2. If any candidates exist, call `SyncService.syncWorkoutData()`
  ///      ONCE — the hardened `_syncScheduledWorkouts` (Bug B.1 fix)
  ///      handles per-row resolution and 23503 self-heal.
  ///   3. Set the flag.
  ///
  /// Failure handling: any exception leaves the flag UNSET so the next
  /// launch retries. Telemetry is logged via debugPrint only — the
  /// migrator is purely opportunistic and shouldn't escalate failures.
  static Future<void> runIfNeeded() async {
    try {
      final userBox = HiveService.instance.userBox;
      if (userBox.get(_flagKey) == true) return;

      final workoutBox = HiveService.instance.workoutBox;
      var candidateCount = 0;
      for (final key in workoutBox.keys) {
        if (key is! String || !key.startsWith('schedule_')) continue;
        final raw = workoutBox.get(key);
        if (raw is! Map) continue;
        final status = raw['status'];
        final completedAt = raw['completed_at'];
        if (status == 'completed' &&
            completedAt is String &&
            completedAt.isNotEmpty) {
          candidateCount++;
        }
      }

      if (candidateCount > 0) {
        // Reuse the standard fan-out — Bug B.1's hardened push handles
        // per-row 23503 resolution + null-template fallback. We don't
        // re-iterate per row here; one syncWorkoutData() call sweeps
        // every schedule entry under the new lookup-by-name path.
        debugPrint(
            '[ScheduledWorkoutsResyncMigrator] $candidateCount candidate(s); calling syncWorkoutData()');
        await SyncService.instance.syncWorkoutData();
      } else {
        debugPrint(
            '[ScheduledWorkoutsResyncMigrator] no completed schedule rows; skipping resync');
      }

      await userBox.put(_flagKey, true);
    } catch (e) {
      // Flag stays UNSET so the next launch retries. Don't rethrow —
      // a fire-and-forget call site shouldn't surface migrator
      // failures to the user.
      debugPrint('[ScheduledWorkoutsResyncMigrator.runIfNeeded] $e');
    }
  }
}
