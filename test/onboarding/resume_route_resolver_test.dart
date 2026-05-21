import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// OB-7 — Onboarding resume from arbitrary step.
///
/// Returns the earliest /onboarding/<step> route based on which canonical
/// field is first null. The order encodes the onboarding flow:
///
///   no profile row     → /onboarding/mission-brief (cold sign-up)
///   full_name == null  → /onboarding/identity
///   primary_goal == null → /onboarding/goal
///   current_weight_kg == null → /onboarding/stats
///   fitness_experience == null → /onboarding/details
///   otherwise          → /onboarding/plan
///
/// **Audit 2026-05-20 / A1 + A9:** logic relocated. Pre-refactor, the
/// `RestoringScreen._resolveOnboardingResumeRoute` private method
/// implemented the decision tree directly. Post-refactor:
///
///   - `restoring_screen.dart` now switches on `PostSignInDestination`
///     (sealed class) returned by `AuthSessionBootstrapper.resolveDestination`.
///   - `lib/core/services/auth_session_bootstrapper.dart` carries the
///     canonical branch logic in `classifyDestination(Map?)` (also exposed
///     via `@visibleForTesting`).
///
/// The contract pins shifted accordingly:
///   1. The branch order is preserved (Dart 3 switch-exhaustiveness on
///      the sealed class compile-checks it).
///   2. RestoringScreen invokes `AuthSessionBootstrapper.resolveDestination`.
///   3. Self-heal stamp logic for the orphan state remains accessible.
///
/// Per `feedback_source_grep_false_confidence.md`, this is presence-only;
/// the canonical behavioral test for the decision tree is
/// `test/contracts/auth_session_bootstrapper_test.dart`.
void main() {
  late String restoringSrc;
  late String bootstrapperSrc;

  setUpAll(() {
    final restoringFile =
        File('lib/features/auth/screens/restoring_screen.dart');
    final bootstrapperFile =
        File('lib/core/services/auth_session_bootstrapper.dart');
    expect(restoringFile.existsSync(), isTrue,
        reason: 'restoring_screen.dart must exist');
    expect(bootstrapperFile.existsSync(), isTrue,
        reason:
            'auth_session_bootstrapper.dart must exist (introduced by audit '
            '2026-05-20 / A1).');
    restoringSrc = restoringFile.readAsStringSync();
    bootstrapperSrc = bootstrapperFile.readAsStringSync();
  });

  group('OB-7 onboarding resume — post-A1 contract', () {
    test('AuthSessionBootstrapper exposes destination resolution', () {
      expect(
        bootstrapperSrc.contains('resolveDestination') ||
            bootstrapperSrc.contains('classifyDestination'),
        isTrue,
        reason:
            'AuthSessionBootstrapper must expose resolveDestination (or '
            'classifyDestination) — the canonical destination decision tree '
            'lives here post-A1.',
      );
      expect(
        bootstrapperSrc.contains('PostSignInDestination'),
        isTrue,
        reason:
            'PostSignInDestination sealed class must be defined or imported '
            'in the bootstrapper.',
      );
    });

    test('5 field-null branches present in canonical order', () {
      // Branch presence is checked in EITHER file (depending on whether the
      // sealed-class enrichment happens in bootstrapper or via the switch
      // in restoring_screen). Most likely the bootstrapper has the routes
      // as `ResumeOnboarding('identity')`, `ResumeOnboarding('goal')`, etc.,
      // OR the legacy literal-route strings.
      final combined = '$restoringSrc\n$bootstrapperSrc';
      const orderedTokens = [
        // First-step token for the "no profile row" case.
        'mission-brief',
        // Then resume by missing field, in order:
        'identity',
        'goal',
        'stats',
        'details',
        'plan',
      ];

      var cursor = 0;
      for (final token in orderedTokens) {
        final idx = combined.indexOf(token, cursor);
        expect(idx, greaterThan(0),
            reason:
                'Onboarding flow token `$token` must appear after position '
                '$cursor across (restoring_screen.dart ⨁ '
                'auth_session_bootstrapper.dart). The order encodes the '
                'onboarding flow — reordering routes users to the wrong step.');
        cursor = idx + token.length;
      }
    });

    test('mid-onboarding branch invokes the bootstrapper', () {
      // restoring_screen.dart must call AuthSessionBootstrapper.resolveDestination
      // (the canonical entry point) — not query Supabase directly.
      expect(
        restoringSrc.contains('AuthSessionBootstrapper.instance.resolveDestination') ||
            restoringSrc.contains('AuthSessionBootstrapper().resolveDestination') ||
            restoringSrc.contains('.resolveDestination('),
        isTrue,
        reason:
            'RestoringScreen must call AuthSessionBootstrapper.resolveDestination '
            'to decide the post-sign-in route. Pre-A1 it called the private '
            '_resolveOnboardingResumeRoute (now superseded).',
      );
    });

    test('self-heal path for orphan onboarding_completed_at state', () {
      // The orphan state: user has current_weight_kg filled locally but
      // onboarding_completed_at never landed in cloud. The self-heal stamp
      // logic lives in the bootstrapper now.
      final hasSelfHeal =
          restoringSrc.contains('_stampOnboardingCompletedAt') ||
              bootstrapperSrc.contains('_stampOnboardingCompletedAt') ||
              bootstrapperSrc.contains('stampOnboardingCompletedAt') ||
              bootstrapperSrc.contains('onboarding_completed_at');
      expect(hasSelfHeal, isTrue,
          reason:
              'Self-heal helper must exist somewhere in the auth-stack to '
              'recover the orphan-completed-but-no-timestamp state.');

      // current_weight_kg heuristic — the trigger condition for self-heal.
      final hasWeightHeuristic =
          restoringSrc.contains('current_weight_kg') ||
              bootstrapperSrc.contains('current_weight_kg');
      expect(hasWeightHeuristic, isTrue,
          reason:
              'Self-heal trigger condition must inspect current_weight_kg '
              '(or another late-flow field) as the heuristic for "user '
              'reached at least Stats step, so onboarding really happened, '
              'just the stamp didn\'t land".');
    });
  });
}
