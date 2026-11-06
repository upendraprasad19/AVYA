// C-6 (audit-2026-05-11) — regression test for the cross-account
// guard lifted from splash_screen.dart into
// HiveUserSession.openForUser. The previous splash guard was a no-op
// because `HiveService.instance.userBox` throws
// `HiveUserSession not opened` at cold start; the try/catch swallowed
// it. The guard now runs inside openForUser itself.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_c6_guard_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('C-6 cross-account guard inside openForUser', () {
    test(
      'mismatched profile.id in namespaced userBox is cleared on openForUser',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
        const userB = '94368fd4-eeee-ffff-1111-222222222222';

        // Simulate Android Auto Backup / dev-build-copy fallout:
        // userA's namespaced box on disk already contains a profile
        // belonging to userB.
        final box = await Hive.openBox('userBox_5f0a13b2');
        await box.put('profile', {'id': userB, 'name': 'Stranger'});
        await box.put('onboarding_completed', true);
        await box.close();

        // userA signs in. openForUser should detect the mismatch and
        // clear the namespaced box in place.
        await HiveUserSession.openForUser(userA);

        final reopened = Hive.box('userBox_5f0a13b2');
        expect(reopened.get('profile'), isNull,
            reason:
                'guard must clear foreign profile so caller cannot inherit it');
        expect(reopened.get('onboarding_completed'), isNull,
            reason:
                'guard must clear the entire namespaced userBox, not just profile');
      },
    );

    test(
      'matching profile.id is left untouched',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';

        await HiveUserSession.openForUser(userA);
        final box = Hive.box('userBox_5f0a13b2');
        await box.put('profile', {'id': userA, 'name': 'Upendra'});
        await box.put('onboarding_completed', true);
        await HiveUserSession.closeAll();

        // Re-open for the same user. Profile must survive.
        await HiveUserSession.openForUser(userA);
        final reopened = Hive.box('userBox_5f0a13b2');
        expect(reopened.get('profile'),
            {'id': userA, 'name': 'Upendra'},
            reason: 'guard must not clear when ids match');
        expect(reopened.get('onboarding_completed'), true);
      },
    );

    test(
      'absent profile is a no-op (fresh box for new user)',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';

        // openForUser must not crash on an empty namespaced box.
        await HiveUserSession.openForUser(userA);
        final box = Hive.box('userBox_5f0a13b2');
        expect(box.get('profile'), isNull);
      },
    );

    test(
      'non-Map profile value is a no-op (defensive, never seen in prod)',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';

        final box = await Hive.openBox('userBox_5f0a13b2');
        await box.put('profile', 'corrupted_string_not_a_map');
        await box.close();

        await HiveUserSession.openForUser(userA);
        final reopened = Hive.box('userBox_5f0a13b2');
        // Guard only fires when profile is a Map with an id. Non-Map
        // value survives — the next mutation will overwrite it
        // cleanly via the WriteServices or repositories.
        expect(reopened.get('profile'), 'corrupted_string_not_a_map');
      },
    );
  });
}
