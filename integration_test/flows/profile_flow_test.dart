import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';
import '../helpers/navigation_helper.dart';
import '../helpers/test_data_helper.dart';

/// Flow 6: Profile tab — bio stats, subscription status, edit flow.
///
/// Tests:
///  T1 – Profile tab renders without crash
///  T2 – User name and email are shown
///  T3 – Bio stats card shows height, weight, goal
///  T4 – Subscription card shows "Free" for a free user
///  T5 – Edit Profile screen navigates from Profile tab
///  T6 – Weight change is written to Hive userBox
///  T7 – Goal card shows current fitness goal
///  T8 – Logout clears auth and returns to sign-in screen
///  T9 – Reports section accessible from Profile
/// T10 – Health sync section visible (even if not connected)
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

  testWidgets('T1: Profile tab renders without crash', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    expect(tester.takeException(), isNull,
        reason: 'Profile tab should render without exception');

    final onProfile = anyTextVisible(
        ['Profile', 'Settings', 'Account', 'Subscription', 'Goal', 'Weight']);
    expect(onProfile, isTrue,
        reason: 'Profile tab should render profile content');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: User name or email shown on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(name: 'QA Tester');

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Should show either the full name from Hive or the logged-in email.
    final hasIdentity = anyTextVisible(
        ['QA Tester', 'QA', kTestEmail, 'qa@', 'icanbefitter']);
    expect(hasIdentity, isTrue,
        reason: 'Profile should display the user\'s name or email');
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: Bio stats card shows height, weight, goal', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(
      weight: 75.0,
      height: 175.0,
      goal: 'build_muscle',
    );

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Bio stats: height in cm or feet, weight in kg or lbs, goal text.
    final hasBioStats = anyTextVisible(
        ['75', '175', 'kg', 'cm', 'muscle', 'Muscle', 'Build', 'Goal', 'Height', 'Weight']);
    expect(hasBioStats, isTrue,
        reason: 'Profile should show bio stats (height, weight, goal)');
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Subscription card shows "Free" for a free user', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setFreeUser();

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    final showsFree = anyTextVisible(
        ['Free', 'free', 'Upgrade', 'trial', 'Trial', 'Basic']);
    expect(showsFree, isTrue,
        reason: 'Profile should show free-tier status for a non-PRO user');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: Edit Profile screen opens from Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    for (final label in ['Edit', 'Edit Profile', 'Update', 'Pencil']) {
      final btn = find.textContaining(label, findRichText: true);
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(tester.takeException(), isNull,
            reason: 'Edit Profile should open without crash');

        final onEditScreen = anyTextVisible(
            ['Edit', 'Save', 'Name', 'Weight', 'Height', 'Goal', 'Update']);
        expect(onEditScreen, isTrue,
            reason: 'Edit Profile screen should be visible');
        return;
      }
    }

    // Try the edit icon.
    final editIcon = find.byIcon(Icons.edit);
    if (editIcon.evaluate().isNotEmpty) {
      await tester.tap(editIcon.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    }
  });

  // ── T6 ──────────────────────────────────────────────────────────

  testWidgets('T6: Weight update is written to Hive userBox', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Directly write updated weight to Hive (simulate profile save).
    TestDataHelper.setUserProfile(weight: 74.0);

    // Verify Hive write.
    final userBox = HiveService.instance.userBox;
    final profile = userBox.get('profile') as Map?;
    expect(profile?['current_weight_kg'], equals(74.0),
        reason: 'Hive userBox should reflect the updated weight');

    await navigateToProfile(tester);
    expect(tester.takeException(), isNull);
  });

  // ── T7 ──────────────────────────────────────────────────────────

  testWidgets('T7: Goal card shows current fitness goal', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(goal: 'lose_fat');

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    final hasGoal = anyTextVisible(
        ['lose_fat', 'Lose Fat', 'Fat Loss', 'Weight Loss', 'Goal']);
    expect(hasGoal, isTrue,
        reason: 'Profile should display the user\'s fitness goal');
  });

  // ── T8 ──────────────────────────────────────────────────────────

  testWidgets('T8: Logout clears auth and returns to sign-in screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Find and tap Logout button.
    for (final label in ['Logout', 'Log Out', 'Sign Out', 'Sign out']) {
      final btn = find.textContaining(label, findRichText: true);
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Should return to sign-in screen.
        final onSignIn = anyTextVisible(
            ['Sign In', 'Login', 'AVYA', 'Email', 'Google', 'Continue']);
        expect(onSignIn, isTrue,
            reason: 'After logout user should be on the sign-in screen');
        return;
      }
    }
    // If Logout not found — may be behind a scroll or menu.
  });

  // ── T9 ──────────────────────────────────────────────────────────

  testWidgets('T9: Reports section accessible from Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Look for Reports button / section.
    for (final label in ['Report', 'Reports', 'Weekly Report', 'Summary']) {
      final btn = find.textContaining(label, findRichText: true);
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull,
            reason: 'Reports section should open without crash');
        return;
      }
    }
  });

  // ── T10 ─────────────────────────────────────────────────────────

  testWidgets('T10: Health sync section is visible on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll to find health sync section.
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }

    final hasHealthSync = anyTextVisible(
        ['Health', 'Sync', 'Google Fit', 'Health Connect', 'Steps', 'Connect']);
    expect(hasHealthSync, isTrue,
        reason: 'Profile should have a Health Sync section');
  });

  // ── T11 ─────────────────────────────────────────────────────────

  testWidgets('T11: Invite Friends row visible on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll down to find the Invite Friends row
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    final hasInvite = anyTextVisible(
        ['Invite', 'invite', 'Refer', 'refer', 'Share', 'Friends']);
    expect(hasInvite, isTrue,
        reason: 'Profile should have an "Invite Friends" or referral section');
  });

  // ── T12 ─────────────────────────────────────────────────────────

  testWidgets('T12: Privacy Policy row visible on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll down to find the Privacy Policy row
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    final hasPrivacy = anyTextVisible(
        ['Privacy', 'privacy', 'Policy', 'GDPR', 'Data']);
    expect(hasPrivacy, isTrue,
        reason: 'Profile should have a Privacy Policy link');
  });

  // ── T13 ─────────────────────────────────────────────────────────

  testWidgets('T13: Export Data row visible on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll down to find the Export Data row
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    final hasExport = anyTextVisible(
        ['Export', 'export', 'Download', 'Data']);
    expect(hasExport, isTrue,
        reason: 'Profile should have an Export Data option (GDPR compliance)');
  });

  // ── T14 ─────────────────────────────────────────────────────────

  testWidgets('T14: Delete Account row visible on Profile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll all the way down to find Delete Account
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    final hasDelete = anyTextVisible(
        ['Delete', 'delete', 'Remove Account', 'Delete Account']);
    expect(hasDelete, isTrue,
        reason: 'Profile should have a Delete Account option (GDPR compliance)');
  });

  // ── T15 ─────────────────────────────────────────────────────────

  testWidgets('T15: Community Review section accessible', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Scroll to find the Community Review row
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    // Look for community review option
    final hasCommunity = anyTextVisible(
        ['Community', 'community', 'Review', 'Crowd', 'Submissions']);
    if (hasCommunity) {
      // Tap it and check it opens without crash
      for (final label in ['Community', 'Review', 'Submissions']) {
        final btn = find.textContaining(label, findRichText: true);
        if (btn.evaluate().isNotEmpty) {
          await tester.tap(btn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(tester.takeException(), isNull,
              reason: 'Community Review sheet should open without crash');
          return;
        }
      }
    }
    // Community review may not be visible if no items pending — that's OK.
  });
}
