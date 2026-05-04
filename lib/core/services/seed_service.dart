import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
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
///
/// Uses granular flags (`seeded_exercises`, `seeded_foods`) so that if
/// one asset fails (corrupt file, disk full), the other can still succeed
/// and the failed one retries on next launch.
class SeedService {
  SeedService._();
  static final SeedService _instance = SeedService._();
  static SeedService get instance => _instance;

  static const String _exerciseAssetPath = 'assets/data/exercise_library.json';
  static const String _foodAssetPath = 'assets/data/food_database.json';

  /// Legacy flag — kept for backward compat with existing installs.
  static const String _seededKey = 'seeded';

  /// Granular flags — one per asset, so partial failures are retried.
  static const String _exercisesSeededKey = 'seeded_exercises';
  static const String _foodsSeededKey = 'seeded_foods';

  /// Bump this integer whenever the bundled exercise_library.json changes
  /// (new exercises added, existing exercises modified). On app launch, if the
  /// stored version is less than this, exercises are re-seeded. putAll() is
  /// idempotent — existing entries are overwritten with the same data while
  /// new entries are added.
  static const int _exerciseLibraryVersion = 5;
  static const String _exerciseVersionKey = 'exercise_library_version';

  /// Bump this integer whenever the bundled food_database.json changes
  /// (new foods added, existing foods modified, schema extended). On app
  /// launch, if the stored version is less than this, foods are re-seeded.
  /// putAll() is idempotent — existing entries are overwritten with the
  /// same data while new entries are added.
  static const int _foodLibraryVersion = 2;
  static const String _foodVersionKey = 'food_library_version';

  final HiveService _hive = HiveService.instance;

  /// Checks if seed data has already been loaded; if not, seeds both
  /// exercise and food databases into Hive.
  ///
  /// On subsequent launches this returns immediately (fast path).
  /// Partial failures are handled: if exercises succeed but foods fail,
  /// exercises won't be re-seeded on the next launch.
  Future<void> seedIfNeeded() async {
    final configBox = _hive.configBox;

    // Fast path: both already seeded (or legacy flag from previous version).
    final alreadySeeded = configBox.get(_seededKey, defaultValue: false) as bool;
    final exercisesSeeded =
        configBox.get(_exercisesSeededKey, defaultValue: false) as bool;
    final foodsSeeded =
        configBox.get(_foodsSeededKey, defaultValue: false) as bool;

    // Check if exercise library needs a version upgrade (new exercises added).
    final storedExVersion =
        configBox.get(_exerciseVersionKey, defaultValue: 0) as int;
    final needExerciseUpgrade =
        exercisesSeeded && storedExVersion < _exerciseLibraryVersion;

    // Check if food library needs a version upgrade (new foods added).
    final storedFdVersion =
        configBox.get(_foodVersionKey, defaultValue: 0) as int;
    final needFoodUpgrade =
        foodsSeeded && storedFdVersion < _foodLibraryVersion;

    if (alreadySeeded &&
        exercisesSeeded &&
        foodsSeeded &&
        !needExerciseUpgrade &&
        !needFoodUpgrade) {
      return;
    }

    // If legacy flag is set but granular flags aren't, migrate.
    if (alreadySeeded && !exercisesSeeded) {
      await configBox.put(_exercisesSeededKey, true);
    }
    if (alreadySeeded && !foodsSeeded) {
      await configBox.put(_foodsSeededKey, true);
    }
    // Don't early-return here if a version upgrade is needed — legacy installs
    // may have alreadySeeded=true but stale library versions.
    if (alreadySeeded && !needExerciseUpgrade && !needFoodUpgrade) return;

    // Seed each asset independently — partial failures don't block the other.
    final needExercises = !exercisesSeeded || needExerciseUpgrade;
    final needFoods = !foodsSeeded || needFoodUpgrade;

    await Future.wait(
      [
        if (needExercises) _seedExercises(),
        if (needFoods) _seedFoods(),
      ],
      eagerError: false, // Let both complete even if one fails
    );

    // Mark individual success flags. The results list maps 1:1 with the
    // futures we passed in, but since we used conditional list entries,
    // we track success via try/catch inside each seed method instead.
    // (The actual success tracking is done by the methods themselves.)

    // If both granular flags are now set, mark legacy flag too.
    final exDone =
        configBox.get(_exercisesSeededKey, defaultValue: false) as bool;
    final fdDone =
        configBox.get(_foodsSeededKey, defaultValue: false) as bool;

    if (exDone && fdDone) {
      await configBox.put(_seededKey, true);
    }
  }

  /// Reads [_exerciseAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every exercise into exerciseBox keyed
  /// by its `id`.
  Future<void> _seedExercises() async {
    try {
      final jsonString = await rootBundle.loadString(_exerciseAssetPath);
      final entries = await compute(_parseJsonToIdMap, jsonString);
      await _hive.exerciseBox.putAll(entries);
      await _hive.configBox.put(_exercisesSeededKey, true);
      await _hive.configBox.put(_exerciseVersionKey, _exerciseLibraryVersion);
      debugPrint('[SeedService] Exercises seeded: ${entries.length} items (v$_exerciseLibraryVersion)');
    } catch (e) {
      debugPrint('[SeedService._seedExercises] FAILED: $e');
      // Will retry on next launch since _exercisesSeededKey stays false.
    }
  }

  /// Reads [_foodAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every food item into foodBox keyed
  /// by its `id`.
  Future<void> _seedFoods() async {
    try {
      final jsonString = await rootBundle.loadString(_foodAssetPath);
      final entries = await compute(_parseJsonToIdMap, jsonString);
      await _hive.foodBox.putAll(entries);
      await _hive.configBox.put(_foodsSeededKey, true);
      await _hive.configBox.put(_foodVersionKey, _foodLibraryVersion);
      debugPrint(
        '[SeedService] Foods seeded: ${entries.length} items (v$_foodLibraryVersion)',
      );
    } catch (e) {
      debugPrint('[SeedService._seedFoods] FAILED: $e');
      // Will retry on next launch since _foodsSeededKey stays false.
    }
  }
}
