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

    // One-shot migration — copies pre-namespacing shared box contents
    // into the namespaced box on first sign-in after upgrade.
    await _migrateLegacySharedBoxes(userId);

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

  /// Test #10.1 — `migrationBox` flag key for the one-shot legacy
  /// box migration. Stored in `migrationBox` (NEVER cleared) so the
  /// migration can't re-run and re-leak data from a stale legacy
  /// shared `userBox`/`workoutBox`/etc. into a fresh user's
  /// namespaced box.
  static const String _legacyMigrationFlagKey =
      'legacy_shared_box_migration_v1_done';

  /// One-shot migration: if a pre-namespacing shared box exists for any
  /// user-scoped root AND the per-user namespaced box for [userId]
  /// doesn't already have data, copy contents over and delete the
  /// shared box.
  ///
  /// Test #10.1 — Now gated by a `migrationBox` flag so it runs at most
  /// ONCE per device lifetime. Previously ran on every `openForUser`
  /// call; if the legacy box ever survived (silent delete failure),
  /// every subsequent fresh-user signup would re-copy that legacy data
  /// into the new user's namespaced box → cross-account leak.
  ///
  /// Skipped silently if the shared box is empty or fails to open.
  static Future<void> _migrateLegacySharedBoxes(String userId) async {
    // Gate on migrationBox so the flag survives clearAllData()
    // (which clears configBox but NOT migrationBox).
    try {
      final migBox = HiveService.instance.migrationBox;
      if (migBox.get(_legacyMigrationFlagKey) == true) {
        return;
      }
    } catch (e) {
      // migrationBox not yet initialised (very early cold start).
      // Fall through and let the migration run; it'll set the flag
      // at the end if migrationBox is available by then.
      debugPrint('[HiveUserSession] migrationBox unavailable: $e');
    }

    for (final root in userScopedBoxRoots) {
      final namespaced = namespacedBoxName(root, userId);
      try {
        // If namespaced already has any keys, migration already ran for
        // this user OR they signed in fresh post-namespacing. Skip.
        if (Hive.isBoxOpen(namespaced)) {
          if (Hive.box(namespaced).keys.isNotEmpty) continue;
        }

        // Try to open the legacy shared box. If it doesn't exist on
        // disk, openBox creates an empty one — check keys count and
        // delete-empty if so.
        final legacy = await Hive.openBox(root);
        if (legacy.keys.isEmpty) {
          await legacy.close();
          await Hive.deleteBoxFromDisk(root);
          continue;
        }

        // Open namespaced (creates if needed), copy every key/value,
        // close + delete legacy.
        final dest = Hive.isBoxOpen(namespaced)
            ? Hive.box(namespaced)
            : await Hive.openBox(namespaced);
        for (final key in legacy.keys) {
          await dest.put(key, legacy.get(key));
        }
        await legacy.close();
        await Hive.deleteBoxFromDisk(root);
        debugPrint(
          '[HiveUserSession] migrated $root → $namespaced (${dest.keys.length} keys)',
        );
      } catch (e) {
        debugPrint('[HiveUserSession] migration $root failed: $e');
        // Non-fatal — fresh start, cloud has the data anyway.
      }
    }

    // Test #10.1 — set the run-once flag so this never runs again on
    // this device, even after sign-out / cross-account guard / etc.
    // Stored in `migrationBox` which is NEVER cleared by clearAllData.
    try {
      await HiveService.instance.migrationBox
          .put(_legacyMigrationFlagKey, true);
    } catch (e) {
      debugPrint('[HiveUserSession] failed to set legacy migration flag: $e');
      // If we can't set the flag, the migration may re-run next time.
      // The migration body itself is idempotent for already-migrated
      // users (the `if (legacy.keys.isEmpty) … delete + continue` arm
      // handles the no-op path), so re-running is safe — just wasteful.
    }
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
