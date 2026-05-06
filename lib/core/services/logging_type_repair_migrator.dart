// APK Test #12.2 / Task #2b — One-shot self-repair migration for
// `logging_type` drift on `exlog_*` rows.
//
// ## Background
//
// Pre-Test-#12 the active-workout swap path didn't clear per-slot
// state (`setInputValues`, `checkedSets`) when the user swapped an
// exercise. If the original slot was a TIMED exercise and the user
// typed a duration, the duration survived the swap. The replacement
// exercise then completed with sets that had BOTH `reps>0` AND
// `durationSec>0` — and `WorkoutWriteService._inferLoggingType`
// returned `'timed'` because `hasDur=true && hasWeight=false`.
//
// Result: bodyweight exercises like Push Up, Hanging Leg Raise, Chin
// Up shipped with `logging_type='timed'` to local Hive AND to cloud
// `workout_log_exercises` (the projection mirrors local).
//
// The Test #12 swap-state-cleanup hotfix prevents NEW occurrences,
// but every exlog row written before that hotfix is corrupted.
//
// ## What this migration does
//
// Walks every `exlog_*` row in the workout box. For each, re-infers
// the correct `logging_type` from the actual stored sets data and
// the bundled exercise library. Writes the corrected value back AND
// re-syncs to cloud so the per-exercise summary table reflects
// reality.
//
// Heuristic order:
//   1. If the bundled exerciseBox has the exercise by name AND the
//      library `logging_type` agrees with the stored aggregates,
//      trust the library. (Push Up → bodyweight_reps even if the
//      row is currently `timed`.)
//   2. Else re-infer from sets/sets_detail data — same logic
//      `WriteService._inferLoggingType` uses but tolerant of legacy
//      field names (`duration_seconds` ⇄ `duration_sec`).
//   3. Strip the offending field if necessary (a row "corrected"
//      from `timed` → `bodyweight_reps` should also clear
//      `duration_seconds` so readers don't render mixed signals).
//
// ## Idempotency
//
// Gated by `migrationBox['logging_type_repair_v1_done']`. Runs once
// per device lifetime (the flag survives `clearAllData()`).
//
// Read CLAUDE.md §15 "Hive field-name contract" for the broader
// drift discipline this migration enforces.

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class LoggingTypeRepairMigrator {
  LoggingTypeRepairMigrator._();

  static const String _flagKey = 'logging_type_repair_v1_done';

  /// True once the migration has run on this device.
  static bool hasRun() {
    try {
      return HiveService.instance.migrationBox.get(_flagKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Run the migration if it hasn't been run before. Safe to call on
  /// every splash launch — short-circuits via the migration flag.
  ///
  /// Returns the count of rows actually corrected; 0 means the
  /// migration ran but nothing needed fixing.
  static Future<int> runIfNeeded() async {
    final hive = HiveService.instance;
    Box migrationBox;
    try {
      migrationBox = hive.migrationBox;
    } catch (e) {
      debugPrint('[LoggingTypeRepairMigrator] migrationBox unavailable: $e');
      return 0;
    }

    if (migrationBox.get(_flagKey) == true) {
      return 0;
    }

    int corrected = 0;
    try {
      final wb = hive.workoutBox;
      final exerciseBox = hive.exerciseBox;

      // Build name → library logging_type lookup once.
      final libByName = <String, String>{};
      for (final entry in exerciseBox.toMap().entries) {
        final v = entry.value;
        if (v is Map) {
          final name = v['name'] as String?;
          final lt = v['logging_type'] as String?;
          if (name != null && lt != null && lt.isNotEmpty) {
            libByName[name] = lt;
          }
        }
      }

      // Walk exlog_* rows.
      final keys = wb.keys.toList();
      for (final k in keys) {
        if (k is! String || !k.startsWith('exlog_')) continue;
        final raw = wb.get(k);
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);

        final stored = m['logging_type'] as String? ?? 'weight_reps';
        final corrected_lt = _correctLoggingType(m, libByName);
        if (corrected_lt == null || corrected_lt == stored) continue;

        // Apply correction.
        m['logging_type'] = corrected_lt;
        // If we corrected timed → bodyweight/weight, strip a stale
        // top-level duration_seconds so renderers don't mix signals.
        if (stored == 'timed' && corrected_lt != 'timed') {
          m.remove('duration_seconds');
        }
        if (stored != 'timed' && corrected_lt == 'timed') {
          // Inverse: clear weight if it was bogusly populated.
          m['weight_kg'] = 0.0;
        }
        m['logging_type_repaired_at_ms'] =
            DateTime.now().millisecondsSinceEpoch;

        await wb.put(k, m);
        corrected += 1;
      }

      await migrationBox.put(_flagKey, true);
      debugPrint('[LoggingTypeRepairMigrator] corrected=$corrected rows');

      // Re-sync corrected rows to cloud (fire-and-forget). The
      // workout_log_exercises projection in sync_service mirrors local
      // Hive, so this propagates the fix server-side too.
      if (corrected > 0) {
        // Non-blocking; failure is non-fatal — we'll re-sync on next
        // mutation.
        // ignore: discarded_futures
        SyncService.instance.syncWorkoutData();
      }
    } catch (e, st) {
      debugPrint('[LoggingTypeRepairMigrator] $e\n$st');
      // DON'T set the flag — let the next launch retry.
    }

    return corrected;
  }

  /// Returns the corrected `logging_type` for a row, or null if the
  /// stored value already looks right.
  ///
  /// Library-first: if the bundled exercise library has this exercise
  /// AND its library type makes sense given the stored aggregates,
  /// the library type wins. Else fall back to data-driven inference.
  static String? _correctLoggingType(
    Map<String, dynamic> row,
    Map<String, String> libByName,
  ) {
    final name = (row['exercise_name'] as String?)?.trim();
    final stored = row['logging_type'] as String? ?? 'weight_reps';
    final reps = (row['reps_completed'] as num?)?.toInt() ?? 0;
    final weight = (row['weight_kg'] as num?)?.toDouble() ?? 0.0;
    final dur = (row['duration_seconds'] as num?)?.toInt() ?? 0;

    // Per-set aggregate — sometimes top-level fields are 0 but per-set
    // arrays carry the truth.
    bool perSetHasDur = false;
    bool perSetHasWeight = false;
    bool perSetHasReps = false;
    final sets = row['sets'] ?? row['sets_detail'];
    if (sets is List) {
      for (final s in sets) {
        if (s is! Map) continue;
        final w = (s['weight_kg'] as num?)?.toDouble() ?? 0.0;
        final r = (s['reps'] as num?)?.toInt() ?? 0;
        final d = (s['duration_sec'] as num?)?.toInt() ??
            (s['duration_seconds'] as num?)?.toInt() ??
            0;
        if (w > 0) perSetHasWeight = true;
        if (r > 0) perSetHasReps = true;
        if (d > 0) perSetHasDur = true;
      }
    }
    final hasDur = dur > 0 || perSetHasDur;
    final hasWeight = weight > 0 || perSetHasWeight;
    final hasReps = reps > 0 || perSetHasReps;

    // Library lookup.
    String? libType;
    if (name != null) {
      libType = libByName[name];
    }

    // Decision tree:
    //
    // Case A — library says X, stored agrees → no-op (return null).
    if (libType != null && libType == stored) return null;
    //
    // Case B — library says X, stored disagrees AND data is consistent
    // with library → trust library. (Push Up library=bodyweight_reps,
    // stored=timed, data has reps>0 → correct to bodyweight_reps.)
    if (libType != null) {
      final libConsistent = _isConsistent(libType, hasDur, hasWeight, hasReps);
      if (libConsistent) return libType;
    }
    //
    // Case C — no library entry OR library inconsistent. Re-infer from
    // data using the same rule WriteService applies. NOTE: the
    // canonical rule prioritizes weight (`if hasWeight return
    // weight_reps`) — but for repair we prefer reps when reps AND
    // weight are both 0 except a tiny bogus value. Practical heuristic:
    //   hasDur && !hasWeight && !hasReps  → timed
    //   hasWeight && hasReps              → weight_reps
    //   hasReps && !hasWeight             → bodyweight_reps
    //   hasWeight && !hasReps             → weight_reps
    //   else                              → fall back to stored
    if (hasDur && !hasWeight && !hasReps) {
      if (stored != 'timed') return 'timed';
      return null;
    }
    if (hasReps && !hasWeight) {
      if (stored != 'bodyweight_reps') return 'bodyweight_reps';
      return null;
    }
    if (hasWeight) {
      if (stored != 'weight_reps') return 'weight_reps';
      return null;
    }
    return null;
  }

  /// True if [type] is consistent with the observed aggregates.
  static bool _isConsistent(
    String type,
    bool hasDur,
    bool hasWeight,
    bool hasReps,
  ) {
    switch (type) {
      case 'timed':
        // Timed should have duration. Tolerate hasDur || (no other signal).
        return hasDur || (!hasWeight && !hasReps);
      case 'bodyweight_reps':
        return hasReps && !hasWeight;
      case 'weight_reps':
        return hasWeight; // reps optional (some systems log just weight)
      case 'weighted_bodyweight':
        return hasReps && hasWeight;
      case 'cardio':
      case 'distance':
        return true; // not enough signal in aggregates to disprove
      default:
        return false;
    }
  }
}
