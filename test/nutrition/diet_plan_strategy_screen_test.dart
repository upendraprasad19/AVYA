// test/nutrition/diet_plan_strategy_screen_test.dart
//
// Diet plan Unit 3b-1b (docs/plans/diet-strategy-3b.md §3.5-§3.8, §4): the
// Diet Plan screen follows the strategy. Pure helpers first (the vegan Keto
// request, the note, the saved-plan match, the PDF header), then widgets
// (the disabled Keto chip, the medical note, the Keto dialog), then the real
// screen on Hive with the catalog's food rows from the shipped asset.
//
// ⚠ The font warm-up test must stay FIRST (the Hive group mocks
// path_provider; see test/widgets/diet_plan_screen_no_modal_test.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_flags.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_pdf.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_strategy_state.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_actions.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_strategy_confirm_dialog.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_strategy_section.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_chips.dart';
import 'package:icanbefitter/shared/widgets/diet_strategy_notes.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

// Energy-consistent: 4 x 150 + 4 x 270 + 9 x 80 = 2400 kcal.
const _pack = <String, dynamic>{
  'full_name': 'T',
  'daily_calories': 2400,
  'protein_grams': 150,
  'carb_grams': 270,
  'carbs_grams': 270,
  'fat_grams': 80,
};

double _carbsFor(DietStrategy s) => s == DietStrategy.balanced
    ? 270
    : BmrCalculator.macroSplit(
        dailyCalories: 2400,
        proteinGrams: 150,
        balancedCarbs: 270,
        strategy: s)
    .carbGrams
    .toDouble();

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

Finder _chip(DietStrategy s) =>
    find.byKey(ValueKey('diet_strategy_chip_${s.storageKey}'));

Map<String, dynamic>? _savedPlan() => UserRepository.instance.getSavedDietPlan();

