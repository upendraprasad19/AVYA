import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep contract test for the Google OAuth redirect flow.
///
/// Fails pre-fix and passes post-fix for diagnose f2b8a1: `signInWithGoogle`
/// passed the mobile-only custom-scheme `redirectTo` unconditionally, with
/// no `kIsWeb` branch — on web a browser has no handler for
/// `io.supabase.icanbefitter://...`, stranding the user after Google
/// consent. Same bug class as e9f2a4 (redirectTo must match the platform /
/// Supabase's allowed redirect list), applied to web-vs-mobile instead of
/// wrong-domain.
///
/// Also pins the Android manifest deep-link intent-filter that lets the
/// mobile branch's redirect actually land back in the app — without it,
/// Google sign-in cannot complete on Android regardless of the redirectTo
/// value.
void main() {
  late String authProvider;
  late String androidManifest;

  setUpAll(() {
    final root = Directory.current.path;
    authProvider = File(
      '$root/lib/features/auth/providers/auth_provider.dart',
    ).readAsStringSync();
    androidManifest = File(
      '$root/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  group('auth_provider.dart — signInWithGoogle redirectTo', () {
    test('branches redirectTo on kIsWeb', () {
      // Anchored on `signInWithOAuth(` — the actual OAuth launch — NOT on a
      // fixed 700-char window from `signInWithGoogle`.
      //
      // The old window broke (2026-08-08, d3a7c9) when the launch was extracted
      // into `launchGoogleOAuth()` so the OAuth-completion watch could be
      // tested. The extracted helper sits ABOVE signInWithGoogle in the file, so
      // a forward-only window from signInWithGoogle could never reach it: the
      // contract still held and the test went red anyway. Its two sibling cases
      // stayed green throughout, because they grep the whole file.
      //
      // Anchoring on the call the contract is ABOUT survives that refactor, and
      // fails for the reason the test exists (a hardcoded single-platform
      // redirect) rather than for where the code happens to live.
      final oauthIndex = authProvider.indexOf('signInWithOAuth(');
      expect(oauthIndex, isNot(-1),
          reason: 'auth_provider must still launch OAuth via signInWithOAuth.');
      final start = (oauthIndex - 200).clamp(0, authProvider.length);
      final end = (oauthIndex + 500).clamp(0, authProvider.length);
      final launchBody = authProvider.substring(start, end);
      expect(
        launchBody,
        contains('redirectTo'),
        reason: 'the OAuth launch must pass an explicit redirectTo.',
      );
      expect(
        launchBody,
        contains('kIsWeb'),
        reason:
            'redirectTo must branch on platform — a single hardcoded value '
            'breaks whichever platform it does not match.',
      );
    });

    test('web branch redirects to the prod SPA origin', () {
      expect(
        authProvider,
        contains("'https://app.icanbefitter.com'"),
        reason:
            'web redirectTo must be the prod web origin, matching the '
            'known-good value from e9f2a4 (forgot_password_sheet.dart), not '
            'a custom mobile scheme a browser cannot resolve.',
      );
    });

    test('mobile branch still redirects to the custom scheme', () {
      expect(
        authProvider,
        contains("'io.supabase.icanbefitter://login-callback/'"),
        reason: 'mobile redirectTo must remain the custom scheme caught by '
            "the AndroidManifest intent-filter.",
      );
    });
  });

  group('AndroidManifest.xml — OAuth redirect intent-filter', () {
    test('declares the io.supabase.icanbefitter scheme', () {
      expect(
        androidManifest,
        contains('android:scheme="io.supabase.icanbefitter"'),
        reason:
            'without this intent-filter, Android has no app registered to '
            'catch the OAuth redirect after Google consent completes.',
      );
    });

    test('scopes the intent-filter to the login-callback host', () {
      expect(
        androidManifest,
        contains('android:host="login-callback"'),
        reason: 'must match the exact host in the redirectTo URI '
            "('io.supabase.icanbefitter://login-callback/').",
      );
    });

    test('intent-filter is BROWSABLE so the OAuth browser can trigger it', () {
      final schemeIndex = androidManifest.indexOf(
        'android:scheme="io.supabase.icanbefitter"',
      );
      expect(schemeIndex, isNot(-1));
      final surrounding = androidManifest.substring(
        (schemeIndex - 300).clamp(0, androidManifest.length),
        schemeIndex,
      );
      expect(
        surrounding,
        contains('android.intent.category.BROWSABLE'),
        reason:
            'BROWSABLE is required for the system browser to be able to '
            'launch this app via the redirect URI.',
      );
    });
  });
}
