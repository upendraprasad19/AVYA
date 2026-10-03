import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the email-first sign-in flow (2026-07, redesigned
/// 2026-08 to merge email entry onto the main view — 3 screens down to 2):
/// entering an email now checks registration status server-side and
/// branches automatically to sign-in or sign-up, replacing the old manual
/// toggle. The email field itself lives inline on the main view (alongside
/// the Google button) instead of behind a separate "ENLIST VIA EMAIL" tap.
///
/// Pins the state-machine shape and the one collision risk that isn't
/// caught by `flutter analyze`: `checkEmailRegistered` must never reach
/// `AuthStatus.success`, since the screen's `ref.listen` auto-navigates to
/// `/restoring` on success and this check happens with no real session.
void main() {
  late String screenSrc;
  late String providerSrc;

  setUpAll(() {
    screenSrc = File(
      'lib/features/auth/screens/sign_in_screen.dart',
    ).readAsStringSync();
    providerSrc = File(
      'lib/features/auth/providers/auth_provider.dart',
    ).readAsStringSync();
  });

  test(
    '_EmailStep enum has exactly the 2 expected values (enterEmail merged into main view)',
    () {
      final enumStart = screenSrc.indexOf('enum _EmailStep {');
      expect(enumStart, isNot(-1), reason: '_EmailStep enum must exist');
      final enumLine = screenSrc.substring(
        enumStart,
        screenSrc.indexOf('}', enumStart) + 1,
      );
      expect(
        enumLine,
        isNot(contains('enterEmail')),
        reason:
            'the enterEmail step was merged into the main view — the '
            'enum must not carry it anymore',
      );
      expect(enumLine, contains('signIn'));
      expect(enumLine, contains('signUp'));
    },
  );

  test('the manual sign-in/sign-up toggle is gone', () {
    expect(
      screenSrc.contains('_isSignUp'),
      isFalse,
      reason:
          'The old manual toggle bool must be fully removed — the app '
          'decides sign-in vs sign-up automatically now.',
    );
  });

  test('the separate enterEmail step widget no longer exists', () {
    expect(
      screenSrc.contains('_buildEmailStepEnterEmail'),
      isFalse,
      reason:
          'email entry now lives inline on _buildMainView, not as its '
          'own step widget',
    );
  });

  test(
    'main view calls checkEmailRegistered, not signIn/signUpWithEmail directly',
    () {
      final start = screenSrc.indexOf('Widget _buildMainView(');
      expect(start, isNot(-1), reason: '_buildMainView must exist');
      final end = screenSrc.indexOf('Widget _buildEnlistButton(', start);
      expect(end, isNot(-1));
      final body = screenSrc.substring(start, end);

      expect(body, contains('checkEmailRegistered'));
      expect(
        body,
        contains('_currentView = _SignInView.email'),
        reason:
            'CONTINUE must transition straight into the email sub-view '
            '(signIn/signUp) — the merged screen has no separate enterEmail '
            'hop to do it for it anymore',
      );
      expect(body, isNot(contains('signInWithEmail(')));
      expect(body, isNot(contains('signUpWithEmail(')));
    },
  );

  test('checkEmailRegistered never sets AuthStatus.success', () {
    final start = providerSrc.indexOf('Future<bool?> checkEmailRegistered(');
    expect(
      start,
      isNot(-1),
      reason: 'checkEmailRegistered must exist on AuthNotifier',
    );
    final end = providerSrc.indexOf(
      '\n  Future<bool> rpcEmailIsRegistered(',
      start,
    );
    expect(end, isNot(-1));
    final body = providerSrc.substring(start, end);

    expect(
      body,
      isNot(contains('AuthStatus.success')),
      reason:
          'checkEmailRegistered must never reach AuthStatus.success — '
          'the screen auto-navigates to /restoring on success, and this '
          'check runs with no real session.',
    );
  });

  test('checkEmailRegistered guards on ensureSupabaseReady and delegates '
      'the network call to rpcEmailIsRegistered', () {
    final start = providerSrc.indexOf('Future<bool?> checkEmailRegistered(');
    final end = providerSrc.indexOf(
      '\n  Future<bool> rpcEmailIsRegistered(',
      start,
    );
    final body = providerSrc.substring(start, end);
    expect(body, contains('ensureSupabaseReady()'));
    expect(body, contains('rpcEmailIsRegistered('));
  });

  test('"change email" resets auth notifier state', () {
    final start = screenSrc.indexOf('void _backToMain(');
    expect(
      start,
      isNot(-1),
      reason:
          '_backToMain must exist (renamed from _backToEnterEmail — '
          'it now returns to the merged main view, not a separate step)',
    );
    final end = screenSrc.indexOf('\n  }', start);
    final body = screenSrc.substring(start, end);
    expect(body, contains('resetState()'));
    expect(body, contains('_SignInView.main'));
  });
}
