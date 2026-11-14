// onboarding-fuse-commit (2026-11-14) — the Plan screen's single I COMMIT tap.
//
// Writer: lib/features/onboarding/providers/onboarding_provider.dart
//         OnboardingNotifier.finalizeLocalCommit (the last local step of
//         completeOnboarding): InductionService.recordCommitment (when no
//         commitment exists) + completeInduction, THEN setOnboarded.
// Readers: lib/core/router/app_router.dart postSessionRedirect (onboarded
//          flag), lib/features/ai_coach/services/ai_snapshot_builder.dart
//          (committed_to_lt_cdr), coach memory sync (sync_coach.dart).
//
// Why the order matters: `isOnboarded == true` must mean the plan AND the
// commitment are durable. If the flag landed first, a failure after it (or
// ADJUST PLAN, or an app kill) would send the user Home through the router
// with the commitment never recorded, and no screen would ask again.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    OnboardingNotifier.debugAfterStampsForTests = null;
    InductionService.debugOnSyncUidForTests = null;
    await tearDownHiveForTests(tempDir);
  });

  group('finalizeLocalCommit', () {
    test('records the commitment, the induction and the onboarded flag',
        () async {
      await OnboardingNotifier.finalizeLocalCommit();

      final coach = HiveService.instance.coachBox;
      expect(coach.get('committed_at'), isA<String>());
      expect(coach.get('committed_to_lt_cdr'), true);
      expect(coach.get('induction_completed_at'), isA<String>());
      expect(UserRepository.instance.isOnboarded, isTrue);
    });

    test(
        'ORDER: the stamps land BEFORE the onboarded flag (a failure between '
        'them leaves the flag false)', () async {
      OnboardingNotifier.debugAfterStampsForTests =
          () async => throw StateError('injected after stamps');

      await expectLater(
          OnboardingNotifier.finalizeLocalCommit(), throwsStateError);

      final coach = HiveService.instance.coachBox;
      expect(coach.get('committed_to_lt_cdr'), true,
          reason: 'the commitment is stamped before the flag');
      expect(coach.get('induction_completed_at'), isA<String>());
      expect(UserRepository.instance.isOnboarded, isFalse,
          reason: 'setOnboarded must be the LAST local write: if it ran '
              'first, isOnboarded would be true with the tail unfinished');
    });

    test('a retry keeps an existing committed_at (never overwrites a pledge)',
        () async {
      const earlier = '2026-11-01T09:00:00.000';
      await HiveService.instance.coachBox.put('committed_at', earlier);
      await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);

      await OnboardingNotifier.finalizeLocalCommit();

      expect(HiveService.instance.coachBox.get('committed_at'), earlier);
      expect(UserRepository.instance.isOnboarded, isTrue);
    });
  });

  group('InductionService coach-memory sync uid', () {
    test(
        'uses the session owner when the profile has no id (the profile '
        'onboarding used to save had none, so the sync was skipped)',
        () async {
      final uids = <String>[];
      InductionService.debugOnSyncUidForTests = uids.add;
      expect(HiveService.instance.userBox.get('profile'), isNull);

      await InductionService.instance.recordCommitment();
      await InductionService.instance.completeInduction();

      expect(uids, [kTestUserId, kTestUserId]);
    });
  });

  group('resolveStartDate reads the answers completeOnboarding captured', () {
    test(
        'a passed answers map wins over the (possibly rebuilt, empty) state',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(onboardingProvider.notifier);
      expect(container.read(onboardingProvider).answers['start_date'], isNull);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(notifier.resolveStartDate({'start_date': 'start_today'}), today,
          reason: 'opening the Hive session can rebuild the notifier and '
              'empty state.answers; the captured choice must still decide');
    });
  });

  group('AuthNotifier.shouldClearForProfileId (the _ensureLocalUser decision)',
      () {
    test('a profile with no id is treated as another account\'s', () {
      expect(AuthNotifier.shouldClearForProfileId(null, kTestUserId), isTrue);
    });
    test('a profile whose id is the signed-in user is kept', () {
      expect(AuthNotifier.shouldClearForProfileId(kTestUserId, kTestUserId),
          isFalse);
    });
    test('a profile from a different user is cleared', () {
      expect(AuthNotifier.shouldClearForProfileId('someone-else', kTestUserId),
          isTrue);
    });
  });

  group('source pins (presence only)', () {
    final provider = File(
      'lib/features/onboarding/providers/onboarding_provider.dart',
    ).readAsStringSync();

    test('completeOnboarding ends its local work with finalizeLocalCommit, '
        'after saveProgress, and calls setOnboarded nowhere else', () {
      final method = provider.indexOf('Future<Phase?> completeOnboarding');
      final progress = provider.indexOf('_userRepo.saveProgress(', method);
      final finalize = provider.indexOf('await finalizeLocalCommit();', method);
      expect(progress, greaterThan(method));
      expect(finalize, greaterThan(progress));
      expect('setOnboarded()'.allMatches(provider).length, 1,
          reason: 'the only setOnboarded call is inside finalizeLocalCommit');
    });

    test('the already_onboarded early return precedes the commit tail', () {
      final method = provider.indexOf('Future<Phase?> completeOnboarding');
      final refuse = provider.indexOf("error: 'already_onboarded'", method);
      final finalize = provider.indexOf('await finalizeLocalCommit();', method);
      expect(refuse, greaterThan(method));
      expect(finalize, greaterThan(refuse),
          reason: 'a refused (already onboarded) run must stamp nothing');
    });

    test('the retired /coach routes redirect home; the screens are gone', () {
      final router =
          File('lib/core/router/app_router.dart').readAsStringSync();
      expect(router.contains('isOnCoachInduction'), isFalse);
      expect(
          RegExp(r"path: '/coach/(induction|muster)',\s*redirect: \(context, state\) => '/home'")
              .allMatches(router)
              .length,
          2);
      expect(
          File('lib/features/ai_coach/screens/induction_screen.dart')
              .existsSync(),
          isFalse);
    });
  });
}
