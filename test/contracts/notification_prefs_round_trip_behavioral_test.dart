// test/contracts/notification_prefs_round_trip_behavioral_test.dart
//
// BEHAVIOURAL contract for OI-98 / e4a1b7 — notification preferences were
// PUSH-ONLY. They rode inside `user_daily_snapshots.snapshot_json`, a derived
// document replaced wholesale on every write, and NOTHING ever read them back
// into Hive. A reinstalled device — whose empty box is indistinguishable from
// "everything enabled" — pushed an all-enabled default that REPLACED the
// server's stored copy. The choice was destroyed, not merely unread.
//
// WHY THIS FILE EXISTS SEPARATELY FROM THE MERGE'S OWN UNIT TESTS.
// The first attempt at this fix shipped a test that RE-IMPLEMENTED the merge
// inline and asserted against its own copy — so replacing the production merge
// with cloud-wins left it green. Every test here drives the REAL
// `mergeCloudNotificationPrefs` / `adoptFromCloud`, which is the whole point:
// swap the production body for `{...local, ...cloud}` and this file reddens.
//
// Run: flutter test test/contracts/notification_prefs_round_trip_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
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

Map<String, Map<String, dynamic>> _norm(Map<String, dynamic> raw) =>
    NotificationPrefsRepository.normalize(raw);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('notif_prefs_round_trip_');
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
    // Cleanup is hygiene, never an assertion — a throw here would stack a
    // second failure that HIDES the real one (§4.9). %TEMP% is reaped anyway.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // Start every test from an EMPTY box, not merely a closed session.
    // Closing a session does not clear Hive — reopening the same user restores
    // the same contents — so without this the "fresh install" and
    // "malformed value" tests inherit the previous test's preferences and
    // assert against state they did not create. Caught by this file's own
    // first run.
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(_userA);
    await HiveService.instance.userBox
        .delete(NotificationPrefsRepository.hiveKey);
    await HiveUserSession.closeAll();
  });

  group('mergeCloudNotificationPrefs — per-key LOCAL wins', () {
    test('empty local adopts the whole cloud map', () {
      final merged = mergeCloudNotificationPrefs(
        local: const <String, Map<String, dynamic>>{},
        cloud: _norm({
          'streak_alerts': {'enabled': false},
          'weekly_recap': {'enabled': false},
        }),
      );
      expect(merged['streak_alerts']?['enabled'], isFalse);
      expect(merged['weekly_recap']?['enabled'], isFalse);
    });

    test('a key the user set on THIS device is never overwritten', () {
      // The reinstall race this rule exists for: RestoringScreen surfaces a
      // CONTINUE escape at 30s while the restore keeps writing in the
      // background, so a user really can flip one switch mid-restore.
      final merged = mergeCloudNotificationPrefs(
        local: _norm({
          'streak_alerts': {'enabled': true}, // just toggled back ON locally
        }),
        cloud: _norm({
          'streak_alerts': {'enabled': false}, // older server copy
          'weekly_recap': {'enabled': false},
        }),
      );
      expect(merged['streak_alerts']?['enabled'], isTrue,
          reason: 'LOCAL wins for a key local already has. Cloud-wins here '
              'would silently undo a toggle the user just flipped.');
      expect(merged['weekly_recap']?['enabled'], isFalse,
          reason: 'and the keys local knows nothing about still restore — '
              'all-or-nothing would discard them');
    });

    test('a fully populated local map is left byte-identical', () {
      final local = _norm({
        'streak_alerts': {'enabled': false},
      });
      final merged = mergeCloudNotificationPrefs(
        local: local,
        cloud: _norm({
          'streak_alerts': {'enabled': true},
        }),
      );
      expect(merged.length, local.length);
      expect(merged['streak_alerts']?['enabled'], isFalse);
    });
  });

  group('legacy alias — the P0 that killed the first design', () {
    test('a legacy-singular local key BLOCKS its canonical cloud twin', () {
      // THE regression. A box holding the legacy `workout_reminder` has no
      // canonical `workout_reminders` key, so a naive
      // `local.containsKey(canonical)` test adopts the cloud's canonical entry
      // — and `emissionMap`'s `direct ?? alias` then prefers that adopted value
      // FOREVER, flipping a deliberate OFF back ON on every single sign-in.
      final merged = mergeCloudNotificationPrefs(
        local: _norm({
          'workout_reminder': {'enabled': false}, // user's deliberate OFF
        }),
        cloud: _norm({
          'workout_reminders': {'enabled': true}, // all-enabled default
        }),
      );

      expect(merged.containsKey('workout_reminders'), isFalse,
          reason: 'adopting the canonical twin is the bug — the canonical key '
              'outranks the legacy one at read time, so this silently '
              'overrides the stored OFF');
      expect(merged['workout_reminder']?['enabled'], isFalse);

      // And the whole point: what the SERVER will be told must still be OFF.
      expect(merged.length, 1,
          reason: 'nothing was adopted, so the box should not be rewritten');
    });

    test('an explicit canonical local key still wins over a legacy one', () {
      final merged = mergeCloudNotificationPrefs(
        local: _norm({
          'workout_reminder': {'enabled': true},
          'workout_reminders': {'enabled': false},
        }),
        cloud: _norm({
          'workout_reminders': {'enabled': true},
        }),
      );
      expect(merged['workout_reminders']?['enabled'], isFalse,
          reason: 'mirrors emissionMap direct ?? alias — the canonical entry is '
              'authoritative when both are present');
    });
  });

  group('the WRITE payload — B-pass Finding 1, the path no test touched', () {
    // The P0 this group exists for: migration 122 moved the concept out of the
    // wholesale-replaced snapshot blob and left the WRITE side with the same
    // defect, because a jsonb COLUMN is also replaced wholesale. The stored map
    // is legitimately sparse, so device A storing {streak_alerts:false} and
    // device B storing {weekly_recap:false} would each DELETE the other's key.
    // Every test in this file passed while that was true, for one reason: none
    // of them asserted the shape of what the client sends.

    test('notification_preferences is NEVER in the upsert payload', () {
      final payload = buildUserPreferencesPayload(
        userId: _userA,
        preferences: {'motivational_style': 'drill', 'preferred_language': 'en'},
      );
      expect(payload.containsKey('notification_preferences'), isFalse,
          reason: 'a jsonb column is REPLACED by an upsert, not merged, so a '
              'sparse local map here deletes every key the device has not '
              'seen. It must go through merge_notification_preferences.');
    });

    test('coaching_notes is NEVER in the upsert payload', () {
      final payload = buildUserPreferencesPayload(
        userId: _userA,
        preferences: {'coaching_notes': null, 'motivational_style': 'drill'},
      );
      expect(payload.containsKey('coaching_notes'), isFalse,
          reason: 'the client is a pure CONSUMER of that column — its writers '
              'are daily-snapshot and assess-body-composition. A key present '
              'with a null value lands in the generated SET list and wipes '
              'the AI coach notes plus the BF% rate-limit stamp.');
    });

    test('an empty preferences map yields user_id ALONE, so the caller skips',
        () {
      final payload =
          buildUserPreferencesPayload(userId: _userA, preferences: const {});
      expect(payload.keys, ['user_id'],
          reason: 'sending motivational_style/preferred_language defaults for '
              'a device that has no preferences map would assert those '
              'defaults over whatever the server already holds');
    });

    test('a populated map carries exactly the two columns the client owns', () {
      final payload = buildUserPreferencesPayload(
        userId: _userA,
        preferences: {'motivational_style': 'drill'},
      );
      expect(payload.keys.toSet(),
          {'user_id', 'motivational_style', 'preferred_language'});
      expect(payload['motivational_style'], 'drill');
      expect(payload['preferred_language'], 'en',
          reason: 'defaulted, not omitted, once the map is non-empty');
    });
  });

  group('adoptFromCloud — the real Hive round trip', () {
    test('a reinstalled device recovers the stored OFF', () async {
      await HiveUserSession.openForUser(_userA);
      expect(NotificationPrefsRepository.read(), isEmpty,
          reason: 'precondition: a fresh install has no local record');

      final wrote = await NotificationPrefsRepository.adoptFromCloud({
        'streak_alerts': {'enabled': false},
        'weekly_recap': {'enabled': true},
      });

      expect(wrote, isTrue);
      final back = NotificationPrefsRepository.read();
      expect(back['streak_alerts']?['enabled'], isFalse,
          reason: 'THE bug: before this leg existed, nothing ever wrote the '
              'cloud copy back and the next push re-enabled everything');
      expect(back['weekly_recap']?['enabled'], isTrue);
    });

    test('emission after adoption reports the restored OFF to the server',
        () async {
      // The full chain — adopt -> read -> emit. A restore that repopulates Hive
      // but does not change what the server is told would be inert.
      await HiveUserSession.openForUser(_userA);
      await NotificationPrefsRepository.adoptFromCloud({
        'streak_alerts': {'enabled': false},
      });
      expect(
        NotificationPrefsRepository.emissionMap()['streak_alerts']?['enabled'],
        isFalse,
      );
    });

    test('adopting nothing new does not rewrite the box', () async {
      await HiveUserSession.openForUser(_userA);
      await NotificationPrefsRepository.adoptFromCloud({
        'streak_alerts': {'enabled': false},
      });
      final second = await NotificationPrefsRepository.adoptFromCloud({
        'streak_alerts': {'enabled': true},
      });
      expect(second, isFalse,
          reason: 'local already answers for every cloud key — skip the write '
              'rather than churn the box');
      expect(NotificationPrefsRepository.read()['streak_alerts']?['enabled'],
          isFalse);
    });

    test('no session ⇒ no write, and no throw', () async {
      await HiveUserSession.closeAll();
      final wrote = await NotificationPrefsRepository.adoptFromCloud({
        'streak_alerts': {'enabled': false},
      });
      expect(wrote, isFalse,
          reason: 'read() short-circuits to {} with no session; a writer that '
              'did not consult the SAME gate would see a spuriously empty '
              'local, degrade to cloud-wins, and adopt over real preferences');
    });

    test('the snapshot fallback OMITS the key when the device has no record',
        () async {
      // THE original defect, pinned at its source. `emissionMap()` pads every
      // key to `{'enabled': true}` when the box is empty — correct under the
      // snapshot's ABSENT => SEND contract, and catastrophic as a WRITE,
      // because a wholesale upsert then replaced the server's stored copy with
      // preferences the device never had. Omitting the key entirely is what
      // makes a reinstalled device incapable of asserting a preference.
      await HiveUserSession.openForUser(_userA);
      final empty = SyncService.instance.compileDailySnapshot();
      expect(empty.containsKey('notification_preferences'), isFalse,
          reason: 'an empty box must emit NOTHING for this key. Emitting an '
              'all-enabled default here is OI-98 itself.');

      await NotificationPrefsRepository.write({
        'streak_alerts': {'enabled': false},
      });
      final populated = SyncService.instance.compileDailySnapshot();
      expect(populated.containsKey('notification_preferences'), isTrue,
          reason: 'a device that HAS a record still publishes it, so a user on '
              'the previous APK keeps being honoured through the fallback');
      // Typed through to the leaf: `emitted['streak_alerts']` is `dynamic`, so
      // chaining `?['enabled']` off it is an `avoid_dynamic_calls` WARNING —
      // and `flutter analyze --no-fatal-infos` (what pre-push runs) does not
      // suppress warnings, only infos.
      final emitted =
          populated['notification_preferences'] as Map<String, dynamic>;
      final streakAlerts = emitted['streak_alerts'] as Map<String, dynamic>?;
      expect(streakAlerts?['enabled'], isFalse);
      expect(emitted.length, NotificationPrefsRepository.allKeys.length,
          reason: 'when it DOES emit, it emits the full padded map — a partial '
              'map in a newer row would shadow a complete older one');
    });

    test('a malformed cloud value is absorbed, not written', () async {
      await HiveUserSession.openForUser(_userA);
      expect(await NotificationPrefsRepository.adoptFromCloud(null), isFalse);
      expect(await NotificationPrefsRepository.adoptFromCloud('nonsense'),
          isFalse);
      expect(await NotificationPrefsRepository.adoptFromCloud(
          const <String, dynamic>{}), isFalse);
      expect(NotificationPrefsRepository.read(), isEmpty);
    });
  });
}
