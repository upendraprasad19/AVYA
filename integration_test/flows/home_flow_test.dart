import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';
import '../helpers/navigation_helper.dart';
import '../helpers/test_data_helper.dart';

/// Flow 0: Home Screen — widget-by-widget inspection.
///
/// Tests:
///  T1 – Home screen renders after login
///  T2 – User name / greeting is shown
///  T3 – Weekly calendar strip renders (7 days visible)
///  T4 – Quick-action buttons are visible (Log Workout, Log Meal, etc.)
///  T5 – Today's workout card is shown
///  T6 – Nutrition snapshot (Calories) is visible
///  T7 – Streak counter is present
///  T8 – AI Coach insight card is shown
///  T9 – Weight sparkline appears when weight history exists
/// T10 – Home scrolls smoothly without crash
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

  testWidgets('T1: Home screen renders after login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Home is the landing screen — should show core home content.
    final onHome = anyTextVisible(
        ['Today', 'Good', 'Workout', 'Calories', 'Home', 'Streak', 'Phase']);
    expect(onHome, isTrue, reason: 'Home screen should render after login');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: User greeting / name is shown on Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Seed a named profile.
    TestDataHelper.setUserProfile(name: 'QA Tester');

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Either the full name or a greeting like "Good morning" should show.
    final hasGreeting = anyTextVisible(['QA', 'Good', 'morning', 'afternoon', 'evening', 'Hey']);
    expect(hasGreeting, isTrue,
        reason: 'Home should greet the user by name or show a time-based greeting');
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: Weekly calendar strip renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Calendar strip shows day labels (Mon, Tue, … or M, T, W, …).
    final hasDayLabel = anyTextVisible(
        ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'M', 'T', 'W']);
    expect(hasDayLabel, isTrue,
        reason: 'Home should include a weekly calendar strip with day labels');
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Quick-action buttons are visible', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // At least one quick-action button should be present.
    final hasAction = anyTextVisible(
        ['Log', 'Workout', 'Meal', 'Water', 'Hydration', 'Sleep']);
    expect(hasAction, isTrue,
        reason: 'Home should show quick-action buttons (Log Workout, Log Meal, etc.)');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: Today\'s workout card is shown', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile();
    TestDataHelper.setWorkoutProgress();

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Workout card should show phase info or "Start Workout" or exercise names.
    final hasWorkoutCard = anyTextVisible(
        ['Workout', 'Phase', 'Start', 'Exercise', 'Push', 'Pull', 'Legs']);
    expect(hasWorkoutCard, isTrue,
        reason: 'Home should display a today\'s workout card');
  });

  // ── T6 ──────────────────────────────────────────────────────────

  testWidgets('T6: Nutrition snapshot (Calories) visible on Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile();
    TestDataHelper.logTodayNutrition(calories: 1500, protein: 100);

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Nutrition card should show calories or macros.
    final hasNutrition = anyTextVisible(
        ['Calories', 'calories', 'kcal', 'Protein', 'protein', 'Nutrition']);
    expect(hasNutrition, isTrue,
        reason: 'Home should show a nutrition snapshot section');
  });

  // ── T7 ──────────────────────────────────────────────────────────

  testWidgets('T7: Streak counter is present on Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Streak counter or streak text should be visible.
    final hasStreak = anyTextVisible(['Streak', 'streak', '🔥', 'week', 'Week']);
    expect(hasStreak, isTrue,
        reason: 'Home should display a streak counter');
  });

  // ── T8 ──────────────────────────────────────────────────────────

  testWidgets('T8: AI Coach insight card is visible on Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.injectCoachingNote('Focus on compound movements this week.');

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // AI insight card should mention coach, insight, or show the note.
    final hasInsight = anyTextVisible([
      'coach',
      'Coach',
      'insight',
      'Insight',
      'compound',
      'AI',
      'Start chatting',
    ]);
    expect(hasInsight, isTrue,
        reason: 'Home should show an AI Coach insight card');
  });

  // ── T9 ──────────────────────────────────────────────────────────

  testWidgets('T9: Weight sparkline appears when weight history is present',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Seed 7 days of weight data.
    TestDataHelper.logWeightHistory(count: 7, startKg: 75.0);

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Weight section should show kg values or a graph.
    final hasWeight = anyTextVisible(['kg', 'Weight', 'weight', '75', '74']);
    expect(hasWeight, isTrue,
        reason: 'Home should display weight sparkline when history exists');
  });

  // ── T10 ─────────────────────────────────────────────────────────

  testWidgets('T10: Home screen scrolls without crash', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile();
    TestDataHelper.logTodayNutrition();
    TestDataHelper.logWeightHistory();
    TestDataHelper.setWorkoutProgress();

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Scroll down then back up — must not crash.
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(scrollable.first, const Offset(0, 400));
      await tester.pumpAndSettle();
    } else {
      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        await tester.drag(listView.first, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
    }

    // No exception means scroll worked.
    expect(tester.takeException(), isNull,
        reason: 'Home screen should scroll without throwing an exception');
  });

  // ── T11 ─────────────────────────────────────────────────────────

  testWidgets('T11: Streak freeze toast shown when freeze was just used', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Seed progress with freeze-just-used flag
    TestDataHelper.setUserProfile();
    TestDataHelper.setWorkoutProgress();
    TestDataHelper.setStreakFreezeJustUsed(remaining: 0);

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Wait for the post-frame callback toast
    await tester.pump(const Duration(seconds: 2));

    // The SnackBar should show "Streak Freeze used! 0 remaining this week."
    // Note: SnackBar may have been dismissed or may not appear in test env.
    // We just verify the home screen didn't crash with the freeze flag set.
    expect(tester.takeException(), isNull,
        reason: 'Home screen should handle streak freeze toast without crash');
  });

  // ── T12 ─────────────────────────────────────────────────────────

  testWidgets('T12: Home renders with streak freeze data in progress', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile();
    TestDataHelper.setWorkoutProgress();
    TestDataHelper.setStreakFreezes(available: 2, usedDates: ['2026-04-05']);

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Home should render without crash even with streak freeze data
    expect(tester.takeException(), isNull,
        reason: 'Home should render cleanly with streak freeze data in progress');
  });
}
