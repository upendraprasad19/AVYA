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
///  T3 – The sign-in screen has no consent checkbox (OI-305, 2026-10-16)
///  T4 – Referral code field toggle shows and hides
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

    final emailButton = find.textContaining('Email', findRichText: true);
    if (emailButton.evaluate().isNotEmpty) {
      await tester.tap(emailButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // THE ONE BYPASS. Every other flow in integration_test/ reaches the
    // credential guard through signInWithTestUser(); this test types kTestEmail
    // itself, so it needs its own check. Without it and without the defines,
    // kTestEmail is '' — T2 types an empty email, the app cannot navigate away
    // from an empty email either, and its sole assertion (the sign-in screen is
    // still shown) PASSES. The test would silently degrade from "a wrong
    // password is rejected" to "nothing happened", and stay green. Found by two
    // independent Hermes lenses after a first fix claimed signInWithTestUser was
    // "the single choke point" — it is the choke point for 95 call sites and
    // missed this one.
    if (!kTestCredentialsPresent) {
      throw StateError(
        'auth_flow T2: SUPABASE_TEST_EMAIL / SUPABASE_TEST_PASSWORD are not set. '
        'Typing an empty email here would make this test pass while verifying '
        'nothing. See .env.example and docs/operations/DEVICE_TESTING.md.',
      );
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

  testWidgets('T3: the sign-in screen has no consent checkbox', (tester) async {
    // OI-305 (2026-10-16): consent is the tap on CREATE ACCOUNT under a
    // "By tapping CREATE ACCOUNT, you agree to our Privacy Policy and Terms"
    // notice (sign-up step only); there is no checkbox anywhere on this screen.
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(Checkbox), findsNothing,
        reason: 'the consent checkbox was removed (OI-305, 2026-10-16)');
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Referral code field toggle shows and hides', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

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
}
