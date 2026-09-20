// test/widgets/log_food_sheet_search_respects_locked_slot_test.dart
//
// Task 7 (food-logging-observations, 2026-09-20): `search_mode_body.dart`
// carried its own independent, drifted inline time-of-day meal-slot
// inference (`_mealTypeForNow`) and never read `mealTypeProvider` at all —
// so opening "LOG TO LUNCH"/"LOG TO DINNER" -> Search tab could silently
// log to whatever time-of-day says instead of the locked slot the user
// explicitly tapped. This test forces `mealTypeProvider` to a value
// computed to DISAGREE with the real wall-clock inference at whatever time
// the test happens to run (round-2 plan review, 2026-09-20 — an earlier
// version hardcoded 'dinner', which only disagreed with the pre-fix
// inference outside the 18:00-22:00 window, so discrimination depended on
// CI's run time), so it fails deterministically pre-fix and passes
// deterministically post-fix regardless of wall-clock time.
//
// ⚠ TWO testWidgets, ORDER LOAD-BEARING — same class as
// test/widgets/diet_plan_screen_no_modal_test.dart's header / root
// CLAUDE.md §4.9's "google_fonts live-fetch" pitfall row. The second test
// mocks path_provider so Hive can open real boxes; google_fonts SAVES a
// fetched font through that same channel, so once path_provider is mocked
// google_fonts attempts a live HTTPS fetch instead of gracefully
// degrading, surfacing as an uncaught exception the first time any
// AppTypography style renders. The first test below renders every font
// family/weight this widget tree uses, with NO mock installed, so
// google_fonts hits the silent-fallback path and caches it BEFORE the
// mock goes up. Must be a separate, earlier test — priming inside the
// same test does not work (the warm-up Future doesn't get real time to
// settle before the very next synchronous line flips path_provider).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/meal_slot_inference.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_sheet.dart';
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
  const testUserId = 'ffff6666-ffff-ffff-ffff-ffffffffffff';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('log_food_search_locked_slot_');
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
        Text('w', style: GoogleFonts.getFont('DM Sans')),
        Text('w',
            style:
                GoogleFonts.getFont('DM Sans', fontWeight: FontWeight.w600)),
        Text('w',
            style: GoogleFonts.getFont('JetBrains Mono',
                fontWeight: FontWeight.w600)),
      ]),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('Search tab logs to the locked slot, not time-of-day inference',
      (tester) async {
    // Real Hive/path_provider I/O must run through tester.runAsync() — a
    // testWidgets body runs in a fake-async zone where a directly-awaited
    // real I/O Future never completes (root CLAUDE.md §4.9's documented
    // "await-ing real disk I/O inside a testWidgets body" pitfall class).
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await tester.runAsync(() async {
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await HiveService.instance.init();
      await HiveUserSession.openForUser(testUserId);

      // Seed one searchable food item — mirrors the shape FoodRepository
      // reads from the bundled food_database box (name + per-100g macros +
      // standard-serving fields), matching the fixture shape used by
      // NutritionWriteService's own logMeal tests
      // (test/nutrition_write_service/logMeal_creates_logs_and_items_atomically_test.dart).
      await HiveService.instance.foodBox.put('oats_test_001', {
        'id': 'oats_test_001',
        'name': 'Oats',
        'standard_serving_g': 40.0,
        'standard_serving_desc': '40g',
        'calories_std': 150,
        'calories_per_100g': 375.0,
        'protein_per_100g': 13.0,
        'carbs_per_100g': 68.0,
        'fat_per_100g': 7.0,
        'fiber_per_100g': 10.0,
        'category': 'grains',
      });
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Pick a locked slot guaranteed to disagree with whatever the real
    // wall-clock inference returns RIGHT NOW, so the lock — not the
    // clock — is what decides the outcome, unconditionally.
    final wallClockSlot = inferMealSlot(DateTime.now());
    final lockedSlot = wallClockSlot == 'dinner' ? 'lunch' : 'dinner';
    container.read(mealTypeProvider.notifier).select(lockedSlot);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LogFoodSheet(
                initial: LogFoodMode.search, lockedSlot: lockedSlot),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(mealTypeProvider), lockedSlot);

    // Type a query, tap the first result, then assert the written Hive
    // row's meal_type is the locked slot regardless of the current
    // wall-clock time.
    await tester.enterText(find.byType(TextField), 'oat');
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsWidgets,
        reason: 'seeded "Oats" food item must appear in the search results');

    // The tap's onTap handler awaits a real Hive write
    // (NutritionWriteService.logMeal -> nutritionBox.put), which — like
    // the direct-await case above — never completes if driven only by
    // pumpAndSettle() inside the fake-async test zone. Escape via
    // runAsync for the tap itself, matching the LOG WORKOUT double-tap
    // pattern in test/widgets/compass_redesign_test.dart.
    await tester.runAsync(() async {
      await tester.tap(find.byType(ListTile).first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final box = HiveService.instance.nutritionBox;
    final written = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('nlog_'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
    expect(written, isNotEmpty,
        reason: 'tapping the search result must write an nlog_* row');
    expect(written.first['meal_type'], lockedSlot,
        reason: 'the locked slot must win over time-of-day inference, '
            'which pre-fix logged wherever _mealTypeForNow() said instead');
  });

  testWidgets(
      'Snack slot CTA (the singular "snack" TodaysMealsCard emits) writes '
      'meal_type "snacks", not a silently-dropped write (round-2 plan '
      'review, 2026-09-20)', (tester) async {
    // Comes AFTER the font-priming test above, so GoogleFonts fallbacks are
    // already cached process-wide — no separate priming needed here.
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await tester.runAsync(() async {
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await HiveService.instance.init();
      await HiveUserSession.openForUser(testUserId);
      // The nutritionBox is NOT cleared between tests in this file (both
      // tests share the same tempDir + testUserId) — without this, the
      // sibling test's own leftover nlog_* row would still be present and
      // `written.first` below could pick IT UP instead of this test's
      // fresh write, since Hive key iteration order is insertion order.
      await HiveService.instance.nutritionBox.clear();
      await HiveService.instance.foodBox.put('oats_test_002', {
        'id': 'oats_test_002',
        'name': 'Oats',
        'standard_serving_g': 40.0,
        'standard_serving_desc': '40g',
        'calories_std': 150,
        'calories_per_100g': 375.0,
        'protein_per_100g': 13.0,
        'carbs_per_100g': 68.0,
        'fat_per_100g': 7.0,
        'fiber_per_100g': 10.0,
        'category': 'grains',
      });
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 'snack' (singular) is exactly the value TodaysMealsCard's
    // onLogSlot callback passes for its Snack CTA — see
    // TodaysMealsCard._slotOrder. Pre-fix, MealTypeNotifier.select stored
    // this verbatim and NutritionWriteService.isAllowedMealType (which
    // only accepts the plural 'snacks') rejected every write with no
    // user-visible error. Selected directly here (mirroring the sibling
    // test above) rather than relying solely on LogFoodSheet's own
    // addPostFrameCallback timing under pumpAndSettle — the write path
    // this test exists to pin is select()'s normalization itself.
    container.read(mealTypeProvider.notifier).select('snack');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: LogFoodSheet(initial: LogFoodMode.search, lockedSlot: 'snack'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The provider must already read the NORMALIZED value.
    expect(container.read(mealTypeProvider), 'snacks');

    await tester.enterText(find.byType(TextField), 'oat');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.byType(ListTile).first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final box = HiveService.instance.nutritionBox;
    final written = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('nlog_'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
    expect(written, isNotEmpty,
        reason: 'the Snack slot write must actually land — pre-fix, '
            'isAllowedMealType(\'snack\') was false and moveMealLog\'s '
            'sibling logMeal path returned WriteResult.fail silently');
    expect(written.first['meal_type'], 'snacks');
  });
}
