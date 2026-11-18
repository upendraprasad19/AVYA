// test/nutrition/diet_plan_supplements_screen_test.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md sections 3 and 7): the
// Diet Plan screen with Supplements. The real screen on Hive, with the
// catalog rows and the two shake rows from the shipped asset.
//
// ⚠ The font warm-up test must stay FIRST (the Hive group mocks
// path_provider; see test/widgets/diet_plan_screen_no_modal_test.dart).
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_supplements_active_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_generator.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_strategy_state.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/services/diet_supplements_flags.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_serving_view_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_macro_cards.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_supplements_section.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_chips.dart';
import 'package:icanbefitter/shared/widgets/food_type_chips.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

// A short-on-protein day for a vegetarian: 1500 kcal / 130 g leaves a gap the
// curated plan does not close, so the shake is added.
const _pack = <String, dynamic>{
  'full_name': 'T',
  'date_of_birth': '1998-01-01',
  'daily_calories': 1500,
  'protein_grams': 130,
  'carb_grams': 160,
  'carbs_grams': 160,
  'fat_grams': 50,
  'diet_preference': 'veg',
};

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

List<String> _savedIds() => [
      for (final m in (_savedPlan()?['meals'] as List? ?? const []))
        for (final i in ((m as Map)['items'] as List? ?? const []))
          (i as Map)['food_id'] as String,
    ];

