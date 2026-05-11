import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'workout_write_service.dart';

/// One-shot migration from `exlog_<timestamp>_<hash>` (Test #5 and
/// earlier) to `exlog_<istDateStr>_<hash(name)>` (Plan A).
///
/// Hash function MUST match WorkoutWriteService.exlogKey — currently
/// the first 8 hex chars of UUID v5 over
/// `exerciseName.toLowerCase().trim()` (H-16 audit-2026-05-11).
///
/// Idempotent — guarded by configBox['exlog_key_migration_v7'].
/// Bumped v6 → v7 in H-16 because the underlying hash function
/// changed from `String.hashCode` (platform-unstable) to UUID v5
/// (cross-platform stable). Devices that ran v6 still have rows
/// keyed under the hashCode shape — v7 re-runs the migration with
/// the new exlogKey() formula and consolidates.
class ExlogKeyMigrator {
  ExlogKeyMigrator._();
  static const _migrationKey = 'exlog_key_migration_v7';

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

      final mergedEntry = <String, dynamic>{
        ...base,
        'sets': mergedSets,
        'set_number': mergedSets.length,
        'weight_kg': maxWeight,
        'reps_completed': totalReps,
        'volume_kg': volume,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };

      // Delete old keys
      for (final mEntry in group) {
        if (mEntry.key != newKey) {
          await box.delete(mEntry.key);
          rekeyed++;
          if (group.length > 1) merged++;
        }
      }
      // Write under new key
      await box.put(newKey, mergedEntry);
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
        '[ExlogKeyMigrator] rekeyed=$rekeyed merged=$merged total_after=${box.keys.where((k) => k.toString().startsWith('exlog_')).length}');
    await config.put(_migrationKey, true);
  }
}
