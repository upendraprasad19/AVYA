// Behavioral regression test for diagnose c9e2b7 — /reset rendered a working
// password form with no session behind it.
//
// The old flow emailed a PKCE link, and PKCE binds the emailed code to the
// client that REQUESTED the reset (the verifier is written to that client's
// storage, gotrue_client.dart:1118). Request in the Android app, open the mail
// in a browser, and the exchange has nothing to verify against — no session.
// But reset_password_screen.dart:44 gated on AppRouter.isPasswordRecovery,
// which only says "this URL looked like a recovery link". Shape, not session.
// So the form rendered, accepted a password, and failed at submit with GoTrue's
// raw "Auth session missing!".
//
// THE DISCRIMINATOR is the no-session case: the screen must refuse to offer the
// form at all. Asserting only the with-session case would pass against the
// original buggy screen, which rendered the form unconditionally.
//
// Supabase.initialize runs INSIDE the test body, not setUpAll — see the note in
// password_reset_redirect_flow_test.dart:272-279: setUpAll runs in a different
// zone than the one TestWidgetsFlutterBinding wraps the body in, so a GoTrue
// timer started during init lands outside the zone pump() advances.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/auth/screens/reset_password_screen.dart';

void _mockPrefsChannel() {
  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(prefsChannel, (MethodCall call) async {
    if (call.method == 'getAll') return <String, dynamic>{};
    return true;
  });
}

Future<void> _initSupabase() async {
  final mockClient = MockClient((request) async {
    if (request.url.path.endsWith('/logout')) return http.Response('', 204);
    return http.Response('{}', 200);
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
}

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/reset',
    routes: [
      GoRoute(path: '/reset', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(
        path: '/sign-in',
        builder: (_, __) => const Scaffold(body: Text('SIGN IN SCREEN')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('/reset requires a real session, not just a recovery-shaped URL '
      '(c9e2b7)', () {
    testWidgets('NO session -> refuses the form and offers a new code',
        (tester) async {
      _mockPrefsChannel();
      await _initSupabase();
      // The flag the OLD guard trusted is deliberately TRUE here: this test
      // must fail for the right reason. Before the fix, this exact state
      // rendered a fully functional-looking password form.
      AppRouter.isPasswordRecovery = true;

      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('UPDATE PASSWORD'),
        findsNothing,
        reason: 'THE REGRESSION: with no session, updateUser can only throw '
            '"Auth session missing!". Offering the form invites the user to '
            'type a password that cannot possibly be saved.',
      );
      expect(
        find.text('REQUEST A NEW CODE'),
        findsOneWidget,
        reason: 'the user needs an action, not an internal error string',
      );
      expect(
        find.textContaining('different device'),
        findsOneWidget,
        reason: 'names the ACTUAL variable — which device requested the reset '
            '— instead of leaving the user to guess',
      );
    });

    testWidgets('WITH a session -> shows the form and names the account',
        (tester) async {
      _mockPrefsChannel();
      await _initSupabase();
      AppRouter.isPasswordRecovery = true;

      // Same shape password_reset_redirect_flow_test feeds setInitialSession —
      // parsed locally, no network.
      await Supabase.instance.client.auth.setInitialSession(jsonEncode({
        'access_token': 'fake-access-token',
        'token_type': 'bearer',
        'refresh_token': 'fake-refresh-token',
        'user': {
          'id': 'fake-user-id',
          'aud': 'authenticated',
          'email': 'recruit@example.com',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }));

      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('UPDATE PASSWORD'),
        findsOneWidget,
        reason: 'DISCRIMINATOR: a screen that refused unconditionally would '
            'pass the first case while breaking reset entirely',
      );
      expect(
        find.text('recruit@example.com'),
        findsOneWidget,
        reason: 'founder observation 2026-08-06 — the screen named no account, '
            'so a wrong-account reset was indistinguishable from a right one. '
            'Only answerable once a session exists to read currentUser from.',
      );
    });
  });
}
