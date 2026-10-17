// APK Test #13 / Phase 2.4 — pins the HiveFieldRenameMigrator contract.
//
// Four tests cover:
//   1. Field rename propagates across all matching-prefix rows
//   2. Shadow-box backup captures pre-migration state
//   3. Idempotency — second run is a no-op (migration flag gate)
//   4. Only keys matching keyPrefix are touched

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:icanbefitter/core/services/hive_field_rename_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_field_rename_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    // Reset state: close + delete all boxes used across tests.
    final boxesToReset = [
      'test_box',
      HiveService.migrationBoxName,
      // shadow boxes produced by the migrator
      'test_box_pre_rename_old_to_new_v1_done_backup',
      'test_box_pre_rename_v1_backup',
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
    for (final name in Hive.isBoxOpen('test_box') ? ['test_box'] : <String>[]) {
      await Hive.box(name).close();
    }
  });

  test('renames a single field across every row in a box', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('row1', {'old_field': 'value1', 'other': 'keep'});
    await box.put('row2', {'old_field': 'value2', 'other': 'keep'});

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_old_to_new_v1_done',
    );

    final after = box.toMap();
    expect((after['row1'] as Map)['new_field'], 'value1');
    expect((after['row1'] as Map).containsKey('old_field'), isFalse);
    expect((after['row1'] as Map)['other'], 'keep');
    expect((after['row2'] as Map)['new_field'], 'value2');
    expect((after['row2'] as Map).containsKey('old_field'), isFalse);
  });

  test('shadow-box backup contains pre-migration state', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('row1', {'old_field': 'value1'});

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );

    final shadow =
        await Hive.openBox<dynamic>('test_box_pre_rename_v1_backup');
    final shadowRow = shadow.get('row1') as Map;
    // Shadow must have the OLD field name (pre-migration state).
    expect(shadowRow['old_field'], 'value1');
    // Shadow must NOT have the new field name.
    expect(shadowRow.containsKey('new_field'), isFalse);
  });

  test('idempotent — second run is no-op (gated by flag)', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('row1', {'old_field': 'value1'});

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );

    // Inject a row with old_field AFTER migration completes.
    await box.put('row2', {'old_field': 'sneaky'});

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );

    // Second run should be a no-op due to migration flag — row2's
    // old_field must still be present (migrator never touched it).
    expect((box.get('row2') as Map)['old_field'], 'sneaky');
    expect((box.get('row2') as Map).containsKey('new_field'), isFalse);
  });

  test('only touches keys matching keyPrefix', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('row1', {'old_field': 'v1'});
    await box.put('other1', {'old_field': 'v2'}); // different prefix

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );

    // 'row1' matched the prefix — field should be renamed.
    expect((box.get('row1') as Map).containsKey('new_field'), isTrue);
    expect((box.get('row1') as Map).containsKey('old_field'), isFalse);

    // 'other1' did NOT match the prefix — must be untouched.
    expect((box.get('other1') as Map).containsKey('old_field'), isTrue);
    expect((box.get('other1') as Map).containsKey('new_field'), isFalse);
  });
}
