// test/contracts/onboarding_completed_at_behavioral_test.dart
//
// BEHAVIORAL contract for the `onboarding_completed_at` SoT registry concept.
//
// Concept: the routing decision made in `AuthSessionBootstrapper.classifyDestination`
// MUST classify a user whose `onboarding_completed_at` IS NOT NULL as `GoHome`,
// and a user whose profile row is absent / incomplete as `StartMissionBrief` or
// `ResumeOnboarding(step)` respectively.
//
// This test exercises the real `classifyDestination` pure static function
// (`@visibleForTesting` — no Hive, no Supabase) so it FAILS if the routing
// condition for `onboarding_completed_at` is removed, renamed, or inverted.
//
// Bug class prevented: writer (onboarding_provider.completeOnboarding) stamps
// 'onboarding_completed_at' on the profile map and syncs to cloud user_profile.
// Reader (restoring_screen.dart → resolveDestination → classifyDestination)
// checks row['onboarding_completed_at'] != null. If the key name drifts on
// either side, a returning user is sent back to onboarding on every login.
// Source-grep on the key string passes even when the semantic is broken; only
// a behavioral call to classifyDestination catches the regression.
//
// Concepts covered: `onboarding_completed_at`
// Writer:  lib/features/onboarding/providers/onboarding_provider.dart
// Reader:  lib/features/auth/screens/restoring_screen.dart via
//          lib/core/services/auth_session_bootstrapper.dart classifyDestination
//
// Run: flutter test test/contracts/onboarding_completed_at_behavioral_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';

// ignore: invalid_use_of_visible_for_testing_member — intentional test usage

void main() {
  group('onboarding_completed_at — classifyDestination routing (behavioral)',
      () {
    test(
        'non-null onboarding_completed_at → GoHome '
        '(returning user reaches home on every re-login)', () {
      final row = <String, dynamic>{
        'onboarding_completed_at': '2026-06-01T10:00:00+05:30',
        'date_of_birth': '1995-06-15',
        'primary_goal': 'build_muscle',
        'current_weight_kg': 72.5,
        'fitness_experience': 'beginner',
      };

      final dest = AuthSessionBootstrapper.classifyDestination(row);

      expect(dest, isA<GoHome>(),
          reason: 'onboarding_completed_at IS NOT NULL '
              '→ classifyDestination MUST return GoHome. '
              'If the key name drifts between the writer '
              '(onboarding_provider) and the reader '
              '(auth_session_bootstrapper), returning users '
              'are incorrectly routed back into onboarding.');
    });

    test(
        'null onboarding_completed_at with all fields populated → '
        'ResumeOnboarding("plan") '
        '(user completed all steps but final stamp is missing)', () {
      final row = <String, dynamic>{
        'onboarding_completed_at': null,
        'date_of_birth': '1997-03-20',
        'primary_goal': 'lose_fat',
        'current_weight_kg': 80.0,
        'fitness_experience': 'intermediate',
      };

      final dest = AuthSessionBootstrapper.classifyDestination(row);

      expect(dest, isA<ResumeOnboarding>());
      expect((dest as ResumeOnboarding).firstMissingStep, 'plan',
          reason: 'all identity/goal/stats/details fields present but '
              'onboarding_completed_at is null → resume at plan step.');
    });

    test(
        'null onboarding_completed_at + null date_of_birth → '
        'ResumeOnboarding("identity") '
        '(user abandoned at identity step)', () {
      final row = <String, dynamic>{
        'onboarding_completed_at': null,
        'date_of_birth': null,
        'primary_goal': null,
        'current_weight_kg': null,
        'fitness_experience': null,
      };

      final dest = AuthSessionBootstrapper.classifyDestination(row);

      expect(dest, isA<ResumeOnboarding>());
      expect((dest as ResumeOnboarding).firstMissingStep, 'identity',
          reason: 'date_of_birth is the identity-step sentinel per '
              'diagnose 2026-05-30-resolve-destination-full-name-drift; '
              'full_name lives on users table NOT user_profile.');
    });

    test(
        'null row → StartMissionBrief '
        '(brand-new user with no user_profile row)', () {
      final dest = AuthSessionBootstrapper.classifyDestination(null);

      expect(dest, isA<StartMissionBrief>(),
          reason: 'absent user_profile row → new user, show Mission Brief.');
    });

    test(
        'partial row — date_of_birth present, primary_goal absent → '
        'ResumeOnboarding("goal")', () {
      final row = <String, dynamic>{
        'onboarding_completed_at': null,
        'date_of_birth': '1999-12-01',
        'primary_goal': null,
        'current_weight_kg': null,
        'fitness_experience': null,
      };

      final dest = AuthSessionBootstrapper.classifyDestination(row);

      expect(dest, isA<ResumeOnboarding>());
      expect((dest as ResumeOnboarding).firstMissingStep, 'goal');
    });
  });
}
