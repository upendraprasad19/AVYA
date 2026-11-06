// FIX-1 Part B (e2e-2026-06-21) — unit truth table for the session-open
// routing guard in GoRouter._authRedirect (AppRouter.shouldGateOnSessionOpen).
//
// Guard contract: when an authenticated user reaches a session-gated route
// before HiveUserSession.openForUser has run (Hive owner still null),
// _authRedirect must route through /restoring to open the session FIRST —
// UNLESS the route is an onboarding route (which self-navigates pre-session).
//
// Why this matters: FIX-1 Part A makes user-scoped Hive reads SERVE EMPTY
// during the owner-null window instead of throwing. Without this guard, the
// `onboarding_completed` read at _authRedirect would return its default
// (false) for an already-onboarded user landing on /home via a web reload /
// deep-link → mis-route to /onboarding. The guard routes through /restoring,
// which opens the session and re-runs the decision tree with a valid owner.
//
// The onboarding exemption prevents the dual trap: the StartMissionBrief /
// ResumeOnboarding paths navigate to /onboarding/* pre-session, so gating
// them would bounce a brand-new user straight back to /restoring forever.
//
// Run: flutter test test/contracts/auth_redirect_session_open_guard_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/router/app_router.dart';

void main() {
  group('AppRouter.shouldGateOnSessionOpen — session-open routing guard', () {
    test('authenticated + owner-null + NOT onboarding → GATE (→ /restoring)',
        () {
      expect(
        AppRouter.shouldGateOnSessionOpen(
          isInitialized: true,
          isAuthenticated: true,
          ownerOpen: false,
          isOnOnboarding: false,
        ),
        isTrue,
        reason: 'the headline case — an onboarded user on a gated route with '
            'the Hive session not yet open must go through /restoring.',
      );
    });

    test('owner already open → do NOT gate (normal authenticated nav)', () {
      expect(
        AppRouter.shouldGateOnSessionOpen(
          isInitialized: true,
          isAuthenticated: true,
          ownerOpen: true,
          isOnOnboarding: false,
        ),
        isFalse,
        reason: 'once openForUser has stamped the owner, the decision tree '
            'reads are trustworthy — no detour.',
      );
    });

    test('onboarding route exempt even with owner-null (no brand-new trap)',
        () {
      expect(
        AppRouter.shouldGateOnSessionOpen(
          isInitialized: true,
          isAuthenticated: true,
          ownerOpen: false,
          isOnOnboarding: true,
        ),
        isFalse,
        reason: 'StartMissionBrief / ResumeOnboarding navigate to /onboarding/* '
            'pre-session; gating them would infinite-loop a new user.',
      );
    });

    test('not authenticated → do NOT gate (the sign-in branch owns this)', () {
      expect(
        AppRouter.shouldGateOnSessionOpen(
          isInitialized: true,
          isAuthenticated: false,
          ownerOpen: false,
          isOnOnboarding: false,
        ),
        isFalse,
      );
    });

    test('Hive not initialized → do NOT gate (startup-race passthrough)', () {
      expect(
        AppRouter.shouldGateOnSessionOpen(
          isInitialized: false,
          isAuthenticated: true,
          ownerOpen: false,
          isOnOnboarding: false,
        ),
        isFalse,
      );
    });
  });
}
