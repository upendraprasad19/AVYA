// lib/core/services/plan_integrity_reconciler.dart
//
// Heals the plan-schedule invariant after a fresh-install restore:
//
//   every PLANNED workout day in the current plan window carries its
//   workout_name + exercises[] (the content the cloud `scheduled_workouts`
//   table cannot supply — it has NO exercises / NO name column).
//
// **Root cause it closes** (restore plan_json skip, diagnose 2026-06-06): on a
// reinstall a plan was locally (re)generated before/around restore, so
// `_restoreWorkoutPlan`'s `if (current_plan != null) return` early-returned and
// the exercise-rich `plan_json.schedules` snapshot was never applied. Only the
// exercise-less `_restoreScheduledWorkouts` populated the days, so every
// not-yet-completed day rendered "REST DAY / No exercises scheduled" with a
// dead START button. The same skip left `plan_start_date` stale, cascading into
// the week/phase numbering.
//
// The reconciler re-applies the cloud `plan_json` snapshot — plan_start_date +
// the date-keyed schedules — using the SAME completed-status-preserving merge
// the restore path uses (a locally-completed day is authoritative and is never
// overwritten by the frozen snapshot).
//
// Properties (mirrors [PhaseProgressReconciler]):
//  - **Symptom-gated** — does NOTHING (no network) unless the current plan
//    window actually has a contentless planned workout day, so a healthy user
//    is always a cheap local no-op.
//  - **Idempotent** — safe to run on every boot; a second run finds no symptom.
//  - **Completed-day safe** — never overwrites a local `status='completed'`
//    day or its `completed_at` (mirrors `feedback_monotonic_field_recompute_demotion`).
//  - **Kill-switch** — skips when `configBox['disable_plan_integrity_reconciler']`
//    is `true` (§4.6 risky-change escape hatch without a rebuild).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'supabase_service.dart';
import 'workout_schedule_read_service.dart';

class PlanIntegrityReconciler {
  PlanIntegrityReconciler._();

  /// Hive `configBox` flag; set `true` to disable the reconciler at runtime.
  static const String killSwitchKey = 'disable_plan_integrity_reconciler';

  static const String _schedulePrefix = 'schedule_';
  static const String _planStartKey = 'plan_start_date';
  static const String _planEndKey = 'plan_end_date';

  /// PURE production helper (shared by the restore path + the boot heal so they
  /// can't drift): merge one `plan_json.schedules` entry into the local Hive
  /// `schedule_*` entry. The plan_json snapshot is the source of the content
  /// (`workout_name` + `exercises[]` + `type` + `workout_focus`) that the
  /// exercise-less `scheduled_workouts` restore drops; the LOCAL row is the
  /// source of live progress (`status` / `completed_at`).
  ///
  ///  - no local row            → take the snapshot wholesale.
  ///  - local `completed`       → KEEP local untouched (the logged session +
  ///                              status are authoritative; never demote to the
  ///                              frozen `planned` snapshot).
  ///  - otherwise (planned/rest)→ take the snapshot's content but keep the
  ///                              local live `status` / `completed_at`.
  static Map<String, dynamic> mergeScheduleEntry(
      Map<String, dynamic>? existing, Map<String, dynamic> planJson) {
    if (existing == null) return Map<String, dynamic>.from(planJson);
    if (existing['status'] == 'completed') {
      return Map<String, dynamic>.from(existing);
    }
    // If the local day ALREADY has its exercises, treat it as authoritative —
    // it may carry a local swap not yet synced into plan_json. Only FILL from
    // the snapshot when the local content was dropped (the restore-skip bug).
    // Keeps restore + the boot heal idempotent + swap-safe (review P1 2026-06-06).
    final localEx = existing['exercises'];
    if (localEx is List && localEx.isNotEmpty) {
      return Map<String, dynamic>.from(existing);
    }
    final merged = Map<String, dynamic>.from(planJson);
    final localStatus = existing['status'];
    if (localStatus != null) merged['status'] = localStatus;
    if (existing['completed_at'] != null) {
      merged['completed_at'] = existing['completed_at'];
    }
    return merged;
  }

  /// PURE (visible for testing): does any entry describe a PLANNED workout day
  /// that lost its exercises — the restore-skip symptom? A genuine rest day
  /// (`type != workout`) and a completed day are both fine.
  @visibleForTesting
  static bool needsHeal(Iterable<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final type = e['type'];
      final isWorkout = type == 'workout' || type == 'custom_template';
      if (!isWorkout) continue;
      if (e['status'] == 'completed') continue;
      final ex = e['exercises'];
      final hasExercises = ex is List && ex.isNotEmpty;
      if (!hasExercises) return true;
    }
    return false;
  }

  /// Reconcile the current user's local schedule against the cloud `plan_json`
  /// snapshot. [scheduleService] is injected so this is callable from the boot
  /// path (via the Riverpod provider) and from tests, mirroring
  /// [PhaseProgressReconciler.reconcile].
  static Future<void> reconcile(
      WorkoutScheduleReadService scheduleService) async {
    try {
      final hive = HiveService.instance;
      if (hive.configBox.get(killSwitchKey) == true) return;

      // Without a known plan window we can't classify the current weeks → skip
      // (a reconcilable user always has a plan_start).
      final planStart = scheduleService.getPlanStartDate();
      if (planStart == null) return;

      // Cheap LOCAL symptom check first — gather the current 4-week window's
      // schedule rows and bail (no network) when every planned workout day
      // already has its exercises.
      final local = <Map<String, dynamic>>[];
      for (var w = 1; w <= 4; w++) {
        local.addAll(scheduleService.getWeek(w));
      }
      if (!needsHeal(local)) return; // healthy → no-op, no fetch

      // Symptom present → pull the authoritative plan_json snapshot from cloud.
      final userId = SupabaseService.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await SupabaseService.instance.client
          .from('user_progress')
          .select('plan_json')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) return;
      final planJson = rows.first['plan_json'];
      if (planJson is! Map) return;
      final bundle = Map<String, dynamic>.from(planJson);

      // Re-anchor plan_start / plan_end from the snapshot (the skip left these
      // stale, which is what inflated the displayed week number).
      final pjStart = bundle['plan_start_date'];
      final pjEnd = bundle['plan_end_date'];
      if (pjStart != null) await MigratedKey.write(_planStartKey, pjStart);
      if (pjEnd != null) await MigratedKey.write(_planEndKey, pjEnd);

      final schedules = bundle['schedules'];
      var healed = 0;
      if (schedules is Map) {
        for (final entry in schedules.entries) {
          final key = entry.key.toString();
          if (!key.startsWith(_schedulePrefix)) continue;
          final incoming = entry.value;
          if (incoming is! Map) continue;
          final existing = hive.workoutBox.get(key);
          final merged = mergeScheduleEntry(
            existing is Map ? Map<String, dynamic>.from(existing) : null,
            Map<String, dynamic>.from(incoming),
          );
          await hive.workoutBox.put(key, merged);
          healed++;
        }
      }

      unawaited(ErrorTelemetry.logEvent(
        'plan_integrity_reconciled',
        message: 'healed=$healed planStart=$pjStart',
      ));
    } catch (e, st) {
      // Non-fatal — never block boot on a reconciliation hiccup.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'plan_integrity_reconciler'));
    }
  }
}
