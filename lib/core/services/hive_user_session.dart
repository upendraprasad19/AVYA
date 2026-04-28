import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'hive_service.dart';

/// Owns the per-user Hive box lifecycle. Opens namespaced boxes
/// (`<box>_<8hex>`) when the user signs in; closes them on sign-out.
///
/// User-scoped boxes — userBox / workoutBox / nutritionBox / healthBox /
/// coachBox / customBox / notificationsBox — are physically separate
/// Hive box files per user. Cross-account leaks become impossible at
/// the storage layer: Avyaansh's sign-in opens `coachBox_94368fd4`,
/// which has no relationship to Upendra's `coachBox_5f0a13b2`.
///
/// Shared boxes — exerciseBox / foodBox / configBox / syncBox — are
/// owned by `HiveService` directly and stay open across the app
/// lifetime; they are NOT touched by this class.
///
/// Bootstrap order (cold start):
///   1. main.dart runs `HiveService.instance.init()` — opens shared
///      boxes only.
///   2. Auth resolves → `_ensureLocalUser` → on success
///      `HiveUserSession.openForUser(user.id)` opens the 7
///      user-scoped boxes.
///   3. UI mounts. Reads through `HiveService.instance.userBox` etc.
///      transparently route to the namespaced box via
///      `currentOwnerHash`.
class HiveUserSession {
  HiveUserSession._();

  /// 8-hex prefix of the currently signed-in user.id. Null when no
  /// user-scoped boxes are open (cold start before sign-in,
  /// post-sign-out before the next sign-in).
  static String? _currentOwnerHash;

  /// Full user.id of the current owner. Stored alongside the hash so
  /// guards can compare full ids without depending on prefix collisions.
  static String? _currentOwnerFullId;

  static String? get currentOwnerHash => _currentOwnerHash;
  static String? get currentOwnerFullId => _currentOwnerFullId;

  /// The 7 user-scoped box roots. Each gets `_<hash>` appended at open.
  static const List<String> userScopedBoxRoots = <String>[
    HiveService.userBoxName,
    HiveService.workoutBoxName,
    HiveService.nutritionBoxName,
    HiveService.healthBoxName,
    HiveService.coachBoxName,
    HiveService.customBoxName,
    HiveService.notificationsBoxName,
  ];

  /// Compute the namespaced box name for a given root + user.id.
  /// `userBox` + `5f0a13b2-...` → `userBox_5f0a13b2`.
  static String namespacedBoxName(String root, String userId) {
    final hash = userId.replaceAll('-', '').substring(0, 8);
    return '${root}_$hash';
  }

  /// Open the 7 user-scoped boxes for [userId]. Idempotent — calling
  /// twice with the same id is a no-op. Calling with a different id
  /// closes the previous user's boxes first.
  ///
  /// Throws [HiveError] if a box file is corrupted; caller should
  /// surface this as a fatal error and force the user to reinstall.
  static Future<void> openForUser(String userId) async {
    if (_currentOwnerFullId == userId) {
      return;
    }
    if (_currentOwnerFullId != null) {
      await closeAll();
    }

    final hash = userId.replaceAll('-', '').substring(0, 8);
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }

    _currentOwnerHash = hash;
    _currentOwnerFullId = userId;
    debugPrint('[HiveUserSession] opened 7 boxes for user $hash');
  }

  /// Close + clear references to all user-scoped boxes. Files remain
  /// on disk (use `clearAllDataForCurrentUser` to delete contents).
  static Future<void> closeAll() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
    }
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
    debugPrint('[HiveUserSession] closed all user-scoped boxes');
  }

  /// Delete every user-scoped box file for the **current** user.
  /// Used by signOut so leftover bytes can't surface on next sign-in.
  static Future<void> deleteAllFilesForCurrentUser() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
        await Hive.deleteBoxFromDisk(boxName);
      } catch (e) {
        debugPrint('[HiveUserSession] failed to delete $boxName: $e');
      }
    }
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
  }
}
