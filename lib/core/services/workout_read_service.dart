import '../utils/ist_date.dart';
import 'hive_service.dart';

/// Canonical READ service for workout-domain Hive surfaces.
///
/// Mirrors the writer-side `WorkoutWriteService` (canonical writer for
/// every `exlog_*`/`wlog_*`/`schedule_*` row). The READ side previously
/// had no canonical home — the same semantic was re-implemented in
/// `WorkoutRepository.loadAllExercisePRs`, `train_screen._bestPerSetReps`,
/// and inline at other callsites. The PR-cumulative-bug surfaced on
/// APK +27 (founder install 2026-05-16) was a direct consequence:
/// two readers diverged on the per-set MAX semantic.
///
/// closes-OI: OI-02 (architecture-gap — no symmetric ReadServices)
/// closes-OI: OI-08 (PR per-set MAX semantic duplicated across 2 files)
///
/// Hive field-name contract (READ side — must agree with the writer
/// contract documented in CLAUDE.md §15 "Hive field-name contract"):
///
/// `exlog_*` rows (canonical, from `WorkoutWriteService.logExercise`):
///   - `exercise_name`     : String
///   - `date`              : String (IST `YYYY-MM-DD`)
///   - `sets[]`            : List<Map> — canonical per-set array
///     - `weight_kg`       : num
///     - `reps`            : num
///     - `duration_sec`    : num (canonical) / `duration_seconds` (legacy alias)
///   - `set_number`        : int (TOTAL completed sets — not "which set")
///   - `reps_completed`    : int (SUM across sets)
///   - `weight_kg`         : num (MAX across sets — top-level convenience)
///   - `duration_seconds`  : int (SUM across sets, only timed/cardio)
///   - `logging_type`      : String
///   - `is_pr`             : bool
///   - `workout_log_id`    : String (Test #12 / Task A-3, may be null on
///                            legacy rows)
///
/// Per-set MAX semantic owner: this service. The top-level
/// `reps_completed` / `duration_seconds` are SUM (Test #6 writer
/// contract); reading them as "best per-set" is the bug class that
/// shipped on +27 (Push Up "100 reps" / Hanging Leg Raise "85 reps").
class WorkoutReadService {
  WorkoutReadService._();
  static final WorkoutReadService instance = WorkoutReadService._();

  // ─────────────────────────────────────────────────────────────
  //  Per-set semantic primitives
  //
  //  These three methods are the canonical "best per-set" extractors.
  //  Every reader that needs the BEST single-set value for a logged
  //  exercise must delegate here — never read top-level `reps_completed`
  //  or `duration_seconds` (those are SUM) as "best per-set".
  // ─────────────────────────────────────────────────────────────

  /// Returns the MAX reps across the per-set `sets[]` array in [log].
  ///
  /// Falls back to top-level `reps_completed` ONLY when:
  ///   (a) `sets[]` is missing or empty AND
  ///   (b) `set_number` (or legacy `sets_completed`) <= 1 — a
  ///       legitimate single-set legacy row.
  /// Multi-set legacy rows without `sets[]` are unrecoverable — returns
  /// 0 rather than surface SUM as "best per-set".
  ///
  /// Used by: `WorkoutRepository.loadAllExercisePRs`,
  /// `train_screen.dart` expanded view, `pr_snapshot.dart`.
  static int bestPerSetReps(Map<String, dynamic> log) {
    final setsRaw = log['sets'];
    if (setsRaw is List && setsRaw.isNotEmpty) {
      var best = 0;
      for (final s in setsRaw) {
        if (s is Map) {
          final r = (s['reps'] as num?)?.toInt() ?? 0;
          if (r > best) best = r;
        }
      }
      if (best > 0) return best;
    }
    final setCount = (log['set_number'] as num?)?.toInt() ??
        (log['sets_completed'] as num?)?.toInt() ??
        1;
    if (setCount <= 1) {
      return (log['reps_completed'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Returns the MAX duration (seconds) across the per-set `sets[]`
  /// array in [log]. Reads both `duration_sec` (canonical) and
  /// `duration_seconds` (legacy restore-path alias) per-set.
  ///
  /// Falls back to top-level `duration_seconds` ONLY for single-set
  /// legacy rows. Same single-set gate as [bestPerSetReps].
  static int bestPerSetDuration(Map<String, dynamic> log) {
    final setsRaw = log['sets'];
    if (setsRaw is List && setsRaw.isNotEmpty) {
      var best = 0;
      for (final s in setsRaw) {
        if (s is Map) {
          final d = (s['duration_sec'] as num?)?.toInt() ??
              (s['duration_seconds'] as num?)?.toInt() ??
              0;
          if (d > best) best = d;
        }
      }
      if (best > 0) return best;
    }
    final setCount = (log['set_number'] as num?)?.toInt() ??
        (log['sets_completed'] as num?)?.toInt() ??
        1;
    if (setCount <= 1) {
      return (log['duration_seconds'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Returns the MAX weight (kg) across the per-set `sets[]` array in
  /// [log]. Pass-through: top-level `weight_kg` is already MAX per the
  /// writer contract, but `sets[]` is preferred when present so readers
  /// don't depend on the writer's denormalisation.
  static double bestPerSetWeight(Map<String, dynamic> log) {
    final setsRaw = log['sets'];
    if (setsRaw is List && setsRaw.isNotEmpty) {
      var best = 0.0;
      for (final s in setsRaw) {
        if (s is Map) {
          final w = (s['weight_kg'] as num?)?.toDouble() ?? 0.0;
          if (w > best) best = w;
        }
      }
      if (best > 0) return best;
    }
    return (log['weight_kg'] as num?)?.toDouble() ?? 0.0;
  }

  /// Extracts the IST date (`YYYY-MM-DD`) for an `exlog_*` Hive row.
  ///
  /// Preferred source: top-level `date` field stamped by the writer.
  /// Fallback: parse `created_at` and shift to IST.
  /// Last-resort fallback: null (caller decides — typically skip the row).
  static String? istDateForExlogRow(Map<String, dynamic> log) {
    final dateField = log['date'];
    if (dateField is String && dateField.isNotEmpty) return dateField;
    final createdAt = log['created_at'];
    if (createdAt is String && createdAt.isNotEmpty) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return istDateStr(parsed);
    }
    return null;
  }

  /// Returns the list of `exlog_*` Hive entries (as
  /// `Map<String, dynamic>`) for [istDate]. Reader-side index lookup;
  /// falls back to a workoutBox scan filtered by the writer-stamped
  /// `date` field when the index is missing or empty (APK Test #16.1
  /// Agent A defence for rogue restore-writer rows).
  ///
  /// Each returned map is a defensive copy — callers may mutate freely.
  List<Map<String, dynamic>> exerciseLogsForIstDate(String istDate) {
    final box = HiveService.instance.workoutBox;
    final out = <Map<String, dynamic>>[];

    final indexKey = 'exercise_log_index_$istDate';
    final indexRaw = box.get(indexKey);
    if (indexRaw is List && indexRaw.isNotEmpty) {
      for (final k in indexRaw) {
        final v = box.get(k);
        if (v is Map) out.add(Map<String, dynamic>.from(v));
      }
      if (out.isNotEmpty) return out;
    }

    // Fallback: scan workoutBox for `exlog_*` rows whose stamped `date`
    // matches istDate. Recovers from missing-index restore failures.
    for (final entry in box.toMap().entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('exlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (istDateForExlogRow(log) == istDate) out.add(log);
    }
    return out;
  }
}
