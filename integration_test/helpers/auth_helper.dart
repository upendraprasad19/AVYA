import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test credentials — this user exists on local Supabase (staging only).
const kTestEmail = 'qa@icanbefitter.com';
const kTestPassword = 'QA_Test_2024!';

/// Ticks the GDPR/DPDP consent checkbox on the sign-in screen.
///
/// Must be called before any sign-in attempt — the consent checkbox
/// gates all sign-in buttons (Google, Email, Phone).
Future<void> tickConsentCheckbox(WidgetTester tester) async {
  // The checkbox is inside a GestureDetector row. Find the Checkbox widget.
  final checkbox = find.byType(Checkbox);
  if (checkbox.evaluate().isNotEmpty) {
    await tester.tap(checkbox.first);
    await tester.pumpAndSettle();
  }
}

/// Drives the sign-in flow using email + password.
///
/// Automatically ticks the GDPR consent checkbox, navigates to the
/// email sign-in view, enters credentials, and waits for navigation.
Future<void> signInWithTestUser(WidgetTester tester) async {
  // Tick GDPR consent checkbox first — required before any sign-in button works.
  await tickConsentCheckbox(tester);

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
