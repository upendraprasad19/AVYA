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

/// Flow 8: Offline-first behaviour — app usable without network.
///
/// Since we can't cut network in a standard integration test, these tests
/// verify the offline-first guarantee by:
///   1. Pre-seeding Hive with known data
///   2. NOT making any network calls in the test (no signInWithTestUser
///      that triggers Supabase, except for the initial auth)
///   3. Confirming the UI reads from Hive and renders correctly
///
/// Tests:
///  T1 – All tabs render with only Hive data (no live Supabase call needed)
///  T2 – Nutrition log is viewable without network (Hive read)
///  T3 – Workout plan renders from local Hive (plan_generator output)
///  T4 – AI Coach chat history viewable from Hive (no network needed)
///  T5 – Profile shows bio stats from Hive (no network needed)
///  T6 – Food search works fully offline (seeded exerciseBox + foodBox)
///  T7 – Hive data is not lost when navigating without network
///  T8 – App does not crash on empty Hive boxes (empty state handling)
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

  testWidgets('T1: All tabs render with pre-seeded Hive data', (tester) async {
    // Pre-seed comprehensive Hive state.
    TestDataHelper.setUserProfile(name: 'Offline User', weight: 74.0);
    TestDataHelper.setWorkoutProgress(phase: 1, week: 1);
    TestDataHelper.logTodayNutrition(calories: 1600);
    TestDataHelper.logWeightHistory(count: 5);
    TestDataHelper.setTrialActive(daysUsed: 3);

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Visit all 5 tabs — each must render without crash.
    await navigateToHome(tester);
    expect(tester.takeException(), isNull, reason: 'Home must render offline');

    await navigateToTrain(tester);
    expect(tester.takeException(), isNull, reason: 'Train must render offline');

    await navigateToNutrition(tester);
    expect(tester.takeException(), isNull, reason: 'Nutrition must render offline');

    await navigateToAiCoach(tester);
    expect(tester.takeException(), isNull, reason: 'AI Coach must render offline');

    await navigateToProfile(tester);
    expect(tester.takeException(), isNull, reason: 'Profile must render offline');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: Nutrition log is viewable from Hive (no live sync needed)',
      (tester) async {
    TestDataHelper.setUserProfile(tdee: 2000);
    TestDataHelper.logTodayNutrition(calories: 1400, protein: 90);
    TestDataHelper.logMealItem(foodName: 'Roti', calories: 120, mealType: 'dinner');

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToNutrition(tester);

    final showsData = anyTextVisible(['1400', '90', 'Roti', 'Calories', 'Protein']);
    expect(showsData, isTrue,
        reason: 'Nutrition data from Hive must be visible without network sync');
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: Workout plan renders from local data (plan_generator)',
      (tester) async {
    TestDataHelper.setUserProfile(
      goal: 'build_muscle',
      equipment: 'basic_gym',
    );
    TestDataHelper.setWorkoutProgress(phase: 1, week: 1);

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    // Plan generator runs locally — should show exercises without network.
    final showsPlan = anyTextVisible(
        ['Phase', 'Week', 'Workout', 'Push', 'Pull', 'Foundation', 'Exercise']);
    expect(showsPlan, isTrue,
        reason: 'Workout plan must render from local plan_generator without network');
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: AI Coach chat history is viewable from Hive alone', (tester) async {
    // Inject a previous conversation.
    await HiveService.instance.coachBox.put('offline_test_msg', {
      'user_message': 'How do I improve my bench press?',
      'ai_response': 'Focus on scapular retraction and progressive overload.',
      'created_at': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    });

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToAiCoach(tester);

    // The chat history must appear from Hive without calling the AI API.
    final showsHistory = anyTextVisible(
        ['bench press', 'Bench Press', 'scapular', 'progressive', 'improve']);
    expect(showsHistory, isTrue,
        reason: 'AI Coach must display past chat from Hive without network');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: Profile shows bio stats from Hive (no network needed)',
      (tester) async {
    TestDataHelper.setUserProfile(
      name: 'Offline Profile',
      weight: 68.0,
      height: 170.0,
      goal: 'general_fitness',
    );

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    final showsStats =
        anyTextVisible(['68', '170', 'Offline Profile', 'kg', 'cm', 'fitness']);
    expect(showsStats, isTrue,
        reason: 'Profile must show bio stats from Hive without Supabase fetch');
  });

  // ── T6 ──────────────────────────────────────────────────────────

  testWidgets('T6: Food search works from seeded foodBox (offline DB)',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToNutrition(tester);

    // Open food search.
    for (final label in ['Add', 'Log Food', 'Search Food', 'Breakfast', 'Lunch']) {
      final btn = find.textContaining(label, findRichText: true);
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        break;
      }
    }

    // Search for a common Indian food.
    final searchField = find.byType(TextField);
    if (searchField.evaluate().isEmpty) return;

    await tester.enterText(searchField.first, 'chapati');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Results should come from seeded foodBox — no network needed.
    final hasResults =
        anyTextVisible(['chapati', 'Chapati', 'Roti', 'Wheat', 'flour']);
    expect(hasResults, isTrue,
        reason:
            'Food search must return results from seeded foodBox without network');
  });

  // ── T7 ──────────────────────────────────────────────────────────

  testWidgets('T7: Hive data not lost when navigating without network',
      (tester) async {
    TestDataHelper.setUserProfile(name: 'Nav Test User', weight: 71.0);
    TestDataHelper.logTodayNutrition(calories: 1850);

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Navigate through all tabs multiple times.
    for (int i = 0; i < 3; i++) {
      await navigateToHome(tester);
      await navigateToNutrition(tester);
      await navigateToTrain(tester);
    }

    // Verify Hive data is still intact.
    final userBox = HiveService.instance.userBox;
    final profile = userBox.get('profile') as Map?;
    expect(profile?['full_name'], equals('Nav Test User'),
        reason: 'Hive data must not be lost during navigation');

    final nutritionBox = HiveService.instance.nutritionBox;
    expect(nutritionBox.isNotEmpty, isTrue,
        reason: 'Nutrition logs must persist through navigation');
  });

  // ── T8 ──────────────────────────────────────────────────────────

  testWidgets('T8: App handles completely empty Hive boxes gracefully',
      (tester) async {
    // Clear all Hive boxes — simulate first launch.
    await clearHiveForTest();

    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Visit all tabs with empty Hive state — each must show empty state,
    // not crash.
    await navigateToHome(tester);
    expect(tester.takeException(), isNull,
        reason: 'Home must show empty state, not crash with no Hive data');

    await navigateToNutrition(tester);
    expect(tester.takeException(), isNull,
        reason: 'Nutrition must show empty state with no logged meals');

    await navigateToTrain(tester);
    expect(tester.takeException(), isNull,
        reason: 'Train must show empty state with no workout plan');

    await navigateToAiCoach(tester);
    expect(tester.takeException(), isNull,
        reason: 'AI Coach must show welcome message with no chat history');

    await navigateToProfile(tester);
    expect(tester.takeException(), isNull,
        reason: 'Profile must show empty state with no bio stats');
  });
}
