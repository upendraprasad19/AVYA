import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import 'hive_service.dart';

// Top-level function required by compute() — runs in a background isolate.
// Parses a JSON array string into a Map keyed by each item's 'id' field.
Map<String, dynamic> _parseJsonToIdMap(String jsonString) {
  final List<dynamic> items = json.decode(jsonString) as List<dynamic>;
  final Map<String, dynamic> result = {};
  for (final item in items) {
    final map = item as Map<String, dynamic>;
    final id = map['id'] as String?;
    if (id != null) result[id] = map;
  }
  return result;
}

/// Seeds bundled JSON assets into Hive on first launch.
///
/// Exercises (200+) and foods (5,000) are shipped inside the APK as JSON
/// and parsed into their respective Hive boxes exactly once.
///
/// JSON parsing runs in a background isolate via [compute] to avoid
/// blocking the main thread during first-launch seeding.
class SeedService {
  SeedService._();
  static final SeedService _instance = SeedService._();
  static SeedService get instance => _instance;

  static const String _exerciseAssetPath = 'assets/data/exercise_library.json';
  static const String _foodAssetPath = 'assets/data/food_database.json';
  static const String _seededKey = 'seeded';

  final HiveService _hive = HiveService.instance;

  /// Checks if seed data has already been loaded; if not, seeds both
  /// exercise and food databases into Hive.
  ///
  /// On subsequent launches this returns immediately (fast path).
  Future<void> seedIfNeeded() async {
    final configBox = _hive.configBox;
    final alreadySeeded = configBox.get(_seededKey, defaultValue: false) as bool;

    if (alreadySeeded) return;

    await Future.wait([
      _seedExercises(),
      _seedFoods(),
    ]);

    await configBox.put(_seededKey, true);
  }

  /// Reads [_exerciseAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every exercise into exerciseBox keyed
  /// by its `id`.
  Future<void> _seedExercises() async {
    final jsonString = await rootBundle.loadString(_exerciseAssetPath);
    final entries = await compute(_parseJsonToIdMap, jsonString);
    await _hive.exerciseBox.putAll(entries);
  }

  /// Reads [_foodAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every food item into foodBox keyed
  /// by its `id`.
  Future<void> _seedFoods() async {
    final jsonString = await rootBundle.loadString(_foodAssetPath);
    final entries = await compute(_parseJsonToIdMap, jsonString);
    await _hive.foodBox.putAll(entries);
  }
}
