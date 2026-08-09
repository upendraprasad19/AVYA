// Behavioral contract for diagnose b7e4c1 — the sign-out redirect race.
//
// THE BUG (founder, live web, 2026-08-05): tapping SIGN OUT sometimes landed on
// the ONBOARDING flow instead of the sign-in screen.
//
// WHY: `AuthNotifier.signOut()` tears down in this order —
//   1. UserRepository.clearAllData()            ← wipes the 7 user-scoped boxes
//   2. HiveUserSession.deleteAllFilesForCurrentUser()
//   3. supabase.auth.signOut()                  ← session ends HERE, last
//   4. unbindSessionIdentity()
// Between (1) and (3) the app is simultaneously AUTHENTICATED and
// `onboarding_completed == false` — not because the user never onboarded, but
// because the box holding that flag was just cleared. `_authRedirect` read that
// `false` at face value and took its `!isOnboarded` branch → `/onboarding`.
//
// It is intermittent, not constant, because GoRouter has no `refreshListenable`
// on auth state here: whether a redirect happens to evaluate inside that window
// is timing-dependent. An intermittent repro is exactly why this needs a
// deterministic unit truth-table rather than a widget-pump race.
//
// WHY NOT JUST FLIP THE ORDER: `clearAllData()` goes through
// `wrapUserScopedBox`, which THROWS when the caller is unauthenticated with a
// non-null owner. End the Supabase session first and all 7 clears throw. Each
// is caught independently so teardown still completes — but every sign-out
// would then fire 7 `recordNonFatal` events and return
// `ClearResult.hasFailures`, and two live recovery paths key off exactly that
// signal (`_ensureLocalUser`, `main.dart`'s interrupted-logout completion).
// Flipping the order would drown a real partial-clear alarm in permanent noise.
// So the ordering stays and the AMBIGUITY is resolved instead.
//
// MUTATION-PROVEN: delete the `if (signOutInProgress)` branch from
// AppRouter.postSessionRedirect and the first test below fails with
// `/onboarding` instead of `/sign-in` — the founder's exact symptom.
//
// Run: flutter test test/contracts/signout_router_guard_behavioral_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

void main() {
  group('AppRouter.postSessionRedirect — sign-out teardown window', () {
    test('THE BUG: mid-teardown (authed + boxes wiped) → /sign-in, NOT /onboarding',
        () {
      final dest = AppRouter.postSessionRedirect(
        signOutInProgress: true,
        // The wiped-box read. Indistinguishable from a never-onboarded user
        // on this input alone — which is the whole point.
        isOnboarded: false,
        isOnAuthRoute: false,
        isOnOnboarding: false,
      );

      expect(
        dest,
        '/sign-in',
        reason: 'the founder tapped SIGN OUT; landing in the onboarding flow '
            'is the reported bug. signOutInProgress must be consulted BEFORE '
            'the ambiguous onboarding_completed read.',
      );
      expect(
        dest,
        isNot('/onboarding'),
        reason: 'explicit negative — this is the exact symptom reported.',
      );
    });

    test('mid-teardown but already on /sign-in → stay put (no redirect loop)',
        () {
      expect(
        AppRouter.postSessionRedirect(
          signOutInProgress: true,
          isOnboarded: false,
          isOnAuthRoute: true,
          isOnOnboarding: false,
        ),
        isNull,
        reason: 'redirecting /sign-in → /sign-in would spin GoRouter.',
      );
    });

    test('mid-teardown overrides even a still-true onboarded flag', () {
      // clearAllData() is not atomic across 7 boxes. If the redirect evaluates
      // after the session flag is gone but before THIS box is cleared, the read
      // is stale-true. The signOut branch must win on either value, or the
      // guard would only work for half the window.
      expect(
        AppRouter.postSessionRedirect(
          signOutInProgress: true,
          isOnboarded: true,
          isOnAuthRoute: false,
          isOnOnboarding: false,
        ),
        '/sign-in',
      );
    });

    test('mid-teardown while ON onboarding → still leaves for /sign-in', () {
      // A user who signs out FROM the onboarding flow must not be pinned there
      // by the isOnOnboarding passthrough below.
      expect(
        AppRouter.postSessionRedirect(
          signOutInProgress: true,
          isOnboarded: false,
          isOnAuthRoute: false,
          isOnOnboarding: true,
        ),
        '/sign-in',
      );
    });

    group('flag OFF — every pre-existing branch is byte-identical', () {
      // The guard is additive. With signOutInProgress false the function must
      // reproduce the old decision tree exactly, or this "fix" is a regression
      // for every non-signing-out user (i.e. all of them, almost all the time).

      test('genuinely not onboarded → /onboarding (unchanged)', () {
        expect(
          AppRouter.postSessionRedirect(
            signOutInProgress: false,
            isOnboarded: false,
            isOnAuthRoute: false,
            isOnOnboarding: false,
          ),
          '/onboarding',
        );
      });

      test('not onboarded + already on onboarding → stay (unchanged)', () {
        expect(
          AppRouter.postSessionRedirect(
            signOutInProgress: false,
            isOnboarded: false,
            isOnAuthRoute: false,
            isOnOnboarding: true,
          ),
          isNull,
        );
      });

      test('onboarded on an auth route → /home (unchanged)', () {
        expect(
          AppRouter.postSessionRedirect(
            signOutInProgress: false,
            isOnboarded: true,
            isOnAuthRoute: true,
            isOnOnboarding: false,
          ),
          '/home',
        );
      });

      test('onboarded on onboarding → /home (unchanged)', () {
        expect(
          AppRouter.postSessionRedirect(
            signOutInProgress: false,
            isOnboarded: true,
            isOnAuthRoute: false,
            isOnOnboarding: true,
          ),
          '/home',
        );
      });

      test('onboarded on an ordinary route → stay (unchanged)', () {
        expect(
          AppRouter.postSessionRedirect(
            signOutInProgress: false,
            isOnboarded: true,
            isOnAuthRoute: false,
            isOnOnboarding: false,
          ),
          isNull,
        );
      });
    });
  });

  group('AuthNotifier.signOutInProgress — the flag itself', () {
    test('defaults to false, so a cold start is never pinned at /sign-in', () {
      expect(
        AuthNotifier.signOutInProgress,
        isFalse,
        reason: 'a stuck-ON flag would hold the entire app at /sign-in until '
            'process restart — which is why signOut() clears it in a finally.',
      );
    });

    test('is static, not a Riverpod provider — _authRedirect has no ref', () {
      // Documents WHY the shape is what it is: _authRedirect is a plain static
      // evaluated synchronously during navigation with no WidgetRef in scope,
      // same constraint that makes HiveUserSession.currentOwnerFullId static.
      // If someone converts this to a provider, _authRedirect cannot read it.
      AuthNotifier.signOutInProgress = true;
      expect(AuthNotifier.signOutInProgress, isTrue);
      AuthNotifier.signOutInProgress = false;
      expect(AuthNotifier.signOutInProgress, isFalse);
    });
  });
}
