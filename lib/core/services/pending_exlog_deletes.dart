import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';

/// OI-246 / L1a-2 U4 — the queue of exercise-log deletes not yet confirmed
/// against the cloud. Written by `WorkoutWriteService.deleteLog` (and, for the
/// SOURCE day, `moveExerciseLogs`) at local-delete time; drained (removed) by
/// `SyncService._drainPendingExlogDeletes` on every exercise-log push, which
/// sends ONE time-filtered UPDATE per entry: every set count of
/// (workout_log_id, exercise_id) written at or before the entry's
/// `deleted_at_ms` is tombstoned, anything written after it survives ("the
/// newest action wins"). Because that filter protects a re-log by itself, a
/// re-log does NOT cancel a timed entry (a cancel would also keep the OLDER
/// version, possibly at a different set count, alive in the cloud); only an
/// entry queued by an app build before L1a-2 (no time) is cancelled by a
/// re-log, since its cutoff would be "the drain moment".
///
/// Unlike `PendingTemplateDeletes`, every entry always carries its FULL
/// natural key at queue time -- `deleteLog` reads the exact Hive row being
/// deleted, so `workoutLogId`/`exerciseId`/`setNumber` are all known
/// immediately. No id-resolution step is needed (contrast
/// `PendingTemplateDeletes`'s null-`id`/name-resolve case, which exists only
/// because a legacy-keyed template's cloud id is genuinely unknown to
/// `WorkoutWriteService`).
///
/// Stored directly in `userBox` (not through a `MigratedKey`-style shared
/// namespace) -- small, user-scoped by the box's own cross-account guard,
/// never read by any other feature. A queued entry survives app restarts and
/// offline periods. It does NOT survive logout -- `userBox` is cleared on
/// sign-out, so an undrained delete is lost on that device, same
/// already-tracked residual as `PendingTemplateDeletes` (OI-253).
class PendingExlogDeletes {
  PendingExlogDeletes._();

  static const String _key = 'pending_exlog_deletes';

  /// The queued deletes, each `{'workout_log_id': ..., 'exercise_id': ...,
  /// 'set_number': ...}` -- the exact natural key
  /// `uniq_wle_user_wlog_ex_set` targets.
  static List<Map<String, dynamic>> read() {
    final raw = HiveService.instance.userBox.get(_key);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) =>
            m['workout_log_id'] is String &&
            m['exercise_id'] is String &&
            m['set_number'] is int)
        // A malformed time reads as "no time" (a pre-L1a-2 entry), never as a
        // cast failure that would stop every exercise-log push.
        .map((m) => <String, dynamic>{
              for (final e in m.entries)
                if (e.key != 'deleted_at_ms' || e.value is int) e.key: e.value,
            })
        .toList();
  }

  /// Queues an exercise log for deletion by its natural key and records WHEN
  /// the user deleted it (`deleted_at_ms`, L1a-2 U4): the drain tombstones only
  /// versions written BEFORE that moment, so a re-log made after the delete
  /// (here or on another device) survives. Queuing the same triple again
  /// REPLACES the earlier entry with the later time (a re-queued delete is a
  /// newer action).
  static Future<void> add({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
    int? deletedAtMs,
  }) async {
    // GROWABLE copy -- read() can return the `const []` literal (nothing
    // queued yet on a fresh box), and .add() below would throw
    // UnsupportedError against it.
    final list = List<Map<String, dynamic>>.of(read())
      ..removeWhere((e) =>
          e['workout_log_id'] == workoutLogId &&
          e['exercise_id'] == exerciseId &&
          e['set_number'] == setNumber);
    list.add({
      'workout_log_id': workoutLogId,
      'exercise_id': exerciseId,
      'set_number': setNumber,
      'deleted_at_ms': deletedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    });
    await HiveService.instance.userBox.put(_key, list);
  }

  /// Cancels the queued deletes for this exercise on this workout day that
  /// carry NO delete time (queued by an app build before L1a-2): their cutoff
  /// would be the drain moment, which would tombstone the version being
  /// written now. A TIMED entry is left alone on purpose -- the drain's
  /// `completed_at <= deleted_at_ms` filter already spares a newer version,
  /// and keeping the entry is what tombstones the OLDER cloud versions (any
  /// set count). The key is the exact queue key [add] stores: `workoutLogId`
  /// = the day's UUID v5 id, `exerciseName` = the exercise_id the push uses.
  /// Never throws: the caller is a log/move write that has already changed
  /// Hive, and a queue failure must not fail it.
  static Future<void> cancelFor({
    required String workoutLogId,
    required String exerciseName,
  }) async {
    try {
      final all = read();
      final kept = all
          .where((e) => !(e['workout_log_id'] == workoutLogId &&
              e['exercise_id'] == exerciseName &&
              e['deleted_at_ms'] == null))
          .toList();
      if (kept.length == all.length) return;
      await HiveService.instance.userBox.put(_key, kept);
    } catch (e, st) {
      debugPrint('[PendingExlogDeletes.cancelFor] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'pending_exlog_deletes_cancel_failed'));
    }
  }

  /// True while this exact queued entry (same triple AND same `deleted_at_ms`)
  /// is still queued. The drain asks this IMMEDIATELY before its cloud UPDATE,
  /// because passes are not serialised and [cancelFor] may have run since the
  /// drain took its copy of the queue.
  static bool isQueued({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
    int? deletedAtMs,
  }) =>
      read().any((e) =>
          e['workout_log_id'] == workoutLogId &&
          e['exercise_id'] == exerciseId &&
          e['set_number'] == setNumber &&
          e['deleted_at_ms'] == deletedAtMs);

  /// Removes the entry matching this exact natural key AND delete time --
  /// called once the drain's cloud write returned. A newer re-queue of the
  /// same triple carries a later `deleted_at_ms`, so it is NOT removed by a
  /// drain that started from the older entry.
  static Future<void> remove({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
    int? deletedAtMs,
  }) async {
    final list = List<Map<String, dynamic>>.of(read())
      ..removeWhere((e) =>
          e['workout_log_id'] == workoutLogId &&
          e['exercise_id'] == exerciseId &&
          e['set_number'] == setNumber &&
          e['deleted_at_ms'] == deletedAtMs);
    await HiveService.instance.userBox.put(_key, list);
  }

  /// Records that the drain's UPDATE touched no row for this entry. The entry
  /// is KEPT for one more pass: a creating push that was already on the wire
  /// when the user deleted may land after the UPDATE (the UPDATE cannot create
  /// a tombstone the way the old upsert could), and the next pass's UPDATE
  /// then tombstones it. A second empty pass removes the entry.
  static Future<void> markEmptyPass({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
    int? deletedAtMs,
  }) async {
    final list = read();
    for (final e in list) {
      if (e['workout_log_id'] == workoutLogId &&
          e['exercise_id'] == exerciseId &&
          e['set_number'] == setNumber &&
          e['deleted_at_ms'] == deletedAtMs) {
        e['empty_pass'] = true;
      }
    }
    await HiveService.instance.userBox.put(_key, list);
  }
}
