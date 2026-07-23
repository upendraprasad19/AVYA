import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/password_recovery_detector.dart';

/// Behavioral regression test for diagnose <id> (2026-07-23): the PKCE
/// `?code=` query-param shape Supabase now sends by default for password
/// recovery was never recognized by the fragment-only detector, so
/// `AppRouter.isPasswordRecovery` stayed false and the reset link fell
/// through to the normal authenticated-user flow (`/restoring` →
/// `/onboarding`) instead of `/reset`.
///
/// Fails on pre-fix `PasswordRecoveryDetector` (fragment-only) and passes
/// after the fix (adds the PKCE branch).
void main() {
  group('PasswordRecoveryDetector.detect', () {
    test('detects PKCE code param on /reset (the actual bug shape)', () {
      final result = PasswordRecoveryDetector.detect(
        Uri.parse('https://app.icanbefitter.com/reset?code=e715f1d9-1afb-4b58-8421-4cc6efb22ec5'),
      );
      expect(result.isRecovery, isTrue);
    });

    test('detects legacy implicit-flow fragment shape', () {
      final result = PasswordRecoveryDetector.detect(
        Uri.parse(
          'https://app.icanbefitter.com/reset#access_token=abc&refresh_token=def&type=recovery',
        ),
      );
      expect(result.isRecovery, isTrue);
      expect(result.accessToken, 'abc');
      expect(result.refreshToken, 'def');
    });

    test('does NOT flag a code param on an unrelated path', () {
      final result = PasswordRecoveryDetector.detect(
        Uri.parse('https://app.icanbefitter.com/sign-in?code=abc'),
      );
      expect(result.isRecovery, isFalse);
    });

    test('does NOT flag /reset with no code param and no recovery fragment', () {
      final result = PasswordRecoveryDetector.detect(
        Uri.parse('https://app.icanbefitter.com/reset'),
      );
      expect(result.isRecovery, isFalse);
    });

    test('does NOT flag an unrelated fragment', () {
      final result = PasswordRecoveryDetector.detect(
        Uri.parse('https://app.icanbefitter.com/home#/restoring'),
      );
      expect(result.isRecovery, isFalse);
    });
  });
}
