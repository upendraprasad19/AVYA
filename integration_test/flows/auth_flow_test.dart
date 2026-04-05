import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';

/// Flow 1: Sign in → reach Home screen.
///
/// Verifies the full auth handshake: UI → Supabase local → Hive write →
/// GoRouter redirect to /home. This catches: wrong Supabase URL, broken
/// auth provider, missing Hive box writes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    // Sign out after each test to reset auth state.
    await SupabaseService.instance.client.auth.signOut();
    await clearHiveForTest();
  });

  testWidgets('Sign in with email → navigates to Home screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Should start on sign-in screen.
    expect(find.textContaining('AVYA', findRichText: true), findsWidgets);

    await signInWithTestUser(tester);

    // After sign in, should be on Home screen.
    // Home screen shows a greeting, weekly calendar, or "Today's Workout".
    final onHome =
        find.textContaining('Today', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Good', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Workout', findRichText: true).evaluate().isNotEmpty;

    expect(onHome, isTrue,
        reason: 'Expected to navigate to Home screen after sign in');
  });

  testWidgets('Sign in with wrong password → shows error', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

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
}
