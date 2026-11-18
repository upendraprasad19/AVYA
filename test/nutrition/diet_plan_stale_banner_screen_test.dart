// test/nutrition/diet_plan_stale_banner_screen_test.dart
//
// goal-change-targets B4, on the real Diet chart screen with Hive and the shipped food asset: a
// saved plan stamped with the targets it was built for shows a banner when the targets move,
// never regenerates by itself, and a Save never launders the stamp.
// Harness copied from diet_plan_chart_v3_screen_test.dart.
//
// ⚠ The font warm-up test must stay FIRST (the Hive group mocks
// path_provider; see test/widgets/diet_plan_screen_no_modal_test.dart).
// A tap whose handler writes Hive runs in tester.runAsync (_tapReal), else
// tearDown's HiveUserSession.closeAll() hangs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_stale_targets.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

// Energy-consistent: 4 x 150 + 4 x 270 + 9 x 80 = 2400 kcal. Keto carb target
// 30 g (ceiling 45 g), Low carb 120 g (ceiling 180 g).
const _pack = <String, dynamic>{
  'full_name': 'T',
  'daily_calories': 2400,
  'protein_grams': 150,
  'carb_grams': 270,
  'carbs_grams': 270,
  'fat_grams': 80,
};

/// A fixed plan seed (not the day's): the tests do not depend on the day they
/// run. `--dart-define=DIET_TEST_SEED=<n>` tries another one.
const int _kPlanSeed = int.fromEnvironment('DIET_TEST_SEED', defaultValue: 4242);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapReal(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await _settle(tester);
}

