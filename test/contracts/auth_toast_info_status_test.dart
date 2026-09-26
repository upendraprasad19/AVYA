// Regression test for diagnose (this batch): the signup "check your email
// (and spam folder) for a confirmation link, then sign in" toast — a
// non-error, expected happy-path message — rendered in the same red
// SnackBar (AppColors.bad) as a genuine sign-in failure, because it was
// forced into AuthStatus.error for lack of any other bucket. Founder: "Red
// toast to be coloured different. Wardroom theme."
//
// Fix: a new AuthStatus.info value + a pure authToastStyleFor(status)
// mapping (real production code, not a copy) that renders info in Wardroom
// gold (matching SyncBanner's tone for the same class of message) and
// leaves error red.
//
// Run: flutter test test/contracts/auth_toast_info_status_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/screens/sign_in_screen.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final m = RegExp(r'(?<!:)//').firstMatch(l);
      return m == null ? l : l.substring(0, m.start);
    })
    .join('\n');

void main() {
  group('authToastStyleFor (behavioral — pure function)', () {
    test('info renders Wardroom gold, not red', () {
      final style = authToastStyleFor(AuthStatus.info);
      expect(style.background, AppColors.accent);
      expect(style.text, AppColors.bgDeep);
      expect(style.background, isNot(AppColors.bad),
          reason: 'the exact regression: info must never render red');
    });

    test('error still renders red with white text (unchanged)', () {
      final style = authToastStyleFor(AuthStatus.error);
      expect(style.background, AppColors.bad);
      expect(style.text, Colors.white);
    });

    test('any other status defaults to error styling (defensive)', () {
      for (final s in [AuthStatus.idle, AuthStatus.loading, AuthStatus.success]) {
        final style = authToastStyleFor(s);
        expect(style.background, AppColors.bad);
      }
    });
  });

  group('AuthNotifier.signUpWithEmail message classification (structural — '
      'source-grep, same justification pattern used throughout this '
      'directory for provider methods that need a live Supabase session to '
      'exercise end-to-end)', () {
    late String providerSrc;

    setUpAll(() {
      providerSrc = _strip(
        File('lib/features/auth/providers/auth_provider.dart')
            .readAsStringSync(),
      );
    });

    test('the confirmation-pending message uses AuthStatus.info, not .error',
        () {
      final i = providerSrc.indexOf(
        "'Check your email (and spam folder) for a confirmation link, then sign in.'",
      );
      expect(i, isNot(-1), reason: 'message text must be unchanged');
      final before = providerSrc.substring((i - 150).clamp(0, i), i);
      expect(before, contains('AuthStatus.info'));
      expect(before, isNot(contains('AuthStatus.error')));
    });

    test(
        'the "account already exists" message is UNCHANGED — still '
        'AuthStatus.error (regression guard: this fix must not silently '
        'soften a real conflict into a gold toast)', () {
      final i = providerSrc.indexOf(
        "'An account with this email already exists. Please sign in.'",
      );
      expect(i, isNot(-1));
      final before = providerSrc.substring((i - 150).clamp(0, i), i);
      expect(before, contains('AuthStatus.error'));
    });
  });

  group('sign_in_screen.dart renders both statuses through the shared style '
      'mapping (structural)', () {
    late String screenSrc;

    setUpAll(() {
      screenSrc = _strip(
        File('lib/features/auth/screens/sign_in_screen.dart')
            .readAsStringSync(),
      );
    });

    test('ref.listen checks for BOTH AuthStatus.error and AuthStatus.info',
        () {
      expect(screenSrc, contains('AuthStatus.error ||'));
      expect(screenSrc, contains('AuthStatus.info'));
    });

    test('the SnackBar background/text colors come from authToastStyleFor, '
        'not a hardcoded AppColors.bad', () {
      final start = screenSrc.indexOf('final toastStyle = authToastStyleFor(');
      expect(start, isNot(-1));
      final end = screenSrc.indexOf(
        'authNotifier.resetState()',
        start,
      );
      expect(end, isNot(-1));
      final body = screenSrc.substring(start, end);
      expect(body, contains('authToastStyleFor(next.status)'));
      expect(body, contains('toastStyle.background'));
      expect(body, contains('toastStyle.text'));
      expect(body, isNot(contains('AppColors.bad')),
          reason: 'a hardcoded AppColors.bad here would silently bypass '
              'authToastStyleFor and reintroduce the bug for one status '
              'while the pure-function tests above stay green');
    });
  });
}
