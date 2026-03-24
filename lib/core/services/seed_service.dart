import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'hive_service.dart';

/// Seeds bundled JSON assets into Hive on first launch.
///
/// Exercises (200+) and foods (5,000) are shipped inside the APK as JSON
/// and parsed into their respective Hive boxes exactly once.
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

  /// Reads [_exerciseAssetPath] from the asset bundle and writes every
  /// exercise into exerciseBox keyed by its `id`.
  Future<void> _seedExercises() async {
    final jsonString = await rootBundle.loadString(_exerciseAssetPath);
    final List<dynamic> exercises = json.decode(jsonString) as List<dynamic>;

    final exerciseBox = _hive.exerciseBox;

    final Map<String, dynamic> entries = {};
    for (final exercise in exercises) {
      final map = exercise as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id != null) {
        entries[id] = map;
      }
    }

    await exerciseBox.putAll(entries);
  }

  /// Reads [_foodAssetPath] from the asset bundle and writes every
  /// food item into foodBox keyed by its `id`.
  Future<void> _seedFoods() async {
    final jsonString = await rootBundle.loadString(_foodAssetPath);
    final List<dynamic> foods = json.decode(jsonString) as List<dynamic>;

    final foodBox = _hive.foodBox;

    final Map<String, dynamic> entries = {};
    for (final food in foods) {
      final map = food as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id != null) {
        entries[id] = map;
      }
    }

    await foodBox.putAll(entries);
  }
}
