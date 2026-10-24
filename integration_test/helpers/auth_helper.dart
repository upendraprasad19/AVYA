import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test credentials, environment-driven — never literals (OI-116).
///
/// Device/integration runs get these from `--dart-define-from-file=.env`; see
/// `.env.example` and `docs/operations/DEVICE_TESTING.md`.
const kTestEmail = String.fromEnvironment('SUPABASE_TEST_EMAIL');
const kTestPassword = String.fromEnvironment('SUPABASE_TEST_PASSWORD');

/// Whether both credentials are present.
///
/// This file previously had NO skip-gate at all. Once the constants became
/// environment-driven that gap turned into a functional bug: a device run
/// without the defines would type an EMPTY email and password into the sign-in
/// form and fail with a UI error, rather than skipping. Every flow that signs
/// in must check this first.
bool get kTestCredentialsPresent =>
    kTestEmail.isNotEmpty && kTestPassword.isNotEmpty;

/// Drives the sign-in flow using email + password.
///
/// Navigates to the email sign-in view, enters credentials, and waits for
/// navigation (there is no consent checkbox since 2026-10-16, OI-305).
Future<void> signInWithTestUser(WidgetTester tester) async {
  // THE GUARD, WIRED. Defining kTestCredentialsPresent and calling it from
  // nowhere is worse than not having it: the B-pass found the constant with a
  // single hit — its own definition — while DEVICE_TESTING.md asserted every
  // sign-in flow checked it. This is the single choke point every device flow
  // reaches before typing anything, so it is the right place.
  //
  // It THROWS rather than skipping. A silent skip on a suite that is invoked by
  // hand is the OI-105 shape — the run looks like it passed and verified
  // nothing. Without the defines the alternative is typing an EMPTY email and
  // password into the form and failing on a UI error that names neither cause.
  if (!kTestCredentialsPresent) {
    throw StateError(
      'signInWithTestUser: SUPABASE_TEST_EMAIL / SUPABASE_TEST_PASSWORD are not '
      'set. Device runs read them from .env via --dart-define-from-file=.env — '
      'see .env.example and docs/operations/DEVICE_TESTING.md. Refusing to type '
      'empty credentials into the sign-in form, which would fail with a UI '
      'error naming neither the missing define nor this helper.',
    );
  }

  // Tap "Continue with Email" if the main sign-in screen is shown first.
  final emailButton = find.textContaining('Email', findRichText: true);
  if (emailButton.evaluate().isNotEmpty) {
    await tester.tap(emailButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // Enter email.
  final emailField = find.byType(TextField).first;
  await tester.enterText(emailField, kTestEmail);
  await tester.pumpAndSettle();

  // Enter password.
  final passwordField = find.byType(TextField).at(1);
  await tester.enterText(passwordField, kTestPassword);
  await tester.pumpAndSettle();

  // Tap sign in.
  final signInButton = find.textContaining('Sign In', findRichText: true);
  await tester.tap(signInButton.first);

  // Wait for auth + navigation (Supabase + Hive writes).
  await tester.pumpAndSettle(const Duration(seconds: 5));
}
