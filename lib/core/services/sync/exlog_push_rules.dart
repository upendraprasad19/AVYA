// lib/core/services/sync/exlog_push_rules.dart
//
// Pure rules for PUSHING an exercise log (plan
// docs/plans/coach-history-correctness-client.md, unit U3; diagnose
// related_bugs e6a2d4, APK Test #12.7). No Hive, no network.

/// The `completed_at` an exercise-log push sends: the LATEST local write.
///
/// The shared resolver (`SyncService._resolveCompletedAtOrNull`) returns
/// `created_at` before `updated_at_ms`, and restore stamps `created_at` with
/// the cloud's old `completed_at`, so an edit or move made AFTER a
/// cross-device delete would push a time from before that delete and the
/// delete-time-filtered drain (U4) would tombstone the newer version. So when
/// the row carries `updated_at_ms`, send `max(resolved, updated_at_ms)`.
/// The resolver itself is unchanged (it also feeds `workout_logs`).
///
/// Readers take the DAY from `workout_log_id`, never from this value.
String latestWriteIso(String resolvedIso, Object? updatedAtMs) {
  final ms = updatedAtMs is num ? updatedAtMs.toInt() : 0;
  if (ms <= 0) return resolvedIso;
  final resolved = DateTime.tryParse(resolvedIso);
  final updated = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  if (resolved == null || updated.isAfter(resolved)) {
    return updated.toIso8601String();
  }
  return resolvedIso;
}

/// Per-set numbering made unique. If two entries carry the same explicit
/// `set_number` (a collision merge appends one day's sets after another's),
/// the upsert key `(user, workout_log_id, exercise_id, set_number)` would
/// collapse them into one row, so renumber the WHOLE list 1..N in list order.
/// No duplicates (including gapped legacy {1,2,4}) means the numbers are kept
/// as they are.
List<Map<String, dynamic>> uniquePerSetNumbers(
    List<Map<String, dynamic>> sets) {
  final seen = <int>{};
  var duplicated = false;
  for (final s in sets) {
    final n = (s['set_number'] as num?)?.toInt();
    if (n == null) continue;
    if (!seen.add(n)) duplicated = true;
  }
  if (!duplicated) return sets;
  return [
    for (var i = 0; i < sets.length; i++)
      {...sets[i], 'set_number': i + 1},
  ];
}
