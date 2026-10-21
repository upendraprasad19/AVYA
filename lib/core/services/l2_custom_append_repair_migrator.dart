// lib/core/services/l2_custom_append_repair_migrator.dart
//
// d4b8e1 Batch 0b (plan docs/plans/2026-10-21-l2-custom-repair.md). The removed
// plan-generator lever L2 appended a user's custom exercises to every generated
// day whose muscles matched (founder's Phase 4: 6 customs on every push day).
// 0a stopped new generations; this one-time PER-USER pass removes those
// customs from the day rows ALREADY generated, after today.
//
// ## What it touches
//
// A `schedule_<date>` row dated AFTER today (string compare of the key's date
// with `istTodayStr()`) with `type: workout`, `status` planned or paused (a
// paused day is pending, not terminal) and no template. Its exercises go
// through `stripRow` (auto_appended_custom.dart, the ONE predicate, shared
// with the repeat-pin read): a custom name that the library does not also hold
// and that carries no provenance stamp is removed. Completed, past, rest and
// template rows are never written. A row the strip would EMPTY is skipped (an
// empty list refills from the plan snapshot, plan_integrity_reconciler.dart).
// TODAY's row is never rewritten: a started workout session lives in memory
// and leaves no reliable stored marker until its first logged set, so the
// pass cannot tell whether one is open; a pass that would have changed today's
// row does not latch, and the row is past by the next day.
//
// Each write is a full copy of the re-read row through
// `WorkoutWriteService.upsertScheduled(source: planGenerator, ifUnchangedFrom:
// <the row read>)`: it refuses a completed day, and refuses when another writer
// replaced the row after this pass read it. The write date comes from the KEY
// via `DaySwapRules.utcDate`, never from parsing the row's `date` (a device
// east of IST would map local midnight to the previous IST day and overwrite
// the neighbouring row). A row carrying an `arranged_at_ms` stamp is
// re-stamped with the write time, so the stripped week wins the restore merge
// (strictly newer) on a device that had taken the polluted rows from another
// device's newer day swap. Afterwards ONE plan push rebuilds the cloud
// `plan_json.schedules` (`upsertScheduled` alone never reaches it); it is
// issued after every completed scan, because a previous pass may have stripped
// rows and then stopped, and `_syncWorkoutPlan` skips an unchanged plan.
//
// ## Gates and latch
//
// Kill switch `disable_l2_custom_strip` (SyncFlags.l2CustomStripEnabled). Then
// the latch `workoutBox['l2_custom_repair_v1_done']` (per-user box, like
// ScheduleHybridRepairMigrator; never a `schedule_` prefix — eight readers
// treat those keys as day rows). No customs: nothing to strip, no latch (a
// later restore may bring them). Restore not settled for the current account:
// withheld, no scan, no latch (every cold start restores, so it retries).
// The settle check is repeated before each write, the push and the latch. The
// latch is set only when no write failed or met a changed row, the pass was
// not stopped, today's row needed nothing, and the plan push was issued.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import 'auto_appended_custom.dart';
import 'day_swap/day_swap_rules.dart';
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'sync_flags.dart';
import 'sync_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/ist_date.dart';

/// One-time per-user removal of the custom exercises lever L2 auto-appended
/// to future planned days. closes-diagnose: c3e9a4 (sibling of d4b8e1).
class L2CustomAppendRepairMigrator {
  L2CustomAppendRepairMigrator._();

  static const String _flagKey = 'l2_custom_repair_v1_done';
  static const String _schedulePrefix = 'schedule_';
  static final RegExp _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static const Set<String> _strippableStatuses = {'planned', 'paused'};

  static Future<int>? _inFlight;

  /// Test seam: replaces the row write so a test can make it fail. Null in
  /// production.
  @visibleForTesting
  static Future<WriteResult> Function(DateTime date, Map<String, dynamic> entry)?
      debugUpsertOverride;

