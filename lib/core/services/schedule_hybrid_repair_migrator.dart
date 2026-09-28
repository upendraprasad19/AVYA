// Spec 2026-09-26-day-swapper-design.md §1.4/§5.7, plan Task 23, diagnose b6e1c8.
//
// One-time PER-USER repair migrator. Three independent repairs, all local Hive,
// idempotent, gated by ONE flag stored in `workoutBox` — deliberately NOT
// `migrationBox` (D10): `migrationBox` is a single SHARED box name opened once
// per DEVICE (`HiveService.migrationBoxName`, never re-namespaced), while
// `workoutBox` resolves through `HiveUserSession.openForUser` to a per-user
// NAMESPACED box file (`workoutBox_<8-char-hash-of-userId>`,
// `hive_user_session.dart:100-103`). Gating on `workoutBox` therefore repairs a
// second account signing into the same device too, which a `migrationBox` gate
// would silently skip.
//
// ## What it does
//
// 1. Walks every `schedule_<date>` row in `workoutBox`. A row with
//    `status: 'rest'`, a workout `type` (per
//    `PlanEngineFlags.isRestDayConsideringLogged`) and NO exercises is the
//    hybrid shape spec §1.3/§1.4 describes (28 live rows across 3 users'
//    plan_json backups as of 2026-09-26) — it is corrected to `type: 'rest'`.
// 2. The SAME shape but WITH non-empty exercises (the single live ambiguous
//    case) is left ALONE — it is in the past and choosing a winner would be a
//    guess, not a fix (spec §5.7) — but logs one `ErrorTelemetry.logEvent`
//    per such row so a recurrence elsewhere is visible.
// 3. Deletes the two dead swap-counter keys, `swaps_this_week` and
//    `swap_week_start` (plan D9 — superseded by `DaySwapAllowance`; they stay
//    listed in `UserConfigMigrator.userScopedKeys` per D9's own text, this
//    migrator is what actually removes them from a device), via
//    `MigratedKey.delete`.
// 4. Deletes the stale `plan_json` copy already sitting inside
//    `userBox['progress']` for existing installs (spec §1.5 / plan Task 20 —
//    Task 20 stops a NEW copy from being written on every restore; this
//    migrator is the one-time cleanup of the copy already on disk).
//
// The hybrid predicate is NOT duplicated here: `classifyRow` calls
// `PlanIntegrityReconciler.isRestHybrid` (Task 21), the same predicate the
// merge normalizer uses, so the one-time repair and every future merge agree
// on what a hybrid is by construction.
//
// No cloud re-sync call inside this migrator: the corrected `schedule_<date>`
// rows are picked up by the NEXT `_syncWorkoutPlan` push
// (`SyncService.instance.pushWorkoutPlanForSyncDomain()`), which rebuilds its
// `plan_json.schedules` bundle by scanning CURRENT `workoutBox` `schedule_*`
// rows on every call (`sync/sync_workout.dart:1128-1136`) — same "no cloud
// re-sync needed, an existing push already covers it" shape as
// `WlogTypeBackfillMigrator`'s own header note.
//
// ## Idempotency
//
// Gated by `workoutBox['hybrid_schedule_repair_v1_done']`. Non-fatal on
// failure (next launch retries) — the flag is set only after every step
// (repair loop, key deletes, plan_json strip) has run without throwing.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';

/// The three outcomes [ScheduleHybridRepairMigrator.classifyRow] can reach
/// for a `schedule_<date>` row.
enum HybridRowVerdict {
  /// Not the hybrid shape at all — left untouched.
  notAHybrid,

  /// `status: rest` + workout type + NO exercises — repaired to `type: rest`.
  needsTypeFix,

  /// `status: rest` + workout type + non-empty exercises — the single
  /// ambiguous live case. Left alone; telemetry only.
  hasExercisesLeaveAlone,
}

/// One-time per-user repair of `schedule_<date>` hybrid rows + dead swap-
/// counter keys + the stale `plan_json` copy in `userBox['progress']`.
/// closes-diagnose: b6e1c8.
class ScheduleHybridRepairMigrator {
  ScheduleHybridRepairMigrator._();

  // Must NOT start with `schedule_`: eight readers treat every workoutBox key
  // with that prefix as a day row (the plan_json bundle push uploads it,
  // WorkoutRepository._hasAnyScheduleRow reads "has a schedule"). Hermes
  // 2026-09-28; pinned by schedule_hybrid_repair_migrator_test.dart.
  static const String _flagKey = 'hybrid_schedule_repair_v1_done';
  static const String _schedulePrefix = 'schedule_';

