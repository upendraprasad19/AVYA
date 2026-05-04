// Test #10.1 — UserConfigMigrator copies user-specific keys from
// shared `configBox` into the per-user `userBox`, then deletes them
// from `configBox`. Idempotent via the `migrationBox` flag.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_migrator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Fresh boxes per test — close + delete to reset state.
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      HiveService.userBoxName,
      'userBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    // Open shared boxes (matching HiveService.init).
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
  });

  test('copies onboarding_completed and PRO state from configBox to userBox',
      () async {
    // Seed configBox as if it's a pre-migration install.
    final cfg = HiveService.instance.configBox;
    await cfg.put('onboarding_completed', true);
    await cfg.put('isPro', true);
    await cfg.put('expiresAt', '2030-01-01T00:00:00Z');
    await cfg.put('plan', 'monthly');
    await cfg.put('lastVerifiedAt', '2026-05-04T00:00:00Z');
    await cfg.put('localActivationAt', '2026-05-04T00:00:00Z');
    // Plus a key that should stay in configBox.
    await cfg.put('units_metric', true);

    // Open per-user box.
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);

    // Run migration.
    final result = await UserConfigMigrator.runIfNeeded();

    // All 6 critical keys copied (lastVerifiedAt matches the constant
    // SubscriptionService._lastVerifiedKey, NOT 'lastVerified').
    expect(result.copiedKeys, containsAll(<String>[
      'onboarding_completed', 'isPro', 'expiresAt',
      'plan', 'lastVerifiedAt', 'localActivationAt',
    ]));

    // userBox now has them.
    final userBox = HiveService.instance.userBox;
    expect(userBox.get('onboarding_completed'), true);
    expect(userBox.get('isPro'), true);
    expect(userBox.get('plan'), 'monthly');

    // configBox lost the migrated keys.
    expect(cfg.containsKey('onboarding_completed'), isFalse);
    expect(cfg.containsKey('isPro'), isFalse);

    // Device-level key untouched.
    expect(cfg.get('units_metric'), true);

    // Flag set so re-run is a no-op.
    final mig = HiveService.instance.migrationBox;
    expect(mig.get('config_to_user_migration_v1_done'), true);

    // Second run is no-op.
    final secondRun = await UserConfigMigrator.runIfNeeded();
    expect(secondRun.copiedKeys, isEmpty);
    expect(secondRun.failures, isEmpty);

    await HiveUserSession.closeAll();
  });
}
