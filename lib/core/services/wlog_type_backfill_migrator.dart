// Bug f1c8e4 — one-shot self-repair for `wlog_*` rows missing
// `type: 'workout_log'`.
//
// ## Background
//
// `WorkoutWriteService.markCompleted` is the canonical LIVE completion writer
// (train_provider.completeWorkout routes here; the A-13 derive-only refactor made
// it "Replace repo.saveWorkoutLog"). Pre-f1c8e4 it wrote the `wlog_<date>` row
// WITHOUT `type: 'workout_log'` and used `completed_at_ms` instead of the ISO
// `completed_at`. EVERY count/history reader filters `type == 'workout_log'`
// (getWeeklyWorkoutCounts → reports "This Week" tile + frequency chart,
// getWorkoutLogs → history + getRecentWorkoutCompletionHours, BadgeService
// totalWorkouts, AiSnapshotBuilder), so a live completion was invisible to all of
// them until a reinstall+restore (sync_workout._restoreWorkoutLogs DOES stamp
// type + completed_at) re-tagged it — and the additive restore guard never
// upgrades a pre-existing type-less row.
//
// The f1c8e4 writer fix stamps both on NEW completions. This migrator heals the
// rows ALREADY on-device (completed before the fix) so historical weeks count
// correctly without forcing a reinstall.
//
// ## What it does
//
// Walks every `wlog_*` row. If `type` is missing (or not 'workout_log'), set it
// to 'workout_log'. If `completed_at` is missing/empty but `completed_at_ms`
// exists, derive the ISO `completed_at` from it. Idempotent.
//
// ## No cloud re-sync
//
// `type` is a Hive-only field — the cloud `workout_logs` table has no `type`
// column and `_syncWorkoutLogs` projects explicit columns (it ignores `type`).
// The rows already reached cloud (the push selects by `wlog_` key-prefix, not by
// type). So unlike LoggingTypeRepairMigrator, this repair is purely local — no
// re-sync.
//
// ## Idempotency
//
// Gated by `migrationBox['wlog_type_backfill_v1_done']`. Runs once per device
// lifetime (the flag survives `clearAllData()` because migrationBox lives in the
// shared box set). Safe to call on every cold start — short-circuits in < 1 ms.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Backfills `type: 'workout_log'` (+ ISO `completed_at`) onto legacy `wlog_*`
/// rows that the pre-f1c8e4 `markCompleted` wrote without them. closes-diagnose:
/// f1c8e4.
class WlogTypeBackfillMigrator {
  WlogTypeBackfillMigrator._();

  static const String _flagKey = 'wlog_type_backfill_v1_done';

  /// True once the migration has run on this device.
  static bool hasRun() {
    try {
      return HiveService.instance.migrationBox.get(_flagKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Pure repair of a single wlog row map. Returns true if [row] was mutated.
  /// Exposed for behavioral testing.
  static bool repairRow(Map<String, dynamic> row) {
    var changed = false;

    if (row['type'] != 'workout_log') {
      row['type'] = 'workout_log';
      changed = true;
    }

    final completedAt = row['completed_at'];
    final hasIso = completedAt is String && completedAt.isNotEmpty;
    if (!hasIso) {
      final ms = row['completed_at_ms'];
      if (ms is int && ms > 0) {
        row['completed_at'] =
            DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
        changed = true;
      }
    }

    return changed;
  }

  /// Run the migration if it hasn't run before. Safe on every launch —
  /// short-circuits via the migration flag. Returns the count of rows repaired
  /// (0 means it ran but nothing needed fixing).
  static Future<int> runIfNeeded() async {
    final hive = HiveService.instance;
    Box migrationBox;
    try {
      migrationBox = hive.migrationBox;
    } catch (e, st) {
      debugPrint('[WlogTypeBackfillMigrator] migrationBox unavailable: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'wlog_type_backfill_migrator_migration_box_unavailable'));
      return 0;
    }

    if (migrationBox.get(_flagKey) == true) {
      return 0;
    }

    int repaired = 0;
    try {
      final wb = hive.workoutBox;
      final keys = wb.keys.toList();
      for (final k in keys) {
        if (k is! String || !k.startsWith('wlog_')) continue;
        final raw = wb.get(k);
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (!repairRow(m)) continue;
        await wb.put(k, m);
        repaired += 1;
      }

      await migrationBox.put(_flagKey, true);
      debugPrint('[WlogTypeBackfillMigrator] repaired=$repaired wlog row(s)');
    } catch (e, st) {
      debugPrint('[WlogTypeBackfillMigrator] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'wlog_type_backfill_migrator_run_if_needed'));
      // DON'T set the flag — let the next launch retry.
    }

    return repaired;
  }
}
