// test/nutrition/diet_plan_chart_v3_screen_test.dart
//
// Diet chart v3 (docs/plans/diet-chart-v3.md §4.1-§4.3, §5), on the real
// screen with Hive and the shipped food asset: the totals row, the swap sheet
// with "Search any food", the strategy that follows the plan (the shift popup,
// accept / cancel / back up), and the guards (free user, flag off, a stale
// write).
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
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_flags.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_totals.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_actions.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_totals_row.dart';
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
String? _profileStrategy() =>
    UserRepository.instance.getProfile()?['diet_strategy'] as String?;

Finder _key(String k) => find.byKey(ValueKey(k));

/// The plan kcal per item, read from the item rows ("350 kcal"; the meal
/// headers read "350 kcal · P 20g" and never match).
int _itemKcalOnScreen(WidgetTester tester) {
  var sum = 0;
  final re = RegExp(r'^(\d+) kcal$');
  for (final t in tester.widgetList<Text>(find.descendant(
      of: find.byType(DietPlanScreen), matching: find.byType(Text)))) {
    final m = re.firstMatch(t.data ?? '');
    if (m != null) sum += int.parse(m.group(1)!);
  }
  return sum;
}

/// The plan figure of one totals cell (the second Text of the cell).
int _cell(WidgetTester tester, String macro) {
  final texts = tester
      .widgetList<Text>(find.descendant(
          of: _key('diet_plan_totals_$macro'), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
  return int.parse(texts[1].replaceAll('g', ''));
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data ?? '';

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

  testWidgets('the totals row alone: 360 dp, text scale 1.0-2.0, no overflow, '
      'within its height ceiling with the fit line and the Back button',
      (tester) async {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(22),
              child: DietPlanTotalsRow(
                totals: DietPlanTotals(
                    calories: 2315, protein: 142, carbs: 118, fat: 96),
                targets: (calories: 2400, protein: 150, carbs: 120, fat: 80),
                targetCaption: 'Low carb',
                fitLine: 'Over the Keto limit (118 g, up to 38 g)',
                fitOk: false,
                backLabel: 'Back to Keto',
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      final h = tester.getSize(_key('diet_plan_totals_row')).height;
      if (scale == 1.0) {
        expect(h, lessThanOrEqualTo(kDietPlanTotalsRowMaxHeight),
            reason: 'height $h at text scale 1.0');
      }
      // ignore: avoid_print
      print('totals row height at scale $scale: $h');
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('B-pass C7: each cell reads as ONE spoken line with units, the '
      'Back button is a 44 dp target, and above scale 1.3 the cells are 2 x 2',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Future<void> pump(double scale) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: DietPlanTotalsRow(
              totals: DietPlanTotals(
                  calories: 2315, protein: 142, carbs: 118, fat: 96),
              targets: (calories: 2400, protein: 150, carbs: 120, fat: 80),
              fitLine: 'Fits Low carb (up to 150 g)',
              backLabel: 'Back to Keto',
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    await pump(1.0);
    expect(find.bySemanticsLabel('Carbs: 118 grams of 120 grams, 2 grams under'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Calories: 2315 kilocalories of 2400 kilocalories, 85 kilocalories under'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Fat: 96 grams of 80 grams, 16 grams over'),
        findsOneWidget);
    expect(tester.getSize(_key('diet_plan_back_up')).height,
        greaterThanOrEqualTo(44));
    final calY = tester.getTopLeft(_key('diet_plan_totals_calories')).dy;
    expect(tester.getTopLeft(_key('diet_plan_totals_protein')).dy,
        closeTo(calY, 6),
        reason: 'one row of four at scale 1.0');
    await pump(1.5);
    // a second row sits a whole cell (>= 30 dp) lower, not a few dp (the cells
    // of one Row are centred, so their tops differ slightly)
    expect(tester.getTopLeft(_key('diet_plan_totals_carbs')).dy,
        greaterThan(tester.getTopLeft(_key('diet_plan_totals_calories')).dy + 30),
        reason: 'two rows of two above scale 1.3');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  group('with Hive', () {
    late Directory dir;
    late List<Map<String, dynamic>> rows;
    late String cucumberId;

    setUpAll(() {
      rows = (jsonDecode(File('assets/data/food_database.json')
              .readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      cucumberId = rows.firstWhere((r) => r['name'] == 'Cucumber (raw)')['id'] as String;
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

    /// Errors of the totals row's own file; the test font is wider than DM
    /// Sans, so the MEAL rows overflow at 360 dp (the layout v2 tests filter
    /// by file the same way).
    List<FlutterErrorDetails> totalsRowErrors = [];

    Future<void> pumpScreen(WidgetTester tester, {double width = 1080}) async {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final old = FlutterError.onError;
      totalsRowErrors = [];
      FlutterError.onError = (d) {
        if (d.toString().contains('diet_plan_totals_row.dart')) {
          totalsRowErrors.add(d);
        }
      };
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(home: DietPlanScreen()),
      ));
      await _settle(tester);
    }

    /// Item 0 swapped for a free food: open the sheet, "Search any food",
    /// type [query], tap the hit, "Add to plan".
    Future<void> pickFree(WidgetTester tester, String query, String hitId,
        {int item = 0}) async {
      await tester.tap(find.byIcon(Icons.swap_horiz).at(item));
      await _settle(tester);
      await _tapReal(tester, _key('diet_swap_search_row'));
      await tester.enterText(_key('diet_search_field'), query);
      await _settle(tester);
      await _tapReal(tester, _key('diet_search_hit_$hitId'));
      await _tapReal(tester, _key('diet_portion_add'));
    }

    Finder dialog() => _key('diet_strategy_confirm_dialog');

    testWidgets('the totals row equals the sum of the item rows, and a swap '
        'moves it', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      expect(_key('diet_plan_totals_row'), findsOneWidget);
      expect(_cell(tester, 'calories'), _itemKcalOnScreen(tester));
      // a catalog swap: the first alternative of item 0
      await tester.tap(find.byIcon(Icons.swap_horiz).first);
      await _settle(tester);
      expect(_key('diet_swap_search_row'), findsOneWidget);
      await _tapReal(
          tester,
          find.descendant(
                  of: find.byType(BottomSheet), matching: find.byType(ListTile))
              .first);
      expect(_cell(tester, 'calories'), _itemKcalOnScreen(tester));
      expect(_savedPlan(), isNull, reason: 'a pick never saves the plan');
      expect(debugDietPlanGenerations, 1);
    });

    testWidgets('the swap sheet lists every alternative, not six, and ends '
        'with Search any food', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      var most = 0;
      final icons = find.byIcon(Icons.swap_horiz);
      final n = tester.widgetList(icons).length;
      for (var i = 0; i < n; i++) {
        await tester.tap(icons.at(i));
        await _settle(tester);
        final tiles = tester
            .widgetList(find.descendant(
                of: find.byType(BottomSheet), matching: find.byType(ListTile)))
            .length;
        if (tiles > most) most = tiles;
        expect(_key('diet_swap_search_row'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await _settle(tester);
      }
      expect(most, greaterThan(6),
          reason: 'a non-veg plan has more than six options for some item');
    });

    testWidgets('Keto + oats: the popup, accept -> Low carb, the plan keeps '
        'the oats and is NOT regenerated or saved', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      expect(debugDietPlanGenerations, 1);
      expect(_textOf(tester, 'diet_plan_fit_line'), startsWith('Fits Keto'));
      final before = _cell(tester, 'carbs');

      await pickFree(tester, 'rolled oats', 'F0695');
      expect(dialog(), findsOneWidget);
      final reason = tester
          .widget<Text>(_key('diet_strategy_confirm_reason'))
          .data!;
      expect(reason, contains('over the Keto limit'));
      expect(reason, contains('Your plan is now Low carb'));
      expect(reason, contains('Save the plan afterwards'));
      expect(_profileStrategy(), 'keto', reason: 'nothing written before Switch');

      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      expect(_profileStrategy(), 'low_carb');
      expect(find.text('Rolled Oats'), findsOneWidget);
      expect(_cell(tester, 'carbs'), greaterThan(before));
      expect(_cell(tester, 'calories'), _itemKcalOnScreen(tester));
      expect(debugDietPlanGenerations, 1, reason: 'the shift did not regenerate');
      expect(_savedPlan(), isNull, reason: 'a shift never saves the plan');
      expect(_textOf(tester, 'diet_plan_fit_line'), startsWith('Fits Low carb'));
      expect(find.text('Plan updated for Low carb. Save to keep it.'),
          findsOneWidget);
      expect(_key('diet_plan_back_up'), findsNothing);
    });

    testWidgets('cancel: nothing is written, the item is not swapped',
        (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      await pickFree(tester, 'rolled oats', 'F0695');
      expect(dialog(), findsOneWidget);
      await _tapReal(tester, _key('diet_strategy_confirm_cancel'));
      expect(_profileStrategy(), 'keto');
      expect(find.text('Rolled Oats'), findsNothing);
      expect(debugDietPlanGenerations, 1);
      expect(_textOf(tester, 'diet_plan_fit_line'), startsWith('Fits Keto'));
      // and the plan still follows Keto: a plain low-carb pick works normally
      await pickFree(tester, 'cucumber', cucumberId, item: 1);
      expect(dialog(), findsNothing);
      expect(find.text('Cucumber (raw)'), findsOneWidget);
    });

    testWidgets('back up: the oats go out, the row offers Back to Keto, the '
        'same dialog, no regeneration', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester, width: 360);
      await pickFree(tester, 'rolled oats', 'F0695');
      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      expect(_profileStrategy(), 'low_carb');
      expect(_key('diet_plan_back_up'), findsNothing);

      // the oats out again for a low-carb food: a pick that CUTS carbs asks
      // nothing, and the day fits Keto again
      await pickFree(tester, 'cucumber', cucumberId);
      expect(dialog(), findsNothing);
      expect(_profileStrategy(), 'low_carb');
      expect(_key('diet_plan_back_up'), findsOneWidget);
      expect(find.text('Back to Keto'), findsOneWidget);
      expect(tester.getSize(_key('diet_plan_totals_row')).height,
          lessThanOrEqualTo(kDietPlanTotalsRowMaxHeight));
      expect(totalsRowErrors, isEmpty);

      await _tapReal(tester, _key('diet_plan_back_up'));
      expect(dialog(), findsOneWidget);
      expect(_key('diet_strategy_confirm_keto_note'), findsOneWidget);
      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      expect(_profileStrategy(), 'keto');
      expect(_key('diet_plan_back_up'), findsNothing);
      expect(_textOf(tester, 'diet_plan_fit_line'), startsWith('Fits Keto'));
      expect(debugDietPlanGenerations, 1);
      expect(_savedPlan(), isNull);
    });

    testWidgets('a pick clears the saved check (the plan on screen is no '
        'longer the saved one)', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(_savedPlan(), isNotNull);
      await tester.tap(find.byIcon(Icons.swap_horiz).first);
      await _settle(tester);
      await _tapReal(
          tester,
          find.descendant(
                  of: find.byType(BottomSheet), matching: find.byType(ListTile))
              .first);
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('a free pick fills the REPLACED item\'s role: swapping it '
        'again still finds that role\'s alternatives', (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      // item 0 is in the Breakfast slot, where a vegetable has no role of its
      // own: only the inherited role can offer alternatives
      await pickFree(tester, 'cucumber', cucumberId);
      expect(find.text('Cucumber (raw)'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.swap_horiz).first);
      await _settle(tester);
      expect(_key('diet_swap_no_alternatives'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.byType(ListTile)),
          findsWidgets);
    });

    testWidgets('a free user (Keto paused) is Balanced: oats never ask',
        (tester) async {
      await seed(tester, pro: false, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      expect(_key('diet_plan_fit_line'), findsNothing);
      await pickFree(tester, 'rolled oats', 'F0695');
      expect(dialog(), findsNothing);
      expect(find.text('Rolled Oats'), findsOneWidget);
      expect(_profileStrategy(), 'keto', reason: 'the stored choice stays');
    });

    testWidgets('strategy flag off: no fit line and no popup', (tester) async {
      DietStrategyFlags.debugEnabledOverride = false;
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      expect(_key('diet_plan_fit_line'), findsNothing);
      await pickFree(tester, 'rolled oats', 'F0695');
      expect(dialog(), findsNothing);
      expect(find.text('Rolled Oats'), findsOneWidget);
    });

    // The pure rule (a carb-cutting pick on a plan over its ceiling never asks,
    // round 1 F1) is pinned by `shift(keto, 60, 55)` in
    // diet_plan_totals_and_fit_test.dart; this is the screen-level sequel.
    testWidgets('after an accepted shift, a carb-cutting pick does not ask '
        'again', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      await pickFree(tester, 'rolled oats', 'F0695');
      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      // a smaller carb source in place of the oats cuts carbs: no popup
      await pickFree(tester, 'cucumber', cucumberId);
      expect(dialog(), findsNothing);
    });
  });

  group('with Hive: the B-pass wiring tests', () {
    late Directory dir;
    late List<Map<String, dynamic>> rows;
    late String cucumberId;

    setUpAll(() {
      rows = (jsonDecode(File('assets/data/food_database.json')
              .readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      cucumberId =
          rows.firstWhere((r) => r['name'] == 'Cucumber (raw)')['id'] as String;
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
        {Map<String, dynamic> extra = const {}}) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields({..._pack, ...extra});
        await MigratedKey.write('isPro', true);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
    }

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final old = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: const MaterialApp(home: DietPlanScreen()),
      ));
      await _settle(tester);
    }

    Future<void> openSearch(WidgetTester tester, String query,
        {int item = 0}) async {
      await tester.tap(find.byIcon(Icons.swap_horiz).at(item));
      await _settle(tester);
      await _tapReal(tester, _key('diet_swap_search_row'));
      await tester.enterText(_key('diet_search_field'), query);
      await _settle(tester);
    }

    Finder anyHit() => find.byWidgetPredicate((w) =>
        w.key is ValueKey &&
        (w.key as ValueKey).value.toString().startsWith('diet_search_hit_'));

    testWidgets('B-pass A1: a CANCELLED shift hands the provisional request '
        'back: the plan saved afterwards is still stamped Keto', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      await openSearch(tester, 'rolled oats');
      await _tapReal(tester, _key('diet_search_hit_F0695'));
      await _tapReal(tester, _key('diet_portion_add'));
      expect(_key('diet_strategy_confirm_dialog'), findsOneWidget);
      await _tapReal(tester, _key('diet_strategy_confirm_cancel'));
      await _tapReal(tester, find.byIcon(Icons.save_outlined));
      final saved = _savedPlan()!;
      expect(saved['diet_strategy'], 'keto');
      expect(saved['diet_strategy_requested'], 'keto',
          reason: 'the provisional Low carb request must not leak into the stamp');
    });

    testWidgets('B-pass C4: a regeneration while the popup is open drops the '
        'pick and writes NOTHING (the screen wires isStale)', (tester) async {
      await seed(tester, extra: const {'diet_strategy': 'keto'});
      await pumpScreen(tester);
      await openSearch(tester, 'rolled oats');
      await _tapReal(tester, _key('diet_search_hit_F0695'));
      await _tapReal(tester, _key('diet_portion_add'));
      expect(_key('diet_strategy_confirm_dialog'), findsOneWidget);
      expect(debugDietPlanGenerations, 1);
      // the effective strategy moves under the open dialog (a restore, a PRO
      // flip): the listener regenerates the plan for it
      final container =
          ProviderScope.containerOf(tester.element(find.byType(DietPlanScreen)));
      await tester.runAsync(() => container
          .read(userProfileProvider.notifier)
          .setDietStrategy(DietStrategy.balanced));
      await _settle(tester);
      expect(debugDietPlanGenerations, 2, reason: 'the plan was rebuilt');
      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      expect(_profileStrategy(), 'balanced',
          reason: 'the stale accept wrote nothing');
      expect(find.text('Rolled Oats'), findsNothing);
      expect(find.text('The plan changed. Pick again.'), findsOneWidget);
    });

    testWidgets('B-pass C4: an adult finds a whey powder, a minor never does',
        (tester) async {
      final y = DateTime.now().year;
      await seed(tester, extra: {'date_of_birth': '${y - 30}-05-05'});
      await pumpScreen(tester);
      await openSearch(tester, 'whey');
      expect(anyHit(), findsWidgets, reason: 'an adult: powders are listed');
    });

    testWidgets('B-pass C4: a minor never sees a protein powder',
        (tester) async {
      final y = DateTime.now().year;
      await seed(tester, extra: {'date_of_birth': '${y - 15}-05-05'});
      await pumpScreen(tester);
      await openSearch(tester, 'whey');
      expect(anyHit(), findsNothing);
    });

    testWidgets('B-pass C4: a food already in the plan is not offered again',
        (tester) async {
      await seed(tester);
      await pumpScreen(tester);
      await openSearch(tester, 'cucumber');
      await _tapReal(tester, _key('diet_search_hit_$cucumberId'));
      await _tapReal(tester, _key('diet_portion_add'));
      expect(find.text('Cucumber (raw)'), findsOneWidget);
      await openSearch(tester, 'cucumber', item: 1);
      expect(_key('diet_search_hit_$cucumberId'), findsNothing,
          reason: 'it is already in the plan');
    });
  });

  group('handleDietStrategyTap guards', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      DietStrategyFlags.debugEnabledOverride = true;
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      UserProfileNotifier.debugFoodTypeEffects = FoodTypeWriteEffects(
        currentUserId: () => kTestUserId,
        pushSnapshot: () {},
        lockFields: (_) async {},
      );
    });

    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      UserProfileNotifier.debugFoodTypeEffects = null;
      await tearDownHiveForTests(dir);
    });

    Future<bool?> run(WidgetTester tester,
        {required bool Function() isStale,
        required void Function() beforeSwitch,
        bool silent = false,
        bool alwaysAsk = true,
        Map<String, dynamic> pack = _pack}) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields(pack);
        await MigratedKey.write('isPro', true);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
      bool? result;
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const ValueKey('go'),
                onPressed: () async {
                  result = await handleDietStrategyTap(
                    context,
                    ref,
                    DietStrategy.lowCarb,
                    current: DietStrategy.balanced,
                    reason: 'because of a swap',
                    alwaysAsk: alwaysAsk,
                    isStale: isStale,
                    silent: silent,
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await _tapReal(tester, _key('go'));
      expect(_key('diet_strategy_confirm_dialog'), findsOneWidget);
      expect(find.text('because of a swap'), findsOneWidget);
      beforeSwitch();
      await _tapReal(tester, _key('diet_strategy_confirm_switch'));
      return result;
    }

    // 20 g of carbs already sit under Low carb's 120 g: no shown number moves
    // (4 x 150 + 4 x 20 + 9 x 191 = 2400 kcal).
    const tight = <String, dynamic>{
      'full_name': 'T',
      'daily_calories': 2400,
      'protein_grams': 150,
      'carb_grams': 20,
      'carbs_grams': 20,
      'fat_grams': 191,
    };

    testWidgets('alwaysAsk asks even when no shown target would move',
        (tester) async {
      final r = await run(tester,
          isStale: () => false, beforeSwitch: () {}, pack: tight);
      expect(r, isTrue);
      expect(_profileStrategy(), 'low_carb');
    });

    testWidgets('without alwaysAsk the same change writes with no dialog '
        '(the chip tap\'s behaviour is unchanged)', (tester) async {
      await tester.runAsync(() async {
        await UserRepository.instance.updateProfileFields(tight);
        await MigratedKey.write('isPro', true);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      });
      bool? result;
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const ValueKey('go'),
                onPressed: () async {
                  result = await handleDietStrategyTap(
                      context, ref, DietStrategy.lowCarb,
                      current: DietStrategy.balanced);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await _tapReal(tester, _key('go'));
      expect(_key('diet_strategy_confirm_dialog'), findsNothing);
      expect(result, isTrue);
      expect(_profileStrategy(), 'low_carb');
    });

    testWidgets('a stale pick writes NOTHING (the plan was rebuilt while the '
        'dialog was open)', (tester) async {
      var stale = false;
      final r = await run(tester,
          isStale: () => stale, beforeSwitch: () => stale = true);
      expect(r, isFalse);
      expect(_profileStrategy(), isNull);
    });

    testWidgets('not stale: written, returns true; silent says nothing, '
        'not silent says it', (tester) async {
      final r = await run(tester,
          isStale: () => false, beforeSwitch: () {}, silent: true);
      expect(r, isTrue);
      expect(_profileStrategy(), 'low_carb');
      expect(find.textContaining('updated'), findsNothing);
      expect(find.textContaining('Low carb is set'), findsNothing);
    });

    testWidgets('not silent: the success snackbar shows', (tester) async {
      final r = await run(tester, isStale: () => false, beforeSwitch: () {});
      expect(r, isTrue);
      expect(find.textContaining('Low carb'), findsWidgets);
      expect(DietPlanFlags.curatedEnabled, isTrue);
    });
  });

  test('PRESENCE: the guards the behavioral tests cannot reach', () {
    final swap = File('lib/features/nutrition/screens/diet_plan_screen_swap.dart')
        .readAsStringSync();
    // the post-write epoch re-check (round 2 N2): a regeneration that lands
    // during the profile write drops the pick and sets no stamp
    final afterWrite = swap.substring(swap.indexOf('written = await handleDietStrategyTap'));
    expect(afterWrite.indexOf('epoch != _planEpoch || !mounted'),
        lessThan(afterWrite.indexOf('_droppedFrom ??= from')));
    // both flows (a pick and Back to ...) hold the busy flag and let go of it
    // in a finally, after handing back an uncommitted provisional request
    expect('_pickBusy = true'.allMatches(swap).length, 2);
    expect('      _pickBusy = false;\n    }'.allMatches(swap).length, 2);
    expect('_requestedStrategy = previousRequested;'.allMatches(swap).length, 2);
    // a pick never saves the plan (round 3 D1)
    expect(swap, isNot(contains('_savePlan')));
    expect(swap, isNot(contains('saveDietPlan')));
    // the request is set BEFORE the write (the regeneration listener)
    expect(
        swap.indexOf('_requestedStrategy = planStrategyFor(next, _foodType);'),
        lessThan(swap.indexOf('written = await handleDietStrategyTap')));
    // the PDF carries the total line
    final screen = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    expect(screen, contains('planTotalLine: _planTotalLine(targets)'));
    expect(screen.split('\n').length, lessThanOrEqualTo(800));
  });
}
