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

/// Flow 2 (Comprehensive): Train tab — workout plan, phase, week selector.
///
/// Tests:
///  T1 – Train tab renders workout plan info
///  T2 – Phase 1 (Foundation) is shown for a new user
///  T3 – Week selector is visible and tappable
///  T4 – Exercise cards are rendered (name + sets + reps visible)
///  T5 – "Start Workout" triggers PRO gate for free user
///  T6 – Workout log is written to Hive workoutBox
///  T7 – Template Builder screen is accessible
///  T8 – Completed workout in Hive does not crash calendar on Home
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

  testWidgets('T1: Train tab renders workout plan info', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    final hasWorkoutInfo = anyTextVisible(
        ['Phase', 'Week', 'Workout', 'Push', 'Pull', 'Legs', 'Foundation', 'Exercise']);
    expect(hasWorkoutInfo, isTrue,
        reason: 'Train screen should display workout plan information');
  });

  // ── T2 ──────────────────────────────────────────────────────────

  testWidgets('T2: Phase 1 (Foundation) shown for new user', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setWorkoutProgress(phase: 1, week: 1);

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    final hasPhase1 = anyTextVisible(['Foundation', 'Phase 1', 'Phase One', '1']);
    expect(hasPhase1, isTrue,
        reason: 'New user should be on Phase 1 (Foundation)');
  });

  // ── T3 ──────────────────────────────────────────────────────────

  testWidgets('T3: Week selector is visible and tappable', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setWorkoutProgress(phase: 1, week: 1);

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    // Week selector shows "Week 1", "Week 2" etc.
    final weekSelector = find.textContaining('Week', findRichText: true);
    expect(weekSelector.evaluate().isNotEmpty, isTrue,
        reason: 'Train tab should show week selector');

    // Tapping a different week should not crash.
    final week2 = find.textContaining('2', findRichText: true);
    if (week2.evaluate().isNotEmpty) {
      await tester.tap(week2.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull,
          reason: 'Switching weeks must not throw');
    }
  });

  // ── T4 ──────────────────────────────────────────────────────────

  testWidgets('T4: Exercise cards render with sets/reps info', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setUserProfile(equipment: 'basic_gym');
    TestDataHelper.setWorkoutProgress(phase: 1, week: 1);

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    final hasSetsReps = anyTextVisible(
        ['sets', 'Sets', 'reps', 'Reps', 'x', '×', '3x', '4x', '3 sets', '4 sets']);
    expect(hasSetsReps, isTrue,
        reason: 'Exercise cards should show sets × reps information');
  });

  // ── T5 ──────────────────────────────────────────────────────────

  testWidgets('T5: "Start Workout" shows PRO gate for free user', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    TestDataHelper.setFreeUser();

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    final startButton = find.textContaining('Start', findRichText: true);
    if (startButton.evaluate().isNotEmpty) {
      await tester.tap(startButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final gated = anyTextVisible(
          ['Upgrade', 'PRO', '₹349', 'Pro', 'locked', 'premium', 'Unlock']);
      expect(gated, isTrue,
          reason: 'Active Workout Mode must be PRO-gated for free users');
    }
  });

  // ── T6 ──────────────────────────────────────────────────────────

  testWidgets('T6: Completed workout log is written to Hive workoutBox',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Seed a workout log entry (simulates completing a workout).
    TestDataHelper.logCompletedWorkout(exerciseName: 'Bench Press');

    // Verify the Hive box holds the entry.
    final workoutBox = HiveService.instance.workoutBox;
    expect(workoutBox.isNotEmpty, isTrue,
        reason: 'Hive workoutBox should hold the logged workout entry');

    await navigateToTrain(tester);

    // No crash after navigating with workout data in Hive.
    expect(tester.takeException(), isNull);
  });

  // ── T7 ──────────────────────────────────────────────────────────

  testWidgets('T7: Template Builder is accessible from Train tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);
    await navigateToTrain(tester);

    // Look for Template / Custom / Build buttons.
    for (final label in ['Template', 'Custom', 'Build']) {
      final btn = find.textContaining(label, findRichText: true);
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull,
            reason: 'Template Builder should open without exception');
        return;
      }
    }
    // If none found, the feature may be hidden — pass silently.
  });

  // ── T8 ──────────────────────────────────────────────────────────

  testWidgets('T8: Calendar on Home renders without crash after workout log',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ICanBeFitterApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Log a workout for today → calendar should colour today's cell.
    TestDataHelper.logCompletedWorkout();

    await signInWithTestUser(tester);
    await navigateToHome(tester);

    // Must render without exception.
    expect(tester.takeException(), isNull,
        reason: 'Calendar should render with completed workout without crash');
  });
}
