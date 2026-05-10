// APK Test #13 / Phase 2.5 — pins the HiveKeyMigrator contract.
//
// Three tests cover:
//   1. Key rename: old keys removed, new keys created, values preserved,
//      shadow backup contains pre-migration state
//   2. Idempotency — second run is a no-op (migration flag gate)
//   3. Collision — target key exists → source left untouched; only one
//      new key created when two sources hash to the same target

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/hive_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('hive_key_migrator_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    // Reset state: close + delete all boxes used across tests so each
    // test starts with a blank slate.
    final boxesToReset = [
      'test_box',
      HiveService.migrationBoxName,
      // Shadow boxes produced by the migrator (all three flagKey variants).
      'test_box_pre_key_rename_v1_backup',
      'test_box_pre_key_rename_v2_backup',
      'test_box_pre_key_rename_collision_v3_backup',
    ];
    for (final name in boxesToReset) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox<dynamic>(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
  });

  tearDown(() async {
    // Close any boxes opened during the test so the next setUp is clean.
    if (Hive.isBoxOpen('test_box')) await Hive.box('test_box').close();
  });

  test('renames keys from old formula to new formula, preserves values',
      () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('tmpl_oldhash1', {'name': 'Push Day', 'exercises': []});
    await box.put('tmpl_oldhash2', {'name': 'Leg Day', 'exercises': []});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_oldhash',
      newKeyFn: (oldKey, value) {
        final name = (value['name'] as String).toLowerCase().trim();
        final h = name.hashCode.toUnsigned(32).toRadixString(16);
        return 'tmpl_$h';
      },
      flagKey: 'key_rename_v1',
    );

    // New keys should exist under canonical formula.
    final newKeys =
        box.keys.where((k) => k.toString().startsWith('tmpl_')).toList();
    expect(newKeys.length, 2);

    // Old keys must be gone.
    expect(box.get('tmpl_oldhash1'), isNull);
    expect(box.get('tmpl_oldhash2'), isNull);

    // Shadow backup must have captured the pre-migration state.
    final shadow =
        await Hive.openBox<dynamic>('test_box_pre_key_rename_v1_backup');
    final shadowRow = shadow.get('tmpl_oldhash1') as Map;
    expect(shadowRow['name'], 'Push Day');
  });

  test('idempotent — second run is no-op (gated by flag)', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('tmpl_oldhash1', {'name': 'Push Day'});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_oldhash',
      newKeyFn: (oldKey, value) {
        final h = (value['name'] as String)
            .toLowerCase()
            .hashCode
            .toUnsigned(32)
            .toRadixString(16);
        return 'tmpl_$h';
      },
      flagKey: 'key_rename_v2',
    );

    // Inject another old-prefix key AFTER the first run completes.
    await box.put('tmpl_oldhash3', {'name': 'Sneaky'});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_oldhash',
      newKeyFn: (oldKey, value) {
        final h = (value['name'] as String)
            .toLowerCase()
            .hashCode
            .toUnsigned(32)
            .toRadixString(16);
        return 'tmpl_$h';
      },
      flagKey: 'key_rename_v2',
    );

    // Second run must be a no-op — the sneaky key still has the old prefix.
    expect(box.get('tmpl_oldhash3'), isNotNull);
  });

  test('collision (target key exists) skips that row, leaves source untouched',
      () async {
    final box = await Hive.openBox<dynamic>('test_box');
    // Two source keys whose names both lowercase to 'push' →
    // same target key → collision.
    await box.put('tmpl_a', {'name': 'PUSH'});
    await box.put('tmpl_b', {'name': 'push'});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_',
      newKeyFn: (oldKey, value) {
        final h = (value['name'] as String)
            .toLowerCase()
            .hashCode
            .toUnsigned(32)
            .toRadixString(16);
        return 'tmpl_target_$h';
      },
      flagKey: 'key_rename_collision_v3',
    );

    // Exactly one new target key created (whichever was iterated first wins).
    final newKeys = box.keys
        .where((k) => k.toString().startsWith('tmpl_target_'))
        .toList();
    expect(newKeys.length, 1);

    // The colliding source key remains in the box (not deleted).
    final remainingSourceKeys = box.keys
        .where((k) =>
            k.toString().startsWith('tmpl_') &&
            !k.toString().startsWith('tmpl_target_'))
        .toList();
    expect(
      remainingSourceKeys.length,
      1,
      reason: 'one of the colliding sources should be preserved',
    );
  });
}
