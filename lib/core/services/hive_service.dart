import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'hive_user_session.dart';

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
  static const String notificationsBoxName = 'notificationsBox';

  /// Shared boxes — opened by `init()` before runApp. Available to all
  /// users / no users.
  static const List<String> _sharedBoxNames = <String>[
    exerciseBoxName,
    foodBoxName,
    syncBoxName,
    configBoxName,
  ];

  /// User-scoped boxes — opened by `HiveUserSession.openForUser(id)`
  /// AFTER auth resolves. Each gets a `_<8hex>` namespace suffix.
  // ignore: unused_field
  static const List<String> _userScopedBoxNames = <String>[
    userBoxName,
    workoutBoxName,
    nutritionBoxName,
    healthBoxName,
    customBoxName,
    coachBoxName,
    notificationsBoxName,
  ];

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    for (final name in _sharedBoxNames) {
      await _safeOpenBox(name);
    }
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
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
    notificationsBoxName,
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
          final ownerId = HiveUserSession.currentOwnerFullId;
          // User-scoped boxes only compact when a user is signed in.
          // Shared boxes (configBox excluded — see _compactableBoxNames
          // comment on line ~104) compact regardless.
          final isUserScoped = HiveUserSession.userScopedBoxRoots.contains(name);
          if (isUserScoped && ownerId == null) {
            continue;
          }
          final actualBoxName = isUserScoped
              ? HiveUserSession.namespacedBoxName(name, ownerId!)
              : name;
          if (!Hive.isBoxOpen(actualBoxName)) continue;
          await Hive.box(actualBoxName).compact();
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
  //
  // Shared boxes (read-only seed + app-level config) resolve to a
  // single global box.
  Box get exerciseBox => getBox(exerciseBoxName);
  Box get foodBox => getBox(foodBoxName);
  Box get syncBox => getBox(syncBoxName);
  Box get configBox => getBox(configBoxName);

  // User-scoped boxes resolve to `<root>_<8hex>` based on the current
  // HiveUserSession owner. Throws StateError if no user is signed in
  // (caller bug — UI should never read user-scoped Hive on the
  // unauthenticated splash screen).
  Box get userBox => _userScopedBox(userBoxName);
  Box get workoutBox => _userScopedBox(workoutBoxName);
  Box get nutritionBox => _userScopedBox(nutritionBoxName);
  Box get healthBox => _userScopedBox(healthBoxName);
  Box get customBox => _userScopedBox(customBoxName);
  Box get coachBox => _userScopedBox(coachBoxName);
  Box get notificationsBox => _userScopedBox(notificationsBoxName);

  Box _userScopedBox(String root) {
    if (!_initialized) {
      throw StateError(
        'HiveService.init() must be called before accessing boxes.',
      );
    }
    final ownerId = HiveUserSession.currentOwnerFullId;
    if (ownerId == null) {
      throw StateError(
        'HiveUserSession not opened — cannot access user-scoped box "$root". '
        'Call HiveUserSession.openForUser(userId) after sign-in.',
      );
    }
    final boxName = HiveUserSession.namespacedBoxName(root, ownerId);
    return Hive.box(boxName);
  }

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
