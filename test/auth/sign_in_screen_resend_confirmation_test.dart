import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';

/// Behavioral coverage for the "Email not confirmed" self-service recovery
/// path — diagnose 2026-09-23 (`sumitk142003@gmail.com` support report):
/// live `auth.users` showed the majority of real external signups whose
/// confirmation email was ever sent never completed confirmation, with no
/// in-app way to request a fresh link. `sign_in_screen.dart` previously had
/// a resend affordance only for phone OTP; a failed email sign-in had
/// nothing but a transient red SnackBar and no recovery action.
///
/// Fakes bypass the real Supabase network calls entirely — same pattern as
/// `sign_in_screen_email_gate_test.dart`'s `_FakeAuthNotifier` — by
/// overriding the public `AuthNotifier` methods the screen calls and driving
/// `state` directly.
class _FakeUnconfirmedAuthNotifier extends AuthNotifier {
  int resendCallCount = 0;
  String? lastResendEmail;

  @override
  Future<bool?> checkEmailRegistered(String email) async => true;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    // Supabase's own GoTrue error string, verbatim (case matches the live
    // AuthException this mirrors — see auth_provider.dart:287-291, which
    // passes e.message straight through unmodified).
    state = state.copyWith(status: AuthStatus.error, errorMessage: 'Email not confirmed');
  }

  @override
  Future<void> resendConfirmationEmail(String email) async {
    resendCallCount++;
    lastResendEmail = email;
    state = state.copyWith(
      status: AuthStatus.info,
      errorMessage: 'Confirmation email resent. Check your inbox (and spam folder).',
    );
  }
}

/// B-pass Finding 1 (docs/reviews/3aa28693fb6f-review.md): the affordance's
/// own doc comment says it stays visible "so the user can resend again if
/// the fresh email also goes astray" — but a FAILED resend (rate-limited,
/// network error, etc.) used to hide it at exactly the moment it's needed
/// most, because the listener recomputed the flag from every error message.
class _FakeUnconfirmedThenFailedResendAuthNotifier extends AuthNotifier {
  int resendCallCount = 0;

  @override
  Future<bool?> checkEmailRegistered(String email) async => true;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.error, errorMessage: 'Email not confirmed');
  }

  @override
  Future<void> resendConfirmationEmail(String email) async {
    resendCallCount++;
    // Mirrors auth_provider.dart's real `on AuthException catch` arm for a
    // rate-limited resend — a genuinely different error message than "Email
    // not confirmed".
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: 'email rate limit exceeded',
    );
  }
}

/// Mirror case (feedback_mistake_guard_without_its_mirror.md): a DIFFERENT
/// sign-in failure must NOT show the resend-confirmation affordance — only
/// the specific "Email not confirmed" error should.
class _FakeWrongPasswordAuthNotifier extends AuthNotifier {
  @override
  Future<bool?> checkEmailRegistered(String email) async => true;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: 'Invalid login credentials',
    );
  }
}

const _resendLinkText = "Didn't get the confirmation email? Resend it";

Future<void> _openSignInStepAndSubmit(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final emailField = find.byType(TextFormField).first;
  await tester.ensureVisible(emailField);
  await tester.enterText(emailField, email);
  await tester.ensureVisible(find.text('CONTINUE'));
  await tester.tap(find.text('CONTINUE'));
  await tester.pumpAndSettle();

  expect(find.text('SIGN IN WITH EMAIL'), findsOneWidget);

  final passwordField = find.byType(TextFormField).first;
  await tester.ensureVisible(passwordField);
  await tester.enterText(passwordField, password);
  await tester.ensureVisible(find.text('SIGN IN WITH EMAIL'));
  await tester.tap(find.text('SIGN IN WITH EMAIL'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a sign-in failing with "Email not confirmed" shows the resend affordance',
    (tester) async {
      final notifier = _FakeUnconfirmedAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openSignInStepAndSubmit(
        tester,
        email: 'sumitk142003@gmail.com',
        password: 'password123',
      );

      expect(
        find.text(_resendLinkText),
        findsOneWidget,
        reason: 'the specific "Email not confirmed" failure must offer a '
            'self-service resend action, not just the transient SnackBar',
      );
    },
  );

  testWidgets(
    'a DIFFERENT sign-in failure (wrong password) does NOT show the resend '
    'affordance — mirror of the positive case',
    (tester) async {
      final notifier = _FakeWrongPasswordAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openSignInStepAndSubmit(
        tester,
        email: 'someone@example.com',
        password: 'wrongpassword',
      );

      expect(
        find.text(_resendLinkText),
        findsNothing,
        reason: 'a wrong-password failure is not an unconfirmed-email '
            'failure — showing "resend confirmation" here would be actively '
            'misleading recovery guidance',
      );
    },
  );

  testWidgets(
    'tapping the resend link calls resendConfirmationEmail with the '
    'trimmed, entered email exactly once',
    (tester) async {
      final notifier = _FakeUnconfirmedAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openSignInStepAndSubmit(
        tester,
        email: '  sumitk142003@gmail.com  ',
        password: 'password123',
      );

      await tester.ensureVisible(find.text(_resendLinkText));
      await tester.tap(find.text(_resendLinkText));
      await tester.pumpAndSettle();

      expect(notifier.resendCallCount, 1);
      expect(notifier.lastResendEmail, 'sumitk142003@gmail.com');
      // The affordance stays visible after a successful resend so the user
      // can resend again if the fresh email also goes astray.
      expect(find.text(_resendLinkText), findsOneWidget);
    },
  );

  testWidgets(
    'a FAILED resend attempt keeps the affordance visible — the sticky-once-'
    'shown fix for B-pass Finding 1 (docs/reviews/3aa28693fb6f-review.md)',
    (tester) async {
      final notifier = _FakeUnconfirmedThenFailedResendAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openSignInStepAndSubmit(
        tester,
        email: 'sumitk142003@gmail.com',
        password: 'password123',
      );
      expect(find.text(_resendLinkText), findsOneWidget);

      await tester.ensureVisible(find.text(_resendLinkText));
      await tester.tap(find.text(_resendLinkText));
      await tester.pumpAndSettle();

      expect(notifier.resendCallCount, 1);
      expect(
        find.text(_resendLinkText),
        findsOneWidget,
        reason: 'a rate-limited/failed resend is exactly the case where the '
            'user most needs to retry — the affordance must not disappear',
      );
    },
  );

  testWidgets(
    '"CHANGE EMAIL" hides a previously-shown resend affordance',
    (tester) async {
      final notifier = _FakeUnconfirmedAuthNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authNotifierProvider.overrideWith(() => notifier)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _openSignInStepAndSubmit(
        tester,
        email: 'sumitk142003@gmail.com',
        password: 'password123',
      );
      expect(find.text(_resendLinkText), findsOneWidget);

      await tester.ensureVisible(find.text('CHANGE EMAIL'));
      await tester.tap(find.text('CHANGE EMAIL'));
      await tester.pumpAndSettle();

      expect(
        find.text(_resendLinkText),
        findsNothing,
        reason: 'the affordance is scoped to the email just attempted — '
            'switching emails must not carry a stale offer forward',
      );
    },
  );
}
