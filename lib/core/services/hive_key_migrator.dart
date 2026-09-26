// APK Test #13 / Phase 2.5 — one-shot Hive KEY rename migrator with
// shadow-box backup.
//
// ## Background
//
// When a Hive key formula changes (e.g. `tmpl_<ms>` →
// `tmpl_<lower(name).hash>`), every existing row on-device retains the
// old key indefinitely. On the next restore, new writes use the canonical
// formula, leaving orphan rows under the old keys. This migrator provides
// a mechanical, one-shot repair path:
//
//   1. Open the target box.
//   2. For every key matching `oldPrefix`, compute the canonical new key
//      via `newKeyFn(oldKey, value)`.
//   3. If the new key already exists in the box, skip — collision is
//      logged so the caller can decide how to resolve duplicates.
//   4. Otherwise, copy the value under the new key, delete the old key,
//      and back up the pre-migration value to a shadow box named
//      `<boxName>_pre_<flagKey>_backup`.
//   5. Write `migrationBox[flagKey] = true` — guarantees the migrator
//      never runs twice on the same device, even across reinstalls.
//
// ## Usage
//
// ```dart
// await HiveKeyMigrator.run(
//   boxName: 'workoutBox',
//   oldPrefix: 'tmpl_',
//   newKeyFn: (oldKey, value) {
//     final name = (value['name'] as String).toLowerCase().trim();
//     return 'tmpl_${name.hashCode.toUnsigned(32).toRadixString(16)}';
//   },
//   flagKey: 'tmpl_key_formula_v2_done',
// );
// ```
//
// Call from the app's splash / init path, AFTER HiveService.init() and
// HiveUserSession.openForUser() have completed.
//
// ## Idempotency
//
// Gated by `migrationBox[flagKey] == true`. Flag survives
// `clearAllData()` (migrationBox lives in `_sharedBoxNames`, never
// cleared by sign-out). Safe to call on every cold start — short-circuits
// in < 1 ms on all subsequent runs.
//
// ## Collision handling
//
// When `newKeyFn` returns a key that already exists in the box, the source
// row is left untouched (not deleted). The collision is logged with the
// old and new key names so the caller can inspect duplicates after the
// migration. The first-come-first-served winner is whichever source key
// was iterated first (map iteration order).
//
// ## Shadow-box
//
// Named `<boxName>_pre_<flagKey>_backup`. Each row backed up contains the
// exact value from the source key BEFORE the rename. This lets you
// inspect / diff pre vs post state if a formula change introduces a
// regression. The shadow box is closed (not deleted) at the end of the
// run; it persists on disk but is not opened on regular app boots.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';

/// APK Test #13 / Phase 2.5 — one-shot Hive KEY rename migrator with
/// shadow-box backup. Sibling to [HiveFieldRenameMigrator] — that one
/// renames fields INSIDE a row's value Map; this one renames the row's
/// KEY itself.
///
/// Gated by `migrationBox[flagKey]` so it never runs twice on the same
/// device.
class HiveKeyMigrator {
  HiveKeyMigrator._();

  /// Rename keys matching [oldPrefix] in the box named [boxName] by
  /// computing each new key via [newKeyFn].
  ///
  /// [newKeyFn] receives `(oldKey, value)` and returns the canonical new
  /// key string. Returning the same value as [oldKey] is a no-op for that
  /// row.
  ///
  /// [flagKey] is written to `migrationBox` on completion; subsequent
  /// calls with the same [flagKey] are no-ops.
  ///
  /// On collision (target key already exists), the source row is left
  /// untouched. Collision details are printed via [debugPrint].
  static Future<void> run({
    required String boxName,
    required String oldPrefix,
    required String Function(String oldKey, Map value) newKeyFn,
    required String flagKey,
  }) async {
    // ── Guard: run at most once per device ──────────────────────────────
    final Box<dynamic> migrationBox = HiveService.instance.migrationBox;
    if (migrationBox.get(flagKey) == true) {
      debugPrint('[HiveKeyMigrator] $flagKey already done — skip');
      return;
    }

    // ── Open the target box ────────────────────────────────────────────
    final Box<dynamic> box = Hive.isBoxOpen(boxName)
        ? Hive.box<dynamic>(boxName)
        : await Hive.openBox<dynamic>(boxName);

    // ── Open the shadow backup box ─────────────────────────────────────
    final String shadowName = '${boxName}_pre_${flagKey}_backup';
    final Box<dynamic> shadow = await Hive.openBox<dynamic>(shadowName);

    // ── Walk keys, compute new key, copy + delete or skip ─────────────
    final List<dynamic> keys = box.keys.toList();
    final List<(String, String)> renames = [];
    final List<String> collisions = [];

    for (final dynamic key in keys) {
      if (key is! String || !key.startsWith(oldPrefix)) continue;
      final dynamic raw = box.get(key);
      if (raw is! Map) continue;

      final String newKey = newKeyFn(key, raw);
      if (newKey == key) continue;

      if (box.containsKey(newKey)) {
        collisions.add('$key → $newKey (target exists)');
        continue;
      }

      // Backup pre-migration state.
      await shadow.put(key, Map<dynamic, dynamic>.from(raw));

      // Move: write under new key, remove old key.
      await box.put(newKey, raw);
      await box.delete(key);
      renames.add((key, newKey));
    }

    // Close shadow box — not needed in memory after the migration.
    await shadow.close();

    // ── Write the idempotency flag ─────────────────────────────────────
    await migrationBox.put(flagKey, true);

    debugPrint(
      '[HiveKeyMigrator] $flagKey: renamed ${renames.length} key(s); '
      'collisions: ${collisions.length}; backup at $shadowName',
    );
    if (collisions.isNotEmpty) {
      debugPrint('[HiveKeyMigrator] collisions: $collisions');
    }
  }
}
