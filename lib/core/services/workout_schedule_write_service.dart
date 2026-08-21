// lib/core/services/workout_schedule_write_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Owns scheduled-workout mutations that aren't swap/template specific:
//   - markCompleted, markSkipped
//   - pauseRange
//   - redoWeek4
//   - copyWeek
//
// Note: the canonical `upsertScheduled` writer lives on
// [WorkoutWriteService] (per APK Test #16.2). This service is the
// schedule-aware orchestrator that calls into WorkoutWriteService for
// each Hive mutation.
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'app_events_service.dart';
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'singleton_lifecycle_registry.dart';
import 'sync_service.dart';
import 'workout_schedule_read_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
import '../utils/ist_date.dart';

/// Typed failure modes for [WorkoutScheduleWriteService.pauseRange].
class PausePlanException implements Exception {
  final String code;
  final String message;
  const PausePlanException(this.code, this.message);
  @override
  String toString() => 'PausePlanException($code): $message';
}

/// Schedule-write orchestrator portion of the former WorkoutScheduleService.
class WorkoutScheduleWriteService {
  WorkoutScheduleWriteService._() {
    _registerLifecycle();
  }
  static final WorkoutScheduleWriteService _instance =
      WorkoutScheduleWriteService._();

  /// Prefer `ref.read(workoutScheduleWriteServiceProvider)`.
  @Deprecated(
      'Use ref.read(workoutScheduleWriteServiceProvider) — singleton path will be removed after full migration')
  static WorkoutScheduleWriteService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register(
        'WorkoutScheduleWriteService', _onUserChanged);
  }

  void _onUserChanged() {
    // No in-memory caches.
  }

  static const String _schedulePrefix = 'schedule_';
  static const String _planEndKey = 'plan_end_date';

  // ── Completion ──────────────────────────────────────────────────

  /// Mark a workout day as completed.
  Future<void> markCompleted(DateTime date, {int durationSeconds = 0}) async {
    final key = '$_schedulePrefix${formatDateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data as Map);
    final completionTime = DateTime.now().toLocal();
    map['status'] = 'completed';
    map['completed_at'] = completionTime.toIso8601String();
    map['duration_seconds'] = durationSeconds;
    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: map,
      source: WriteSource.schedSwap,
    );
  }

  /// Mark a workout day as skipped.
  Future<void> markSkipped(DateTime date) async {
    final key = '$_schedulePrefix${formatDateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data as Map);
    map['status'] = 'skipped';
    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: map,
      source: WriteSource.schedSwap,
    );
  }

  // ── Pause range (Phase D.4) ─────────────────────────────────────

  /// Pauses scheduled workouts for [days] consecutive dates starting at
  /// [startDate]. See original docstring on WorkoutScheduleService.
  Future<List<String>> pauseRange({
    required DateTime startDate,
    required int days,
    String? reason,
  }) async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final startMidnight =
        DateTime(startDate.year, startDate.month, startDate.day);
    if (startMidnight.isBefore(
        todayMidnight.subtract(const Duration(days: 1)))) {
      throw PausePlanException(
        'past_date',
        'Cannot pause dates older than yesterday (got ${formatDateKey(startDate)})',
      );
    }

    final box = _hive.workoutBox;
    final pausedAt = DateTime.now().toIso8601String();
    final pausedDates = <String>[];

    for (var i = 0; i < days; i++) {
      final d = startMidnight.add(Duration(days: i));
      final dateStr = formatDateKey(d);
      final key = '$_schedulePrefix$dateStr';
      final raw = box.get(key);
      if (raw is! Map) continue;

      final map = Map<String, dynamic>.from(raw);
      if (map['status'] == 'completed') continue;

      map['status'] = 'paused';
      map['paused_via'] = 'ai_coach';
      map['paused_at'] = pausedAt;
      if (reason != null && reason.trim().isNotEmpty) {
        map['pause_reason'] = reason.trim();
      }
      // audit-fixwave 2026-07-02 / F3 — route through the canonical writer
      // (like markCompleted / markSkipped) instead of a bare `box.put`. Pre-fix
      // a coach "pause my plan" wrote local Hive only: no cloud fan-out that
      // tick, no calendar/today/plan provider invalidation, no per-date mutex —
      // the Train UI stayed stale until a later rebuild and the pause was lost
      // on reinstall-before-next-sync. upsertScheduled fans out
      // `syncWorkoutData`, invalidates the readers, and takes the mutex.
      // `status='paused'` reaches cloud (scheduled_workouts has NO status CHECK,
      // verified live); `paused_via/paused_at/pause_reason` are local-only
      // annotations (no cloud columns, never synced by any path) and survive in
      // Hive via upsertScheduled's `...entry` spread.
      await WorkoutWriteService.instance.upsertScheduled(
        date: d,
        entry: map,
        source: WriteSource.schedSwap,
      );
      pausedDates.add(dateStr);
    }

    if (pausedDates.isEmpty) {
      throw PausePlanException(
        'no_schedules_in_range',
        'No scheduled workouts to pause in that date range',
      );
    }

    return pausedDates;
  }

  // ── Free-tier Re-do Week 4 (audit H9 / B1) ──────────────────────

  /// Copies the last week of the current Phase forward by 7 days.
  Future<void> redoWeek4() async {
    final readSvc = WorkoutScheduleReadService.instance;
    final planEnd = readSvc.getPlanEndDate();
    if (planEnd == null) return;

    final workoutBox = _hive.workoutBox;
    final week4Start = planEnd.subtract(const Duration(days: 6));
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final rollStart = todayMidnight.isAfter(planEnd)
        ? todayMidnight
        : planEnd.add(const Duration(days: 1));

    for (int offset = 0; offset < 7; offset++) {
      final sourceDate = week4Start.add(Duration(days: offset));
      final targetDate = rollStart.add(Duration(days: offset));
      final sourceKey = '$_schedulePrefix${formatDateKey(sourceDate)}';

      final raw = workoutBox.get(sourceKey);
      if (raw is! Map) continue;

      final copy = Map<String, dynamic>.from(raw);
      copy['date'] = formatDateKey(targetDate);
      copy['status'] = copy['type'] == 'rest' ? 'rest' : 'planned';
      copy['completed_at'] = null;
      copy['is_swapped'] = false;
      copy['original_date'] = null;

      await WorkoutWriteService.instance.upsertScheduled(
        date: targetDate,
        entry: copy,
        source: WriteSource.schedSwap,
      );
    }

    final newEnd = rollStart.add(const Duration(days: 6));
    await MigratedKey.write(_planEndKey, newEnd.toIso8601String());
  }

  // ── Free-tier "Hold the Line" (holdWeek — ship-dark replacement for redoWeek4) ──

  /// Re-entrancy guard mirroring `pro_phase_advance._advanceInFlight`. NOTE: it
  /// does NOT cover holdWeek-vs-PRO-advance (that path guards a SEPARATE bool) —
  /// safe by tier-exclusivity: advance is PRO-only, the hold triggers are
  /// free-tier surfaces.
  static bool _holdInFlight = false;

  /// Materialize a fresh training week that CONTAINS today (backdated to THIS
  /// week's Monday), sourced from the phase's canonical **Peak** week — or the
  /// **deload** week every 4th hold — at FLAT loads (a verbatim copy, no decay:
  /// free maintains, PRO progresses). Extends `plan_end` so the phase is no
  /// longer expired, and durably pushes the fresh `plan_json` so the hold
  /// survives a reinstall.
  ///
  /// Ship-dark behind `enable_hold_weeks` (default OFF) — the plan-expired
  /// triggers call [redoWeek4] when the flag is OFF. Design contract +
  /// ×2-review record: `docs/plan-reviews/hold-mechanic.md`; diagnose
  /// `docs/diagnoses/2026-07-21-free-tier-hold-mechanic-<id>.md`.
  Future<void> holdWeek() async {
    if (_holdInFlight) return; // check+set with no await between (mutex)
    _holdInFlight = true;
    try {
      final readSvc = WorkoutScheduleReadService.instance;
      final planStart = readSvc.getPlanStartDate();
      final planEnd = readSvc.getPlanEndDate();
      if (planStart == null || planEnd == null) return;

      // "Backdate to Monday always": the hold occupies THIS week (Mon-Sun),
      // using the SAME raw-weekday normalizer `plan_start` was set with (NOT
      // `mondayOfIst`) so `(rollStart - plan_start)` stays a whole number of
      // weeks. `nowWall()` is seam-aware (dev time-travel / year-sim).
      var start = readSvc.normalizeToMonday(nowWall());
      // Defensive: never overwrite the live phase window. The expired-only
      // button gate already guarantees today > plan_end, but a stray caller
      // must still not clobber weeks 1-4. plan_end is a Sunday by construction,
      // so (plan_end + 1) normalizes to the next Monday.
      if (!start.isAfter(planEnd)) {
        start = readSvc.normalizeToMonday(planEnd.add(const Duration(days: 1)));
      }
      final rollStart = start;

      // Ordinal N = (max hold_ordinal among rows dated < rollStart) + 1, else 1.
      // Excluding rows AT rollStart makes a crash-partial retry idempotent
      // (rows stamped but plan_end not yet extended recompute to the same N and
      // overwrite cleanly — no deload-cadence drift).
      final n = _nextHoldOrdinal(rollStart);

      // Every 4th hold sources the deload week (plan_start + 21..27); else the
      // Peak week (plan_start + 14..20). NEVER plan_end-derived (redoWeek4's bug
      // was copying the trailing deload week every time).
      final deload = n % 4 == 0;
      final sourceWeekStart =
          planStart.add(Duration(days: deload ? 21 : 14));

      for (int offset = 0; offset < 7; offset++) {
        final sourceDate = sourceWeekStart.add(Duration(days: offset));
        final targetDate = rollStart.add(Duration(days: offset));
        final sourceKey = '$_schedulePrefix${formatDateKey(sourceDate)}';

        final raw = _hive.workoutBox.get(sourceKey);
        if (raw is! Map) continue;

        final copy = Map<String, dynamic>.from(raw);
        copy['date'] = formatDateKey(targetDate);
        // The push maps cloud `week_number` <- entry['week'] (sync_workout.dart),
        // so stamp 'week' (NOT 'week_number') — else the copied Peak 'week':3
        // would push 3. Schema-safe (>4, nullable int, no CHECK, no EF reader).
        copy['week'] = 4 + n;
        // Hive-map + plan_json ONLY (no cloud column — kept out of the push
        // field-set so it can't 400). Drives the deload cadence + the H-chip.
        copy['is_hold'] = true;
        copy['hold_ordinal'] = n;
        copy['status'] = copy['type'] == 'rest' ? 'rest' : 'planned';
        copy['completed_at'] = null;
        copy['is_swapped'] = false;
        copy['original_date'] = null;
        // 'phase' is deliberately NOT re-stamped — the verbatim copy already
        // carries the source week's phase (= current); an explicit stamp would
        // trip legacy `bucketPastRows` carry-forward and collapse a legacy
        // multi-phase user's real history (free-tier-hold-findings P1).

        await WorkoutWriteService.instance.upsertScheduled(
          date: targetDate,
          entry: copy,
          source: WriteSource.schedSwap,
        );
      }

      final newEnd = rollStart.add(const Duration(days: 6));
      await MigratedKey.write(_planEndKey, newEnd.toIso8601String());

      // FOB-5 (OI-60): holds were UNOBSERVABLE. The five phase_1_day_29_*
      // events have zero consumers repo-wide, so holds-taken / hold->convert /
      // hold->churn were all unmeasurable — and the free-tier retention thesis
      // rests on this mechanic.
      //
      // Its consumer is REAL, not aspirational: migration 120 adds
      // holds_started_today / holds_started_7d / holders_total to
      // founder_metrics_engagement(), and admin-dashboard-data/index.ts:255
      // spreads that row wholesale, so these reach the founder dashboard with
      // NO Edge Function redeploy. An event with no consumer is what FOB-5
      // filed in the first place.
      //
      // Placed HERE, at the last statement of the successful path, rather than
      // after the durability push below: every earlier exit (the no-plan early
      // return, any throw) skips it, so the event cannot claim a hold that was
      // not materialized. A later push failure does not falsify it either —
      // the hold IS committed locally (offline-first) at this point.
      //
      // Fire-and-forget by construction: AppEventsService.log never awaits and
      // drops a failed insert, so telemetry adds no await inside the mutex.
      //
      // The try/catch is NOT redundant belt-and-braces. `log` not throwing is a
      // property of a DIFFERENT file (app_events_service.dart) that nothing
      // pins, and this call sits inside the try whose `finally` only clears the
      // mutex — a sync throw here would propagate out of holdWeek AFTER the
      // hold is committed to Hive, skipping the durability push below and
      // surfacing a materialized hold to the caller as a failure. Three lines
      // make that impossible locally instead of assuming it remotely.
      try {
        AppEventsService.instance.log('hold_week_started', metadata: {
          'ordinal': n,
        });
      } catch (_) {
        // Telemetry must never be able to fail a committed hold.
      }
    } finally {
      _holdInFlight = false;
    }

    // Durability (AFTER releasing the mutex — H4 idempotency covers a
    // concurrent-after-release call): the coalesced `syncWorkoutData` fan-out
    // does NOT push `plan_json`, so without this the extended plan_end +
    // exercise-rich hold rows + hold_ordinal wouldn't reach cloud until the
    // next weeklyFullSync (≤24h) — a hold→reinstall-before-launch would
    // collapse. `pushWorkoutPlanForSyncDomain` -> `_syncWorkoutPlan` is
    // self-catching (offline → no-op, retried next full sync); the extra
    // try/catch guards the `_ensureSessionOpen` await OUTSIDE that catch so a
    // push hiccup can never surface a locally-committed hold as a failure.
    // Reached ONLY on a successful materialization — an early return (no plan)
    // or a throw exits via the `finally` above without reaching here.
    try {
      await SyncService.instance.pushWorkoutPlanForSyncDomain();
    } catch (e, st) {
      // Committed locally (offline-first); cloud catches up on next full sync.
      // Telemetry pair — `_ensureSessionOpen` sits OUTSIDE `_syncWorkoutPlan`'s
      // own catch, so record here too (B-pass P2, observability-first §4.10).
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'hold_week_durability_push'));
    }
  }

  /// Next hold ordinal: `max(hold_ordinal among rows dated < [rollStart]) + 1`,
  /// else 1. Scans the Hive `schedule_*` rows for `is_hold == true`; excluding
  /// rows AT/after `rollStart` keeps a crash-partial retry idempotent.
  int _nextHoldOrdinal(DateTime rollStart) {
    var maxOrdinal = 0;
    final box = _hive.workoutBox;
    for (final key in box.keys) {
      if (key is! String || !key.startsWith(_schedulePrefix)) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (raw['is_hold'] != true) continue;
      final dateStr = raw['date'];
      if (dateStr is! String) continue;
      final d = DateTime.tryParse(dateStr);
      if (d == null || !d.isBefore(rollStart)) continue;
      final ord = raw['hold_ordinal'];
      final ordInt = ord is int ? ord : (ord is num ? ord.toInt() : 0);
      if (ordInt > maxOrdinal) maxOrdinal = ordInt;
    }
    return maxOrdinal + 1;
  }

  // ── Week-Copy ────────────────────────────────────────────────────

  /// Copy all schedule entries from [sourceWeek] to [targetWeek].
  Future<void> copyWeek({
    required int sourceWeek,
    required int targetWeek,
    required String planStartDateIso,
  }) async {
    if (sourceWeek == targetWeek) return;
    final planStart = DateTime.tryParse(planStartDateIso) ?? DateTime.now();
    final sourceWeekStart = planStart.add(Duration(days: (sourceWeek - 1) * 7));
    final targetWeekStart = planStart.add(Duration(days: (targetWeek - 1) * 7));
    final workoutBox = _hive.workoutBox;

    for (int day = 0; day < 7; day++) {
      final sourceDate = sourceWeekStart.add(Duration(days: day));
      final targetDate = targetWeekStart.add(Duration(days: day));
      final sourceDateKey = formatDateKey(sourceDate);
      final targetDateKey = formatDateKey(targetDate);

      final sourceEntry = workoutBox.get('$_schedulePrefix$sourceDateKey');
      if (sourceEntry == null) continue;

      final newEntry = Map<String, dynamic>.from(sourceEntry as Map)
        ..['date'] = targetDateKey
        ..['week'] = targetWeek
        ..['status'] = (sourceEntry['type'] == 'rest') ? 'rest' : 'planned'
        ..['completed_at'] = null
        ..['is_swapped'] = false
        ..['original_date'] = null;

      await WorkoutWriteService.instance.upsertScheduled(
        date: targetDate,
        entry: newEntry,
        source: WriteSource.schedSwap,
      );
    }
  }
}
