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
/// **2026-07-23 update 2 (diagnose b7d4e2):** detection logic extracted from
/// main.dart into the pure, unit-testable `PasswordRecoveryDetector` (see
/// `password_recovery_detector_test.dart` for the behavioral coverage this
/// source-grep test can't provide) — main.dart now delegates instead of
/// inlining the fragment check. Also adds recognition of the PKCE `?code=`
/// query-param shape Supabase now sends by default, which the fragment-only
/// check never covered.
///
/// Pins:
/// 1. `redirectTo` URL in forgot_password_sheet.dart — must be prod domain.
/// 2. main.dart delegates to `PasswordRecoveryDetector.detect` BEFORE runApp()
///    and stashes the result on AppRouter.
/// 3. `/reset` route in app_router.dart — GoRoute registration + name.
/// 4. `_authRedirect` exemption for `/reset` in app_router.dart.
/// 5. splash_screen.dart applies stashed recovery session after Supabase init.
/// 6. app_router.dart declares static token fields for stash.
/// 7. `PasswordRecoveryDetector` recognizes both the fragment and PKCE shapes.
void main() {
  late String forgotSheet;
  late String mainSrc;
  late String splashScreen;
  late String appRouter;
  late String resetScreen;
  late String recoveryDetector;

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
    recoveryDetector = File(
      '$root/lib/core/utils/password_recovery_detector.dart',
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
    test('delegates to PasswordRecoveryDetector before runApp()', () {
      expect(
        mainSrc,
        contains('PasswordRecoveryDetector.detect(Uri.base)'),
        reason: 'must detect recovery via the pure detector before runApp()',
      );
      expect(
        mainSrc,
        contains('AppRouter.isPasswordRecovery = true'),
        reason: 'must set flag when recovery detected',
      );
    });

    test('stashes recovery tokens from the detector result on AppRouter', () {
      expect(
        mainSrc,
        contains('result.accessToken'),
        reason: 'must stash access_token from the detector result',
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

  group('password_recovery_detector.dart', () {
    test('recognizes the legacy implicit-flow fragment shape', () {
      expect(
        recoveryDetector,
        contains("fragment.contains('type=recovery')"),
        reason: 'must check for type=recovery in the fragment',
      );
    });

    test('recognizes the PKCE code query-param shape scoped to /reset', () {
      expect(
        recoveryDetector,
        contains("queryParameters.containsKey('code')"),
        reason: 'must check for the PKCE code param',
      );
      expect(
        recoveryDetector,
        contains("uri.path == resetPath"),
        reason: 'PKCE code check must be scoped to the /reset path',
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
