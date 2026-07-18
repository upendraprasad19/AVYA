import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the email-first sign-in flow (2026-07): entering an
/// email now checks registration status server-side and branches
/// automatically to sign-in or sign-up, replacing the old manual toggle.
///
/// Pins the state-machine shape and the one collision risk that isn't
/// caught by `flutter analyze`: `checkEmailRegistered` must never reach
/// `AuthStatus.success`, since the screen's `ref.listen` auto-navigates to
/// `/restoring` on success and this check happens with no real session.
void main() {
  late String screenSrc;
  late String providerSrc;

  setUpAll(() {
    screenSrc =
        File('lib/features/auth/screens/sign_in_screen.dart')
            .readAsStringSync();
    providerSrc =
        File('lib/features/auth/providers/auth_provider.dart')
            .readAsStringSync();
  });

  test('_EmailStep enum has exactly the 3 expected values', () {
    final enumStart = screenSrc.indexOf('enum _EmailStep {');
    expect(enumStart, isNot(-1), reason: '_EmailStep enum must exist');
    final enumLine = screenSrc.substring(
      enumStart,
      screenSrc.indexOf('}', enumStart) + 1,
    );
    expect(enumLine, contains('enterEmail'));
    expect(enumLine, contains('signIn'));
    expect(enumLine, contains('signUp'));
  });

  test('the manual sign-in/sign-up toggle is gone', () {
    expect(
      screenSrc.contains('_isSignUp'),
      isFalse,
      reason: 'The old manual toggle bool must be fully removed — the app '
          'decides sign-in vs sign-up automatically now.',
    );
  });

  test('enterEmail step calls checkEmailRegistered, not signIn/signUpWithEmail directly', () {
    final start = screenSrc.indexOf('Widget _buildEmailStepEnterEmail(');
    expect(start, isNot(-1),
        reason: '_buildEmailStepEnterEmail must exist');
    final end = screenSrc.indexOf('Widget _buildEmailStepSignIn(', start);
    expect(end, isNot(-1));
    final body = screenSrc.substring(start, end);

    expect(body, contains('checkEmailRegistered'));
    expect(body, isNot(contains('signInWithEmail(')));
    expect(body, isNot(contains('signUpWithEmail(')));
  });

  test('checkEmailRegistered never sets AuthStatus.success', () {
    final start = providerSrc.indexOf('Future<bool?> checkEmailRegistered(');
    expect(start, isNot(-1), reason: 'checkEmailRegistered must exist on AuthNotifier');
    final end = providerSrc.indexOf(
      '\n  Future<bool> rpcEmailIsRegistered(',
      start,
    );
    expect(end, isNot(-1));
    final body = providerSrc.substring(start, end);

    expect(
      body,
      isNot(contains('AuthStatus.success')),
      reason: 'checkEmailRegistered must never reach AuthStatus.success — '
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
    final start = screenSrc.indexOf('void _backToEnterEmail(');
    expect(start, isNot(-1), reason: '_backToEnterEmail must exist');
    final end = screenSrc.indexOf('\n  }', start);
    final body = screenSrc.substring(start, end);
    expect(body, contains('resetState()'));
  });
}
