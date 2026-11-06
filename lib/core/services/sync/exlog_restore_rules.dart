// lib/core/services/sync/exlog_restore_rules.dart
//
// Pure rules for restoring exercise logs from the cloud (plan
// docs/plans/coach-history-correctness-client.md, unit U2; diagnose
// related_bugs e6a2d4 / oi83). No Hive, no network: `_restoreExerciseLogs`
// (`sync_workout.dart`) feeds these the cloud rows and acts on the answer.
//
// The cloud keeps, per (workout_log_id, exercise_id), ONE live summary row
// (migration 155 `single_live`) plus per-set rows in `workout_log_sets`.
// Before this file the restore kept the FIRST row it saw per group (the read
// is newest-first, so the newest write won whatever its set count), joined
// every per-set row (including sets above the summary's count) and dated the
// restored log by `completed_at`, which is the WRITE time, not the workout day.

import 'package:icanbefitter/core/services/sync_service.dart';

/// The IST day that owns a cloud `workout_log_id`, by inverting the app's own
/// derivation (`SyncService.workoutLogIdForDate` = UUID v5 of
/// `workout_<IST date>`) over a fixed horizon: 2020-01-01 up to today + 400
/// days (the same horizon as the server readers, so a row the coach moved
/// FORWARD still resolves). `completed_at` is the write time, so it is only
/// the fallback.
class ExlogWorkoutDays {
  ExlogWorkoutDays._();

  static const String firstDay = '2020-01-01';
  static const int futureDays = 400;

  static String? _builtThrough;
  static Map<String, String> _byLogId = const {};

  static String _ymd(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// `workout_log_id -> 'YYYY-MM-DD'`, built once per IST day.
  /// [istToday] is the caller's IST date key (`istDateStr(DateTime.now())`).
  static Map<String, String> forToday(String istToday) {
    final end = _ymd(
      DateTime.utc(
        int.parse(istToday.substring(0, 4)),
        int.parse(istToday.substring(5, 7)),
        int.parse(istToday.substring(8, 10)),
      ).add(const Duration(days: futureDays)),
    );
    if (_builtThrough == end) return _byLogId;
    final out = <String, String>{};
    var d = DateTime.utc(2020, 1, 1);
    final last = DateTime.parse('${end}T00:00:00Z');
    while (!d.isAfter(last)) {
      final ymd = _ymd(d);
      out[SyncService.workoutLogIdForDate(ymd)] = ymd;
      d = d.add(const Duration(days: 1));
    }
    _byLogId = out;
    _builtThrough = end;
    return out;
  }

  /// The IST midnight of [ymd] as an instant. Built from `DateTime.utc` and
  /// shifted back 5h30, never from a local `DateTime(y, m, d)`: on a device
  /// east of IST the local constructor lands on the PREVIOUS IST day.
  static DateTime istMidnight(String ymd) => DateTime.utc(
        int.parse(ymd.substring(0, 4)),
        int.parse(ymd.substring(5, 7)),
        int.parse(ymd.substring(8, 10)),
      ).subtract(const Duration(hours: 5, minutes: 30));
}

/// Picks the rows to restore: live (not tombstoned) and ONE per
/// `(workout_log_id, exercise_id)` - the one with the highest `set_number`
/// (the set COUNT; after migration 155 there is one live row, the selector
/// replaces iteration order). Ties break on the later `completed_at`, then
/// the later `created_at`, then the later `id`, so the choice is
/// deterministic whatever order the pages arrived in.
List<Map<String, dynamic>> selectLiveSummaries(Iterable<dynamic> rows) {
  final best = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final raw in rows) {
    final m = Map<String, dynamic>.from(raw as Map);
    if (m['deleted_at'] != null) continue;
    final key = '${m['workout_log_id'] ?? ''}|${m['exercise_id'] ?? m['exercise_name'] ?? ''}';
    final cur = best[key];
    if (cur == null) {
      best[key] = m;
      order.add(key);
    } else if (_beats(m, cur)) {
      best[key] = m;
    }
  }
  return [for (final k in order) best[k]!];
}

bool _beats(Map<String, dynamic> a, Map<String, dynamic> b) {
  int c = _count(a).compareTo(_count(b));
  if (c != 0) return c > 0;
  c = _instant(a['completed_at']).compareTo(_instant(b['completed_at']));
  if (c != 0) return c > 0;
  c = _instant(a['created_at']).compareTo(_instant(b['created_at']));
  if (c != 0) return c > 0;
  return _s(a['id']).compareTo(_s(b['id'])) > 0;
}

/// A timestamp as an instant, so two spellings of one moment (`+00:00`,
/// `Z`, `+05:30`) compare by time, not by text. Unparseable sorts first.
int _instant(Object? v) {
  final d = v is String ? DateTime.tryParse(v) : null;
  return d == null ? -1 : d.microsecondsSinceEpoch;
}

int _count(Map<String, dynamic> m) => (m['set_number'] as num?)?.toInt() ?? 0;
String _s(Object? v) => v is String ? v : '';

/// The per-set rows to join under a summary of [count] sets: sort by
/// `set_number` and take the first [count]. A rank cut, not a
/// `set_number <= count` filter, so a gapped legacy {1,2,4} at count 3 keeps
/// set 4 (the next push sends `summarySetCount = sets.length` and would
/// otherwise delete it in the cloud) while an over-count 1..7 at count 4 is
/// trimmed to 1..4. `count <= 0` means "unknown": take all.
List<Map<String, dynamic>> rankedSetRows(
    List<Map<String, dynamic>> sets, int count) {
  final sorted = List<Map<String, dynamic>>.of(sets)
    ..sort((a, b) => ((a['set_number'] as num?)?.toInt() ?? 0)
        .compareTo((b['set_number'] as num?)?.toInt() ?? 0));
  if (count <= 0 || sorted.length <= count) return sorted;
  return sorted.sublist(0, count);
}

/// L1a-3 (B-pass B F3): true only when the push bundle built from a RESTORED
/// log would put exactly the cloud's content back, so recording its
/// fingerprint can never hide a cloud row that differs (gapped per-set
/// numbers the push renumbers, a summary count the per-set rows do not back,
/// legacy NULL columns the push fills, a different exercise_id / day id,
/// a differently formatted completed_at). When false the row simply pushes
/// once, as before.
bool restoredBundleEqualsCloud({
  required Map<String, dynamic> summary,
  required List<Map<String, dynamic>> sets,
  required Map<String, dynamic> cloudSummary,
  required List<dynamic> restoredSets,
}) {
  num? n(Object? v) => v is num ? v : null;
  if (summary['workout_log_id'] != cloudSummary['workout_log_id']) return false;
  final cloudExercise = cloudSummary['exercise_id'] ?? cloudSummary['exercise_name'];
  if (summary['exercise_id'] != cloudExercise) return false;
  if (cloudSummary['logging_type'] == null) return false;
  if (n(summary['set_number']) != n(cloudSummary['set_number'])) return false;
  if ((n(summary['duration_seconds']) ?? 0) !=
      (n(cloudSummary['duration_seconds']) ?? 0)) {
    return false;
  }
  if (summary['completed_at'] != cloudSummary['completed_at']) return false;
  final restored = [
    for (final r in restoredSets)
      if (r is Map) n(r['set_number'])?.toInt()
  ];
  final pushed = [for (final r in sets) n(r['set_number'])?.toInt()];
  if (restored.length != pushed.length) return false;
  for (var i = 0; i < pushed.length; i++) {
    if (restored[i] != pushed[i]) return false;
  }
  return true;
}
