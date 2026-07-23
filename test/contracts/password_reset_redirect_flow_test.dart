import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep contract test for the password-reset redirect flow.
///
/// Fails on `main` (pre-fix) and passes after the fix for diagnose e9f2a4:
/// Supabase dashboard Site URL overrides client `redirectTo` — the
/// `resetPasswordForEmail` call pointed to `vercel.app` instead of
/// `app.icanbefitter.com`, and no `/reset` route or handler existed.
///
/// **2026-07-23 update:** Recovery-detection shifted from splash_screen.dart
/// to main.dart because GoRouter's `initialLocation` clears the URL hash
/// before any widget mounts. The fragment is now checked in `main()` pre-`runApp()`.
///
/// Pins:
/// 1. `redirectTo` URL in forgot_password_sheet.dart — must be prod domain.
/// 2. Recovery detection in main.dart — checks URL fragment for `type=recovery`
///    BEFORE runApp() and stashes tokens on AppRouter.
/// 3. `/reset` route in app_router.dart — GoRoute registration + name.
/// 4. `_authRedirect` exemption for `/reset` in app_router.dart.
/// 5. splash_screen.dart applies stashed recovery session after Supabase init.
/// 6. app_router.dart declares static token fields for stash.
void main() {
  late String forgotSheet;
  late String mainSrc;
  late String splashScreen;
  late String appRouter;
  late String resetScreen;

  setUpAll(() {
    final root = Directory.current.path;
    forgotSheet = File(
      '$root/lib/features/auth/widgets/forgot_password_sheet.dart',
    ).readAsStringSync();
    mainSrc = File(
      '$root/lib/main.dart',
    ).readAsStringSync();
    splashScreen = File(
      '$root/lib/features/auth/screens/splash_screen.dart',
    ).readAsStringSync();
    appRouter = File(
      '$root/lib/core/router/app_router.dart',
    ).readAsStringSync();
    resetScreen = File(
      '$root/lib/features/auth/screens/reset_password_screen.dart',
    ).readAsStringSync();
  });

  group('forgot_password_sheet.dart', () {
    test('redirectTo points to app.icanbefitter.com/reset', () {
      expect(
        forgotSheet,
        contains("'https://app.icanbefitter.com/reset'"),
        reason: 'redirectTo must use the prod SPA domain, not vercel.app',
      );
    });

    test('does NOT reference vercel.app for redirect', () {
      expect(
        forgotSheet,
        isNot(contains('vercel.app/reset')),
        reason: 'stale vercel.app redirect URL must not remain',
      );
    });
  });

  group('main.dart', () {
    test('checks Uri.base.fragment for type=recovery before runApp()', () {
      expect(
        mainSrc,
        contains('Uri.base.fragment'),
        reason: 'must parse URL fragment in main() before runApp()',
      );
      expect(
        mainSrc,
        contains("'type=recovery'"),
        reason: 'must check for type=recovery in the fragment',
      );
      expect(
        mainSrc,
        contains('AppRouter.isPasswordRecovery = true'),
        reason: 'must set flag when recovery detected',
      );
    });

    test('stashes recovery tokens from fragment on AppRouter', () {
      expect(
        mainSrc,
        contains("params['access_token']"),
        reason: 'must extract access_token from fragment params',
      );
      expect(
        mainSrc,
        contains('AppRouter.recoveryAccessToken'),
        reason: 'must stash access_token on AppRouter',
      );
      expect(
        mainSrc,
        contains('AppRouter.recoveryRefreshToken'),
        reason: 'must stash refresh_token on AppRouter',
      );
    });
  });

  group('splash_screen.dart', () {
    test('applies stashed recovery session after Supabase init', () {
      expect(
        splashScreen,
        contains('auth.setSession'),
        reason:
            'must call setSession after Supabase init when recovery detected',
      );
      expect(
        splashScreen,
        contains('AppRouter.recoveryRefreshToken'),
        reason: 'reads stashed refresh_token from AppRouter',
      );
      expect(
        splashScreen,
        contains('AppRouter.recoveryAccessToken'),
        reason: 'reads stashed access_token from AppRouter',
      );
    });

    test('routes to /reset when recovery flag is set', () {
      expect(
        splashScreen,
        contains("context.go('/reset')"),
        reason: '_navigateNext must route to /reset when recovery detected',
      );
    });
  });

  group('app_router.dart', () {
    test('declares static isPasswordRecovery flag', () {
      expect(
        appRouter,
        contains('static bool isPasswordRecovery'),
        reason: 'flag set by main, read by reset_password_screen',
      );
    });

    test('declares static token stash fields', () {
      expect(
        appRouter,
        contains('static String? recoveryAccessToken'),
        reason:
            'stashed access_token from recovery URL fragment, set by main',
      );
      expect(
        appRouter,
        contains('static String? recoveryRefreshToken'),
        reason:
            'stashed refresh_token from recovery URL fragment, set by main',
      );
    });

    test('registers /reset GoRoute', () {
      expect(
        appRouter,
        contains("path: '/reset'"),
        reason: '/reset route must exist',
      );
      expect(
        appRouter,
        contains("name: 'resetPassword'"),
        reason: 'route must be named resetPassword',
      );
    });

    test('exempts /reset from _authRedirect', () {
      expect(
        appRouter,
        contains("matchedLocation == '/reset'"),
        reason:
            '_authRedirect must check for /reset to return null passthrough',
      );
    });
  });

  group('reset_password_screen.dart', () {
    test('guards against recovery flag being false on mount', () {
      expect(
        resetScreen,
        contains('!AppRouter.isPasswordRecovery'),
        reason:
            'must redirect to /sign-in if recovery flag is not set',
      );
    });

    test('resets recovery flag after password update', () {
      expect(
        resetScreen,
        contains('AppRouter.isPasswordRecovery = false'),
        reason: 'flag must be reset so guard works on next mount',
      );
    });

    test('calls updateUser for password change', () {
      expect(
        resetScreen,
        contains('auth.updateUser'),
        reason: 'must use Supabase auth.updateUser to set new password',
      );
    });
  });
}
