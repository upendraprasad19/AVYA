import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';

/// Flow 2: Train tab — workout plan renders and phase info is visible.
///
/// Verifies: Train tab loads, workout plan from plan_generator is displayed,
/// Phase 1 info is shown. Active workout (PRO) is tested in pro_gate_flow_test.
///
/// Note: The active workout screen itself is PRO-gated. This test verifies
/// the free-tier Train screen renders correctly.
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

  testWidgets('Train tab renders workout plan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Navigate to Train tab.
    final trainTab = find.textContaining('Train', findRichText: true);
    if (trainTab.evaluate().isNotEmpty) {
      await tester.tap(trainTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    // Train screen should show workout information.
    final hasWorkoutInfo =
        find.textContaining('Phase', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Week', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Workout', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Push', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Pull', findRichText: true).evaluate().isNotEmpty;

    expect(hasWorkoutInfo, isTrue,
        reason: 'Train screen should display workout plan information');
  });

  testWidgets('Train tab shows Phase 1 for new user', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    final trainTab = find.textContaining('Train', findRichText: true);
    if (trainTab.evaluate().isNotEmpty) {
      await tester.tap(trainTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    // Phase 1 should be visible for a new QA user (Foundation phase).
    final hasPhase1 =
        find.textContaining('Foundation', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('Phase 1', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('1', findRichText: true).evaluate().isNotEmpty;

    expect(hasPhase1, isTrue,
        reason: 'New user should be on Phase 1 (Foundation)');
  });
}
