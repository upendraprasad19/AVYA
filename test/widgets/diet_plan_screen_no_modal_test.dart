// test/widgets/diet_plan_screen_no_modal_test.dart
//
// Widget test for DietPlanScreen ensuring the saved-plan-found modal is not shown.
// Obs 8: when a saved diet plan exists, it should be rendered immediately without
// a blocking dialog. The AppBar's Regenerate and Save icons already provide
// user actions.
//
// ⚠ TWO testWidgets, ORDER LOAD-BEARING — same class as
// test/contracts/exercise_plate_widgets_test.dart's header, read that first if
// this file ever needs touching again. The second test below mocks the
// path_provider platform channel so Hive can open a box. google_fonts SAVES a
// fetched font through that same channel (`_httpFetchFontAndSaveToDevice`) —
// with the REAL (unmocked) channel, google_fonts can't resolve a cache
// directory and degrades to a fallback face SILENTLY, which is the ordinary,
// no-network-attempt behaviour every other widget test in this repo relies on.
// Once path_provider is mocked, google_fonts gets far enough to attempt a live
// HTTPS fetch instead, which the test binding's HttpClient override always
// fails — surfacing as an UNCAUGHT exception the first time any AppTypography
// style renders, instead of the ordinary silent fallback.
//
// The first test below renders every font family/weight DietPlanScreen uses,
// with NO mock installed, so google_fonts hits the graceful/silent path and
// CACHES the fallback per family+weight before the mock goes up. Priming
// inside the SAME test as the mock does NOT work (tried, still red — the
// warm-up's internal font-loading Future doesn't get real time to settle
// before the very next synchronous line flips path_provider); it must be a
// separate test so its own pumpAndSettle genuinely drains it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('diet_plan_screen_no_modal_');
    // ⚠ path_provider is deliberately NOT mocked here, and Hive is
    // deliberately NOT opened here — both happen only inside the SECOND
    // test, after the first test has primed google_fonts. See file header.
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
  });

  // ---- FIRST, and Hive-free / path_provider-free by design. ----
  testWidgets(
      'primes google_fonts fallbacks before path_provider is ever mocked',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Text('warm', style: GoogleFonts.getFont('DM Sans')),
        Text('warm',
            style: GoogleFonts.getFont('DM Sans', fontWeight: FontWeight.w600)),
        Text('warm',
            style: GoogleFonts.getFont('JetBrains Mono',
                fontWeight: FontWeight.w600)),
        Text('warm', style: GoogleFonts.getFont('Fraunces')),
      ]),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('renders saved plan immediately with no dialog',
      (WidgetTester tester) async {
    const testUserId = 'eeee5555-eeee-eeee-eeee-eeeeeeeeeeee';

    // ⚠ Real disk I/O (Hive init/box opens, HiveUserSession, and the real
    // Hive write via UserRepository.saveDietPlan further below) must run
    // through tester.runAsync() — a testWidgets body runs in a fake-async
    // zone where a directly-awaited real I/O Future never completes and the
    // harness hangs until it gives up (root CLAUDE.md §4.9's documented
    // "await-ing real disk I/O inside a testWidgets body" pitfall class;
    // see test/contracts/exercise_plate_widgets_test.dart for the same fix
    // applied to the same underlying Hive-open pattern).
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await tester.runAsync(() async {
      Hive.init(tempDir.path);
      await Hive.openBox(HiveService.exerciseBoxName);
      await Hive.openBox(HiveService.foodBoxName);
      await Hive.openBox(HiveService.syncBoxName);
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.debugMarkInitializedForTests();
      GuardedBox.testBypassOwnership = true;
      await HiveUserSession.openForUser(testUserId);
    });

    // Seed Hive with a saved diet plan via UserRepository
    final savedPlan = <String, dynamic>{
      'id': 'diet_plan_1234567890',
      'created_at': DateTime(2026, 9, 20).toIso8601String(),
      'meals': [
        {
          'name': 'Breakfast',
          'items': [
            {
              'food_id': 'oats_001',
              'name': 'Oats',
              'serving_desc': '50g',
              'serving_g': 50.0,
              'calories': 180,
              'protein': 6,
              'carbs': 27,
              'fat': 5,
              'category': 'grains'
            }
          ],
          'targetCalories': 400,
          'targetProtein': 15,
        },
        {
          'name': 'Lunch',
          'items': [
            {
              'food_id': 'rice_001',
              'name': 'Brown rice',
              'serving_desc': '150g',
              'serving_g': 150.0,
              'calories': 400,
              'protein': 8,
              'carbs': 85,
              'fat': 3,
              'category': 'grains'
            }
          ],
          'targetCalories': 600,
          'targetProtein': 20,
        }
      ],
    };
    await tester.runAsync(() async {
      await UserRepository.instance.saveDietPlan(savedPlan);
    });

    // Render the DietPlanScreen
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: DietPlanScreen())),
    );
    await tester.pumpAndSettle();

    // Verify no AlertDialog is shown (obs 8 — the modal must not appear)
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'obs 8 — the saved-plan-found dialog must not appear');
    expect(find.text('Saved Diet Plan Found'), findsNothing,
        reason: 'the modal title must not be visible');

    // Verify the saved plan's actual content loaded (mutation proof:
    // a no-op _loadSavedPlan would still render the icons but not the meals)
    expect(find.text('Oats'), findsOneWidget,
        reason: 'saved-plan content (breakfast Oats) must be rendered');
    expect(find.text('Brown rice'), findsOneWidget,
        reason: 'saved-plan content (lunch Brown rice) must be rendered');

    // Verify the toolbar icons are present (these already give users
    // the actions the old dialog offered). _loadSavedPlan sets `_saved =
    // true` (line 328) because a plan loaded from storage IS already
    // saved — so the Save action correctly renders as Icons.check_circle,
    // not Icons.save_outlined (which only shows before the first save).
    expect(find.byIcon(Icons.refresh), findsOneWidget,
        reason: 'toolbar Regenerate icon must be present');
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason:
            'toolbar Save icon must reflect the already-saved state for a loaded plan');
  });
}
