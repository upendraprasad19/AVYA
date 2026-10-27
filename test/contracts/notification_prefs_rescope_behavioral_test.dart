// test/contracts/notification_prefs_rescope_behavioral_test.dart
//
// BEHAVIOURAL contract for Unit C — bug (c): notification preferences were
// device-global, not per-account.
//
// Pre-fix, `notification_preferences` lived in the SHARED `configBox`
// (profile/screen.dart wrote it directly). configBox carries no owner, so on a
// shared device the last saver silently set preferences for whoever signed in
// next: user A turns off streak alerts, user B stops receiving them, and user B
// has no way to discover why.
//
// A source-grep test would pass the moment the string `userBox` appears in the
// repository. Only an open→write→close→open-as-someone-else sequence proves the
// value does not cross accounts, which is the whole claim (§4.4 r21,
// feedback_source_grep_false_confidence.md).
//
// Also pins the two ways the fix could be quietly undone:
//   - reading via MigratedKey (its configBox fallback re-creates the leak), and
//   - the migration COPYING configBox -> userBox instead of deleting.
//
// Run: flutter test test/contracts/notification_prefs_rescope_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/features/profile/services/notification_prefs_repository.dart';
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

const _userA = 'aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _userB = 'bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('notif_prefs_rescope_');
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
    await HiveService.instance.configBox.clear();
    await HiveService.instance.migrationBox.clear();
  });

  group('bug (c) — preferences are per-account, not per-device', () {
    test('user B does NOT inherit user A preferences on the same device',
        () async {
      await HiveUserSession.openForUser(_userA);
      final wroteA = await NotificationPrefsRepository.write({
        'streak_alerts': {'enabled': false},
      });
      expect(wroteA, isTrue, reason: 'write must persist for a signed-in user');
      expect(NotificationPrefsRepository.read()['streak_alerts']?['enabled'],
          isFalse);

      // Same device, different account.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(_userB);

      final bPrefs = NotificationPrefsRepository.read();
      expect(bPrefs, isEmpty,
          reason: 'THE bug. User B must not see user A stored preferences. A '
              'non-empty map here means the value crossed accounts — either '
              'the write went to the shared configBox, or the read fell back '
              'to it (the MigratedKey trap).');

      // And A's own value is intact when A returns — the fix must not have
      // achieved isolation by simply losing the data.
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(_userA);
      expect(NotificationPrefsRepository.read()['streak_alerts']?['enabled'],
          isFalse,
          reason: 'user A preferences must survive the round-trip');
    });

    test('nothing is written to the SHARED configBox', () async {
      await HiveUserSession.openForUser(_userA);
      await NotificationPrefsRepository.write({
        'weekly_recap': {'enabled': false},
      });
      expect(
        HiveService.instance.configBox
            .containsKey(NotificationPrefsRepository.hiveKey),
        isFalse,
        reason: 'configBox is shared and ownerless — a write there is bug (c).',
      );
    });

    test('no session: read is {} and write is a no-op', () async {
      await HiveUserSession.closeAll();
      expect(NotificationPrefsRepository.read(), isEmpty);

      final wrote = await NotificationPrefsRepository.write({
        'streak_alerts': {'enabled': false},
      });
      expect(wrote, isFalse, reason: 'must report that it did not persist');
      expect(
        HiveService.instance.configBox
            .containsKey(NotificationPrefsRepository.hiveKey),
        isFalse,
        reason: 'a signed-out write must NOT seed the shared box — that is '
            'exactly how the next signer-in inherits a stranger preference.',
      );
    });
  });

  group('normalisation — malformed values must never throw or darken a push',
      () {
    test('Hive Map<dynamic,dynamic> nesting does not throw', () async {
      await HiveUserSession.openForUser(_userA);
      // What Hive actually hands back: dynamic-keyed inner maps. A naive
      // Map<String,dynamic>.from() on the INNER map throws, and an unhandled
      // throw on this path kills the user's ENTIRE daily snapshot.
      await HiveService.instance.userBox.put(
        NotificationPrefsRepository.hiveKey,
        <dynamic, dynamic>{
          'streak_alerts': <dynamic, dynamic>{'enabled': false, 'time': '07:00'},
        },
      );
      final prefs = NotificationPrefsRepository.read();
      expect(prefs['streak_alerts']?['enabled'], isFalse);
      expect(prefs['streak_alerts']?['time'], '07:00',
          reason: 'sibling fields must survive normalisation');
    });

    test('a non-Map entry becomes {enabled: true} — absent means SEND',
        () async {
      await HiveUserSession.openForUser(_userA);
      await HiveService.instance.userBox.put(
        NotificationPrefsRepository.hiveKey,
        <dynamic, dynamic>{'streak_alerts': 'garbage'},
      );
      expect(NotificationPrefsRepository.read()['streak_alerts']?['enabled'],
          isTrue,
          reason: 'decision N2 — a corrupted value must not silently darken a '
              'notification for a user who never turned it off.');
    });

    test('a Map missing `enabled`, and a non-bool `enabled`, both default true',
        () async {
      expect(
        NotificationPrefsRepository.normalize({
          'a': {'time': '07:00'},
          'b': {'enabled': 'false'}, // string, not bool
        }),
        {
          'a': {'time': '07:00', 'enabled': true},
          'b': {'enabled': true},
        },
        reason: 'only a literal false disables; anything else fails safe',
      );
    });

    test('normalize is total — null and scalars return {} without throwing',
        () {
      expect(NotificationPrefsRepository.normalize(null), isEmpty);
      expect(NotificationPrefsRepository.normalize('nope'), isEmpty);
      expect(NotificationPrefsRepository.normalize(42), isEmpty);
    });
  });

  group('migration is DELETE-ONLY — a copy would BE the bug', () {
    test('purge removes the shared key and does NOT copy it into userBox',
        () async {
      // Simulate a legacy install: the value sits in the shared box, owner
      // unknown by construction.
      await HiveService.instance.configBox.put(
        NotificationPrefsRepository.hiveKey,
        {'streak_alerts': {'enabled': false}},
      );
      await HiveUserSession.openForUser(_userB);

      await UserConfigMigrator.purgeDeleteOnlyKeys();

      expect(
        HiveService.instance.configBox
            .containsKey(NotificationPrefsRepository.hiveKey),
        isFalse,
        reason: 'the shared copy must be dropped',
      );
      expect(NotificationPrefsRepository.read(), isEmpty,
          reason: 'copying it into whoever happens to be signed in is exactly '
              'how user A preferences become user B permanent settings. '
              'Ownership of a shared-box value is unknowable, so the only '
              'safe action is delete.');
    });

    test('the key is in deleteOnlyKeys and NOT in the copy sweep', () {
      expect(UserConfigMigrator.deleteOnlyKeys,
          contains(NotificationPrefsRepository.hiveKey));
      expect(UserConfigMigrator.userScopedKeys,
          isNot(contains(NotificationPrefsRepository.hiveKey)),
          reason: 'userScopedKeys COPIES before deleting — that path must '
              'never be used for an ownerless value.');
    });

    test('purge runs once per device', () async {
      await HiveUserSession.openForUser(_userA);
      await UserConfigMigrator.purgeDeleteOnlyKeys();

      // A later write by the legitimate owner must survive a second purge.
      await NotificationPrefsRepository.write({
        'weekly_recap': {'enabled': false},
      });
      await UserConfigMigrator.purgeDeleteOnlyKeys();

      expect(NotificationPrefsRepository.read()['weekly_recap']?['enabled'],
          isFalse,
          reason: 'the purge is flagged; re-running must not touch userBox at '
              'all — it only ever deletes from the shared box.');
    });
  });
}
