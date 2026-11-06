import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'pending_exlog_deletes.dart';
import 'sync/sync_skip_index.dart';
import 'sync_flags.dart';
import 'sync_service.dart';
import 'workout_write_service.dart';

/// One-shot migration from `exlog_<timestamp>_<hash>` (Test #5 and
/// earlier) to `exlog_<istDateStr>_<hash(name)>` (Plan A).
///
/// Hash function MUST match WorkoutWriteService.exlogKey — currently
/// the first 8 hex chars of UUID v5 over
/// `exerciseName.toLowerCase().trim()` (H-16 audit-2026-05-11).
///
/// Idempotent — guarded by configBox['exlog_key_migration_v8'].
/// Bumped v6 → v7 in H-16 because the underlying hash function
/// changed from `String.hashCode` (platform-unstable) to UUID v5
/// (cross-platform stable). Devices that ran v6 still have rows
/// keyed under the hashCode shape — v7 re-runs the migration with
/// the new exlogKey() formula and consolidates.
///
/// APK Test #16.1 / Agent A — bumped v7 → v8 because two rogue
/// writers (`SyncService._restoreExerciseLogs` and
/// `WorkoutRepository.logSetWithPrRescan`) were still emitting
/// non-canonical `exlog_*` keys (hashCode-based and
/// timestamp+hashCode-based respectively) AFTER v7 ran. Founder hit
/// 26+ phantom exlog rows for May 14 on a +24 APK install. v8
/// re-runs the merge against the v7 boundary, picking up the
/// rogue rows; the writers themselves were rewritten to delegate
/// to [WorkoutWriteService.exlogKey] so the issue does not recur.
///
/// sync-storm-first-sweep W1 — a single canonical row whose recomputed
/// aggregates already equal the stored row is NOT rewritten (no `put`, no
/// `updated_at_ms = now`). The restore records the push fingerprint of every
/// row it writes; the push sends `completed_at = max(resolved, updated_at_ms)`
/// and `completed_at` is part of that fingerprint, so a blind rewrite made the
/// next push re-upload every restored exercise. Kill switch
/// `disable_exlog_migrator_skip_unchanged` restores the unconditional rewrite.
class ExlogKeyMigrator {
  ExlogKeyMigrator._();
  static const _migrationKey = 'exlog_key_migration_v8';

  static Future<void> runIfNeeded() async {
    final config = HiveService.instance.configBox;
    if (config.get(_migrationKey) == true) return;

    final box = HiveService.instance.workoutBox;
    final oldKeys = box.keys
        .where((k) => k.toString().startsWith('exlog_'))
        .map((k) => k.toString())
        .toList();

    int rekeyed = 0;
    int merged = 0;
    int unchanged = 0;
    int rewritten = 0;
    final skipUnchanged = SyncFlags.exlogMigratorSkipUnchangedEnabled;
    var compareErrorReported = false;

    // Group existing entries by their NEW key.
    final byNewKey = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final oldKey in oldKeys) {
      final v = box.get(oldKey);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final name = m['exercise_name'] as String?;
      final dateStr = m['date'] as String?;
      if (name == null || dateStr == null) continue;

      // Parse the IST date from the entry to feed exlogKey().
      DateTime? d;
      try {
        d = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }
      final newKey = WorkoutWriteService.exlogKey(d, name);
      byNewKey.putIfAbsent(newKey, () => []).add(MapEntry(oldKey, m));
    }

