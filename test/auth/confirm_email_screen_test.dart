import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/confirm_email_screen.dart';

/// Fails the test if [confirmEmail] is ever called — proves the missing/empty
/// token_hash guard short-circuits before touching Supabase at all, rather
/// than merely happening to render the right text on top of a real call.
class _CallCountingAuthNotifier extends AuthNotifier {
  int confirmEmailCallCount = 0;
  String? lastTokenHash;

  @override
  Future<void> confirmEmail(String tokenHash) async {
    confirmEmailCallCount++;
    lastTokenHash = tokenHash;
  }
}

/// Never actually calls Supabase — [succeed] flips `state` directly to
/// simulate confirmEmail's async work completing, without a real network
/// call. Used only for the navigation test below.
class _SucceedingAuthNotifier extends AuthNotifier {
  @override
  Future<void> confirmEmail(String tokenHash) async {}

  void succeed() {
    state = state.copyWith(status: AuthStatus.success);
  }
}

/// Starts already in the OI-205-guard-blocked error state (as if confirmEmail
/// already ran and refused) and tracks whether [signOut] was actually
/// invoked — round 2's exact concern: does the CTA in this state perform a
/// real sign-out, or merely navigate (a no-op for an authenticated user)?
class _AlreadyAuthenticatedAuthNotifier extends AuthNotifier {
  bool signOutCalled = false;

  @override
  AuthState2 build() {
    ref.onDispose(cancelOAuthWatch);
    return const AuthState2(
      status: AuthStatus.error,
      errorMessage: AuthNotifier.alreadyAuthenticatedConfirmMessage,
    );
  }

  @override
  Future<void> confirmEmail(String tokenHash) async {
    // Deliberately a no-op: the screen must already be showing the blocked
    // state from build() above, not depend on a real confirmEmail call.
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    state = const AuthState2();
  }
}

