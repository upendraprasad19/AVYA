import 'hive_service.dart';

/// OI-246 — the queue of exercise-log deletes not yet confirmed against the
/// cloud. Written by `WorkoutWriteService.deleteLog` at local-delete time;
/// drained (removed) by `SyncService._drainPendingExlogDeletes` on every
/// exercise-log push, which UPSERTs a tombstone for each queued natural key.
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

  /// Cancels every queued delete for this exercise on this workout day, at
  /// any set count -- called when the exercise is logged (or moved) back onto
  /// that day, so a stale delete cannot tombstone the new version. The key is
  /// the exact queue key [add] stores: `workoutLogId` = the day's UUID v5 id,
  /// `exerciseName` = the exercise_id the push uses (the exercise name).
  static Future<void> cancelFor({
    required String workoutLogId,
    required String exerciseName,
  }) async {
    final all = read();
    final kept = all
        .where((e) =>
            !(e['workout_log_id'] == workoutLogId &&
                e['exercise_id'] == exerciseName))
        .toList();
    if (kept.length == all.length) return;
    await HiveService.instance.userBox.put(_key, kept);
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
}
