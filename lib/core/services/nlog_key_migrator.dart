import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'nutrition_write_service.dart';

/// One-shot migration from `nlog_<timestamp>` (Test #5 and earlier)
/// to `nlog_<date>_<mealType>_<hash(items)>` (Plan C).
///
/// The key this migrator computes is NOT the writer's key: [_stableItemsHash]
/// is `String.hashCode` over `name|quantityG` (a field `FoodItem.toMap` never
/// writes — it writes `quantity_g` — so every grams value reads 0.0), on the
/// date of `logged_at`. The writer (`NutritionWriteService.computeLogKey`) is
/// UUID v5 over `name|grams` on the IST day. (This comment said "mirrors the
/// v5 hash" until OI-493 Landing B; it never did.)
///
/// OI-493 Landing B (B4), founder decision F4 (the same meal logged twice is
/// two entries):
/// - a row whose key already has the current shape
///   (`NutritionWriteService.kNlogKeyShape`, with or without an occurrence
///   suffix) is LEFT ALONE: before, a fresh device's first restore re-keyed
///   every v5 row to a hashCode key on the UTC day of `logged_at` and kept
///   only the latest row of a group, collapsing repeat servings;
/// - legacy rows (`nlog_<ms>`, `nlog_<uuid>`) are still re-keyed, but each
///   keeps its own entry: a group of N takes the first free occurrences of its
///   computed key (read against the live box after each put), not the latest
///   row only. Each copy records `migrated_from`, so a run interrupted between
///   a put and its delete only finishes the delete next time (idempotent).
///   Legacy keys stay the hashCode shape (testers only; no reader
///   parses the key).
///
/// Idempotent — guarded by configBox['nlog_key_migration_v7'].
/// Bumped v6 → v7 in H-17 when the writer's hash changed from
/// `String.hashCode` to UUID v5.
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

    // OI-493 Landing B (B4): legacy keys an interrupted earlier run already
    // copied (put done, delete not): the copy carries `migrated_from`, so a
    // re-run only finishes the delete instead of writing a second copy.
    final alreadyCopied = <String>{
      for (final k in oldKeys)
        if (box.get(k) case final Map v)
          if (v['migrated_from'] case final String from) from,
    };

    // Group existing entries by their NEW key.
    final byNewKey = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final oldKey in oldKeys) {
      // OI-493 Landing B (B4): a current-shape row is never regrouped.
      if (NutritionWriteService.kNlogKeyShape.hasMatch(oldKey)) continue;
      if (alreadyCopied.contains(oldKey)) {
        await box.delete(oldKey);
        continue;
      }
      final v = box.get(oldKey);
      if (v is! Map) continue;
      final m = v.cast<String, dynamic>();
      final dateStr = m['logged_at'] as String?;
      final mealType = m['meal_type'] as String? ?? 'custom';
      final items = m['items'] as List?;
      if (dateStr == null || items == null) continue;

      // The date of `logged_at` (a UTC instant for current rows).
      DateTime? d;
      try {
        d = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }

      // The legacy key (hashCode; NOT the writer's v5 key, see the class comment).
      final newKey = _computeLogKey(d, mealType, items);
      byNewKey.putIfAbsent(newKey, () => []).add(MapEntry(oldKey, m));
    }

    // OI-493 Landing B (B4): every legacy row keeps its own entry, oldest
    // first, each at the first FREE occurrence of its group's key (never over
    // a skipped current-shape row, never over a row this loop just wrote).
    for (final entry in byNewKey.entries) {
      final newKey = entry.key;
      final group = entry.value;
      group.sort((a, b) {
        final at = (a.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        final bt = (b.value['updated_at_ms'] as num?)?.toInt() ?? 0;
        return at.compareTo(bt);
      });

      for (final mEntry in group) {
        final row = Map<String, dynamic>.from(mEntry.value)
          ..['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
        // Write under the new key FIRST, then delete the old key (b8d5c2
        // B-pass F1): an interrupted put never leaves the row deleted with
        // nothing written. The choice and the put have no `await` between.
        final target = NutritionWriteService.firstFreeLogKey(
            box.containsKey, newKey);
        row['id'] = target;
        row['log_key'] = target;
        row['migrated_from'] = mEntry.key;
        await box.put(target, row);
        await box.delete(mEntry.key);
        rekeyed++;
        if (group.length > 1) merged++;
      }
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

  /// The LEGACY key (see the class comment): NOT the writer's v5 key.
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

  /// `String.hashCode` over `name|quantityG` (legacy; see the class comment).
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