void main() {
  testWidgets(
    'a missing token_hash shows the invalid-link message without calling confirmEmail',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: ConfirmEmailScreen(tokenHash: null)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('missing its token'),
        findsOneWidget,
        reason: 'a null token_hash must show the malformed-link message',
      );
      expect(
        notifier.confirmEmailCallCount,
        0,
        reason:
            'a null token_hash must never reach confirmEmail — there is '
            'nothing valid to verify',
      );
    },
  );

  testWidgets(
    'an empty token_hash shows the invalid-link message without calling confirmEmail',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: ConfirmEmailScreen(tokenHash: '')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('missing its token'), findsOneWidget);
      expect(notifier.confirmEmailCallCount, 0);
    },
  );

  testWidgets(
    'a present token_hash calls confirmEmail exactly once and shows the loading state',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
        ),
      );
      // NOT pumpAndSettle: the loading state's CircularProgressIndicator
      // animates forever, so pumpAndSettle would time out waiting for it.
      await tester.pump();

      expect(find.textContaining('Confirming your account'), findsOneWidget);
      expect(notifier.confirmEmailCallCount, 1);

      // A rebuild (e.g. a parent re-layout) must not re-trigger verification
      // — the _started guard is the whole point, mirroring
      // ResetPasswordScreen's identical initState guard.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
        ),
      );
      await tester.pump();
      expect(notifier.confirmEmailCallCount, 1);
    },
  );

  testWidgets(
    'a DIFFERENT token_hash delivered to the same mounted State re-triggers '
    'confirmEmail (B-pass Finding 1 — go_router reuses the State via '
    'didUpdateWidget, not initState, since pageKey is path-only)',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'token-A'),
          ),
        ),
      );
      await tester.pump();
      expect(notifier.confirmEmailCallCount, 1);
      expect(notifier.lastTokenHash, 'token-A');

      // Same root widget type/position, different tokenHash — Flutter
      // reuses the existing Element/State and calls didUpdateWidget, exactly
      // the shape a second /confirm?token_hash=... intent produces on a
      // singleTop Activity while the first is still resolving.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(tokenHash: 'token-B'),
          ),
        ),
      );
      await tester.pump();

      expect(
        notifier.confirmEmailCallCount,
        2,
        reason:
            'a genuinely different token must re-trigger verification even '
            'though the State was reused — pre-fix, the bare bool `_started` '
            'guard permanently blocked any second token on the same State.',
      );
      expect(notifier.lastTokenHash, 'token-B');
    },
  );

  testWidgets(
    'starting verification clears AppRouter.pendingConfirmTokenHash — '
    'round-1 plan-review Finding 1: unlike isPasswordRecovery, this field '
    'had no gate, so a later re-render of /confirm would silently re-supply '
    'an already-consumed/expired token',
    (tester) async {
      final notifier = _CallCountingAuthNotifier();
      AppRouter.pendingConfirmTokenHash = 'stale-boot-time-fallback-token';
      addTearDown(() => AppRouter.pendingConfirmTokenHash = null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(
            home: ConfirmEmailScreen(
              tokenHash: 'stale-boot-time-fallback-token',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        notifier.confirmEmailCallCount,
        1,
        reason: 'verification must still start normally for this token',
      );
      expect(
        AppRouter.pendingConfirmTokenHash,
        isNull,
        reason:
            'the one-shot boot-time fallback must be cleared the moment '
            'verification actually starts for it, so a later re-render of '
            '/confirm (which always falls back to this field, since '
            'state.uri.queryParameters is structurally always empty under '
            'HashUrlStrategy) shows the missing-token error instead of '
            'silently re-attempting an already-consumed/expired token.',
      );
    },
  );

  testWidgets(
    'a successful confirmation navigates to /restoring (B-pass Finding 6 — '
    'the one path this feature exists to reach was previously untested)',
    (tester) async {
      final notifier = _SucceedingAuthNotifier();
      final router = GoRouter(
        initialLocation: '/confirm',
        routes: [
          GoRoute(
            path: '/confirm',
            builder: (_, _) =>
                const ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
          GoRoute(
            path: '/restoring',
            builder: (_, _) =>
                const Scaffold(body: Text('RESTORING-SCREEN-STUB')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Confirming your account'), findsOneWidget);

      notifier.succeed();
      // Bounded manual pumps, not pumpAndSettle: matches the established
      // pattern in password_reset_redirect_flow_test.dart — a state change
      // made directly on the notifier (not via a widget rebuild) can take
      // more than one frame to propagate through ref.listen + GoRouter's own
      // route resolution.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('RESTORING-SCREEN-STUB').evaluate().isNotEmpty) break;
      }

      expect(
        find.text('RESTORING-SCREEN-STUB'),
        findsOneWidget,
        reason:
            'success must navigate to /restoring. Pre-fix, nothing in this '
            'suite ever drove AuthStatus.success, so a typo\'d route name or '
            'a ref.listen firing on the wrong status would have passed.',
      );
    },
  );

  testWidgets(
    'the already-signed-in guard state actually signs out before navigating '
    '(round 2 Finding 1 — GO TO SIGN IN alone is a no-op for an '
    'authenticated user; _authRedirect bounces back to /home before '
    'SignInScreen ever renders)',
    (tester) async {
      final notifier = _AlreadyAuthenticatedAuthNotifier();
      final router = GoRouter(
        initialLocation: '/confirm',
        routes: [
          GoRoute(
            path: '/confirm',
            builder: (_, _) =>
                const ConfirmEmailScreen(tokenHash: 'real-token-hash'),
          ),
          GoRoute(
            path: '/sign-in',
            builder: (_, _) =>
                const Scaffold(body: Text('SIGN-IN-SCREEN-STUB')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('SIGN OUT'), findsOneWidget);
      expect(
        find.text('GO TO SIGN IN'),
        findsNothing,
        reason:
            'the already-signed-in state must NOT show the generic '
            '"GO TO SIGN IN" CTA — that button alone would be a silent '
            'no-op for this exact population.',
      );

      await tester.tap(find.text('SIGN OUT'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('SIGN-IN-SCREEN-STUB').evaluate().isNotEmpty) break;
      }

      expect(
        notifier.signOutCalled,
        isTrue,
        reason:
            'tapping SIGN OUT must actually call AuthNotifier.signOut — not '
            'just navigate, which _authRedirect would silently reject for '
            'an authenticated user.',
      );
      expect(find.text('SIGN-IN-SCREEN-STUB'), findsOneWidget);
    },
  );
}
