// test/contracts/user_scoped_hive_keys_behavioral_test.dart
//
// BEHAVIORAL contract for the `user_scoped_hive_keys` SoT registry concept.
//
// Concept: `MigratedKey.write(key, value)` with an active user session writes
// to the namespaced `userBox`, so that when user-A's session is closed and
// user-B's session is opened, `MigratedKey.readWithDefault(key, default)`
// returns the default value — NOT user-A's value.
//
// This test exercises the real read/write routing logic inside MigratedKey:
//   - When HiveUserSession.currentOwnerFullId != null → write/read targets userBox
//   - When HiveUserSession.currentOwnerFullId == null  → read falls through to
//     configBox (returns null if not there) and readWithDefault returns defaultValue
//
// It FAILS if:
//   - MigratedKey.write no longer routes to userBox when a session is open
//   - MigratedKey.read ignores the currentOwnerFullId gate and reads the wrong box
//   - closeAll() doesn't set _currentOwnerFullId to null
//   - The namespacing changes so user-A and user-B share the same userBox
//
// Bug class prevented: if MigratedKey.read skipped the session check and always
// read from configBox, user-A's value would leak into user-B's session (or
// vice-versa on a configBox fallback write). This is the auth_hive_owner
// sibling for the MigratedKey layer.
//
// Concepts covered: `user_scoped_hive_keys`
// Writer + Reader: lib/core/services/migrated_key.dart
//
// Run: flutter test test/contracts/user_scoped_hive_keys_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('migrated_key_hive_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
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
    await HiveUserSession.closeAll();
  });

  group('user_scoped_hive_keys — MigratedKey isolation contract (behavioral)',
      () {
    test(
        'value written under user-A session is readable by user-A '
        '(MigratedKey routes to namespaced userBox)', () async {
      const userA = 'aaaa5555-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      await HiveUserSession.openForUser(userA);

      await MigratedKey.write('test_isolation_key', 'user_a_value');
      final result = MigratedKey.readWithDefault<String>(
          'test_isolation_key', 'DEFAULT');

      expect(result, 'user_a_value',
          reason: 'MigratedKey.write routes to userBox when session is open; '
              'MigratedKey.read should find the value in the same box.');
    });

    test(
        'after closeAll(), MigratedKey.readWithDefault returns the default '
        '(NOT user-A\'s value — session isolation is enforced)', () async {
      const userA = 'aaaa6666-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      await HiveUserSession.openForUser(userA);

      await MigratedKey.write('test_swap_key', 'user_a_secret');
      expect(MigratedKey.read<String>('test_swap_key'), 'user_a_secret',
          reason: 'sanity: readable before session is closed');

      // Simulate user-A signing out: close the session.
      await HiveUserSession.closeAll();

      // After closeAll, currentOwnerFullId is null.
      // MigratedKey.read skips userBox and falls through to configBox.
      // configBox doesn't have 'test_swap_key', so read returns null.
      expect(HiveUserSession.currentOwnerFullId, isNull,
          reason: 'closeAll must set currentOwnerFullId to null');

      final afterClose = MigratedKey.readWithDefault<String>(
          'test_swap_key', 'DEFAULT_SENTINEL');

      expect(afterClose, 'DEFAULT_SENTINEL',
          reason: 'after session close, MigratedKey.readWithDefault MUST '
              'return the default — not user-A\'s userBox value. '
              'If this fails, MigratedKey.read is bypassing the '
              'currentOwnerFullId guard and exposing a stale session\'s data.');
    });

    test(
        'user-B session sees only user-B values, not user-A values, '
        'for the same key', () async {
      const userA = 'aaaa7777-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const userB = 'bbbb7777-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

      // User A writes a value.
      await HiveUserSession.openForUser(userA);
      await MigratedKey.write('shared_key_name', 'value_for_A');
      expect(MigratedKey.read<String>('shared_key_name'), 'value_for_A');

      // Swap to user B.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(userB);

      // User B has NOT written 'shared_key_name' — their userBox is empty for it.
      final resultForB = MigratedKey.readWithDefault<String>(
          'shared_key_name', 'B_DEFAULT');

      expect(resultForB, 'B_DEFAULT',
          reason: 'user-B must not inherit user-A\'s value for the same key. '
              'Each user has a separate namespaced userBox '
              '(HiveUserSession.namespacedBoxName). If this fails, the '
              'namespacing has broken and user-B reads user-A\'s data — '
              'a cross-user data leak.');

      // User B writes their own value.
      await MigratedKey.write('shared_key_name', 'value_for_B');
      expect(MigratedKey.read<String>('shared_key_name'), 'value_for_B',
          reason: 'user-B can write their own value after swapping in');

      // Re-open user-A and confirm their value is still intact.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(userA);
      expect(MigratedKey.read<String>('shared_key_name'), 'value_for_A',
          reason: 'user-A\'s value must not be clobbered by user-B\'s write '
              '(separate namespaced boxes)');
    });
  });
}
