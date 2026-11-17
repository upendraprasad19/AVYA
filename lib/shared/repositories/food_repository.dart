import 'package:icanbefitter/core/services/hive_service.dart';

/// Queries the foodBox (seeded from bundled JSON).
///
/// All reads are local Hive lookups — zero network latency.
/// 5,000 Indian-first foods available offline.
class FoodRepository {
  FoodRepository._();
  static final FoodRepository _instance = FoodRepository._();
  static FoodRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  /// Returns all food items as a list of maps.
  List<Map<String, dynamic>> getAll() {
    final box = _hive.foodBox;
    return box.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// The user's OWN foods (`custom_food_*` keys of the customBox), for the Diet
  /// chart's swap search (diet chart v3).
  ///
  /// Selected by the key PREFIX alone: a row restored from the cloud
  /// (`sync_community.dart`) carries no `type` and no `is_custom`, and
  /// requiring either hid every restored food (APK Test #15.4, the same bug in
  /// `exercise_repository.dart`). Custom exercises use `custom_exercise_`. The
  /// key's suffix is injected as `id` when a row has none.
  List<Map<String, dynamic>> getCustomFoods() {
    final box = _hive.customBox;
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('custom_food_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      row['id'] ??= key.substring('custom_food_'.length);
      if ((row['name'] as String?)?.trim().isNotEmpty != true) continue;
      out.add(row);
    }
    return out;
  }

  /// Returns a single food item by its [id], or null.
  ///
  /// gate16-exempt: seed-data read. The food JSON already carries its
  /// `id` field (stable seed identifier); the Hive key equals the id.
  /// No re-injection needed.
  Map<String, dynamic>? getById(String id) {
    final raw = _hive.foodBox.get(id);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Full-text search across food name.
  ///
  /// Case-insensitive substring match. Returns up to [limit] results
  /// (default 50) for performance with 5K items.
  List<Map<String, dynamic>> search(String query, {int limit = 50}) {
    if (query.isEmpty) return getAll().take(limit).toList();

    final q = query.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final raw in _hive.foodBox.values) {
      final food = Map<String, dynamic>.from(raw as Map);
      final name = (food['name'] as String?)?.toLowerCase() ?? '';
      if (name.contains(q)) {
        results.add(food);
        if (results.length >= limit) break;
      }
    }

    return results;
  }

  /// Returns food items filtered by [category].
  List<Map<String, dynamic>> getByCategory(String category) {
    return getAll()
        .where((f) =>
            (f['category'] as String?)?.toLowerCase() ==
            category.toLowerCase())
        .toList();
  }

  /// Returns all distinct categories present in the food database.
  List<String> getCategories() {
    final categories = <String>{};
    for (final f in getAll()) {
      final cat = f['category'] as String?;
      if (cat != null) categories.add(cat);
    }
    return categories.toList()..sort();
  }

  /// Returns Indian foods only (is_indian == true).
  List<Map<String, dynamic>> getIndianFoods({int limit = 50}) {
    final results = <Map<String, dynamic>>[];
    for (final raw in _hive.foodBox.values) {
      final food = Map<String, dynamic>.from(raw as Map);
      if (food['is_indian'] == true) {
        results.add(food);
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}
