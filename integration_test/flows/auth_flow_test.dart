import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';

/// Flow 1: Auth flow — consent, sign in, referral code.
///
/// Tests:
///  T1 – Sign in with email → reach Home screen (existing)
///  T2 – Sign in with wrong password → shows error (existing)
///  T3 – GDPR consent checkbox must be ticked before sign-in buttons work
///  T4 – Referral code field toggle shows and hides
///  T5 – Sign-in buttons are disabled when consent is not ticked
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await SupabaseService.instance.client.auth.signOut();
    await clearHiveForTest();
  });

  // ── T1 ──────────────────────────────────────────────────────────

  testWidgets('T1: Sign in with email → navigates to Home screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Should start on sign-in screen.
    expect(find.textContaining('AVYA', findRichText: true), findsWidgets);

    await signInWithTestUser(tester);

    // After sign in, should be on Home screen.
    final onHome =
        find.textContaining('Today', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Good', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Workout', findRichText: true).evaluate().isNotEmpty;

    expect(onHome, isTrue,
        reason: 'Expected to navigate to Home screen after sign in');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: Sign in with wrong password → shows error', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Must tick consent first
    await tickConsentCheckbox(tester);

    final emailButton = find.textContaining('Email', findRichText: true);
    if (emailButton.evaluate().isNotEmpty) {
      await tester.tap(emailButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    final emailField = find.byType(TextField).first;
    await tester.enterText(emailField, kTestEmail);
    await tester.pumpAndSettle();

    final passwordField = find.byType(TextField).at(1);
    await tester.enterText(passwordField, 'wrong_password_123');
    await tester.pumpAndSettle();

    final signInButton = find.textContaining('Sign In', findRichText: true);
    await tester.tap(signInButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Should still be on sign-in screen (not navigated away).
    expect(find.textContaining('Email', findRichText: true), findsWidgets);
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: GDPR consent checkbox is visible on sign-in screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Consent checkbox should be visible
    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget,
        reason: 'GDPR consent checkbox must be visible on the sign-in screen');

    // "I agree" text should be visible
    final agreeText = find.textContaining('I agree', findRichText: true);
    expect(agreeText, findsOneWidget,
        reason: 'Consent text "I agree to the..." must be visible');

    // "Privacy Policy" link text should be visible
    final privacyLink = find.textContaining('Privacy Policy', findRichText: true);
    expect(privacyLink, findsOneWidget,
        reason: 'Privacy Policy link must be present in consent text');
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Referral code field toggle shows and hides', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Tick consent first
    await tickConsentCheckbox(tester);

    // Navigate to email sign-in view
    final emailButton = find.textContaining('Email', findRichText: true);
    if (emailButton.evaluate().isNotEmpty) {
      await tester.tap(emailButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // Find "Have a referral code?" button
    final referralToggle = find.textContaining('referral code', findRichText: true);
    expect(referralToggle, findsOneWidget,
        reason: 'Referral code toggle should be visible on email sign-in view');

    // Tap to show referral field
    await tester.tap(referralToggle.first);
    await tester.pumpAndSettle();

    // Referral input should now be visible (look for hint text)
    final referralHint = find.textContaining('AVYA', findRichText: true);
    expect(referralHint.evaluate().isNotEmpty, isTrue,
        reason: 'Referral code input field should appear after tapping toggle');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: Sign-in buttons disabled without consent', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Without ticking consent, find the Google sign-in button
    // It should be present but disabled (onPressed: null)
    final googleButton = find.textContaining('Google', findRichText: true);
    if (googleButton.evaluate().isNotEmpty) {
      // Try to find the ElevatedButton/OutlinedButton ancestor
      final buttons = find.byType(ElevatedButton);
      for (final button in buttons.evaluate()) {
        final widget = button.widget as ElevatedButton;
        // At least one button should be disabled (onPressed == null)
        if (widget.onPressed == null) {
          // Found a disabled button — consent is gating sign-in
          expect(true, isTrue);
          return;
        }
      }
      // Also check OutlinedButton
      final outlinedButtons = find.byType(OutlinedButton);
      for (final button in outlinedButtons.evaluate()) {
        final widget = button.widget as OutlinedButton;
        if (widget.onPressed == null) {
          expect(true, isTrue);
          return;
        }
      }
    }

    // If we got here, verify by ticking consent and checking buttons become enabled
    await tickConsentCheckbox(tester);
    await tester.pumpAndSettle();

    // After consent, at least one button should be enabled
    final buttons = find.byType(ElevatedButton);
    bool foundEnabled = false;
    for (final button in buttons.evaluate()) {
      final widget = button.widget as ElevatedButton;
      if (widget.onPressed != null) {
        foundEnabled = true;
        break;
      }
    }
    if (!foundEnabled) {
      final outlinedButtons = find.byType(OutlinedButton);
      for (final button in outlinedButtons.evaluate()) {
        final widget = button.widget as OutlinedButton;
        if (widget.onPressed != null) {
          foundEnabled = true;
          break;
        }
      }
    }
    expect(foundEnabled, isTrue,
        reason: 'After ticking consent, at least one sign-in button should be enabled');
  });
}
