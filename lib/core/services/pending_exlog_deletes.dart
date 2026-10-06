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

  /// Queues an exercise log for deletion by its natural key. A no-op if this
  /// exact (workoutLogId, exerciseId, setNumber) triple is already queued.
  static Future<void> add({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
  }) async {
    // GROWABLE copy — read() can return the `const []` literal (nothing
    // queued yet on a fresh box), and .add() below would throw
    // UnsupportedError against it. Caught live by this file's own test
    // (test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart) on
    // the very first delete for a fresh user; PendingTemplateDeletes shares
    // this exact `return const []` shape and is NOT independently fixed
    // here — out of scope, filed separately.
    final list = List<Map<String, dynamic>>.of(read());
    final alreadyQueued = list.any((e) =>
        e['workout_log_id'] == workoutLogId &&
        e['exercise_id'] == exerciseId &&
        e['set_number'] == setNumber);
    if (alreadyQueued) return;
    list.add({
      'workout_log_id': workoutLogId,
      'exercise_id': exerciseId,
      'set_number': setNumber,
    });
    await HiveService.instance.userBox.put(_key, list);
  }

  /// Removes the entry matching this exact natural key -- called once the
  /// drain confirms the cloud tombstone UPSERT raised no exception.
  static Future<void> remove({
    required String workoutLogId,
    required String exerciseId,
    required int setNumber,
  }) async {
    final list = List<Map<String, dynamic>>.of(read())
      ..removeWhere((e) =>
          e['workout_log_id'] == workoutLogId &&
          e['exercise_id'] == exerciseId &&
          e['set_number'] == setNumber);
    await HiveService.instance.userBox.put(_key, list);
  }
}