  /// True once the repair has latched for the CURRENTLY OPEN user.
  static bool hasRun() {
    try {
      return HiveService.instance.workoutBox.get(_flagKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// The write date for a `schedule_<suffix>` key: UTC midnight of that
  /// calendar date, or null when [suffix] is not a real `YYYY-MM-DD` date
  /// (the round trip rejects `2026-13-45`).
  @visibleForTesting
  static DateTime? writeDateForSuffix(String suffix) {
    if (!_dateShape.hasMatch(suffix)) return null;
    final date = DaySwapRules.utcDate(suffix);
    return DaySwapRules.format(date) == suffix ? date : null;
  }

  /// Runs the repair unless it is switched off, latched or withheld. Returns
  /// how many rows were rewritten. Never throws. A second caller while a pass
  /// is running gets that pass's result.
  static Future<int> runIfNeeded() async {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final pass = _run();
    _inFlight = pass;
    try {
      return await pass;
    } finally {
      _inFlight = null;
    }
  }

  static Future<int> _run() async {
    if (!SyncFlags.l2CustomStripEnabled) return 0;
    try {
      if (HiveService.instance.workoutBox.get(_flagKey) == true) return 0;
      final customs = ExerciseRepository.instance.customNamesLower();
      if (customs.isEmpty) return 0;
      final sync = SyncService.instance;
      if (!sync.restoreSettledForCurrentUser) {
        final reason = sync.lastRestoreWithheldReason;
        if (reason != null) {
          unawaited(ErrorTelemetry.logEvent('l2_custom_repair_withheld',
              message: 'reason=$reason'));
        }
        return 0;
      }

      final today = istTodayStr();
      final keys = <String>[
        for (final k in HiveService.instance.workoutBox.keys)
          if (k is String &&
              k.startsWith(_schedulePrefix) &&
              k.substring(_schedulePrefix.length).compareTo(today) >= 0)
            k,
      ]..sort();
      bool libraryHas(String name) =>
          ExerciseRepository.instance.hasExactNameWhere(name, isLibraryRow);

      var rows = 0;
      var removed = 0;
      var skippedEmpty = 0;
      var failed = 0;
      var changed = 0;
      var todayPending = false;
      var stopped = false;
      for (final key in keys) {
        if (!sync.restoreSettledForCurrentUser) {
          stopped = true;
          break;
        }
        final suffix = key.substring(_schedulePrefix.length);
        final date = writeDateForSuffix(suffix);
        if (date == null) continue;
        // Re-read at write time: a fresh box reference per row, so another
        // writer's change since the key scan is what gets stripped.
        final raw = HiveService.instance.workoutBox.get(key);
        if (raw is! Map) continue;
        if (raw['type'] != 'workout' ||
            !_strippableStatuses.contains(raw['status'])) {
          continue;
        }
        final template = raw['template_id'];
        if (template != null && template.toString().isNotEmpty) continue;
        final exercises = raw['exercises'];
        if (exercises is! List) continue;
        final copy =
            stripRow(raw, customNamesLower: customs, libraryHas: libraryHas);
        final kept = copy['exercises'] as List;
        if (kept.length == exercises.length) continue;
        if (kept.isEmpty) {
          skippedEmpty++;
          continue;
        }
        if (suffix == today) {
          todayPending = true;
          continue;
        }
        if (copy['arranged_at_ms'] != null) {
          copy['arranged_at_ms'] = DateTime.now().millisecondsSinceEpoch;
        }
        final result = await (debugUpsertOverride?.call(date, copy) ??
            WorkoutWriteService.instance.upsertScheduled(
              date: date,
              entry: copy,
              source: WriteSource.planGenerator,
              ifUnchangedFrom: raw,
            ));
        if (result.success) {
          rows++;
          removed += exercises.length - kept.length;
        } else if (result.errorMessage ==
            WorkoutWriteService.rowChangedMessage) {
          // Another writer replaced the row after this read: no write, and
          // no latch, so the next launch looks at the new row.
          changed++;
        } else if (result.errorMessage !=
            WorkoutWriteService.completedDayRefusedMessage) {
          // A completed-day refusal is a benign race (the day was completed
          // after the scan); anything else is a real failure.
          failed++;
        }
      }

      // Counts only — exercise names are user text.
      unawaited(ErrorTelemetry.logEvent('l2_custom_strip',
          message: 'rows=$rows exercises=$removed skipped_empty=$skippedEmpty '
              'failed=$failed changed=$changed today_pending=$todayPending '
              'stopped=$stopped'));

      if (stopped || !sync.restoreSettledForCurrentUser) return rows;
      final pushed = _pushPlan(today);
      if (pushed && failed == 0 && changed == 0 && !todayPending) {
        await HiveService.instance.workoutBox.put(_flagKey, true);
      }
      return rows;
    } catch (e, st) {
      debugPrint('[L2CustomAppendRepairMigrator] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'l2_custom_repair_migrator'));
      // No latch: the next launch retries.
      return 0;
    }
  }

  /// ONE plan push so cloud `plan_json.schedules` loses the customs too.
  /// Returns false (withheld) when a planned workout day from [today] on has
  /// no exercises: never upload a plan the snapshot heal would have to refill.
  static bool _pushPlan(String today) {
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys) {
      if (k is! String || !k.startsWith(_schedulePrefix)) continue;
      if (k.substring(_schedulePrefix.length).compareTo(today) < 0) continue;
      final row = box.get(k);
      if (row is! Map) continue;
      if (row['status'] != 'planned' || row['type'] != 'workout') continue;
      final exercises = row['exercises'];
      if (exercises is! List || exercises.isEmpty) {
        unawaited(ErrorTelemetry.logEvent('l2_custom_repair_push_skipped'));
        return false;
      }
    }
    // _syncWorkoutPlan reports its own failures (sync_failure telemetry) and
    // skips a plan whose fingerprint is unchanged since the last confirmed
    // push. It confirms only after a successful upsert, so a push that fails
    // after this pass latched is re-sent by the next plan push
    // (weeklyFullSync). The catchError only guards an unexpected throw.
    unawaited(SyncService.instance
        .pushWorkoutPlanForSyncDomain()
        .catchError((Object e, StackTrace st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'l2_custom_repair_push'));
    }));
    return true;
  }
}
