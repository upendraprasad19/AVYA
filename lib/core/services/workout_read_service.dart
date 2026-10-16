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
/// contract documented in docs/architecture/sync.md "Hive field-name contract"):
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

  // ─────────────────────────────────────────────────────────────
  //  Aggregate semantic primitives  (Unit 7 / OI-50)
  //
  //  Distinct from the per-set MAX block above: these answer "how many
  //  sets in TOTAL" and "how long in TOTAL".
  //
  //  They exist because the two writers of an `exlog_*` row emit
  //  DIFFERENT subsets of the aggregate fields:
  //
  //    modern  (`workout_write_service.dart:177-181`)
  //        → `sets[]` + `set_number`; NO top-level `duration_seconds`
  //    restore (`sync/sync_workout.dart:733-767`)
  //        → `set_number` + top-level `duration_seconds` (:765-766),
  //          and `sets[]` ONLY when the `workout_log_sets` join came
  //          back non-empty (:777)
  //
  //  Two readers each hand-rolled their own reconciliation of that and
  //  one of them got it wrong, which is what OI-50 actually was. Every
  //  reader that needs a TOTAL delegates here so a third cannot drift
  //  again — the workout-domain equivalent of
  //  `NutritionReadService.deriveMealDisplayName`.
  // ─────────────────────────────────────────────────────────────

  /// The per-set array for [log] — the LONGER of canonical `sets[]` and
  /// legacy `sets_detail[]`. Empty list when neither is a populated List.
  ///
  /// Deliberately NOT `log['sets'] ?? log['sets_detail']`: `??` is
  /// null-coalescing, so a row carrying `sets: []` alongside a populated
  /// `sets_detail` would resolve to the EMPTY list and silently lose the
  /// legacy array. The receipt's pre-Unit-7 code measured both lengths
  /// independently and MAXed them, and the two remaining train-screen
  /// readers still do; taking the longer preserves that exactly.
  static List<Map> _perSetList(Map<String, dynamic> log) {
    final canonical = log['sets'];
    final legacy = log['sets_detail'];
    final a = canonical is List ? canonical.whereType<Map>().toList() : const <Map>[];
    final b = legacy is List ? legacy.whereType<Map>().toList() : const <Map>[];
    return a.length >= b.length ? a : b;
  }

  /// TOTAL completed sets for an `exlog_*` row.
  ///
  /// MAX across every field that can carry the count, because no single
  /// one is reliably present:
  ///   - `set_number`           canonical (modern AND restore writer)
  ///   - `sets_completed`       legacy pre-Test-#6 alias
  ///   - `sets[]`/`sets_detail[]` length
  ///
  /// MAX rather than first-non-null is deliberate (APK Test #12.1/#12.2,
  /// founder observation 2026-05-06): rows exist where BOTH `set_number`
  /// and `sets_completed` are 0 while the per-set array is populated —
  /// the receipt rendered "0 sets" while the cloud projection, which
  /// prefers array length, had shipped 4.
  static int aggregateSetCount(Map<String, dynamic> log) {
    final candidates = <int>[
      (log['set_number'] as num?)?.toInt() ?? 0,
      (log['sets_completed'] as num?)?.toInt() ?? 0,
      _perSetList(log).length,
    ];
    return candidates.reduce((a, b) => a > b ? a : b);
  }

  /// Whether [log] carries ANY set-count signal at all.
  ///
  /// Distinguishes "genuinely zero sets" from "every count key is
  /// absent". The edit sheet needs the distinction so it doesn't present
  /// an absent value as a user-entered 0 and then write that 0 back on
  /// save. [aggregateSetCount] alone cannot express it — it returns 0
  /// for both cases.
  static bool hasAggregateSetCount(Map<String, dynamic> log) =>
      log['set_number'] is num ||
      log['sets_completed'] is num ||
      _perSetList(log).isNotEmpty;

  /// TOTAL duration in seconds for an `exlog_*` row, or `null` when the
  /// row carries no duration signal at all.
  ///
  /// Precedence:
  ///   1. SUM across the per-set array (`duration_sec` canonical,
  ///      `duration_seconds` the restore-path per-set alias at
  ///      `sync_workout.dart:792`) — canonical, and the only source a
  ///      modern-writer row can supply.
  ///   2. Top-level `duration_seconds` — the documented exlog aggregate
  ///      (see the field contract in this class's doc comment). The
  ///      MODERN writer does not emit it, but the RESTORE writer does
  ///      (`sync_workout.dart:765-766`), so for a restored row whose
  ///      `workout_log_sets` join came back empty this is the ONLY
  ///      surviving duration. Reading 0 instead is the OI-50 defect.
  ///   3. `null` — genuinely no signal. Caller renders nothing and
  ///      should emit telemetry rather than display a fabricated 0.
  ///
  /// A per-set sum of 0 falls through to the top-level value on purpose:
  /// a restored row can carry per-set rows with no `duration_secs` while
  /// the summary row still holds the true total.
  static int? aggregateDurationSeconds(Map<String, dynamic> log) {
    var sum = 0;
    for (final s in _perSetList(log)) {
      sum += (s['duration_sec'] as num?)?.toInt() ??
          (s['duration_seconds'] as num?)?.toInt() ??
          0;
    }
    if (sum > 0) return sum;
    final topLevel = (log['duration_seconds'] as num?)?.toInt();
    if (topLevel != null && topLevel > 0) return topLevel;
    return null;
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

  /// OI-39 (audit-2026-05-17 Hermes C5) — cross-date `exlog_*` lookup by
  /// exercise name. Replaces the inline `workoutBox.values` scans that
  /// previously lived in `train_provider._getLastPerformance` +
  /// `exerciseHistoryProvider` (and that would have re-diverged on next
  /// edit if not consolidated).
  ///
  /// Returns logs chronologically sorted (oldest first). Name match is
  /// exact case-insensitive first, then fuzzy contains ONLY when BOTH
  /// names are ≥6 chars (prevents "Press" matching "Leg Press").
  ///
  /// Each returned map is a defensive copy.
  List<Map<String, dynamic>> logsForExercise(String exerciseName) {
    final box = HiveService.instance.workoutBox;
    final nameLower = exerciseName.toLowerCase();
    final entries = <MapEntry<DateTime, Map<String, dynamic>>>[];

    for (final entry in box.toMap().entries) {
      final keyStr = entry.key.toString();
      // OI-39 — restrict to canonical `exlog_*` rows so we don't pick up
      // schedule entries / templates / streaks. Pre-OI-39 the provider
      // filtered on `type == 'exercise_log'` which depended on the writer
      // stamping that string; safer to gate by key prefix here.
      if (!keyStr.startsWith('exlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      final logName = (log['exercise_name'] as String? ?? '').toLowerCase();
      if (logName.isEmpty) continue;
      // Exact match first; fuzzy contains only when both names are long
      // enough to avoid false positives.
      if (logName != nameLower) {
        if (nameLower.length < 6 || logName.length < 6) continue;
        if (!logName.contains(nameLower) && !nameLower.contains(logName)) {
          continue;
        }
      }

      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      entries.add(MapEntry(date, log));
    }

    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => e.value).toList();
  }
}
