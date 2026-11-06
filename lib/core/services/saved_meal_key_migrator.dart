import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'nutrition_write_service.dart';

/// One-shot migration of saved-meal Hive keys from the legacy
/// `saved_meal_<millisecondsSinceEpoch>` shape (written by an older
/// `NutritionWriteService.saveMealPreset`) to the canonical
/// `saved_meal_<nameHash>` shape produced by
/// `NutritionWriteService.savedMealKey(name)` — the SAME key the cloud restore
/// (`SyncService._restoreSavedMeals`) derives and the cloud natural key
/// `(user_id, name)`.
///
/// **Root cause it closes** (diagnose b8d5c2, 2026-06-03 — surfaced by the
/// f7e3a1 B-pass): the writer keyed by timestamp while the restore keyed by
/// name-hash, so every saved meal got a SECOND local Hive row after a
/// restore/reinstall → the saved-meals list showed duplicates. Aligning the
/// writer to the name-hash key (this batch) and re-keying existing rows here
/// makes writer == restore == cloud natural-key, so the same meal collapses to
/// ONE row on every path.
///
/// Mirrors [NlogKeyMigrator]: groups existing `saved_meal_*` rows by their
/// canonical key and MERGES collisions (the legacy `<ms>` row + an already-
/// restored `<nameHash>` row — exactly the duplicate this bug creates), keeping
/// the most-recently-created entry and the max `times_used`, then deletes the
/// non-canonical keys. Idempotent — guarded by
/// `configBox['saved_meal_key_migration_v1']`.
class SavedMealKeyMigrator {
  SavedMealKeyMigrator._();
  static const _migrationKey = 'saved_meal_key_migration_v1';

  static Future<void> runIfNeeded() async {
    final config = HiveService.instance.configBox;
    if (config.get(_migrationKey) == true) return;

    final box = HiveService.instance.nutritionBox;
    final oldKeys = box.keys
        .where((k) => k.toString().startsWith('saved_meal_'))
        .map((k) => k.toString())
        .toList();

    int rekeyed = 0;
    int merged = 0;

    // Group existing saved-meal rows by their canonical (name-hash) key.
    final byNewKey = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final oldKey in oldKeys) {
      final v = box.get(oldKey);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      if (m['is_saved_meal'] != true) continue;
      final name = (m['name'] as String?)?.trim();
      // A nameless meal can't be name-keyed (the restore falls back to an
      // id-hash for those); saveMealPreset rejects empty names, so this only
      // skips rare corrupted/legacy rows. Leave them untouched.
      if (name == null || name.isEmpty) continue;
      final newKey = NutritionWriteService.savedMealKey(name);
      byNewKey.putIfAbsent(newKey, () => []).add(MapEntry(oldKey, m));
    }

    for (final entry in byNewKey.entries) {
      final newKey = entry.key;
      final group = entry.value;

      // Already canonical and unique → nothing to do.
      if (group.length == 1 && group.first.key == newKey) continue;

      // Latest by created_at wins for content; times_used is the max so a
      // re-log count is never lost on merge.
      group.sort((a, b) {
        final at = DateTime.tryParse(a.value['created_at'] as String? ?? '')
                ?.millisecondsSinceEpoch ??
            0;
        final bt = DateTime.tryParse(b.value['created_at'] as String? ?? '')
                ?.millisecondsSinceEpoch ??
            0;
        return at.compareTo(bt);
      });
      final maxTimesUsed = group.fold<int>(0, (mx, e) {
        final t = (e.value['times_used'] as num?)?.toInt() ?? 0;
        return t > mx ? t : mx;
      });
      final mergedEntry = Map<String, dynamic>.from(group.last.value)
        ..['id'] = newKey
        ..['times_used'] = maxTimesUsed;

      // Write the merged row under the canonical key FIRST, then delete the
      // legacy keys (F1, f7e3a1 B-pass) — so a put that throws / is interrupted
      // never leaves the group with the old keys deleted but nothing written.
      // Stays idempotent: an interrupted put-then-delete re-enters the group next
      // boot (old keys still present) and reproduces the same result.
      await box.put(newKey, mergedEntry);
      for (final mEntry in group) {
        if (mEntry.key != newKey) {
          await box.delete(mEntry.key);
          rekeyed++;
        }
      }
      if (group.length > 1) merged += group.length - 1;
    }

    debugPrint(
        '[SavedMealKeyMigrator] rekeyed=$rekeyed merged=$merged total_after=${box.keys.where((k) => k.toString().startsWith('saved_meal_')).length}');
    await config.put(_migrationKey, true);
  }
}
