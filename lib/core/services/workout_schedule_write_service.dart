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

import 'hive_service.dart';
import 'migrated_key.dart';
import 'singleton_lifecycle_registry.dart';
import 'workout_schedule_read_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';

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
