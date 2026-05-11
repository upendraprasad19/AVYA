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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class LoggingTypeRepairMigrator {
  LoggingTypeRepairMigrator._();

  // APK Test #12.5 — bump flag from v2 to v3.
  //
  // v2 (Test #12.4) was library-strict for top-level fields but the
  // `bodyweight_reps` branch did NOT walk per-set arrays (`sets[]` /
  // `sets_detail[]`). Founder install of APK 12.4 surfaced the gap:
  // top-level `logging_type` was correctly flipped to `bodyweight_reps`
  // for Push Up + Hanging Leg Raise, but per-set entries still carried
  // `duration_sec` values from the original corrupt write. WardSetChips
  // continued rendering "18 secs" because the chip pulled per-set
  // `duration_sec` directly.
  //
  // v3 mirrors the `timed` branch's per-set migration into the
  // `bodyweight_reps` branch: walk `sets[]` + `sets_detail[]`, move
  // any `duration_sec`>0 (with `reps==0`) into `reps`, drop bogus
  // weight, drop residual `duration_sec`. Bumping the flag forces
  // re-run on every device.
  static const String _flagKey = 'logging_type_repair_v3_done';

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
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[LoggingTypeRepairMigrator] migrationBox unavailable: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'logging_type_repair_migrator_migration_box_unavailable'));
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
        final repaired = _repairRow(m, libByName);
        if (!repaired) continue;

        m['logging_type_repaired_at_ms'] =
            DateTime.now().millisecondsSinceEpoch;
        await wb.put(k, m);
        corrected += 1;
        debugPrint('[LoggingTypeRepairMigrator] repaired $k stored=$stored '
            '→ ${m['logging_type']}');
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
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[LoggingTypeRepairMigrator] $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'logging_type_repair_migrator_run_if_needed'));
      // DON'T set the flag — let the next launch retry.
    }

    return corrected;
  }

  /// APK Test #12.4 — library-strict repair. Returns true if the row
  /// was MUTATED in any way (logging_type or data shape).
  ///
  /// Policy:
  ///   1. If library has the exercise, LIBRARY TYPE WINS. Migrate the
  ///      data shape to match the library's type. (Move reps→duration
  ///      when library says timed but row has stuffed reps; clear
  ///      weight when library says bodyweight_reps but row has bogus
  ///      weight; etc.)
  ///   2. If exercise is custom (not in library), fall back to
  ///      data-driven inference.
  ///
  /// Why library wins: Test #12.2 v1 used data-driven fallback when
  /// library was inconsistent with data shape. For Jump Rope (library
  /// timed, data had reps=1080 from corrupt swap-state retention),
  /// data-driven flipped to bodyweight_reps — making the corrupt data
  /// "permanent" in the wrong type. The right move is the OPPOSITE:
  /// trust library, fix the data.
  static bool _repairRow(
    Map<String, dynamic> row,
    Map<String, String> libByName,
  ) {
    final name = (row['exercise_name'] as String?)?.trim();
    final stored = row['logging_type'] as String? ?? 'weight_reps';

    // Library lookup.
    final libType = (name != null) ? libByName[name] : null;

    if (libType != null) {
      return _libraryStrictRepair(row, libType, stored);
    }
    return _dataDrivenRepair(row, stored);
  }

  /// Library-strict path: the stored type AND the data shape must
  /// match what the library says. Mutates `row` to match.
  static bool _libraryStrictRepair(
    Map<String, dynamic> row,
    String libType,
    String stored,
  ) {
    var changed = false;

    // 1. Set logging_type to library value.
    if (stored != libType) {
      row['logging_type'] = libType;
      changed = true;
    }

    // 2. Migrate data shape to match.
    switch (libType) {
      case 'timed':
        // Library says timed. If row has reps but no duration, the
        // user's typed value got stuffed into the reps field by the
        // pre-Test-#12 swap drift. Move it to duration_seconds.
        final reps = (row['reps_completed'] as num?)?.toInt() ?? 0;
        final dur = (row['duration_seconds'] as num?)?.toInt() ?? 0;
        if (reps > 0 && dur == 0) {
          row['duration_seconds'] = reps;
          row['reps_completed'] = 0;
          changed = true;
        }
        // Clear bogus weight (timed = bodyweight, no external load).
        final weight = (row['weight_kg'] as num?)?.toDouble() ?? 0.0;
        if (weight > 0) {
          row['weight_kg'] = 0.0;
          changed = true;
        }
        // Per-set entries: same migration. Build a fresh
        // List<Map<String, dynamic>> rather than mutating the existing
        // list — Hive may deserialize per-set entries as
        // List<Map<String, int>> (narrow type), which rejects
        // assignment of Map<String, dynamic> back into the list slot.
        final sets = row['sets'];
        if (sets is List) {
          final out = <Map<String, dynamic>>[];
          var perSetChanged = false;
          for (final s in sets) {
            if (s is! Map) {
              out.add(<String, dynamic>{});
              continue;
            }
            final m = Map<String, dynamic>.from(s);
            final r = (m['reps'] as num?)?.toInt() ?? 0;
            final d = (m['duration_sec'] as num?)?.toInt() ??
                (m['duration_seconds'] as num?)?.toInt() ??
                0;
            if (r > 0 && d == 0) {
              m['duration_sec'] = r;
              m['reps'] = 0;
              perSetChanged = true;
            }
            final w = (m['weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (w > 0) {
              m['weight_kg'] = 0.0;
              perSetChanged = true;
            }
            out.add(m);
          }
          if (perSetChanged) {
            row['sets'] = out;
            changed = true;
          }
        }
        final setsDetail = row['sets_detail'];
        if (setsDetail is List) {
          final out = <Map<String, dynamic>>[];
          var perSetChanged = false;
          for (final s in setsDetail) {
            if (s is! Map) {
              out.add(<String, dynamic>{});
              continue;
            }
            final m = Map<String, dynamic>.from(s);
            final r = (m['reps'] as num?)?.toInt() ?? 0;
            final d = (m['duration_sec'] as num?)?.toInt() ??
                (m['duration_seconds'] as num?)?.toInt() ??
                0;
            if (r > 0 && d == 0) {
              m['duration_seconds'] = r;
              m['reps'] = 0;
              perSetChanged = true;
            }
            final w = (m['weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (w > 0) {
              m['weight_kg'] = 0.0;
              perSetChanged = true;
            }
            out.add(m);
          }
          if (perSetChanged) {
            row['sets_detail'] = out;
            changed = true;
          }
        }
        break;

      case 'bodyweight_reps':
        // Library says bodyweight_reps. Clear bogus weight (was 1kg
        // for Handstand Hold etc. via swap drift in reverse).
        final weight = (row['weight_kg'] as num?)?.toDouble() ?? 0.0;
        if (weight > 0) {
          row['weight_kg'] = 0.0;
          changed = true;
        }
        // If row has duration but no reps (timed-as-bodyweight inverse
        // drift), move duration → reps.
        final reps = (row['reps_completed'] as num?)?.toInt() ?? 0;
        final dur = (row['duration_seconds'] as num?)?.toInt() ?? 0;
        if (dur > 0 && reps == 0) {
          row['reps_completed'] = dur;
          row.remove('duration_seconds');
          changed = true;
        } else if (dur > 0) {
          // Have both — strip duration as it doesn't apply to bodyweight.
          row.remove('duration_seconds');
          changed = true;
        }
        // APK Test #12.5 / v3 — per-set migration. v2 only did
        // top-level. Receipt + WardSetChips read per-set
        // `duration_sec` directly; without this loop, "18 secs"
        // chips persist after the type flip.
        final sets = row['sets'];
        if (sets is List) {
          final out = <Map<String, dynamic>>[];
          var perSetChanged = false;
          for (final s in sets) {
            if (s is! Map) {
              out.add(<String, dynamic>{});
              continue;
            }
            final m = Map<String, dynamic>.from(s);
            final r = (m['reps'] as num?)?.toInt() ?? 0;
            final d = (m['duration_sec'] as num?)?.toInt() ??
                (m['duration_seconds'] as num?)?.toInt() ??
                0;
            if (d > 0 && r == 0) {
              m['reps'] = d;
              m.remove('duration_sec');
              m.remove('duration_seconds');
              perSetChanged = true;
            } else if (d > 0) {
              m.remove('duration_sec');
              m.remove('duration_seconds');
              perSetChanged = true;
            }
            final w = (m['weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (w > 0) {
              m['weight_kg'] = 0.0;
              perSetChanged = true;
            }
            out.add(m);
          }
          if (perSetChanged) {
            row['sets'] = out;
            changed = true;
          }
        }
        final setsDetail = row['sets_detail'];
        if (setsDetail is List) {
          final out = <Map<String, dynamic>>[];
          var perSetChanged = false;
          for (final s in setsDetail) {
            if (s is! Map) {
              out.add(<String, dynamic>{});
              continue;
            }
            final m = Map<String, dynamic>.from(s);
            final r = (m['reps'] as num?)?.toInt() ?? 0;
            final d = (m['duration_sec'] as num?)?.toInt() ??
                (m['duration_seconds'] as num?)?.toInt() ??
                0;
            if (d > 0 && r == 0) {
              m['reps'] = d;
              m.remove('duration_sec');
              m.remove('duration_seconds');
              perSetChanged = true;
            } else if (d > 0) {
              m.remove('duration_sec');
              m.remove('duration_seconds');
              perSetChanged = true;
            }
            final w = (m['weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (w > 0) {
              m['weight_kg'] = 0.0;
              perSetChanged = true;
            }
            out.add(m);
          }
          if (perSetChanged) {
            row['sets_detail'] = out;
            changed = true;
          }
        }
        break;

      case 'weight_reps':
      case 'weighted_bodyweight':
        // Trust the data shape; just enforce the type label.
        // (Most weight-based drift is type-only; reps and weight
        // fields are usually correct.)
        break;
    }
    return changed;
  }

  /// Custom-exercise path (not in library). Fall back to data-driven
  /// inference — same rule WorkoutWriteService._inferLoggingType uses.
  static bool _dataDrivenRepair(
    Map<String, dynamic> row,
    String stored,
  ) {
    final reps = (row['reps_completed'] as num?)?.toInt() ?? 0;
    final weight = (row['weight_kg'] as num?)?.toDouble() ?? 0.0;
    final dur = (row['duration_seconds'] as num?)?.toInt() ?? 0;

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

    String inferred;
    if (hasDur && !hasWeight && !hasReps) {
      inferred = 'timed';
    } else if (hasWeight) {
      inferred = 'weight_reps';
    } else if (hasReps) {
      inferred = 'bodyweight_reps';
    } else {
      return false; // No signal — leave alone.
    }

    if (inferred == stored) return false;
    row['logging_type'] = inferred;
    return true;
  }
}
