import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';
import 'sync_service.dart';
import 'write_result.dart';

/// The ONE writer for workout_logs / workout_log_exercises /
/// workout_log_sets. All Hive `exlog_*`, `wlog_*`, and `schedule_<date>`
/// mutations flow through this service.
///
/// Per-(date, exerciseName) mutex serializes concurrent writes — two
/// simultaneous logExercise calls for the same exercise will merge
/// their sets into a single Hive entry rather than racing.
///
/// Hive key scheme (post Plan A):
/// - `exlog_<istDateStr>_<hash(name)>`  — deterministic; one row per
///   (date, exerciseName).
/// - `wlog_<istDateStr>`                — workout-level summary.
/// - `schedule_<istDateStr>`            — schedule entry.
///
/// Cloud sync is 3-tier (writes 1 + 1 + N rows):
/// - `workout_logs`             (1 per date)
/// - `workout_log_exercises`    (1 per (date, exerciseName))
/// - `workout_log_sets`         (N per (date, exerciseName) — one per
///                               ExerciseSet)
///
/// Cloud sync fires fire-and-forget after the Hive write succeeds.
class WorkoutWriteService {
  WorkoutWriteService._();
  static final WorkoutWriteService instance = WorkoutWriteService._();

  /// Per-key mutex. Key format: `<istDateStr>::<exerciseName>` for
  /// per-exercise methods, `<istDateStr>` for schedule-only methods.
  final Map<String, Completer<void>> _locks = {};

  /// 60-second dedup window for per-set duplicate detection.
  static const int kDedupWindowMs = 60000;

  /// Provider invalidation batch fired after every successful write.
  /// Caller injects [ref] when running under Riverpod; pure-Hive
  /// callers (tests, headless paths) pass null.
  void Function(WidgetRef ref)? onInvalidate;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  Future<WriteResult> logExercise({
    required DateTime date,
    required String exerciseName,
    required List<ExerciseSet> sets,
    String? notes,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('logExercise — implemented in Task A-4');
  }

  Future<WriteResult> markCompleted({
    required DateTime date,
    required String workoutName,
    required int durationSec,
    int? rpe,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('markCompleted — implemented in Task A-6');
  }

  Future<WriteResult> upsertScheduled({
    required DateTime date,
    required Map<String, dynamic> entry,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('upsertScheduled — implemented in Task A-7');
  }

  Future<WriteResult> rescheduleDay({
    required DateTime fromDate,
    required DateTime toDate,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('rescheduleDay — implemented in Task A-8');
  }

  Future<WriteResult> regenerateWeek({
    required DateTime fromDate,
    required Map<String, dynamic> params,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('regenerateWeek — implemented in Task A-8');
  }

  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('editLog — implemented in Task A-9');
  }

  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
    required WriteSource source,
    WidgetRef? ref,
  }) async {
    throw UnimplementedError('deleteLog — implemented in Task A-9');
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers (used by methods implemented in later tasks)
  // ─────────────────────────────────────────────────────────────

  /// IST-derived YYYY-MM-DD string. Public for callers that already
  /// have an IST-aware DateTime and need the same hashing rule.
  static String istDateStr(DateTime dt) {
    // Convert to IST regardless of input zone.
    final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Deterministic Hive key for an exercise log.
  static String exlogKey(DateTime date, String exerciseName) {
    final d = istDateStr(date);
    final h = exerciseName.toLowerCase().trim().hashCode;
    return 'exlog_${d}_$h';
  }

  /// Deterministic Hive key for a workout-level summary.
  static String wlogKey(DateTime date) => 'wlog_${istDateStr(date)}';

  /// Deterministic Hive key for a schedule entry.
  static String scheduleKey(DateTime date) =>
      'schedule_${istDateStr(date)}';

  /// Acquire mutex for the given key. Returns the completer the
  /// caller MUST `complete()` in a finally block.
  Future<Completer<void>> _acquireLock(String key) async {
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    final c = Completer<void>();
    _locks[key] = c;
    return c;
  }

  void _releaseLock(String key, Completer<void> c) {
    _locks.remove(key);
    if (!c.isCompleted) c.complete();
  }
}