/// Every catalog food id of the saved plan.
List<String> _savedIds() => [
      for (final m in (_savedPlan()?['meals'] as List? ?? const []))
        for (final i in ((m as Map)['items'] as List? ?? const []))
          (i as Map)['food_id'] as String,
    ];

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

  group('pure', () {
    test('planStrategyFor: Low carb only for Keto + Vegan', () {
      for (final s in DietStrategy.values) {
        for (final f in FoodType.values) {
          final want = s == DietStrategy.keto && f == FoodType.vegan
              ? DietStrategy.lowCarb
              : s;
          expect(planStrategyFor(s, f), want, reason: '$s $f');
        }
      }
    });

    test('the plan note: none when the plan matches; Balanced wins', () {
      String? note(DietStrategy p, DietStrategy e, FoodType f) =>
          dietPlanStrategyNote(planStrategy: p, effective: e, foodType: f);
      expect(note(DietStrategy.keto, DietStrategy.keto, FoodType.veg), isNull);
      expect(note(DietStrategy.balanced, DietStrategy.balanced, FoodType.vegan),
          isNull);
      expect(note(DietStrategy.balanced, DietStrategy.keto, FoodType.nonVeg),
          kBalancedPlanNote);
      expect(note(DietStrategy.balanced, DietStrategy.keto, FoodType.vegan),
          kBalancedPlanNote,
          reason: 'a fallback for a vegan Keto user says Balanced');
      expect(note(DietStrategy.lowCarb, DietStrategy.keto, FoodType.vegan),
          kVeganKetoPlanNote);
      expect(note(DietStrategy.lowCarb, DietStrategy.keto, FoodType.veg),
          isNull,
          reason: 'only the vegan pair is explained');
    });

    test('savedPlanMatchesStrategy: a stamp matches only itself; no stamp '
        'is Balanced', () {
      for (final current in DietStrategy.values) {
        expect(savedPlanMatchesStrategy(const {}, current),
            current == DietStrategy.balanced);
        for (final stamp in DietStrategy.values) {
          expect(
              savedPlanMatchesStrategy(
                  {'diet_strategy': stamp.storageKey}, current),
              stamp == current,
              reason: '$stamp vs $current');
        }
      }
    });

    test('savedPlanMatchesStrategy: the REQUESTED stamp wins; a garbage '
        'stamp is Balanced (3b-1b B-pass P1, seat C finding 6)', () {
      // A plan built Balanced after a fallback, requested Keto.
      const fellBack = {
        'diet_strategy': 'balanced',
        'diet_strategy_requested': 'keto',
      };
      expect(savedPlanMatchesStrategy(fellBack, DietStrategy.keto), isTrue);
      expect(
          savedPlanMatchesStrategy(fellBack, DietStrategy.balanced), isFalse);
      expect(savedPlanMatchesStrategy(const {'diet_strategy': 'paleo'},
          DietStrategy.balanced), isTrue);
      expect(savedPlanMatchesStrategy(const {'diet_strategy': 'paleo'},
          DietStrategy.keto), isFalse);
    });

    test('dietPlanNeedsRegeneration: never before the first plan; only for '
        'a different request (round 4 finding 2)', () {
      bool needs(int epoch, DietStrategy effective, FoodType t,
              DietStrategy requested) =>
          dietPlanNeedsRegeneration(
              planEpoch: epoch,
              effective: effective,
              foodType: t,
              requested: requested);
      expect(needs(0, DietStrategy.keto, FoodType.nonVeg,
          DietStrategy.balanced), isFalse,
          reason: 'the first generation reads the live strategy itself');
      expect(needs(1, DietStrategy.keto, FoodType.nonVeg,
          DietStrategy.balanced), isTrue);
      expect(needs(1, DietStrategy.keto, FoodType.nonVeg, DietStrategy.keto),
          isFalse);
      expect(needs(3, DietStrategy.keto, FoodType.vegan,
          DietStrategy.lowCarb), isFalse,
          reason: 'vegan Keto asks for the same Low carb plan');
    });

    test('the plan request: flag off and Balanced send no carb target; Keto '
        'sends its own; vegan Keto asks for Low carb with the LOW CARB '
        'target', () {
      Map<String, double> t(DietStrategy s) => {
            'calories': 2400,
            'protein': 150,
            'carbs': _carbsFor(s),
            'fat': 80,
            'strategy_index': s.index.toDouble(),
          };
      final off = dietPlanRequestFor(
          targets: t(DietStrategy.keto),
          foodType: FoodType.nonVeg,
          profile: _pack,
          enabled: false);
      expect(off.strategy, DietStrategy.balanced);
      expect(off.carbTarget, isNull);
      final bal = dietPlanRequestFor(
          targets: t(DietStrategy.balanced),
          foodType: FoodType.nonVeg,
          profile: _pack,
          enabled: true);
      expect(bal.strategy, DietStrategy.balanced);
      expect(bal.carbTarget, isNull);
      final keto = dietPlanRequestFor(
          targets: t(DietStrategy.keto),
          foodType: FoodType.veg,
          profile: _pack,
          enabled: true);
      expect(keto.strategy, DietStrategy.keto);
      expect(keto.carbTarget, _carbsFor(DietStrategy.keto));
      final vegan = dietPlanRequestFor(
          targets: t(DietStrategy.keto),
          foodType: FoodType.vegan,
          profile: _pack,
          enabled: true);
      expect(vegan.strategy, DietStrategy.lowCarb);
      expect(vegan.carbTarget, closeTo(_carbsFor(DietStrategy.lowCarb), 0.5));
      // Literals for the 2400 / 150 / 270 fixture (seat C finding 5), so the
      // expectation is not only the code's own macroSplit.
      expect(vegan.carbTarget, closeTo(120, 0.5));
      expect(keto.carbTarget, closeTo(30, 0.5));
      expect(_carbsFor(DietStrategy.lowCarb),
          greaterThan(_carbsFor(DietStrategy.keto) + 20),
          reason: 'the two targets differ, so the assertion can tell them '
              'apart');
      final noPack = dietPlanRequestFor(
          targets: t(DietStrategy.keto),
          foodType: FoodType.vegan,
          profile: const {},
          enabled: true);
      expect(noPack.strategy, DietStrategy.lowCarb);
      expect(noPack.carbTarget, isNull);
    });

    test('PDF: the label is the PLAN strategy; the note is a header line', () {
      expect(dietPlanPdfStrategyLabel(DietStrategy.balanced), isNull);
      expect(dietPlanPdfStrategyLabel(DietStrategy.lowCarb), 'Low carb');
      final lines = dietPlanPdfHeaderLines(
          date: '14 Nov 2026',
          foodTypeLabel: 'Vegan',
          strategyLabel: dietPlanPdfStrategyLabel(DietStrategy.lowCarb),
          planNote: kVeganKetoPlanNote,
          calorieTarget: 2400,
          proteinTarget: 150,
          carbTarget: 30,
          fatTarget: 187,
          fiberTarget: 30);
      expect(lines, [
        'Generated on 14 Nov 2026  |  Food type: Vegan  |  Strategy: Low carb',
        'Target: 2400 kcal  |  Protein: 150g  |  Carbs: 30g  |  Fat: 187g  |  Fiber: 30g',
        kVeganKetoPlanNote,
      ]);
      expect(
          dietPlanPdfHeaderLines(
                  date: 'd',
                  foodTypeLabel: 'Veg',
                  calorieTarget: 1,
                  proteinTarget: 1,
                  carbTarget: 1,
                  fatTarget: 1,
                  fiberTarget: 1)
              .length,
          2,
          reason: 'no note, no line (the pre-3b header)');
    });
  });

  group('widgets', () {
    testWidgets('a disabled chip ignores taps, is announced disabled, and '
        'stays selected when it is the value', (tester) async {
      final taps = <DietStrategy>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DietStrategyChips(
            value: DietStrategy.keto,
            isPro: true,
            disabled: const {DietStrategy.keto},
            onChanged: taps.add,
          ),
        ),
      ));
      await tester.tap(_chip(DietStrategy.keto));
      await tester.tap(_chip(DietStrategy.lowCarb));
      expect(taps, [DietStrategy.lowCarb]);
      final keto = tester.getSemantics(_chip(DietStrategy.keto)).flagsCollection;
      expect(keto.isEnabled, Tristate.isFalse);
      expect(keto.isSelected, Tristate.isTrue);
      expect(
          tester.getSemantics(_chip(DietStrategy.lowCarb)).flagsCollection
              .isEnabled,
          Tristate.isTrue);
    });

    testWidgets('the notes under the chips (both screens): the vegan reason '
        'only for Vegan, the medical note only while Keto is selected',
        (tester) async {
      Future<void> pump(FoodType f, DietStrategy s) => tester.pumpWidget(
          MaterialApp(
              home: Scaffold(
                  body: DietStrategyNotes(foodType: f, selected: s))));
      for (final f in FoodType.values) {
        expect(dietStrategiesDisabledFor(f),
            f == FoodType.vegan ? {DietStrategy.keto} : isEmpty);
        for (final s in DietStrategy.values) {
          await pump(f, s);
          expect(find.text(kVeganKetoChipReason),
              f == FoodType.vegan ? findsOneWidget : findsNothing,
              reason: '$f $s');
          expect(find.text(kKetoMedicalNote),
              s == DietStrategy.keto ? findsOneWidget : findsNothing,
              reason: '$f $s');
        }
      }
    });

    test('PRESENCE: Edit Profile disables by the FORM food type and mounts '
        'the shared notes for the form strategy', () {
      final src = File('lib/features/profile/screens/edit_profile_screen.dart')
          .readAsStringSync();
      expect(src, contains('disabled: dietStrategiesDisabledFor(_foodType),'));
      expect(src,
          contains('DietStrategyNotes(foodType: _foodType, selected: _dietStrategy),'));
    });

    testWidgets('the Keto dialog with no numbers: the medical note and the '
        'two buttons, no rows', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DietStrategyConfirmDialog(next: DietStrategy.keto, preview: null),
        ),
      ));
      expect(find.text(kKetoMedicalNote), findsOneWidget);
      expect(find.text('Your daily targets change:'), findsNothing);
      expect(find.byKey(const ValueKey('diet_strategy_confirm_switch')),
          findsOneWidget);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DietStrategyConfirmDialog(
              next: DietStrategy.lowCarb, preview: null),
        ),
      ));
      expect(find.text(kKetoMedicalNote), findsNothing);
    });
  });

  group('with Hive', () {
    late Directory dir;
    late List<Map<String, dynamic>> catalogRows;

    setUpAll(() {
      final ids = {for (final e in kDietPlanCatalog) e.foodId};
      catalogRows = [
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
      await HiveService.instance.foodBox.putAll(
          {for (final r in catalogRows) r['id'] as String: r});
    });

    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
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
      // A tall surface: the ListView builds lazily, and the notes sit below
      // the chips and targets.
      tester.view.physicalSize = const Size(1080, 6000);
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

    /// The names every swap sheet on the screen offers (each sheet opened
    /// and closed in turn).
    Future<List<String>> offeredSwapNames(WidgetTester tester) async {
      final offered = <String>[];
      final icons = find.byIcon(Icons.swap_horiz);
      final n = tester.widgetList(icons).length;
      expect(n, greaterThan(0), reason: 'precondition: swappable items');
      for (var i = 0; i < n; i++) {
        await tester.tap(icons.at(i));
        await _settle(tester);
        final sheet = find.byType(BottomSheet);
        if (sheet.evaluate().isEmpty) continue; // the no-swap snackbar
        for (final tile in tester.widgetList<ListTile>(find.descendant(
            of: sheet, matching: find.byType(ListTile)))) {
          final title = tile.title;
          if (title is Text) offered.add(title.data ?? '');
        }
        await tester.tapAt(const Offset(10, 10)); // the barrier
        await _settle(tester);
      }
      return offered;
    }

    Set<String> lowCarbNames() => {
          for (final r in catalogRows)
            if (kDietPlanCatalog
                .any((e) => e.foodId == r['id'] && e.lowCarbOnly))
              r['name'] as String,
        };

    bool isGrain(String id) {
      final e = kDietPlanCatalog.firstWhere((c) => c.foodId == id);
      return e.roles.every((r) => r == DietRole.grain);
    }

    testWidgets('Keto (non-veg): one generation, a Keto plan with no grain, '
        'stamped keto; no note', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      expect(find.byKey(const ValueKey('diet_plan_strategy_note')),
          findsNothing);
      expect(find.text('NON-VEG · KETO'), findsOneWidget);
      expect(find.text(kKetoMedicalNote), findsOneWidget);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'keto');
      expect(_savedIds(), isNotEmpty);
      expect(_savedIds().where(isGrain), isEmpty,
          reason: 'Keto templates hold no grain');
    });

    testWidgets('Vegan + Keto: the Keto chip is disabled with the reason, a '
        'Low carb plan with the vegan line, stamped low_carb', (tester) async {
      await seed(tester,
          extra: const {'diet_strategy': 'keto', 'diet_preference': 'vegan'});
      await pumpScreen(tester);
      expect(find.text(kVeganKetoPlanNote), findsOneWidget);
      expect(find.text(kVeganKetoChipReason), findsOneWidget);
      expect(
          tester.getSemantics(_chip(DietStrategy.keto)).flagsCollection
              .isEnabled,
          Tristate.isFalse);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'low_carb');
      expect(debugDietPlanGenerations, 1);
    });

    testWidgets('the legacy generator (kill switch) under Keto: the Balanced '
        'line, stamped balanced', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await tester.runAsync(() => HiveService.instance.configBox
          .put(DietPlanFlags.disableCuratedKey, true));
      final c = await pumpScreen(tester);
      expect(find.text(kBalancedPlanNote), findsOneWidget);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'balanced');
      // 3b-1b B-pass P1: the plan still belongs to its Keto request, so it
      // gives hints and loads again (no new generation on re-open).
      expect(_savedPlan()?['diet_strategy_requested'], 'keto');
      expect(c.read(dietPlanProvider), isNotEmpty);
      final shownBefore = _savedIds();
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1, reason: 'the saved plan loaded');
      expect(find.text(kBalancedPlanNote), findsOneWidget);
      expect(_savedIds(), shownBefore);
    });

    testWidgets('the legacy generator (kill switch) under Keto: no swap '
        'offers a Low carb only food (the swap gets the BUILT strategy)',
        (tester) async {
      // 3b-1a B-pass seat B finding 1: swapAlternatives does not repeat the
      // generator's fallback, so the screen must pass the plan's built
      // strategy (Balanced here), never the requested Keto.
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await tester.runAsync(() => HiveService.instance.configBox
          .put(DietPlanFlags.disableCuratedKey, true));
      await pumpScreen(tester);
      expect(lowCarbNames(), hasLength(14), reason: 'precondition');
      final offered = await offeredSwapNames(tester);
      expect(offered, isNotEmpty, reason: 'precondition: some alternatives');
      expect(offered.toSet().intersection(lowCarbNames()), isEmpty);
    });

    testWidgets('a strategy change regenerates ONCE and the saved stamp '
        'follows; a Veg tap under Keto regenerates once through its door',
        (tester) async {
      await seed(tester);
      final c = await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      await tester.runAsync(() async {
        await c.read(userProfileProvider.notifier)
            .setDietStrategy(DietStrategy.keto);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);
      expect(debugDietPlanGenerations, 2);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'keto');

      // Non-veg -> Veg: the food-type door regenerates once (the plan it
      // asks for stays Keto, so nothing else may generate).
      await _tapReal(tester, find.text('Veg'));
      expect(debugDietPlanGenerations, 3);
    });

    testWidgets('vegan: Keto -> Low carb asks for the same Low carb plan, '
        'so nothing regenerates', (tester) async {
      await seed(tester,
          extra: const {'diet_strategy': 'keto', 'diet_preference': 'vegan'});
      final c = await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      await tester.runAsync(() async {
        await c.read(userProfileProvider.notifier)
            .setDietStrategy(DietStrategy.lowCarb);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);
      expect(debugDietPlanGenerations, 1,
          reason: 'planStrategyFor(keto, vegan) == planStrategyFor(lowCarb, '
              'vegan): the listener is idempotent');
      expect(find.text(kVeganKetoPlanNote), findsNothing,
          reason: 'Low carb is now the strategy itself');
    });

    testWidgets('PRO resolving after the first frame: the saved Keto plan '
        'replaces the Balanced one generated at first', (tester) async {
      await seed(tester, pro: false, extra: const {'diet_strategy': 'keto'});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p3',
            'food_type': 'non_veg',
            'diet_strategy': 'keto',
            'meals': [
              {
                'name': 'Lunch',
                'items': [
                  {'food_id': 'F0371', 'name': 'Late keto egg', 'calories': 90}
                ],
              }
            ],
          }));
      final c = await pumpScreen(tester);
      expect(find.text('Late keto egg'), findsNothing,
          reason: 'free: Balanced is in effect, the Keto plan does not match');
      expect(debugDietPlanGenerations, 1);
      await tester.runAsync(() => MigratedKey.write('isPro', true));
      c.invalidate(subscriptionInfoProvider);
      await _settle(tester);
      expect(find.text('Late keto egg'), findsOneWidget,
          reason: 'the saved-plan check re-ran for the new strategy');
      expect(debugDietPlanGenerations, 1);
    });

    testWidgets('a stamped Keto plan loads for a Keto user, with no '
        'generation; for a Balanced user it is replaced with no notice',
        (tester) async {
      Map<String, dynamic> plan(String stamp) => {
            'id': 'p1',
            'created_at': '2026-11-14T10:00:00',
            'food_type': 'non_veg',
            'diet_strategy': stamp,
            'meals': [
              {
                'name': 'Breakfast',
                'items': [
                  {
                    'food_id': 'F0371',
                    'name': 'Saved fried egg',
                    'serving_desc': '1 egg',
                    'serving_g': 50,
                    'calories': 90,
                    'protein': 6,
                    'carbs': 0,
                    'fat': 7,
                    'category': 'eggs',
                  }
                ],
              }
            ],
          };
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await tester.runAsync(
          () => UserRepository.instance.saveDietPlan(plan('keto')));
      final c = await pumpScreen(tester);
      expect(find.text('Saved fried egg'), findsOneWidget);
      expect(debugDietPlanGenerations, 0);
      expect(c.read(dietPlanProvider), isNotEmpty,
          reason: 'the stamp matches: hints are given');

      // Back to Balanced: the listener re-runs the saved-plan check, the
      // Keto plan no longer matches, a fresh plan replaces it, no snackbar.
      await tester.runAsync(() async {
        await c.read(userProfileProvider.notifier)
            .setDietStrategy(DietStrategy.balanced);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);
      expect(find.text('Saved fried egg'), findsNothing);
      expect(debugDietPlanGenerations, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(c.read(dietPlanProvider), isEmpty,
          reason: 'no hints from a plan built for another strategy');
    });

    testWidgets('flag OFF: a stamped Keto plan still loads and no stamp is '
        'written', (tester) async {
      DietStrategyFlags.debugEnabledOverride = false;
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await tester.runAsync(() => UserRepository.instance.saveDietPlan({
            'id': 'p2',
            'food_type': 'non_veg',
            'diet_strategy': 'keto',
            'meals': [
              {
                'name': 'Lunch',
                'items': [
                  {'food_id': 'F0371', 'name': 'Old keto egg', 'calories': 90}
                ],
              }
            ],
          }));
      final c = await pumpScreen(tester);
      expect(find.text('Old keto egg'), findsOneWidget);
      expect(c.read(dietPlanProvider), isNotEmpty);
      await _tapReal(tester, find.byIcon(Icons.refresh));
      await save(tester);
      expect(_savedPlan()!.containsKey('diet_strategy'), isFalse);
    });

    testWidgets('flag OFF: a plan saved as Keto with the flag on loads as '
        'Balanced for the swap (round 4 finding 1, seat C finding 1)',
        (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'keto');
      final ketoOffers = await offeredSwapNames(tester);
      expect(ketoOffers.toSet().intersection(lowCarbNames()), isNotEmpty,
          reason: 'precondition: this plan\'s Keto swaps do offer Low carb '
              'only foods, so the flag-off check below can see a leak');
      await tester.pumpWidget(const SizedBox());
      DietStrategyFlags.debugEnabledOverride = false;
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1, reason: 'the saved plan loaded');
      final offered = await offeredSwapNames(tester);
      expect(offered.toSet().intersection(lowCarbNames()), isEmpty);
    });

    testWidgets('Keto, Non-veg -> Vegan: one generation into a Low carb plan '
        'with the vegan line; back to Non-veg restores Keto (round 4 '
        'finding 3, seat C finding 3)', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      expect(find.text(kVeganKetoPlanNote), findsNothing);
      await _tapReal(tester, find.text('Vegan'));
      expect(debugDietPlanGenerations, 2);
      expect(find.text(kVeganKetoPlanNote), findsOneWidget);
      expect(
          tester.getSemantics(_chip(DietStrategy.keto)).flagsCollection
              .isEnabled,
          Tristate.isFalse);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'low_carb');
      expect(_savedPlan()?['diet_strategy_requested'], 'low_carb');
      await _tapReal(tester, find.text('Non-veg'));
      expect(debugDietPlanGenerations, 3);
      expect(find.text(kVeganKetoPlanNote), findsNothing);
      await save(tester);
      expect(_savedPlan()?['diet_strategy'], 'keto');
      expect(_savedIds().where(isGrain), isEmpty);
    });

    testWidgets('a swap sheet opened before a regeneration changes nothing',
        (tester) async {
      await seed(tester);
      final c = await pumpScreen(tester);
      List<String> shown() => [
            for (final t in tester.widgetList<Text>(find.descendant(
                of: find.byType(ListView), matching: find.byType(Text))))
              t.data ?? '',
          ];
      await tester.tap(find.byIcon(Icons.swap_horiz).first);
      await _settle(tester);
      final tiles = find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(ListTile));
      expect(tiles, findsWidgets);
      final altName = tester
          .widget<Text>(find.descendant(
              of: tiles.first, matching: find.byType(Text)).first)
          .data!;
      await tester.runAsync(() async {
        await c.read(userProfileProvider.notifier)
            .setDietStrategy(DietStrategy.lowCarb);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);
      expect(debugDietPlanGenerations, 2);
      final regenerated = shown();
      expect(regenerated, isNot(contains(altName)),
          reason: 'precondition: the stale pick is not already in the plan');
      await tester.tap(tiles.first);
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(shown(), regenerated,
          reason: 'the stale pick did not land in the new plan');
    });

    testWidgets('Keto tap with equal shown targets still asks, with the '
        'medical note', (tester) async {
      // Balanced carbs 20 g already sit under Keto's: the numbers do not move.
      await seed(tester, extra: const {
        'daily_calories': 1500,
        'protein_grams': 150,
        'carb_grams': 20,
        'carbs_grams': 20,
        'fat_grams': 91,
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: DietStrategySection())),
        ),
      ));
      await tester.pump();
      await _tapReal(tester, _chip(DietStrategy.keto));
      expect(find.byKey(const ValueKey('diet_strategy_confirm_dialog')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('diet_strategy_confirm_keto_note')),
          findsOneWidget);
      expect(find.text('Your daily targets change:'), findsNothing);
      await _tapReal(
          tester, find.byKey(const ValueKey('diet_strategy_confirm_switch')));
      expect(UserRepository.instance.getProfile()?['diet_strategy'], 'keto');
    });

    testWidgets('Edit Profile Save: a change to Keto asks even with no '
        'numbers; Low carb with no numbers does not', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      Future<bool?>? pending;
      pending = confirmEditProfileDietStrategy(ctx,
          profile: const {},
          edited: const {},
          recomputeAfter: null,
          next: DietStrategy.lowCarb,
          pro: true);
      expect(await pending, isTrue);
      pending = confirmEditProfileDietStrategy(ctx,
          profile: const {},
          edited: const {},
          recomputeAfter: null,
          next: DietStrategy.keto,
          pro: true);
      await tester.pumpAndSettle();
      expect(find.text(kKetoMedicalNote), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diet_strategy_confirm_cancel')));
      await tester.pumpAndSettle();
      expect(await pending, isNull);
    });
  });
}
