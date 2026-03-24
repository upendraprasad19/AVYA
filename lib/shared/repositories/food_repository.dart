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

  /// Returns a single food item by its [id], or null.
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
