import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/auth/screens/reset_password_screen.dart';

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
    mainSrc = File('$root/lib/main.dart').readAsStringSync();
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
        reason: 'stashed access_token from recovery URL fragment, set by main',
      );
      expect(
        appRouter,
        contains('static String? recoveryRefreshToken'),
        reason: 'stashed refresh_token from recovery URL fragment, set by main',
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
        reason: 'must redirect to /sign-in if recovery flag is not set',
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

    test(
      'navigates to /sign-in after the sign-out sequence (diagnose c8f1d3)',
      () {
        final signOutIndex = resetScreen.indexOf('auth.signOut()');
        expect(signOutIndex, isNot(-1));
        final tail = resetScreen.substring(signOutIndex);
        expect(
          tail,
          contains("context.go('/sign-in')"),
          reason:
              'a successful reset signs the user out but GoRouter has no '
              'refreshListenable tied to auth state and /reset is exempt from '
              '_authRedirect — nothing else moves the user off /reset, so the '
              'screen must navigate explicitly (diagnose c8f1d3, the '
              'stuck-screen bug). See the behavioral group below for a real '
              'end-to-end assertion, not just presence.',
        );
      },
    );
  });

  group('ResetPasswordScreen — behavioral: navigates after a successful reset '
      '(diagnose c8f1d3, the fourth password-reset-flow gap — not e9f2a4/'
      '9f5c41/b7d4e2, which are all about *reaching* /reset, not what happens '
      'after a successful update)', () {
    testWidgets(
      'submitting a valid new password navigates away from /reset to /sign-in',
      (tester) async {
        // Supabase.initialize + session seeding run INSIDE the testWidgets
        // body (not setUpAll) deliberately: setUpAll executes in a
        // different zone than the one TestWidgetsFlutterBinding wraps
        // around the test body, so a Timer GoTrueClient starts during
        // Supabase.initialize() ends up outside the zone pump()
        // advances — pumpAndSettle then never observed it settle.
        // Confirmed via a standalone diagnostic: identical setup done
        // inline here settles in under a second with plain pump() calls.

        // supabase_flutter's default local storage touches
        // shared_preferences during Supabase.initialize() — mock the
        // channel so init doesn't need a real platform plugin. Same
        // pattern as test/supabase/supabase_test_helper.dart.
        const prefsChannel = MethodChannel(
          'plugins.flutter.io/shared_preferences',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(prefsChannel, (MethodCall call) async {
              if (call.method == 'getAll') return <String, dynamic>{};
              return true;
            });

        // _updatePassword's post-success sequence calls
        // releaseDeviceSessionIdentity(), which calls OneSignal.logout()
        // when !kIsWeb (true in this VM test run). Mock it to resolve
        // immediately, matching production behavior — the call is
        // already try/caught as non-fatal there either way.
        const oneSignalChannel = MethodChannel('OneSignal');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(oneSignalChannel, (
              MethodCall call,
            ) async {
              return null;
            });

        // Fake HTTP transport for the two GoTrue REST calls
        // _updatePassword makes — auth.updateUser (PUT .../user) and
        // auth.signOut (POST .../logout) — so the real widget code runs
        // end-to-end with no network access and no real Supabase project.
        final mockClient = MockClient((request) async {
          if (request.method == 'PUT' && request.url.path.endsWith('/user')) {
            return http.Response(
              jsonEncode({
                'id': 'fake-user-id',
                'aud': 'authenticated',
                'email': 'reset-test@example.com',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
                'created_at': '2026-01-01T00:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/logout')) {
            return http.Response('', 204);
          }
          return http.Response('unexpected request: ${request.url}', 404);
        });

        await Supabase.initialize(
          url: 'https://fake-project.supabase.co',
          anonKey: 'fake-anon-key',
          httpClient: mockClient,
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
          ),
        );

        // Seed a session with no network round trip (setInitialSession
        // only parses the JSON locally) — mirrors what
        // splash_screen.dart does for a real recovery link via
        // auth.setSession, so updateUser() has a session to attach its
        // request to.
        await Supabase.instance.client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'fake-access-token',
            'token_type': 'bearer',
            'refresh_token': 'fake-refresh-token',
            'user': {
              'id': 'fake-user-id',
              'aud': 'authenticated',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );

        AppRouter.isPasswordRecovery = true;
        addTearDown(() => AppRouter.isPasswordRecovery = false);

        final router = GoRouter(
          initialLocation: '/reset',
          routes: [
            GoRoute(
              path: '/reset',
              builder: (_, _) => const ResetPasswordScreen(),
            ),
            GoRoute(
              path: '/sign-in',
              builder: (_, _) =>
                  const Scaffold(body: Text('SIGN-IN-SCREEN-STUB')),
            ),
          ],
        );

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump(const Duration(milliseconds: 350));

        final passwordFields = find.byType(TextFormField);
        expect(passwordFields, findsNWidgets(2));
        await tester.enterText(passwordFields.at(0), 'newpassword123');
        await tester.enterText(passwordFields.at(1), 'newpassword123');
        await tester.pump();

        await tester.ensureVisible(find.text('UPDATE PASSWORD'));
        await tester.tap(find.text('UPDATE PASSWORD'));

        // Bounded manual pumps instead of pumpAndSettle: GoTrueClient
        // starts a real (non-virtualized) background Timer.periodic for
        // token auto-refresh even with autoRefreshToken:false passed
        // above (it still constructs the ticker, just skips the refresh
        // work when it fires) — pumpAndSettle's "wait until no frame is
        // scheduled" heuristic never quiesces because of it, even though
        // the actual navigation this test cares about completes in under
        // a second. Confirmed via a standalone diagnostic: the same flow
        // with stepped pump() calls settles in ~700ms.
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (find.text('SIGN-IN-SCREEN-STUB').evaluate().isNotEmpty) break;
        }

        expect(
          find.text('SIGN-IN-SCREEN-STUB'),
          findsOneWidget,
          reason:
              'a successful password reset must navigate away from /reset. '
              'Pre-fix, _updatePassword signs the user out but never calls '
              'context.go — the screen sits on /reset showing the success '
              'SnackBar with nothing left to do (the reported stuck-screen '
              'bug). GoRouter has no refreshListenable tied to auth state '
              'and /reset is exempt from _authRedirect, so nothing else '
              'moves the user off this route without an explicit call.',
        );
      },
    );
  });
}