    // For each newKey, merge entries (concat sets[], pick latest
    // updated_at_ms for top-level fields).
    for (final entry in byNewKey.entries) {
      final newKey = entry.key;
      final group = entry.value;
      group.sort((a, b) {
        final at = (a.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        final bt = (b.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        return at.compareTo(bt);
      });

      // Concat sets[] in updated_at_ms order.
      final List<Map> mergedSets = [];
      for (final mEntry in group) {
        final sets = (mEntry.value['sets'] as List?)?.cast<Map>() ?? const [];
        if (sets.isNotEmpty) {
          mergedSets.addAll(sets);
        } else {
          // Legacy entry — synthesize a single ExerciseSet from
          // top-level weight_kg + reps_completed
          final w = (mEntry.value['weight_kg'] as num?)?.toDouble() ?? 0.0;
          final r = (mEntry.value['reps_completed'] as num?)?.toInt() ?? 0;
          mergedSets.add({
            'weight_kg': w,
            'reps': r,
            'logged_at_ms':
                (mEntry.value['updated_at_ms'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
          });
        }
      }

      // Use latest entry as the base for top-level fields, override
      // sets[] + aggregates.
      final base = group.last.value;
      final maxWeight = mergedSets.fold<double>(
          0.0,
          (a, s) => ((s['weight_kg'] as num?)?.toDouble() ?? 0.0) > a
              ? (s['weight_kg'] as num).toDouble()
              : a);
      final totalReps = mergedSets.fold<int>(
          0, (a, s) => a + ((s['reps'] as num?)?.toInt() ?? 0));
      final volume = mergedSets.fold<double>(
          0.0,
          (a, s) =>
              a +
              (((s['weight_kg'] as num?)?.toDouble() ?? 0.0) *
                  ((s['reps'] as num?)?.toInt() ?? 0)));

      // Everything the migrator would write, minus the new write stamp.
      final candidate = <String, dynamic>{
        ...base,
        'sets': mergedSets,
        'set_number': mergedSets.length,
        'weight_kg': maxWeight,
        'reps_completed': totalReps,
        'volume_kg': volume,
      };

      // sync-storm-first-sweep W1 — a lone canonical row that the rewrite would
      // leave byte-equal is left alone. `.first` (not `.single`) so a
      // multi-entry group simply fails the length test; such a group can never
      // be equal anyway (every extra entry adds a set). The comparison may
      // throw (NaN/Infinity makes jsonEncode throw): fall back to the rewrite.
      var rowUnchanged = false;
      if (skipUnchanged && group.length == 1 && group.first.key == newKey) {
        try {
          rowUnchanged = SyncFingerprint.canonicalJson(candidate) ==
              SyncFingerprint.canonicalJson(base);
        } catch (e, st) {
          if (!compareErrorReported) {
            compareErrorReported = true;
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_exlog_migrator_compare'));
          }
        }
      }

      // Write under the new key FIRST, then delete the old keys (b8d5c2 B-pass
      // F1) — a throwing/interrupted put never leaves the group with the old
      // keys deleted but nothing written. Idempotent: an interrupted
      // put-then-delete re-enters the group next boot (old keys still present)
      // and reproduces the result.
      if (rowUnchanged) {
        unchanged++;
      } else {
        await box.put(newKey, <String, dynamic>{
          ...candidate,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
        rewritten++;
      }
      // L1a-2 U4: the migrator re-creates the row, so a delete still queued
      // for this exercise on this day is cancelled (same as a re-log). Kept on
      // the unchanged path too: the arguments come from `base`, so the call is
      // identical to today's.
      final migratedName = candidate['exercise_name'] as String?;
      final migratedDate = candidate['date'] as String?;
      if (migratedName != null && migratedDate != null) {
        await PendingExlogDeletes.cancelFor(
          workoutLogId: SyncService.workoutLogIdForDate(migratedDate),
          exerciseName: migratedName,
        );
      }
      for (final mEntry in group) {
        if (mEntry.key != newKey) {
          await box.delete(mEntry.key);
          rekeyed++;
          if (group.length > 1) merged++;
        }
      }
    }

    // Rebuild exercise_log_index_<date> from current state
    final indexKeys = box.keys
        .where((k) => k.toString().startsWith('exercise_log_index_'))
        .toList();
    for (final ik in indexKeys) {
      await box.delete(ik);
    }
    for (final k in box.keys) {
      final ks = k.toString();
      if (!ks.startsWith('exlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final dateStr = v['date'] as String?;
      if (dateStr == null) continue;
      final indexKey = 'exercise_log_index_$dateStr';
      final raw = box.get(indexKey);
      final list = (raw is List) ? raw.cast<String>().toList() : <String>[];
      if (!list.contains(ks)) list.add(ks);
      await box.put(indexKey, list);
    }

    debugPrint(
        '[ExlogKeyMigrator] rekeyed=$rekeyed merged=$merged unchanged=$unchanged rewritten=$rewritten total_after=${box.keys.where((k) => k.toString().startsWith('exlog_')).length}');
    await config.put(_migrationKey, true);
  }
}
