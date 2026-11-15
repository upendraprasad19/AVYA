// APK Test #13 / Phase 2.3 — one-shot Hive field-rename migrator with
// shadow-box backup.
//
// ## Background
//
// When a Hive field name changes (e.g. `set_number` → `sets_completed`),
// every existing row on-device retains the old field name indefinitely.
// Readers that switched to the new name silently get null / default values.
// This migrator provides a mechanical, one-shot repair path:
//
//   1. Open the target box.
//   2. For every key matching `keyPrefix`, find `oldFieldName` in the
//      value Map, write the value under `newFieldName`, and remove
//      `oldFieldName`.
//   3. Before touching any row, back up the pre-migration value to a
//      shadow box named `<boxName>_pre_<flagKey>_backup`. The shadow box
//      is closed after the run so it doesn't consume memory.
//   4. Write `migrationBox[flagKey] = true` — guarantees the migrator
//      never runs twice on the same device, even across reinstalls (the
//      migrationBox is intentionally NOT cleared by `clearAllData()`).
//
// ## Usage
//
// ```dart
// await HiveFieldRenameMigrator.run(
//   boxName: 'workoutBox',
//   keyPrefix: 'exlog_',
//   oldFieldName: 'sets_completed',
//   newFieldName: 'set_number',
//   flagKey: 'exlog_sets_completed_to_set_number_v1_done',
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
// ## Shadow-box
//
// Named `<boxName>_pre_<flagKey>_backup`. Each row written into the
// shadow box is an exact copy of the Hive value BEFORE the rename.
// This lets you inspect / diff the pre vs post state if a rename
// introduces a regression. The shadow box is closed (not deleted)
// at the end of the run; it persists on disk but is not opened on
// regular app boots.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';

/// APK Test #13 / Phase 2.3 — one-shot Hive field rename migrator with
/// shadow-box backup. Gated by `migrationBox[flagKey]` so it never runs
/// twice on the same device.
class HiveFieldRenameMigrator {
  HiveFieldRenameMigrator._();

  /// Rename [oldFieldName] → [newFieldName] in every value Map whose key
  /// starts with [keyPrefix] inside the box named [boxName].
  ///
  /// [flagKey] is written to `migrationBox` on completion; subsequent
  /// calls with the same [flagKey] are no-ops.
  ///
  /// The box must be open (or openable via `Hive.openBox`) before calling.
  /// If [boxName] is a user-scoped box, call AFTER
  /// `HiveUserSession.openForUser(userId)` so the namespaced box name is
  /// already known and open.
  static Future<void> run({
    required String boxName,
    required String keyPrefix,
    required String oldFieldName,
    required String newFieldName,
    required String flagKey,
  }) async {
    // ── Guard: run at most once per device ──────────────────────────────
    final Box<dynamic> migrationBox = HiveService.instance.migrationBox;
    if (migrationBox.get(flagKey) == true) {
      debugPrint('[HiveFieldRenameMigrator] $flagKey already done — skip');
      return;
    }

    // ── Open the target box ────────────────────────────────────────────
    final Box<dynamic> box = Hive.isBoxOpen(boxName)
        ? Hive.box<dynamic>(boxName)
        : await Hive.openBox<dynamic>(boxName);

    // ── Open the shadow backup box ─────────────────────────────────────
    final String shadowName = '${boxName}_pre_${flagKey}_backup';
    final Box<dynamic> shadow = await Hive.openBox<dynamic>(shadowName);

    // ── Walk keys, rename field, backup pre-state ──────────────────────
    final List<dynamic> keys = box.keys.toList();
    final List<String> affected = [];

    for (final dynamic key in keys) {
      if (key is! String || !key.startsWith(keyPrefix)) continue;
      final dynamic raw = box.get(key);
      if (raw is! Map) continue;
      if (!raw.containsKey(oldFieldName)) continue;

      // Backup pre-migration state (exact copy of current value).
      await shadow.put(key, Map<dynamic, dynamic>.from(raw));

      // Rename: copy value under new name, remove old name.
      final Map<dynamic, dynamic> updated = Map<dynamic, dynamic>.from(raw);
      updated[newFieldName] = updated.remove(oldFieldName);
      await box.put(key, updated);
      affected.add(key);
    }

    // Close shadow box — we don't need it in memory after the migration.
    await shadow.close();

    // ── Write the idempotency flag ─────────────────────────────────────
    await migrationBox.put(flagKey, true);

    debugPrint(
      '[HiveFieldRenameMigrator] $flagKey: renamed '
      '$oldFieldName → $newFieldName on ${affected.length} key(s); '
      'backup at $shadowName',
    );
  }
}
