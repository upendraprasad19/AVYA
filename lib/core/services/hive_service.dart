import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Singleton service that manages all Hive boxes.
///
/// Registers adapters and opens all 10 boxes on app startup.
/// All reads/writes go through Hive first (offline-first architecture).
///
/// Also implements [WidgetsBindingObserver] to trigger periodic
/// `box.compact()` on app pause (added 2026-04-18 per audit H1).
/// Hive's underlying file is append-only — deletes and overwrites leave
/// "dead" bytes that can inflate box size 30-60% over months of use.
/// Compaction rewrites the file, keeping only live entries. Gated at
/// once per 7 days via `configBox['last_compact_at']` to avoid
/// compacting on every short background → foreground cycle.
class HiveService with WidgetsBindingObserver {
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

    // Register lifecycle observer for periodic compact on pause.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Not running inside a Flutter binding (e.g. unit tests) — skip.
    }
  }

  // ── Lifecycle-driven compaction ──────────────────────────────

  /// Boxes that see frequent writes/deletes and benefit most from compact.
  /// exerciseBox + foodBox are seed-only (ship with the APK, barely
  /// mutated) so we skip them — pure waste of CPU.
  static const List<String> _compactableBoxNames = [
    userBoxName,
    workoutBoxName,
    nutritionBoxName,
    healthBoxName,
    customBoxName,
    coachBoxName,
    syncBoxName,
    // configBox stays excluded — tiny and we store `last_compact_at`
    // there, which would churn the compaction state itself.
  ];

  /// Minimum interval between compact passes. Runs at most once per week
  /// even if the user pauses the app dozens of times in between.
  static const Duration _compactInterval = Duration(days: 7);

  /// Key in `configBox` holding the last successful compact timestamp.
  static const String _lastCompactKey = 'last_compact_at';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Compact on `paused` — the app is still in memory but the user has
    // left it. Safe window to do background IO. We specifically skip
    // `detached` (app's about to be killed; no point starting work).
    if (state == AppLifecycleState.paused) {
      _maybeCompact();
    }
  }

  /// Runs `box.compact()` on the mutation-heavy boxes if >= 7 days since
  /// the last pass. Fire-and-forget — never blocks caller. Errors are
  /// logged but swallowed (a failed compact is harmless).
  Future<void> _maybeCompact() async {
    if (!_initialized) return;
    try {
      final cfg = configBox;
      final lastStr = cfg.get(_lastCompactKey) as String?;
      if (lastStr != null) {
        final last = DateTime.tryParse(lastStr);
        if (last != null && DateTime.now().difference(last) < _compactInterval) {
          return;
        }
      }

      for (final name in _compactableBoxNames) {
        try {
          await Hive.box(name).compact();
        } catch (e) {
          debugPrint('[HiveService._maybeCompact] $name: $e');
        }
      }

      await cfg.put(_lastCompactKey, DateTime.now().toIso8601String());
      debugPrint('[HiveService] compact pass complete');
    } catch (e) {
      debugPrint('[HiveService._maybeCompact] $e');
    }
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

  /// Test-only hook. Marks the singleton as initialized after the test
  /// has opened the boxes itself with raw `Hive.openBox`. Avoids calling
  /// [init] (which routes through `Hive.initFlutter` + path_provider) in
  /// pure-VM unit tests. Production callers must use [init].
  @visibleForTesting
  void markInitializedForTests() {
    _initialized = true;
  }

  /// Static convenience wrapper for [markInitializedForTests].
  @visibleForTesting
  static void debugMarkInitializedForTests() =>
      _instance.markInitializedForTests();
}
