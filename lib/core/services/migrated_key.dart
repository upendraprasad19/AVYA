// Test #10.1 — Helper for accessing keys that have been migrated from
// the shared `configBox` to the per-user `userBox` by [UserConfigMigrator].
//
// Behavior:
//   - Read: try `userBox` first; if no session is open (pre-auth) or
//     the key isn't there, fall back to `configBox` for compatibility
//     with installs that haven't yet run the migration.
//   - Write: always to `userBox`. If no session is open, falls back to
//     `configBox` so pre-auth writes still land somewhere — those keys
//     migrate to `userBox` automatically on the next `_ensureLocalUser`.
//   - Delete: deletes from both boxes (defensive).
//
// Once every install has gone through `_ensureLocalUser` post-hotfix,
// `configBox` will be clean for these keys and only `userBox` will hold
// the data. The fallback paths can be deleted in a future cleanup.
//
// IMPORTANT: only use for keys listed in
// `UserConfigMigrator.userScopedKeys`. Don't use this for genuinely
// device-level keys (units_metric, seed flags, etc.).

import 'package:flutter/foundation.dart';
import 'hive_service.dart';
import 'hive_user_session.dart';

class MigratedKey {
  MigratedKey._();

  /// Read a value, preferring the per-user `userBox`.
  static T? read<T>(String key) {
    final hive = HiveService.instance;
    // Try userBox first IF a session is open.
    if (HiveUserSession.currentOwnerFullId != null) {
      try {
        final v = hive.userBox.get(key);
        if (v != null) return v as T?;
      } catch (e) {
        debugPrint('[MigratedKey.read] userBox $key threw: $e');
      }
    }
    // Fallback to configBox (pre-migration installs / no-session reads).
    try {
      return hive.configBox.get(key) as T?;
    } catch (e) {
      debugPrint('[MigratedKey.read] configBox $key threw: $e');
      return null;
    }
  }

  /// Read a value with a default. Equivalent to `read<T>(key) ?? defaultValue`.
  static T readWithDefault<T>(String key, T defaultValue) {
    return read<T>(key) ?? defaultValue;
  }

  /// Returns whether either box contains the key.
  static bool containsKey(String key) {
    final hive = HiveService.instance;
    if (HiveUserSession.currentOwnerFullId != null) {
      try {
        if (hive.userBox.containsKey(key)) return true;
      } catch (_) {}
    }
    try {
      return hive.configBox.containsKey(key);
    } catch (_) {
      return false;
    }
  }

  /// Write a value, preferring the per-user `userBox`. Falls back to
  /// `configBox` if no session is open.
  static Future<void> write(String key, dynamic value) async {
    final hive = HiveService.instance;
    if (HiveUserSession.currentOwnerFullId != null) {
      try {
        await hive.userBox.put(key, value);
        return;
      } catch (e) {
        debugPrint('[MigratedKey.write] userBox $key threw: $e — falling back to configBox');
      }
    }
    try {
      await hive.configBox.put(key, value);
    } catch (e) {
      debugPrint('[MigratedKey.write] configBox $key threw: $e');
    }
  }

  /// Delete a key from both boxes (defensive — in case it lingers in
  /// configBox after a partial migration).
  static Future<void> delete(String key) async {
    final hive = HiveService.instance;
    if (HiveUserSession.currentOwnerFullId != null) {
      try {
        await hive.userBox.delete(key);
      } catch (e) {
        debugPrint('[MigratedKey.delete] userBox $key threw: $e');
      }
    }
    try {
      await hive.configBox.delete(key);
    } catch (e) {
      debugPrint('[MigratedKey.delete] configBox $key threw: $e');
    }
  }
}
