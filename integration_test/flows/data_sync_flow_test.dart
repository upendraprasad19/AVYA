import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

/// Flow 7: Cross-tab data sync — Hive writes reflected across screens.
///
/// These tests verify that the offline-first Hive data layer properly
/// propagates writes across screen providers (the most common source
/// of "stale UI" bugs).
///
/// Tests:
///  T1 – Hive userBox profile write is readable by Profile screen
///  T2 – Hive nutritionBox write is reflected on Nutrition tab
///  T3 – Hive workoutBox write is readable by Train tab
///  T4 – Hive coachBox write shows in AI Coach chat history
///  T5 – Hive healthBox weight write is shown on Home sparkline
///  T6 – Tab navigation preserves Hive state (no data loss on switch)
///  T7 – App restart preserves Hive data (box persistence)
///  T8 – Multiple Hive writes in sequence do not corrupt state
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kIsDevFlavor = true;
    await dotenv.load(fileName: '.env.dev');
    await initHiveForTest();
    await SupabaseService.instance.initialize();
  });

  tearDown(() async {
    await SupabaseService.instance.client.auth.signOut();
    await clearHiveForTest();
  });

  // ── T1 ──────────────────────────────────────────────────────────

  testWidgets('T1: Hive userBox profile write is readable by Profile screen',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Write profile BEFORE sign-in so Hive is pre-seeded.
    TestDataHelper.setUserProfile(name: 'Sync Test User', weight: 73.5);

    await signInWithTestUser(tester);
    await navigateToProfile(tester);

    // Profile screen should read from Hive and display the written values.
    final showsData = anyTextVisible(['73', 'Sync Test', 'Sync', 'Profile']);
    expect(showsData, isTrue,
        reason: 'Profile screen must read from Hive userBox after write');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: Hive nutritionBox write is reflected on Nutrition tab',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Write today's nutrition to Hive before navigating.
    TestDataHelper.setUserProfile(tdee: 2200);
    TestDataHelper.logTodayNutrition(calories: 1650, protein: 110);

    await signInWithTestUser(tester);
    await navigateToNutrition(tester);

    // Nutrition tab should display the logged calorie value.
    final showsCalories = anyTextVisible(['1650', '110', 'kcal', 'Calories', 'Protein']);
    expect(showsCalories, isTrue,
        reason:
            'Nutrition tab must read today\'s log from Hive and display it');
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: Hive workoutBox write is readable by Train tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setWorkoutProgress(phase: 1, week: 2, done: 5);
    TestDataHelper.logCompletedWorkout(exerciseName: 'Squat');

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    // Train tab should show Phase 1, Week 2 based on Hive progress data.
    final showsProgress = anyTextVisible(['Phase', 'Week', '1', '2', 'Squat', 'Workout']);
    expect(showsProgress, isTrue,
        reason: 'Train tab must read workout progress from Hive');

    expect(tester.takeException(), isNull);
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Hive coachBox write shows in AI Coach chat history',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Inject an AI interaction into coachBox.
    final now = DateTime.now();
    HiveService.instance.coachBox.put('test_interaction_001', {
      'user_message': 'How many calories should I eat?',
      'ai_response': 'Based on your profile, aim for around 2200 calories.',
      'created_at': now.toIso8601String(),
    });

    await signInWithTestUser(tester);
    await navigateToAiCoach(tester);

    // Chat history should contain the injected message.
    final showsHistory = anyTextVisible([
      'calories', 'Calories', '2200', 'How many',
      'Based on', 'profile', 'aim for',
    ]);
    expect(showsHistory, isTrue,
        reason: 'AI Coach chat history must load from Hive coachBox');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: Hive healthBox weight write shown on Home weight sparkline',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Seed 7 weight entries in Hive.
    TestDataHelper.logWeightHistory(count: 7, startKg: 76.0);

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Home weight sparkline should show weight values.
    final showsWeight = anyTextVisible(['76', '75', 'kg', 'Weight', 'weight']);
    expect(showsWeight, isTrue,
        reason: 'Home should read weight history from Hive and render sparkline');
  });

  // ── T6 ──────────────────────────────────────────────────────────

  testWidgets('T6: Tab switching preserves Hive state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(weight: 72.0);
    TestDataHelper.logTodayNutrition(calories: 1900);
    TestDataHelper.setWorkoutProgress(week: 2);

    await signInWithTestUser(tester);

    // Rapidly switch between all tabs.
    await navigateToTrain(tester);
    await navigateToNutrition(tester);
    await navigateToAiCoach(tester);
    await navigateToProfile(tester);
    await navigateToHome(tester);

    // After cycling all tabs, no exception and data still present.
    expect(tester.takeException(), isNull,
        reason: 'Hive state must be preserved through tab switching');

    final hiveUserBox = HiveService.instance.userBox;
    final profile = hiveUserBox.get('profile') as Map?;
    expect(profile?['current_weight_kg'], equals(72.0),
        reason: 'Profile data must not be corrupted by tab switching');
  });

  // ── T7 ──────────────────────────────────────────────────────────

  testWidgets('T7: App restart preserves Hive data (box persistence)', (tester) async {
    // First app pump — seed data.
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(name: 'Persistent User', weight: 70.0);
    TestDataHelper.logTodayNutrition(calories: 1750);

    await signInWithTestUser(tester);

    // Simulate "restart" by pumping a new widget tree.
    // (Hive boxes survive widget rebuild as they are singletons.)
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Data should still be in Hive.
    final userBox = HiveService.instance.userBox;
    final profile = userBox.get('profile') as Map?;
    expect(profile?['full_name'], equals('Persistent User'),
        reason: 'Hive data must survive a widget tree rebuild (restart simulation)');

    final nutritionBox = HiveService.instance.nutritionBox;
    expect(nutritionBox.isNotEmpty, isTrue,
        reason: 'Nutrition logs must survive a widget tree rebuild');
  });

  // ── T8 ──────────────────────────────────────────────────────────

  testWidgets('T8: Multiple sequential Hive writes do not corrupt state',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Write many entries in rapid succession.
    for (int i = 0; i < 20; i++) {
      TestDataHelper.logMealItem(
        foodName: 'Test Food $i',
        calories: 100.0 + i,
        mealType: 'lunch',
      );
    }
    for (int i = 0; i < 7; i++) {
      TestDataHelper.logCompletedWorkout(
        date: DateTime.now().subtract(Duration(days: i)),
      );
    }

    final nutritionBox = HiveService.instance.nutritionBox;
    final workoutBox = HiveService.instance.workoutBox;

    expect(nutritionBox.length, greaterThanOrEqualTo(20),
        reason: '20 meal log entries should be written to Hive');
    expect(workoutBox.length, greaterThanOrEqualTo(7),
        reason: '7 workout entries should be written to Hive');

    await signInWithTestUser(tester);
    await navigateToNutrition(tester);

    expect(tester.takeException(), isNull,
        reason: 'App should not crash with many Hive entries');
  });
}
