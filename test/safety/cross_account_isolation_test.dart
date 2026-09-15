import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_5_iso_');
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

  group('cross-account isolation (Plan A)', () {
    test(
      'user A writes -> closeAll -> user B opens -> reads return empty (different namespace)',
      () async {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
        const userB = '94368fd4-eeee-ffff-1111-222222222222';

        // Sign in as A and write
        await HiveUserSession.openForUser(userA);
        final aCoach = Hive.box('coachBox_5f0a13b2');
        await aCoach.put('msg_1', {'role': 'user', 'content': 'A says hi'});
        expect(aCoach.get('msg_1'), {'role': 'user', 'content': 'A says hi'});
        await HiveUserSession.closeAll();

        // Sign in as B
        await HiveUserSession.openForUser(userB);
        final bCoach = Hive.box('coachBox_94368fd4');
        // B's coachBox is a different file -- empty
        expect(bCoach.get('msg_1'), isNull,
          reason: 'B must NOT see A\'s coach messages -- namespacing is the storage-level guarantee');
        expect(bCoach.keys.length, 0);

        // A's data still exists in its own file
        // (re-open A's box directly to confirm)
        final aCoachStillThere = await Hive.openBox('coachBox_5f0a13b2');
        expect(aCoachStillThere.get('msg_1'),
          {'role': 'user', 'content': 'A says hi'});
      },
    );

    test(
      'namespaced box name is `<root>_<8hex of dehyphenated user.id>`',
      () {
        const userA = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
        expect(HiveUserSession.namespacedBoxName('coachBox', userA),
          'coachBox_5f0a13b2');
        expect(HiveUserSession.namespacedBoxName('userBox', userA),
          'userBox_5f0a13b2');
      },
    );

    test(
      'splash_screen reconciliation: profile with goal+experience+weight but NULL onboarding_completed_at is treated as onboarded',
      () {
        // Pure logic test -- mirrors the boolean rule in
        // splash_screen._navigateNext (Layer 4 reconciliation,
        // adapted from the plan's RestoringScreen target).
        bool isOnboarded(Map<String, dynamic> profile) {
          final hasFlag = profile['onboarding_completed_at'] != null;
          final hasCore = profile['primary_goal'] != null
              && profile['fitness_experience'] != null
              && profile['current_weight_kg'] != null;
          return hasFlag || hasCore;
        }

        // Affected account shape (Upendra-class, OBS-3)
        final populatedNullFlag = <String, dynamic>{
          'onboarding_completed_at': null,
          'primary_goal': 'build_muscle',
          'fitness_experience': 'intermediate',
          'current_weight_kg': 75.0,
        };
        expect(isOnboarded(populatedNullFlag), true,
          reason: 'self-heal: populated profile MUST be treated as onboarded even with NULL flag');

        // Genuinely new user
        final blankProfile = <String, dynamic>{
          'onboarding_completed_at': null,
          'primary_goal': null,
          'fitness_experience': null,
          'current_weight_kg': null,
        };
        expect(isOnboarded(blankProfile), false);

        // Already-onboarded normal user
        final stampedProfile = <String, dynamic>{
          'onboarding_completed_at': '2026-04-01T10:00:00Z',
          'primary_goal': 'build_muscle',
          'fitness_experience': 'intermediate',
          'current_weight_kg': 75.0,
        };
        expect(isOnboarded(stampedProfile), true);
      },
    );
  });
}