  /// True once the migration has run for the CURRENTLY OPEN user's
  /// `workoutBox` (D10 — per-user, not per-device).
  static bool hasRun() {
    try {
      return HiveService.instance.workoutBox.get(_flagKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// PURE (visible for testing): does [row] describe the hybrid shape, and
  /// if so which of the two outcomes applies?
  @visibleForTesting
  static HybridRowVerdict classifyRow(Map<String, dynamic> row) {
    // The ONE hybrid predicate lives in PlanIntegrityReconciler (Task 21) so
    // the merge normalizer and this repair can never disagree.
    if (PlanIntegrityReconciler.isRestHybrid(row)) {
      return HybridRowVerdict.needsTypeFix;
    }
    // Same shape except it carries exercises: ambiguous, left alone.
    if (PlanIntegrityReconciler.isRestHybrid(
        {...row, 'exercises': const <Object>[]})) {
      return HybridRowVerdict.hasExercisesLeaveAlone;
    }
    return HybridRowVerdict.notAHybrid;
  }

  /// PURE (visible for testing): mutates [row]'s `type` to `'rest'` IFF
  /// [classifyRow] returns [HybridRowVerdict.needsTypeFix]. Returns true if
  /// [row] was mutated. Mirrors [WlogTypeBackfillMigrator.repairRow]'s
  /// mutate-in-place + bool shape.
  @visibleForTesting
  static bool repairRow(Map<String, dynamic> row) {
    if (classifyRow(row) != HybridRowVerdict.needsTypeFix) return false;
    row['type'] = 'rest';
    return true;
  }

  /// Run the migration if it hasn't run before for the current user. Safe on
  /// every launch — short-circuits via the per-user flag. Returns the count
  /// of rows REPAIRED (needsTypeFix only; a `hasExercisesLeaveAlone` row is
  /// not counted here — it is reported via telemetry instead).
  static Future<int> runIfNeeded() async {
    final hive = HiveService.instance;
    Box workoutBox;
    try {
      workoutBox = hive.workoutBox;
    } catch (e, st) {
      debugPrint('[ScheduleHybridRepairMigrator] workoutBox unavailable: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'schedule_hybrid_repair_migrator_workout_box_unavailable'));
      return 0;
    }

    if (workoutBox.get(_flagKey) == true) {
      return 0;
    }

    var repaired = 0;
    var leftAlone = 0;
    try {
      final keys = workoutBox.keys.toList();
      for (final k in keys) {
        if (k is! String || !k.startsWith(_schedulePrefix)) continue;
        final raw = workoutBox.get(k);
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final verdict = classifyRow(row);
        // repairRow owns the mutation (one definition of the fix; round-2
        // review E F2) — it re-classifies, so it returns true here.
        if (verdict == HybridRowVerdict.needsTypeFix && repairRow(row)) {
          await workoutBox.put(k, row);
          repaired += 1;
        } else if (verdict == HybridRowVerdict.hasExercisesLeaveAlone) {
          leftAlone += 1;
          unawaited(ErrorTelemetry.logEvent('schedule_hybrid_left_alone',
              message: 'key=$k'));
        }
      }

      // Plan D9 — dead swap-counter keys, superseded by DaySwapAllowance.
      await MigratedKey.delete('swaps_this_week');
      await MigratedKey.delete('swap_week_start');

      // Spec §1.5 / plan Task 20 — delete the stale plan_json copy already
      // on disk inside userBox['progress'] for installs that ran an earlier
      // build (Task 20 stops a NEW copy being written going forward).
      final progress = hive.userBox.get('progress');
      if (progress is Map && progress.containsKey('plan_json')) {
        final cleaned = Map<String, dynamic>.from(progress)
          ..remove('plan_json');
        await hive.userBox.put('progress', cleaned);
      }

      await workoutBox.put(_flagKey, true);
      debugPrint(
          '[ScheduleHybridRepairMigrator] repaired=$repaired leftAlone=$leftAlone');
    } catch (e, st) {
      debugPrint('[ScheduleHybridRepairMigrator] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'schedule_hybrid_repair_migrator_run_if_needed'));
      // DON'T set the flag — let the next launch retry.
    }

    return repaired;
  }
}
