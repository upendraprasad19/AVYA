import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Pure-function coverage for [AuthNotifier.isEmailNotConfirmedMessage] —
/// the detector `sign_in_screen.dart` uses to decide whether to show the
/// "resend confirmation email" affordance. See
/// `test/auth/sign_in_screen_resend_confirmation_test.dart` for the
/// end-to-end widget coverage; this file pins the SELECTION logic in
/// isolation, the same split `confirm_email_error_mapping_test.dart` uses
/// for its sibling pure functions.
void main() {
  test('matches Supabase\'s exact GoTrue message', () {
    expect(AuthNotifier.isEmailNotConfirmedMessage('Email not confirmed'), isTrue);
  });

  test('matches case-insensitively', () {
    expect(AuthNotifier.isEmailNotConfirmedMessage('email not confirmed'), isTrue);
    expect(AuthNotifier.isEmailNotConfirmedMessage('EMAIL NOT CONFIRMED'), isTrue);
  });

  test('null does not match', () {
    expect(AuthNotifier.isEmailNotConfirmedMessage(null), isFalse);
  });

  test('a different auth failure does not match', () {
    expect(
      AuthNotifier.isEmailNotConfirmedMessage('Invalid login credentials'),
      isFalse,
      reason: 'the mirror case — a wrong-password failure must never trigger '
          'the resend-confirmation affordance',
    );
  });

  test('an unrelated info message does not match', () {
    expect(
      AuthNotifier.isEmailNotConfirmedMessage(
        'Check your email (and spam folder) for a confirmation link, then sign in.',
      ),
      isFalse,
      reason: 'the sign-up confirmation-pending message must not itself be '
          'mistaken for the sign-in failure it precedes',
    );
  });
}
