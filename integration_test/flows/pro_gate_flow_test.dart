import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/app.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/auth_helper.dart';

/// Flow 5: PRO gate → PaywallSheet appears for a free user.
///
/// Verifies that free users see the paywall (not the feature) when they tap
/// a PRO-locked feature. This is the most critical business rule — a bug here
/// means free users can access PRO features.
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

  testWidgets('Free user tapping PRO feature sees PaywallSheet', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    // Navigate to Train tab.
    final trainTab = find.textContaining('Train', findRichText: true);
    if (trainTab.evaluate().isNotEmpty) {
      await tester.tap(trainTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // Try to start an active workout (PRO feature: active_workout_mode).
    final startWorkout = find.textContaining('Start', findRichText: true);
    if (startWorkout.evaluate().isNotEmpty) {
      await tester.tap(startWorkout.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // PaywallSheet should appear (has "Upgrade" or "PRO" text).
    final paywallVisible =
        find.textContaining('Upgrade', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('PRO', findRichText: true).evaluate().isNotEmpty ||
        find.textContaining('₹349', findRichText: true).evaluate().isNotEmpty;

    expect(paywallVisible, isTrue,
        reason: 'PaywallSheet must appear when a free user taps a PRO feature');
  });

  testWidgets('PaywallSheet can be dismissed', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await signInWithTestUser(tester);

    final trainTab = find.textContaining('Train', findRichText: true);
    if (trainTab.evaluate().isNotEmpty) {
      await tester.tap(trainTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    final startWorkout = find.textContaining('Start', findRichText: true);
    if (startWorkout.evaluate().isNotEmpty) {
      await tester.tap(startWorkout.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // Dismiss paywall by tapping close / back.
    final closeButton = find.byIcon(Icons.close);
    if (closeButton.evaluate().isNotEmpty) {
      await tester.tap(closeButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    } else {
      // Drag to dismiss bottom sheet.
      await tester.drag(
        find.byType(DraggableScrollableSheet).first,
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
    }

    // Should be back on Train screen (paywall gone).
    expect(find.textContaining('₹349', findRichText: true), findsNothing);
  });
}
