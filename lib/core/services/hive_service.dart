import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Singleton service that manages all Hive boxes.
///
/// Registers adapters and opens all 10 boxes on app startup.
/// All reads/writes go through Hive first (offline-first architecture).
class HiveService {
  HiveService._();
  static final HiveService _instance = HiveService._();
  static HiveService get instance => _instance;

  bool _initialized = false;

  /// Whether [init] has completed successfully.
  bool get isInitialized => _initialized;

  /// All box names used by the app.
  static const String userBoxName = 'userBox';
  static const String workoutBoxName = 'workoutBox';
  static const String nutritionBoxName = 'nutritionBox';
  static const String healthBoxName = 'healthBox';
  static const String exerciseBoxName = 'exerciseBox';
  static const String foodBoxName = 'foodBox';
  static const String customBoxName = 'customBox';
  static const String coachBoxName = 'coachBox';
  static const String syncBoxName = 'syncBox';
  static const String configBoxName = 'configBox';

  static const List<String> _allBoxNames = [
    userBoxName,
    workoutBoxName,
    nutritionBoxName,
    healthBoxName,
    exerciseBoxName,
    foodBoxName,
    customBoxName,
    coachBoxName,
    syncBoxName,
    configBoxName,
  ];

  /// Initialize Hive: register adapters and open all boxes.
  ///
  /// Must be called once in main() before runApp().
  /// Safe to call multiple times — skips if already initialized.
  Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();

    // Register custom Hive adapters here as models are created.
    // For now we use Map<dynamic, dynamic> storage (no adapters needed).
    // Example:
    //   Hive.registerAdapter(UserProfileAdapter());

    // Open all boxes in parallel for fastest startup.
    // Uses safe open — if a box is corrupted, it is deleted and recreated
    // rather than crashing the app in an irrecoverable loop.
    await Future.wait(
      _allBoxNames.map((name) => _safeOpenBox(name)),
    );

    _initialized = true;
  }

  /// Opens a Hive box safely.
  ///
  /// If the box is corrupted (e.g. app was killed mid-write), deletes it
  /// and opens a fresh empty box rather than crashing the app permanently.
  Future<Box> _safeOpenBox(String name) async {
    try {
      return await Hive.openBox(name);
    } catch (e) {
      debugPrint('[HiveService._safeOpenBox] $e');
      await Hive.deleteBoxFromDisk(name);
      return await Hive.openBox(name);
    }
  }

  /// Returns a previously opened Hive box by name.
  ///
  /// Throws [StateError] if [init] has not been called.
  /// Throws [HiveError] if the box name is invalid.
  Box getBox(String name) {
    if (!_initialized) {
      throw StateError(
        'HiveService.init() must be called before accessing boxes.',
      );
    }
    return Hive.box(name);
  }

  // ── Convenience getters for each box ──────────────────────────

  Box get userBox => getBox(userBoxName);
  Box get workoutBox => getBox(workoutBoxName);
  Box get nutritionBox => getBox(nutritionBoxName);
  Box get healthBox => getBox(healthBoxName);
  Box get exerciseBox => getBox(exerciseBoxName);
  Box get foodBox => getBox(foodBoxName);
  Box get customBox => getBox(customBoxName);
  Box get coachBox => getBox(coachBoxName);
  Box get syncBox => getBox(syncBoxName);
  Box get configBox => getBox(configBoxName);
}
