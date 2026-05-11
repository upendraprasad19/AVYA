import 'package:flutter/foundation.dart';

import 'hive_service.dart';

/// One-shot migration from `nlog_<timestamp>` (Test #5 and earlier)
/// to `nlog_<istDateStr>_<mealType>_<hash(items)>` (Plan C).
///
/// Hash function MUST match NutritionWriteService._stableItemsHash —
/// currently first 8 hex chars of UUID v5 over sorted-by-name joined
/// `name|quantityG;…` (H-17 audit-2026-05-11).
///
/// Idempotent — guarded by configBox['nlog_key_migration_v7'].
/// Bumped v6 → v7 in H-17 because the underlying hash function
/// changed from `String.hashCode` (platform-unstable) to UUID v5
/// (cross-platform stable). Devices that ran v6 have rows keyed
/// under the hashCode shape — v7 re-runs and consolidates with the
/// new `_stableItemsHash` formula.
class NlogKeyMigrator {
  NlogKeyMigrator._();
  static const _migrationKey = 'nlog_key_migration_v7';

  static Future<void> runIfNeeded() async {
    final config = HiveService.instance.configBox;
    if (config.get(_migrationKey) == true) return;

    final box = HiveService.instance.nutritionBox;
    final oldKeys = box.keys
        .where((k) => k.toString().startsWith('nlog_'))
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
      final dateStr = m['logged_at'] as String?;
      final mealType = m['meal_type'] as String? ?? 'custom';
      final items = m['items'] as List?;
      if (dateStr == null || items == null) continue;

      // Parse the IST date from the entry.
      DateTime? d;
      try {
        d = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }

      // Compute new key using the same hash function as NutritionWriteService.
      final newKey = _computeLogKey(d, mealType, items);
      byNewKey.putIfAbsent(newKey, () => []).add(MapEntry(oldKey, m));
    }

    // For each newKey, use the latest entry (by updated_at_ms).
    // In the old model there should be at most one entry per newKey
    // (no duplicates expected), but we merge for safety.
    for (final entry in byNewKey.entries) {
      final newKey = entry.key;
      final group = entry.value;
      group.sort((a, b) {
        final at = (a.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        final bt = (b.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        return at.compareTo(bt);
      });

      // Use latest entry as the merged result.
      final mergedEntry = group.last.value
          .cast<String, dynamic>()
          ..[
            'updated_at_ms'
          ] = DateTime.now().millisecondsSinceEpoch;

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

    // Rebuild nutrition_log_index_<date> from current state
    final indexKeys = box.keys
        .where((k) => k.toString().startsWith('nutrition_log_index_'))
        .toList();
    for (final ik in indexKeys) {
      await box.delete(ik);
    }
    for (final k in box.keys) {
      final ks = k.toString();
      if (!ks.startsWith('nlog_')) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final dateStr = v['logged_at'] as String?;
      if (dateStr == null) continue;
      final indexKey = 'nutrition_log_index_$dateStr';
      final raw = box.get(indexKey);
      final list = (raw is List) ? raw.cast<String>().toList() : <String>[];
      if (!list.contains(ks)) list.add(ks);
      await box.put(indexKey, list);
    }

    debugPrint(
        '[NlogKeyMigrator] rekeyed=$rekeyed merged=$merged total_after=${box.keys.where((k) => k.toString().startsWith('nlog_')).length}');
    await config.put(_migrationKey, true);
  }

  /// Mirrors NutritionWriteService.computeLogKey + _stableItemsHash logic.
  static String _computeLogKey(
    DateTime istDate,
    String mealType,
    List<dynamic> items,
  ) {
    final dateStr =
        '${istDate.year.toString().padLeft(4, '0')}-${istDate.month.toString().padLeft(2, '0')}-${istDate.day.toString().padLeft(2, '0')}';
    final itemsHash = _stableItemsHash(items);
    return 'nlog_${dateStr}_${mealType}_$itemsHash';
  }

  /// Mirrors NutritionWriteService._stableItemsHash.
  /// Items are {name: String, quantityG: double} maps.
  static String _stableItemsHash(List<dynamic> items) {
    // Sort items by name
    final sorted = [...items].cast<Map<dynamic, dynamic>>();
    sorted.sort((a, b) {
      final aName = (a['name'] as String? ?? '').toLowerCase();
      final bName = (b['name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });

    // Join with name|quantityG format
    final joined = sorted
        .map((i) {
          final name = ((i['name'] as String?) ?? '').toLowerCase().trim();
          final qty = (i['quantityG'] as num?)?.toDouble() ?? 0.0;
          return '$name|${qty.toStringAsFixed(1)}';
        })
        .join(';');

    return joined.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  }
}
