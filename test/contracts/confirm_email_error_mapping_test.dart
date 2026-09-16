import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Behavioral tests for [AuthNotifier.confirmEmailErrorState] — the pure
/// mapping `confirmEmail`'s catch clauses delegate to.
///
/// Why a pure function and not an end-to-end test of `confirmEmail` itself:
/// `confirmEmail` calls the real `Supabase.instance.client.auth.verifyOTP`,
/// and this codebase has no dependency-injection seam for that call (unlike
/// `AuthNotifier.boundSignIn`, which IS injectable — see
/// `sign_in_timeout_behavioral_test.dart`). Extracting the error → message
/// SELECTION logic into a pure function makes it directly testable without
/// a live network call, the same shape this file's sibling tests already use
/// for `resolveDestination`/`postSessionRedirect`.
///
/// Regression this pins (B-pass Findings 2 + 3, email-confirm-ux):
/// pre-fix, `confirmEmail`'s only catch clauses were `on AuthException` and a
/// generic `catch (e)` that unconditionally showed "invalid or expired" —
/// wrong for BOTH a timeout (the confirmation may well have succeeded; the
/// user should retry, not request a new link) and a StateError from
/// `_ensureLocalUser`'s cross-account guard (confirmation DID succeed; the
/// user should just sign in again).
void main() {
  final loadingState = const AuthState2().copyWith(status: AuthStatus.loading);

  test('a TimeoutException maps to the actionable "taking longer" message', () {
    final result = AuthNotifier.confirmEmailErrorState(
      loadingState,
      TimeoutException('confirmEmail exceeded ceiling'),
    );

    expect(result.status, AuthStatus.error);
    expect(result.errorMessage, contains('taking longer than usual'));
    expect(
      result.errorMessage,
      isNot(contains('invalid or has expired')),
      reason:
          'a timeout is not the same failure as an invalid/expired link — '
          'the wrong message sends the user toward the wrong recovery '
          'action (requesting a new email instead of just retrying).',
    );
  });

  test(
    'a StateError (poisoned cross-account clear) maps to the sign-in-again '
    'message, not "invalid or expired"',
    () {
      final result = AuthNotifier.confirmEmailErrorState(
        loadingState,
        StateError('Cross-account clear partial-failed; signed out for safety.'),
      );

      expect(result.status, AuthStatus.error);
      expect(result.errorMessage, contains('sign in again'));
      expect(
        result.errorMessage,
        isNot(contains('invalid or has expired')),
        reason:
            'by the time _ensureLocalUser throws this StateError, '
            'verifyOTP already SUCCEEDED — the failure is local Hive '
            'cleanup, not a bad link. Pre-fix this fell into the generic '
            'catch and told the user their (valid, already-consumed) link '
            'was invalid.',
      );
    },
  );

  test('an AuthException surfaces its own message verbatim', () {
    final result = AuthNotifier.confirmEmailErrorState(
      loadingState,
      AuthException('otp_expired'),
    );

    expect(result.status, AuthStatus.error);
    expect(result.errorMessage, 'otp_expired');
  });

  test('any other exception falls back to the generic invalid-or-expired message', () {
    final result = AuthNotifier.confirmEmailErrorState(
      loadingState,
      Exception('some unrelated failure'),
    );

    expect(result.status, AuthStatus.error);
    expect(result.errorMessage, contains('invalid or has expired'));
  });

  group(
    'confirmEmailAuthGuardState — OI-205 interim guard (block, don\'t '
    'silently switch accounts, when already authenticated)',
    () {
      test('blocks with an actionable message when already authenticated', () {
        final result = AuthNotifier.confirmEmailAuthGuardState(
          loadingState,
          alreadyAuthenticated: true,
        );

        expect(result, isNotNull);
        expect(result!.status, AuthStatus.error);
        expect(result.errorMessage, contains('already signed in'));
        expect(
          result.errorMessage,
          isNot(contains('invalid or has expired')),
          reason:
              'this is a distinct, more specific refusal — not the generic '
              'link-invalid fallback.',
        );
      });

      test('does not block (returns null) when not authenticated', () {
        final result = AuthNotifier.confirmEmailAuthGuardState(
          loadingState,
          alreadyAuthenticated: false,
        );

        expect(
          result,
          isNull,
          reason:
              'the mirror case: the overwhelming majority of real /confirm '
              'opens are an unauthenticated user completing signup — this '
              'must never be blocked.',
        );
      });
    },
  );
}
