import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test credentials — this user exists on local Supabase (staging only).
const kTestEmail = 'qa@icanbefitter.com';
const kTestPassword = 'QA_Test_2024!';

/// Drives the sign-in flow using email + password.
///
/// Finds the email input, password input, and sign-in button
/// then waits for navigation to complete.
Future<void> signInWithTestUser(WidgetTester tester) async {
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
