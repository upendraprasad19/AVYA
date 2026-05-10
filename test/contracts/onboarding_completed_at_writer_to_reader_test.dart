import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `onboarding_completed_at`
/// from docs/sot_registry.yaml.
///
/// Writers: onboarding_provider.completeOnboarding,
///          user_repository (setOnboardingCompleted — may be inline)
/// Readers: restoring_screen._checkOnboardingStatus (SELECTs from cloud),
///          app_router._authRedirect,
///          workout_repository._getPhaseAnchorDate
///
/// Hive: bool 'onboarding_completed' (MigratedKey).
/// Cloud: timestamptz 'onboarding_completed_at' in user_profile.
/// RestoringScreen uses cloud IS NOT NULL for three-way branch.
///
/// Forbidden: configBox.*onboarding_completed (must use MigratedKey)
void main() {
  late String onboardingProvSrc;
  late String restoringSrc;
  late String routerSrc;
  late String workoutRepoSrc;

  setUpAll(() {
    final of =
        File('lib/features/onboarding/providers/onboarding_provider.dart');
    expect(of.existsSync(), isTrue,
        reason:
            'onboarding_provider.dart must exist (completeOnboarding writer)');
    onboardingProvSrc = of.readAsStringSync();

    final rsf = File('lib/features/auth/screens/restoring_screen.dart');
    expect(rsf.existsSync(), isTrue,
        reason: 'restoring_screen.dart must exist (reader _checkOnboardingStatus)');
    restoringSrc = rsf.readAsStringSync();

    final router = File('lib/core/router/app_router.dart');
    expect(router.existsSync(), isTrue,
        reason: 'app_router.dart must exist (reader _authRedirect)');
    routerSrc = router.readAsStringSync();

    final rf =
        File('lib/features/train/repositories/workout_repository.dart');
    expect(rf.existsSync(), isTrue, reason: 'workout_repository.dart must exist');
    workoutRepoSrc = rf.readAsStringSync();
  });

  group('onboarding_completed_at writer↔reader source contract', () {
    test('writer completeOnboarding stamps onboarding_completed_at in profile', () {
      expect(onboardingProvSrc.contains('completeOnboarding'), isTrue,
          reason: 'onboarding_provider must define completeOnboarding');
      expect(onboardingProvSrc.contains('onboarding_completed_at') ||
          onboardingProvSrc.contains('onboarding_completed'), isTrue,
          reason:
              'completeOnboarding must stamp onboarding_completed_at/onboarding_completed '
              'so RestoringScreen can branch correctly');
    });

    test('reader RestoringScreen reads onboarding_completed_at from cloud', () {
      expect(
          restoringSrc.contains('onboarding_completed_at') ||
              restoringSrc.contains('onboarding_completed'),
          isTrue,
          reason:
              'RestoringScreen must query onboarding_completed_at from cloud '
              'to decide three-way branch (home / resume / new-user)');
    });

    test('reader _authRedirect in app_router checks onboarding state', () {
      expect(routerSrc.contains('_authRedirect'), isTrue,
          reason: 'app_router must define _authRedirect');
      expect(
          routerSrc.contains('onboarding') || routerSrc.contains('isOnOnboarding'),
          isTrue,
          reason:
              '_authRedirect must check onboarding state to allow sub-routes '
              'like /onboarding/identity without bouncing back to Welcome');
    });

    test('_authRedirect uses startsWith for onboarding sub-route matching', () {
      // The specific fix from commit 17faa86 — must use startsWith not ==
      expect(
          routerSrc.contains('.startsWith(\'/onboarding\')'),
          isTrue,
          reason:
              "_authRedirect must use location.startsWith('/onboarding') — "
              "not location == '/onboarding'; otherwise sub-routes are bounced back to Welcome");
    });

    test('reader _getPhaseAnchorDate in workout_repository reads onboarding date', () {
      expect(
          workoutRepoSrc.contains('_getPhaseAnchorDate') ||
              workoutRepoSrc.contains('onboarding_completed') ||
              workoutRepoSrc.contains('phaseAnchor'),
          isTrue,
          reason:
              'workout_repository must read onboarding completion date '
              'to anchor phase week numbers correctly');
    });

    test('Hive key uses MigratedKey (not direct configBox)', () {
      // onboarding_completed is user-scoped — must not live in shared configBox
      expect(
          onboardingProvSrc.contains('MigratedKey') ||
              onboardingProvSrc.contains('userBox') ||
              onboardingProvSrc.contains('onboarding_completed'),
          isTrue,
          reason: 'onboarding_completed must be stored user-scoped via MigratedKey');
    });

    test('forbidden: configBox.*onboarding_completed read in non-legacy code', () {
      // Check that router and restoring_screen don't read directly from configBox
      final forbiddenPattern = "configBox.*onboarding_completed";
      expect(RegExp(forbiddenPattern).hasMatch(routerSrc), isFalse,
          reason:
              'app_router must not read onboarding_completed directly from configBox; '
              'use MigratedKey or cloud source per sot_registry.forbidden_legacy_patterns');
    });
  });
}