Map<String, dynamic>? _savedPlan() => UserRepository.instance.getSavedDietPlan();
String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data ?? '';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.mono),
          Text('f', style: AppTypography.h1),
          Text('t', style: AppTypography.titleS),
          Text('s', style: AppTypography.bodyS),
          Text('g', style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
          Text('h', style: AppTypography.body.copyWith(fontWeight: FontWeight.w400)),
          Text('j', style: AppTypography.body.copyWith(fontWeight: FontWeight.w800)),
          Text('k', style: AppTypography.body.copyWith(fontWeight: FontWeight.w900)),
          Text('i', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700)),
          Text('l', style: AppTypography.monoXs.copyWith(fontWeight: FontWeight.w700)),
          Text('m', style: AppTypography.monoXs.copyWith(fontWeight: FontWeight.w400)),
          Text('n', style: AppTypography.mono.copyWith(fontWeight: FontWeight.w600)),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('with Hive', () {
    late Directory dir;
    late List<Map<String, dynamic>> rows;

    setUpAll(() {
      rows = (jsonDecode(File('assets/data/food_database.json')
              .readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
    });

    setUp(() async {
      dir = await setUpHiveForTests();
      DietStrategyFlags.debugEnabledOverride = true;
      debugDietPlanGenerations = 0;
      debugDietPlanSeedOverride = _kPlanSeed;
      debugResetDietPlanMismatchNotices();
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      UserProfileNotifier.debugFoodTypeEffects = FoodTypeWriteEffects(
        currentUserId: () => kTestUserId,
        pushSnapshot: () {},
        lockFields: (_) async {},
      );
      await HiveService.instance.foodBox
          .putAll({for (final r in rows) r['id'] as String: r});
    });

    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
      debugDietPlanSeedOverride = null;
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      UserProfileNotifier.debugFoodTypeEffects = null;
      await tearDownHiveForTests(dir);
    });

    Future<void> seed(WidgetTester tester,
        {bool pro = true, Map<String, dynamic> extra = const {}}) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields({..._pack, ...extra});
        await MigratedKey.write('isPro', pro);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
    }

    Future<void> pumpScreen(WidgetTester tester, {double width = 1080}) async {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final old = FlutterError.onError;
      // The test font is wider than DM Sans, so the MEAL rows overflow at 360 dp; this screen is
      // pumped at 1080 dp and the banner is asserted by finders, not by layout errors.
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(home: DietPlanScreen()),
      ));
      await _settle(tester);
    }


    Future<void> retarget(WidgetTester tester, int cal, int protein) async {
      await tester.runAsync(() => UserRepository.instance.updateProfileFields({
            'daily_calories': cal,
            'protein_grams': protein,
            'carb_grams': 200,
            'carbs_grams': 200,
            'fat_grams': 60,
          }));
      final c = ProviderScope.containerOf(tester.element(find.byType(DietPlanScreen)));
      c.invalidate(macroTargetsProvider);
      await _settle(tester);
    }

    Future<void> openAndSave(WidgetTester tester) async {
      await pumpScreen(tester);
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
    }

    Future<void> reopen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      debugDietPlanGenerations = 0;
      await pumpScreen(tester);
    }

    final banner = _key('diet_plan_stale_banner');

    testWidgets('a stamped saved plan with a different target shows the banner; nothing regenerates',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      expect(_savedPlan()![kDietTargetCaloriesKey], 2400);
      expect(_savedPlan()![kDietTargetProteinKey], 150);
      await tester.runAsync(() => UserRepository.instance.updateProfileFields({
            'daily_calories': 1900, 'protein_grams': 130,
            'carb_grams': 200, 'carbs_grams': 200, 'fat_grams': 60,
          }));
      await reopen(tester);
      expect(debugDietPlanGenerations, 0, reason: 'the saved plan was loaded, not regenerated');
      expect(banner, findsOneWidget);
      expect(_textOf(tester, 'diet_plan_stale_calories'), 'Daily calories 2,400 \u2192 1,900 kcal');
      expect(_textOf(tester, 'diet_plan_stale_protein'), 'Protein 150 \u2192 130 g');
      expect(debugDietPlanGenerations, 0);
    });

    testWidgets('the same target shows no banner', (tester) async {
      await seed(tester);
      await openAndSave(tester);
      await reopen(tester);
      expect(debugDietPlanGenerations, 0);
      expect(banner, findsNothing);
    });

    testWidgets('an UNSTAMPED saved plan shows no banner, and the saved-plan path really ran',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      final plan = _savedPlan()!
        ..remove(kDietTargetCaloriesKey)
        ..remove(kDietTargetProteinKey);
      await tester.runAsync(() => UserRepository.instance.saveDietPlan(plan));
      await tester.runAsync(() => UserRepository.instance.updateProfileFields({
            'daily_calories': 1900, 'protein_grams': 130,
            'carb_grams': 200, 'carbs_grams': 200, 'fat_grams': 60,
          }));
      await reopen(tester);
      expect(debugDietPlanGenerations, 0);
      expect(banner, findsNothing);
      // re-saved, it stays unstamped (no new numbers are invented for an old plan)
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
      expect(_savedPlan()!.containsKey(kDietTargetCaloriesKey), isFalse);
      expect(_savedPlan()!.containsKey(kDietTargetProteinKey), isFalse);
    });

    testWidgets('a target that moves while the screen is open shows the banner after the provider is invalidated',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      await reopen(tester);
      expect(banner, findsNothing);
      await retarget(tester, 1900, 130);
      expect(banner, findsOneWidget);
    });

    testWidgets('Regenerate adds one generation, removes the banner and leaves the saved plan untouched',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      await retarget(tester, 1900, 130);
      await reopen(tester);
      final savedBefore = _savedPlan();
      expect(banner, findsOneWidget);
      String planText() => tester
          .widgetList<Text>(find.descendant(
              of: find.byType(DietPlanScreen), matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .where((t) =>
              !t.startsWith('Daily calories') &&
              !t.startsWith('Protein ') &&
              !t.startsWith('Your targets') &&
              !t.startsWith('Regenerat'))
          .join('|');
      final planBefore = planText();
      await _tapReal(tester, _key('diet_plan_stale_regenerate'));
      expect(debugDietPlanGenerations, 1);
      expect(planText(), isNot(planBefore),
          reason: 'the plan on screen is rebuilt for the new targets');
      expect(banner, findsNothing, reason: 'the new plan is stamped with the new targets');
      expect(_savedPlan(), savedBefore, reason: 'the old saved plan is untouched until Save');
    });

    testWidgets('a fresh plan generated, the target changed, then Save stamps the GENERATION-time numbers',
        (tester) async {
      await seed(tester);
      await pumpScreen(tester); // no saved plan: generated for 2400 / 150
      await retarget(tester, 1900, 130);
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
      expect(_savedPlan()![kDietTargetCaloriesKey], 2400);
      expect(_savedPlan()![kDietTargetProteinKey], 150);
    });

    testWidgets('a LOADED stale plan re-saved keeps its OLD stamp and the banner stays',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      await retarget(tester, 1900, 130);
      await reopen(tester);
      expect(banner, findsOneWidget);
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
      expect(_savedPlan()![kDietTargetCaloriesKey], 2400);
      expect(banner, findsOneWidget);
    });

    testWidgets('dismissal hides the banner for that pair and it returns when the target moves again',
        (tester) async {
      await seed(tester);
      await openAndSave(tester);
      await retarget(tester, 1900, 130);
      await reopen(tester);
      await _tapReal(tester, _key('diet_plan_stale_dismiss'));
      expect(banner, findsNothing);
      await retarget(tester, 1800, 130);
      expect(banner, findsOneWidget);
    });
  });
}