const _wheyName = 'Whey Isolate (Generic)';
const _peaName = 'Plant Protein (Pea)';

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
      final ids = {for (final e in kDietPlanCatalog) e.foodId, 'F0823', 'F0831'};
      rows = [
        for (final r
            in (jsonDecode(File('assets/data/food_database.json')
                    .readAsStringSync()) as List)
                .cast<Map<String, dynamic>>())
          if (ids.contains(r['id'])) r,
      ];
    });

    setUp(() async {
      dir = await setUpHiveForTests();
      DietStrategyFlags.debugEnabledOverride = true;
      DietSupplementsFlags.debugEnabledOverride = true;
      debugDietPlanGenerations = 0;
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
      DietSupplementsFlags.debugEnabledOverride = null;
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

    Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(home: DietPlanScreen()),
      ));
      await _settle(tester);
      return ProviderScope.containerOf(
          tester.element(find.byType(DietPlanScreen)));
    }

    Future<void> save(WidgetTester tester) =>
        _tapReal(tester, find.byIcon(Icons.save_outlined));

    Finder cardAnywhere() => find.byWidgetPredicate((w) =>
        w.key == const ValueKey('diet_supplement_card') ||
        w.key == const ValueKey('diet_supplement_card_collapsed'));

    Finder switchFinder() => find.byKey(const ValueKey('diet_supplements_switch'));

    /// Pumps the screen on a 360 dp wide surface and returns every
    /// FlutterError raised while laying it out. The test font (Ahem) is far
    /// wider than DM Sans, so the MEAL rows overflow here; callers filter by
    /// file. The handler is restored before this returns (a test that fails
    /// later must not leave it overridden).
    Future<List<FlutterErrorDetails>> pump360(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(ProviderScope(
          overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
          child: const MaterialApp(home: DietPlanScreen()),
        ));
        await _settle(tester);
      } finally {
        FlutterError.onError = old;
      }
      return errors;
    }

    /// The food ids the curated generator gives for the SAME request the
    /// screen makes today (seed, targets, strategy), without the shake step.
    List<String> generatorIds(ProviderContainer c) {
      final targets = c.read(macroTargetsProvider);
      final profile = UserRepository.instance.getProfile() ?? const {};
      final foodType = foodTypeOfProfile(profile);
      final request = dietPlanRequestFor(
          targets: targets, foodType: foodType, profile: profile, enabled: true);
      final built = CuratedDietPlanGenerator.instance.generatePlan(DietPlanInputs(
        calorieTarget: targets['calories']!.round(),
        proteinTarget: targets['protein']!.round(),
        dietPreference: foodType.storageKey,
        fiberTarget: (profile['fiber_grams'] as num?)?.toInt() ?? 30,
        seed: dietPlanSeed(DateTime.now(), 0),
        strategy: request.strategy,
        carbTarget: request.carbTarget,
      ));
      return [
        for (final m in built.meals) for (final i in m.items) i.foodId,
      ];
    }

    testWidgets('IDENTITY: a user who did not opt in gets exactly the '
        'generator\'s plan', (tester) async {
      await seed(tester);
      final c = await pumpScreen(tester);
      await save(tester);
      expect(_savedIds(), generatorIds(c));
    });

    testWidgets('IDENTITY: the kill switch off gives the generator\'s plan '
        'even for an opted-in PRO adult', (tester) async {
      DietSupplementsFlags.debugEnabledOverride = false;
      await seed(tester, extra: const {'diet_supplements': true});
      final c = await pumpScreen(tester);
      await save(tester);
      expect(_savedIds(), generatorIds(c));
    });

    testWidgets('the opted-in plan is the generator\'s plan plus the shake '
        'and what the shake displaced', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      final c = await pumpScreen(tester);
      await save(tester);
      final base = generatorIds(c);
      final ids = _savedIds();
      expect(ids.where((i) => i == 'F0823').length, 1);
      // Everything else was in the generator's plan (items may only be
      // removed, never invented).
      expect(base.toSet().containsAll(ids.where((i) => i != 'F0823')), isTrue);
    });

    /// The swap icon beside the item named [name] (null when it has none).
    Finder swapIconIn(String name) => find.descendant(
        of: find.ancestor(
            of: find.text(name), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.swap_horiz));

    testWidgets('active: one scoop of whey in the plan, no swap icon on it, '
        'the card below the switch, the stamp saved', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      expect(find.text(_wheyName), findsOneWidget);
      // The card sits under the meals, collapsed to one line.
      expect(find.byKey(const ValueKey('diet_supplement_card_collapsed')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_supplement_card')), findsNothing);
      expect(find.text('Your supplements'), findsOneWidget);
      expect(find.text('Strong evidence base.'), findsNothing,
          reason: 'collapsed: names only, no doses or notes');
      expect(
          tester.getTopLeft(find.text('Your supplements')).dy,
          greaterThan(tester.getTopLeft(find.text(_wheyName)).dy),
          reason: 'under the meals, not between the switch and the plan');
      await _tapReal(
          tester, find.byKey(const ValueKey('diet_supplement_card_toggle')));
      expect(find.byKey(const ValueKey('diet_supplement_card')), findsOneWidget);
      expect(find.text('Strong evidence base.'), findsOneWidget);
      await _tapReal(
          tester, find.byKey(const ValueKey('diet_supplement_card_toggle')));
      expect(find.byKey(const ValueKey('diet_supplement_card')), findsNothing);
      expect(swapIconIn(_wheyName), findsNothing,
          reason: 'the shake has no alternatives');
      // Every other item keeps its swap icon.
      expect(find.byIcon(Icons.swap_horiz), findsWidgets);
      await save(tester);
      final saved = _savedPlan()!;
      expect(saved['diet_supplements'], isTrue);
      expect(_savedIds(), contains('F0823'));
    });

    testWidgets('a vegan gets the pea protein row, not whey', (tester) async {
      await seed(tester, extra: const {
        'diet_supplements': true,
        'diet_preference': 'vegan',
      });
      await pumpScreen(tester);
      expect(find.text(_peaName), findsOneWidget);
      expect(find.text(_wheyName), findsNothing);
    });

    testWidgets('not opted in: no shake, no card, no stamp, the switch is off',
        (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      expect(find.text(_wheyName), findsNothing);
      expect(cardAnywhere(), findsNothing);
      expect(tester.widget<Switch>(switchFinder()).value, isFalse);
      await save(tester);
      expect(_savedPlan()!.containsKey('diet_supplements'), isFalse);
      expect(_savedIds().where((i) => i == 'F0823' || i == 'F0831'), isEmpty);
    });

    testWidgets('under 18: no section at all, no shake, even with the switch '
        'stored on', (tester) async {
      await seed(tester, extra: {
        'diet_supplements': true,
        'date_of_birth': '${DateTime.now().year - 15}-06-01',
      });
      await pumpScreen(tester);
      expect(find.byType(DietSupplementsField), findsNothing);
      expect(switchFinder(), findsNothing);
      expect(find.text('Supplements'), findsNothing);
      expect(find.text(_wheyName), findsNothing);
      expect(cardAnywhere(), findsNothing);
    });

    testWidgets('an unreadable date of birth: the hint, no switch, no shake',
        (tester) async {
      await seed(tester,
          extra: const {'diet_supplements': true, 'date_of_birth': 'not-a-date'});
      await pumpScreen(tester);
      expect(find.text(kDietSupplementsNeedsDobHint), findsOneWidget);
      expect(switchFinder(), findsNothing);
      expect(find.text(_wheyName), findsNothing);
    });

    testWidgets('a stored "on" with PRO lapsed: paused hint, the switch shows '
        'the stored choice, no shake, no card, and OFF is allowed',
        (tester) async {
      await seed(tester, pro: false, extra: const {'diet_supplements': true});
      await pumpScreen(tester);
      expect(find.text(kDietSupplementsPausedHint), findsOneWidget);
      expect(tester.widget<Switch>(switchFinder()).value, isTrue);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text(_wheyName), findsNothing);
      expect(cardAnywhere(), findsNothing);
      // Turning it off needs no PRO: the stored choice is cleared.
      await _tapReal(tester, switchFinder());
      expect(UserRepository.instance.getProfile()!['diet_supplements'], isFalse);
      expect(find.text(kDietSupplementsPausedHint), findsNothing);
      expect(tester.widget<Switch>(switchFinder()).value, isFalse);
    });

    testWidgets('a free user tapping the switch gets the paywall and nothing '
        'is written', (tester) async {
      await seed(tester, pro: false);
      await pumpScreen(tester);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget,
          reason: 'a free adult sees the lock');
      await tester.tap(switchFinder());
      await tester.pumpAndSettle();
      expect(find.text('Diet Supplements is a PRO feature'), findsOneWidget);
      expect(find.text('A daily supplement card and a protein shake in your plan.'),
          findsOneWidget);
      expect(UserRepository.instance.getProfile()!['diet_supplements'], isNull);
      // Close the sheet so no route animation outlives the test.
      Navigator.of(tester.element(find.text('Diet Supplements is a PRO feature')))
          .pop();
      await tester.pumpAndSettle();
    });

    testWidgets('PRO turning it on: stored true, ONE regeneration, shake '
        'appears; turning it off removes it again', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      expect(find.text(_wheyName), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing,
          reason: 'PRO: no lock');
      await _tapReal(tester, switchFinder());
      expect(UserRepository.instance.getProfile()!['diet_supplements'], isTrue);
      expect(debugDietPlanGenerations, 2, reason: 'one regeneration, not two');
      expect(find.text(_wheyName), findsOneWidget);
      expect(find.byKey(const ValueKey('diet_supplement_card_collapsed')),
          findsOneWidget);
      await _tapReal(tester, switchFinder());
      expect(UserRepository.instance.getProfile()!['diet_supplements'], isFalse);
      expect(debugDietPlanGenerations, 3);
      expect(find.text(_wheyName), findsNothing);
      expect(cardAnywhere(), findsNothing);
    });

    testWidgets('layout v2: the title, then ONE row of the three controls, '
        'then the compact calorie and macro blocks, then the plan, and the '
        'supplement card last', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      // The wide test surface (the test font is wider than DM Sans, so a
      // phone width overflows the meal rows).
      tester.view.physicalSize = const Size(1080, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(home: DietPlanScreen()),
      ));
      await _settle(tester);
      expect(find.text('Diet chart'), findsOneWidget);
      expect(find.text('Diet Plan'), findsNothing);
      final food =
          find.byKey(const ValueKey('diet_plan_food_type_dropdown'));
      final strategy =
          find.byKey(const ValueKey('diet_plan_strategy_dropdown'));
      final supp = find.byKey(const ValueKey('diet_plan_supplements_field'));
      expect(tester.getTopLeft(food).dy, tester.getTopLeft(strategy).dy,
          reason: 'one row');
      expect(tester.getTopLeft(strategy).dy, tester.getTopLeft(supp).dy,
          reason: 'one row');
      expect(tester.getTopLeft(food).dx,
          lessThan(tester.getTopLeft(strategy).dx));
      expect(tester.getTopLeft(strategy).dx,
          lessThan(tester.getTopLeft(supp).dx));
      final tdee = find.byKey(const ValueKey('diet_plan_tdee_card'));
      final macros = find.byKey(const ValueKey('diet_plan_macro_card'));
      expect(tester.getBottomLeft(supp).dy,
          lessThan(tester.getTopLeft(tdee).dy));
      expect(tester.getBottomLeft(tdee).dy,
          lessThan(tester.getTopLeft(macros).dy));
      expect(tester.getBottomLeft(macros).dy,
          lessThan(tester.getTopLeft(find.text('Breakfast')).dy));
      // The compact card keeps every figure's unit (BMR, TDEE, TARGET).
      expect(find.descendant(of: tdee, matching: find.textContaining('kcal')),
          findsNWidgets(3));
      expect(tester.getSize(tdee).height,
          lessThanOrEqualTo(kDietPlanCompactCardMaxHeight));
      expect(tester.getSize(macros).height,
          lessThanOrEqualTo(kDietPlanCompactCardMaxHeight));
      // The switch is inside its field; the card is below the last meal.
      expect(tester.getTopLeft(switchFinder()).dy,
          lessThan(tester.getTopLeft(find.text('Breakfast')).dy));
      expect(
          tester.getTopLeft(find.byKey(
              const ValueKey('diet_supplement_card_collapsed'))).dy,
          greaterThan(tester.getBottomLeft(find.text('Dinner')).dy));
      // The old chip rows are gone from this screen.
      expect(find.byType(FoodTypeChips), findsNothing);
      expect(find.byType(DietStrategyChips), findsNothing);
    });

    testWidgets('layout v2: the food-type menu lists every option and the '
        'closed field shows the stored one', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      final field = find.byKey(const ValueKey('diet_plan_food_type_dropdown'));
      expect(find.descendant(of: field, matching: find.text('Veg')),
          findsOneWidget);
      await _tapReal(tester, field);
      for (final t in FoodType.values) {
        expect(find.byKey(ValueKey('food_type_chip_${t.storageKey}')),
            findsOneWidget,
            reason: '${t.label} is listed');
      }
    });

    testWidgets('layout v2 (review R1): a free user keeps the lock out of '
        'the field, and a tap on the field text asks for PRO', (tester) async {
      await seed(tester, pro: false);
      await pumpScreen(tester);
      final field = find.byKey(const ValueKey('diet_plan_supplements_field'));
      expect(find.descendant(of: field, matching: find.byIcon(Icons.lock_outline)),
          findsNothing,
          reason: 'the lock must not take the field\'s width');
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.descendant(of: field, matching: find.text('Off')),
          findsOneWidget);
      // The whole field is the tap target, not only the switch.
      await tester.tap(find.descendant(of: field, matching: find.text('Off')));
      await tester.pumpAndSettle();
      expect(find.text('Diet Supplements is a PRO feature'), findsOneWidget);
      Navigator.of(tester.element(find.text('Diet Supplements is a PRO feature')))
          .pop();
      await tester.pumpAndSettle();
    });

    testWidgets('layout v2 (review R2): at 360 dp a free user\'s On/Off slot '
        'keeps its room (the lock is not in the field)', (tester) async {
      await seed(tester, pro: false);
      await pump360(tester);
      final field = find.byKey(const ValueKey('diet_plan_supplements_field'));
      final slot = tester.getSize(
          find.descendant(of: field, matching: find.byType(Expanded)));
      expect(slot.width, greaterThanOrEqualTo(26),
          reason: 'a 100 dp column minus border, padding and the Switch box');
      expect(find.descendant(of: field, matching: find.byIcon(Icons.lock_outline)),
          findsNothing);
    });

    testWidgets('layout v2 (review R1): PRO, a tap on the field text turns '
        'Supplements on', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      final field = find.byKey(const ValueKey('diet_plan_supplements_field'));
      await _tapReal(
          tester, find.descendant(of: field, matching: find.text('Off')));
      expect(UserRepository.instance.getProfile()!['diet_supplements'], true);
      expect(find.descendant(of: field, matching: find.text('On')),
          findsOneWidget);
    });

    testWidgets('layout v2 (review R1/R2): the fields carry their names for a '
        'screen reader, and a long food type scales instead of being cut',
        (tester) async {
      await seed(tester, extra: const {'diet_preference': 'pescatarian'});
      final handle = tester.ensureSemantics();
      await pump360(tester);
      expect(find.bySemanticsLabel(RegExp('^Food type')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Diet strategy')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Supplements')), findsWidgets);
      final food = find.byKey(const ValueKey('diet_plan_food_type_dropdown'));
      final fitted = find.descendant(
          of: food,
          matching: find.ancestor(
              of: find.text('Pescatarian'), matching: find.byType(FittedBox)));
      expect(fitted, findsOneWidget,
          reason: 'the selected label sits in a FittedBox, never an ellipsis');
      // Laid out at its natural width in a narrower box: drawn scaled, whole.
      expect(
          tester
              .getSize(find.descendant(of: fitted, matching: find.text('Pescatarian')))
              .width,
          greaterThan(tester.getSize(fitted).width));
      // The supplements node carries the tap action itself.
      final supp = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^Supplements')).first);
      expect(supp.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('layout v2: a minor gets two columns (no Supplements field)',
        (tester) async {
      await seed(tester, extra: {
        'date_of_birth': '${DateTime.now().year - 15}-06-01',
      });
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('diet_plan_supplements_field')),
          findsNothing);
      expect(find.byKey(const ValueKey('diet_plan_strategy_dropdown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_plan_food_type_dropdown')),
          findsOneWidget);
    });

    testWidgets(
        'OI-517: the Grams view labels every meal row with the weight; '
        'Portions shows no weight prefix', (tester) async {
      final gramsRow = RegExp(r'^\d+ (g|ml)( \(.+\))? \u00B7 P\d+g C\d+g F\d+g$');
      List<String> mealRows() => [
            for (final t in tester.widgetList<Text>(find.byType(Text)))
              if ((t.data ?? '').contains(' \u00B7 P') &&
                  (t.data ?? '').contains(' F'))
                t.data!,
          ];

      await seed(tester, extra: const {'diet_serving_view': 'grams'});
      await pumpScreen(tester);
      final grams = mealRows();
      expect(grams, isNotEmpty);
      for (final r in grams) {
        expect(gramsRow.hasMatch(r), isTrue, reason: r);
      }

      await seed(tester, extra: const {'diet_serving_view': 'portions'});
      final c = ProviderScope.containerOf(
          tester.element(find.byType(DietPlanScreen)));
      c.invalidate(dietServingViewProvider);
      await _settle(tester);
      final portions = mealRows();
      expect(portions, isNotEmpty);
      for (final r in portions) {
        expect(RegExp(r'^\d+ (g|ml) \(').hasMatch(r), isFalse, reason: r);
      }
    });

    test('OI-517: the PDF rows are labelled at share time (presence pin)', () {
      final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
          .readAsStringSync();
      expect(RegExp(r'servingDesc:\s*servingLabelFor\(').hasMatch(src), isTrue);
    });

    testWidgets('layout v2: no overflow at 360 dp with every control on',
        (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      final errors = await pump360(tester);
      for (final k in const [
        'diet_plan_food_type_dropdown',
        'diet_plan_strategy_dropdown',
        'diet_plan_supplements_field',
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(k))).width, greaterThan(90));
      }
      // The On/Off slot (the field minus border, padding and the Switch box)
      // keeps room for the word at any font: measured as layout, not text.
      final slot = tester.getSize(find.descendant(
          of: find.byKey(const ValueKey('diet_plan_supplements_field')),
          matching: find.byType(Expanded)));
      expect(slot.width, greaterThanOrEqualTo(26));
      // Only the meal rows may overflow on the narrow test surface (the test
      // font is wider than DM Sans); every file of the settings row and the
      // two compact cards must not (the creator chain names the file).
      const rowFiles = [
        'diet_plan_dropdown',
        'diet_plan_settings_row',
        'diet_plan_macro_cards',
        'diet_strategy_section',
        'diet_supplements_section',
      ];
      final rowErrors = errors.where((e) {
        final text = e.toString();
        return text.contains('overflowed') && rowFiles.any(text.contains);
      });
      expect(rowErrors, isEmpty);
    });

    testWidgets('the plan follows the switch with no stale-state heal in the '
        'normal path', (tester) async {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add(op);
      await seed(tester);
      await pumpScreen(tester);
      await _tapReal(tester, switchFinder());
      expect(find.text(_wheyName), findsOneWidget);
      await _tapReal(tester, switchFinder());
      expect(find.text(_wheyName), findsNothing);
      expect(events, isNot(contains('diet_supplements_plan_healed')),
          reason: 'the listener delivered both changes; the heal stays quiet');
    });

    testWidgets('HEAL: a plan built under another Supplements state than the '
        'one now shown is rebuilt once, and the event says so', (tester) async {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add(op);
      // Mounted with the kill switch off: no listener is registered, so the
      // heal in build is the ONLY path that can notice the change.
      DietSupplementsFlags.debugEnabledOverride = false;
      await seed(tester, extra: const {'diet_supplements': true});
      final c = await pumpScreen(tester);
      expect(find.text(_wheyName), findsNothing);
      expect(debugDietPlanGenerations, 1);
      DietSupplementsFlags.debugEnabledOverride = true;
      c.invalidate(dietSupplementsActiveProvider);
      // The screen did not watch the provider while the switch was off; any
      // rebuild now reads the new state.
      tester.element(find.byType(DietPlanScreen)).markNeedsBuild();
      await _settle(tester);
      expect(find.text(_wheyName), findsOneWidget,
          reason: 'the shake came without a Regenerate tap');
      expect(debugDietPlanGenerations, 2, reason: 'one rebuild, no loop');
      expect(events.where((e) => e == 'diet_supplements_plan_healed').length, 1);
      await _settle(tester);
      expect(debugDietPlanGenerations, 2);
    });

    testWidgets('a saved plan built with Supplements loads when active; the '
        'shake in it has no swap icon', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p1',
            'food_type': 'veg',
            'diet_supplements': true,
            'meals': [
              {
                'name': 'Evening Snack',
                'items': [
                  {
                    'food_id': 'F0823',
                    'name': _wheyName,
                    'serving_desc': '1 scoop',
                    'calories': 108,
                    'protein': 27,
                  }
                ],
              }
            ],
          }));
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 0, reason: 'the saved plan loaded');
      expect(find.text(_wheyName), findsOneWidget);
      expect(swapIconIn(_wheyName), findsNothing);
    });

    testWidgets('the kill switch off: a plan stamped with Supplements is not '
        'loaded (its shake would outlive the switch)', (tester) async {
      DietSupplementsFlags.debugEnabledOverride = false;
      await seed(tester, extra: const {'diet_supplements': true});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p1',
            'food_type': 'veg',
            'diet_supplements': true,
            'meals': [
              {
                'name': 'Evening Snack',
                'items': [
                  {
                    'food_id': 'F0823',
                    'name': _wheyName,
                    'serving_desc': '1 scoop',
                    'calories': 108,
                    'protein': 27,
                  }
                ],
              }
            ],
          }));
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1, reason: 'generated fresh, not loaded');
      expect(find.text(_wheyName), findsNothing);
      expect(find.byType(DietSupplementsField), findsNothing);
    });

    testWidgets('a loaded stamped plan is regenerated once when the switch '
        'goes off (the loaded stamp is the plan\'s state)', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p1',
            'food_type': 'veg',
            'diet_supplements': true,
            'meals': [
              {
                'name': 'Evening Snack',
                'items': [
                  {
                    'food_id': 'F0823',
                    'name': _wheyName,
                    'serving_desc': '1 scoop',
                    'calories': 108,
                    'protein': 27,
                  }
                ],
              }
            ],
          }));
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 0);
      expect(find.text(_wheyName), findsOneWidget);
      await _tapReal(tester, switchFinder());
      expect(UserRepository.instance.getProfile()!['diet_supplements'], isFalse);
      expect(debugDietPlanGenerations, 1, reason: 'one regeneration');
      expect(find.text(_wheyName), findsNothing);
    });

    testWidgets('a saved plan WITHOUT the stamp does not load once Supplements '
        'are active: a fresh plan is generated', (tester) async {
      await seed(tester, extra: const {'diet_supplements': true});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p2',
            'food_type': 'veg',
            'meals': [
              {
                'name': 'Lunch',
                'items': [
                  {'food_id': 'F0371', 'name': 'Old plan egg', 'calories': 90}
                ],
              }
            ],
          }));
      await pumpScreen(tester);
      expect(find.text('Old plan egg'), findsNothing);
      expect(debugDietPlanGenerations, 1);
      expect(find.text(_wheyName), findsOneWidget);
    });

    testWidgets('a stamped plan does not load when Supplements are off',
        (tester) async {
      await seed(tester);
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p4',
            'food_type': 'veg',
            'diet_supplements': true,
            'meals': [
              {
                'name': 'Lunch',
                'items': [
                  {'food_id': 'F0371', 'name': 'Stamped egg', 'calories': 90}
                ],
              }
            ],
          }));
      await pumpScreen(tester);
      expect(find.text('Stamped egg'), findsNothing);
      expect(debugDietPlanGenerations, 1);
    });

    testWidgets('a missing shake row (stale food box): no shake, no crash, '
        'the plan still builds', (tester) async {
      await tester.runAsync(() async {
        await HiveService.instance.foodBox.delete('F0823');
      });
      await seed(tester, extra: const {'diet_supplements': true});
      await pumpScreen(tester);
      expect(find.text(_wheyName), findsNothing);
      expect(find.byType(DietPlanScreen), findsOneWidget);
      expect(debugDietPlanGenerations, 1);
    });

    testWidgets('the real kill switch (no seam): no section, no shake, no '
        'stamp, even with everything on', (tester) async {
      DietSupplementsFlags.debugEnabledOverride = null;
      await tester.runAsync(() => HiveService.instance.configBox
          .put(DietSupplementsFlags.disableKey, true));
      expect(DietSupplementsFlags.enabled, isFalse);
      await seed(tester, extra: const {'diet_supplements': true});
      await pumpScreen(tester);
      expect(find.byType(DietSupplementsField), findsNothing);
      expect(find.text(_wheyName), findsNothing);
      await save(tester);
      expect(_savedPlan()!.containsKey('diet_supplements'), isFalse);
    });
  });
}
