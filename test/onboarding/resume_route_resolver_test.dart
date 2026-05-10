import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// OB-7 — Onboarding resume from arbitrary step.
///
/// `RestoringScreen._resolveOnboardingResumeRoute(userId)` reads
/// user_profile and returns the earliest /onboarding/<step> route based
/// on which canonical field is first null. The order encodes the
/// onboarding flow:
///
///   no profile row     → /onboarding/mission-brief (cold sign-up)
///   full_name == null  → /onboarding/identity
///   primary_goal == null → /onboarding/goal
///   current_weight_kg == null → /onboarding/stats
///   fitness_experience == null → /onboarding/details
///   otherwise          → /onboarding/plan
///
/// Pre-OB-7 behavior was to send users to first step always. Now mid-
/// onboarding abandonment + return picks up where they left off.
///
/// Source-grep contract pins:
///   1. _resolveOnboardingResumeRoute method exists.
///   2. The 5 field-null branches are present in correct order.
///   3. RestoringScreen actually calls the resolver when
///      onboarding_completed_at is null (mid-flow state).
///   4. Self-heal stamping path exists for the orphan-completed-but-no-
///      timestamp state.
void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/features/auth/screens/restoring_screen.dart');
    expect(f.existsSync(), isTrue,
        reason: 'restoring_screen.dart must exist (OB-7 home)');
    src = f.readAsStringSync();
  });

  group('OB-7 onboarding resume route resolver', () {
    test('_resolveOnboardingResumeRoute method exists', () {
      expect(
        src.contains('Future<String> _resolveOnboardingResumeRoute'),
        isTrue,
        reason:
            'RestoringScreen must expose a private method that takes a '
            'userId and returns the route string for the next missing '
            'onboarding step. Removing it reverts OB-7 (everyone restarts '
            'at the welcome screen).',
      );
    });

    test('5 field-null branches present in canonical order', () {
      // The order MUST match the onboarding flow:
      //   1. profile == null → mission-brief
      //   2. full_name → identity
      //   3. primary_goal → goal
      //   4. current_weight_kg → stats
      //   5. fitness_experience → details
      //   6. (else) plan
      const branches = [
        "if (profile == null) return '/onboarding/mission-brief';",
        "if (profile['full_name'] == null) return '/onboarding/identity';",
        "if (profile['primary_goal'] == null) return '/onboarding/goal';",
        "if (profile['current_weight_kg'] == null) return '/onboarding/stats';",
        "if (profile['fitness_experience'] == null) return '/onboarding/details';",
        "return '/onboarding/plan';",
      ];

      // Walk forward through src — each branch must appear AFTER the
      // previous one (canonical order is part of the contract).
      var cursor = 0;
      for (final branch in branches) {
        final idx = src.indexOf(branch, cursor);
        expect(idx, greaterThan(0),
            reason:
                'Resume resolver must contain `$branch` after position '
                '$cursor. The order encodes the onboarding flow — '
                'reordering routes users to the wrong step.');
        cursor = idx + branch.length;
      }
    });

    test('mid-onboarding branch invokes the resolver', () {
      // RestoringScreen._handleStartup must call _resolveOnboardingResumeRoute
      // when profile['onboarding_completed_at'] == null AND the profile is
      // not in the orphan-completed-but-no-timestamp state.
      expect(
        src.contains('await _resolveOnboardingResumeRoute(user.id)'),
        isTrue,
        reason:
            'mid-onboarding branch in RestoringScreen must call '
            '_resolveOnboardingResumeRoute(user.id) so the user lands at '
            'the first missing step rather than the welcome screen.',
      );
    });

    test('self-heal path stamps onboarding_completed_at on orphan state', () {
      // A user with current_weight_kg filled but onboarding_completed_at
      // null is in the orphan state — onboarding completed locally but
      // the cloud stamp never landed. Self-heal stamps the timestamp +
      // treats the user as fully onboarded so they don't re-do steps.
      expect(
        src.contains('_stampOnboardingCompletedAt'),
        isTrue,
        reason:
            'self-heal helper _stampOnboardingCompletedAt must exist to '
            'recover the orphan-completed-but-no-timestamp state.',
      );
      expect(
        src.contains('current_weight_kg'),
        isTrue,
        reason:
            'self-heal trigger condition must inspect current_weight_kg '
            '(or another late-flow field) — that field is the heuristic '
            'for "user reached at least Stats step, so onboarding really '
            'happened, just the stamp didn\'t land".',
      );
    });
  });
}
