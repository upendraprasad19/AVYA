// lib/core/services/completed_title_healer.dart
//
// OI-284 (plan docs/plans/swap-title-and-launch-refresh.md v3, diagnose
// 2026-10-04-completed-row-title-follows-log-*). After a cross-device day swap
// a phone's COMPLETED non-template schedule row kept its pre-swap title:
// `PlanIntegrityReconciler.mergeScheduleEntry` returns a local completed row
// unchanged (plan_integrity_reconciler.dart:105-107) and the status overlay
// `_restoreScheduledWorkouts` spreads `...existingMap`, writing a title only
// from a cloud TEMPLATE (sync_workout.dart:2562-2589) — while the completed
// card, receipt and calendar read the performed LOG (`wlog_<date>`).
//
// This pass makes the row's title agree with the title the completed card
// shows. It reads ONLY local Hive (no network, no plan bundle, no stash) and
// changes ONLY `workout_name`. It runs after a SUCCEEDED full restore
// (`SyncService.healCompletedTitlesAfterRestore`).
//
// A row is left untouched, silently, unless ALL hold:
//  - `status == 'completed'` (planned rows belong to the merge);
//  - no `template_id` (a template row is rewritten by the overlay from the
//    cloud template and converges on its own — a heal would fight it);
//  - `type != 'logged'` (those rows take their name from the completions
//    table, not a log);
//  - `wlog_<date>` is a Map of `type == 'workout_log'` whose `source` is not
//    `cloud_restore_completion` (that source is synthetic: it copies the
//    completions name, so it is circular). `source: 'cloud_restore'` wlogs
//    hold the REAL cloud name and are eligible;
//  - the log's name is non-empty and not a placeholder
//    ([kPlaceholderWorkoutNames]: "Workout" / "Chat Workout");
//  - the log's name differs from the row's, ignoring case and surrounding
//    whitespace (Train writes its log names upper-case, so "PULL + CORE" vs
//    "Pull + Core" is not a difference).
//
// Atomicity: Dart is single-isolate and Hive's put updates its keystore
// synchronously before its first await, so the get-then-put below (no `await`
// between them) cannot interleave with another Dart writer. A restore writer
// that read the row BEFORE this pass and writes it AFTER re-puts the stale
// title; the pass is idempotent and heals again at the next successful
// restore. No `_acquireLock`: there is no new public API on
// WorkoutWriteService.
//
// Not hooked (and why): `restoreLightweightAlways` restores no logs; the
// `*ForSyncDomain` entry points are flag-gated OFF; `sync_realtime.dart`
// touches no schedule or wlog rows. Whoever flips them — or OI-279's
// resume-pull — must call `CompletedTitleHealer.run()` after restoring logs.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'workout_write_service.dart' show kPlaceholderWorkoutNames;

class CompletedTitleHealer {
  CompletedTitleHealer._();

  static const String _schedulePrefix = 'schedule_';
  static const String _wlogPrefix = 'wlog_';
  static final RegExp _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Heals every eligible row. Returns how many rows changed. Never throws:
  /// after an account switch or sign-out the user-scoped box is closed, the
  /// next operation throws, and the pass reports 0 — it is NOT a restore
  /// failure and must not surface as one.
  static Future<int> run() async {
    try {
      final keys = <String>[
        for (final k in HiveService.instance.workoutBox.keys)
          if (k is String &&
              k.startsWith(_schedulePrefix) &&
              _dateKey.hasMatch(k.substring(_schedulePrefix.length)))
            k,
      ];
      var healed = 0;
      for (final key in keys) {
        // A fresh box reference per row — never held across an await, so an
        // account switch mid-pass is seen by the next iteration.
        final box = HiveService.instance.workoutBox;
        final date = key.substring(_schedulePrefix.length);
        final raw = box.get(key);
        if (raw is! Map) continue;
        if (raw['status'] != 'completed') continue;
        final template = raw['template_id'];
        if (template != null && template.toString().isNotEmpty) continue;
        if (raw['type'] == 'logged') continue;

        final log = box.get('$_wlogPrefix$date');
        if (log is! Map) continue;
        if (log['type'] != 'workout_log') continue;
        if (log['source'] == 'cloud_restore_completion') continue;
        final logName = (log['workout_name'] as String?)?.trim() ?? '';
        final logNorm = logName.toLowerCase();
        if (logNorm.isEmpty || kPlaceholderWorkoutNames.contains(logNorm)) {
          continue;
        }
        final rowNorm =
            ((raw['workout_name'] as String?) ?? '').trim().toLowerCase();
        if (logNorm == rowNorm) continue;

        // Read-modify-write with no await between the get above and this put.
        final updated = Map<String, dynamic>.from(raw)
          ..['workout_name'] = logName;
        await box.put(key, updated);
        healed++;
      }
      if (healed > 0) {
        // Counts only — a workout name is user data (PII). unawaited so the
        // network post never delays the restore result or navigation.
        unawaited(ErrorTelemetry.logEvent('completed_title_healed',
            message: 'count=$healed'));
      }
      return healed;
    } catch (e) {
      debugPrint('[CompletedTitleHealer] pass skipped: $e');
      // H-42: a debugPrint-only catch is invisible in production. The error
      // TYPE only (never the message — it can echo a workout name).
      unawaited(ErrorTelemetry.logEvent('completed_title_heal_skipped',
          message: e.runtimeType.toString()));
      return 0;
    }
  }
}
