// BEHAVIORAL CONTRACT TEST — singleton_lifecycle_registry
//
// Concept:   singleton_lifecycle_registry
// Writer:    lib/core/services/hive_user_session.dart (closeAll / openForUser)
// Reader:    lib/core/services/singleton_lifecycle_registry.dart (callbacks)
//
// Assert:
//   1. After HiveUserSession.closeAll(), every registered callback fires exactly once.
//   2. After HiveUserSession.openForUser(newUser), every registered callback fires exactly once.
//   3. A second registration under the SAME name replaces the first (idempotent registry).
//   4. Callbacks registered under DIFFERENT names both fire.
//
// This test uses real Hive (path_provider mock pattern) because closeAll /
// openForUser touch user-scoped boxes.  The registry callbacks are plain counters
// — no Supabase / network required.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Fake path provider (matches auth_hive_owner_agreement_behavioral_test.dart)
// ---------------------------------------------------------------------------

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;

  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('slr_behavioral_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    // Open the 5 shared (non-user-scoped) boxes that HiveService expects.
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Close all user boxes + reset the registry before every test.
    await HiveUserSession.closeAll();
    SingletonLifecycleRegistry.resetForTesting();
  });

  tearDown(() {
    SingletonLifecycleRegistry.resetForTesting();
  });

  // -------------------------------------------------------------------------
  // Test 1 — closeAll() triggers exactly one notifyUserChanged()
  // -------------------------------------------------------------------------

  test(
    'closeAll() fires every registered singleton callback exactly once',
    () async {
      const userId = 'aaaaaaaa-bbbb-cccc-dddd-000000000001';

      // Register two distinct callbacks before the lifecycle event.
      var counterA = 0;
      var counterB = 0;
      SingletonLifecycleRegistry.register('hook_a', () => counterA++);
      SingletonLifecycleRegistry.register('hook_b', () => counterB++);

      // Open a user session first so closeAll() has something to close.
      await HiveUserSession.openForUser(userId);

      // Reset counters AFTER openForUser so the open's notification doesn't
      // count toward our closeAll() assertion.
      counterA = 0;
      counterB = 0;

      // ACT
      await HiveUserSession.closeAll();

      // ASSERT — each callback fired exactly once.
      expect(counterA, 1,
          reason: 'hook_a must fire exactly once on closeAll()');
      expect(counterB, 1,
          reason: 'hook_b must fire exactly once on closeAll()');
    },
  );

  // -------------------------------------------------------------------------
  // Test 2 — openForUser() triggers exactly one notifyUserChanged()
  // -------------------------------------------------------------------------

  test(
    'openForUser() fires every registered singleton callback exactly once',
    () async {
      const userId = 'aaaaaaaa-bbbb-cccc-dddd-000000000002';

      var counter = 0;
      SingletonLifecycleRegistry.register('hook_open', () => counter++);

      // ACT
      await HiveUserSession.openForUser(userId);

      // ASSERT
      expect(counter, 1,
          reason:
              'hook_open must fire exactly once on openForUser()');
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — re-registering the SAME name replaces the old callback
  // -------------------------------------------------------------------------

  test(
    'registering the same name twice replaces the first callback',
    () async {
      const userId = 'aaaaaaaa-bbbb-cccc-dddd-000000000003';

      var v1Fired = 0;
      var v2Fired = 0;

      SingletonLifecycleRegistry.register('my_service', () => v1Fired++);
      // Override with a new callback.
      SingletonLifecycleRegistry.register('my_service', () => v2Fired++);

      await HiveUserSession.openForUser(userId);

      // Only the v2 callback must have fired.
      expect(v1Fired, 0,
          reason:
              'first callback replaced — must NOT fire after re-registration');
      expect(v2Fired, 1,
          reason: 'second callback must fire after re-registration');
    },
  );

  // -------------------------------------------------------------------------
  // Test 4 — registry count is correct
  // -------------------------------------------------------------------------

  test(
    'registeredNames() reflects the current registry contents',
    () async {
      expect(SingletonLifecycleRegistry.count, 0,
          reason: 'registry must start empty after resetForTesting()');

      SingletonLifecycleRegistry.register('svc_x', () {});
      SingletonLifecycleRegistry.register('svc_y', () {});
      expect(SingletonLifecycleRegistry.count, 2);
      expect(SingletonLifecycleRegistry.registeredNames(),
          containsAll(['svc_x', 'svc_y']));
    },
  );
}
