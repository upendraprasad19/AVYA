// OI-348 Landing 3b (plan docs/plans/oi348-landing3b.md, founder P5): a coach
// meal shows one row per food and is saved only on a tap. No 5 s auto-save
// for a food tag; a food card waits at most an hour.
//
// Writers: lib/features/ai_coach/services/conversational_log_handler.dart
//   _logFood (coachItemsFromTag) and tool_dispatcher.dart
//   _executeLogMealByText (coachToolOverrides) -> CoachMealLog.write ->
//   NutritionWriteService.logMeal (totals via mealTotals).
// Readers: LogConfirmCard (food variant), ToolConfirmCard (meal rows),
//   CoachMealItemsView, the nlog_ row, PendingLogActionsNotifier.addActions
//   (stale-food sweep).
//
// Fonts render first (before Hive mocks path_provider); Hive per test.
//
// closes-diagnose: docs/diagnoses/2026-11-26-coach-meal-tag-example-copied-b3f7a1.md
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_meal_log.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/log_confirm_card.dart';
import 'package:icanbefitter/features/ai_coach/widgets/tool_confirm_card.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// The media prompt's food example (OI-348 Landing 3b), copied from
/// supabase/functions/_shared/write_claim_prompt.ts MEDIA_FOOD_ITEMS_TAG_LINE
/// (the Deno test pins the same JSON). Keep the two in step.
const Map<String, dynamic> _mediaExample = {
  'food_name': 'Idli and Sambar',
  'quantity_g': 270,
  'calories_estimate': 270,
  'protein_estimate': 10,
  'carbs_estimate': 50,
  'fat_estimate': 4,
  'items': [
    {
      'name': 'Idli',
      'quantity_g': 120,
      'calories': 160,
      'protein_g': 5,
      'carbs_g': 34,
      'fat_g': 1,
    },
    {
      'name': 'Sambar',
      'quantity_g': 150,
      'calories': 110,
      'protein_g': 5,
      'carbs_g': 16,
      'fat_g': 3,
    },
  ],
};

class _Seeded extends PendingLogActionsNotifier {
  _Seeded(this.seed);
  final List<PendingLogAction> seed;
  @override
  List<PendingLogAction> build() => [...seed];
}

/// 10:00 IST on 2026-11-26 (a lunch-free hour in Kolkata: breakfast).
final _t0 = DateTime.utc(2026, 11, 26, 4, 30);

PendingLogAction _food(String id, Map<String, dynamic> data,
        {DateTime? createdAt}) =>
    PendingLogAction(
      id: id,
      type: LogActionType.food,
      data: data,
      displayText: 'meal',
      createdAt: createdAt ?? _t0,
    );

ToolIntent _mealIntent(Map<String, dynamic> payload, {DateTime? createdAt}) =>
    ToolIntent(
      id: 'meal-intent',
      type: 'log_meal_by_text',
      payload: {
        'original_description': 'idli sambar',
        'food_name': 'Idli, Sambar',
        ...payload,
      },
      confirmationClass: ConfirmationClass.trivial,
      previewSummary: 'Idli, Sambar',
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );

List<Map<String, dynamic>> _nlogRows() => HiveService.instance.nutritionBox
    .toMap()
    .entries
    .where((e) => e.key.toString().startsWith('nlog_') && e.value is Map)
    .map((e) => Map<String, dynamic>.from(e.value as Map))
    .toList();

void main() {
  // ── pure rules (no Hive) ───────────────────────────────────────────────

  group('pure', () {
    tearDown(() => debugCoachMealItemsCardDisabled = null);

    test('T7 coachItemsFromTag: items win; unusable entries are skipped; '
        'none usable falls back to the flat item', () {
      final two = coachItemsFromTag(_mediaExample)!;
      expect(two.map((i) => i.name), ['Idli', 'Sambar']);
      expect(two.map((i) => i.quantityG), [120.0, 150.0]);
      expect(two.map((i) => i.calories), [160.0, 110.0]);

      final mixed = coachItemsFromTag({
        'food_name': 'x',
        'calories_estimate': 99,
        'items': [
          {'name': 'Good', 'calories': 50, 'quantity_g': 0},
          {'name': '  ', 'calories': 50},
          {'name': 'NoCal'},
          {'name': 'Neg', 'calories': -5},
          {'name': 'NaN', 'calories': double.nan},
          'junk',
        ],
      })!;
      expect(mixed.map((i) => i.name), ['Good']);
      expect(mixed.single.quantityG, 100.0, reason: 'grams <= 0 -> 100');

      for (final items in [null, <Object>[], [{'name': ''}]]) {
        final out = coachItemsFromTag({
          'food_name': 'Poha',
          'calories_estimate': 270,
          'items': ?items,
        })!;
        expect(out.single.name, 'Poha', reason: 'fallback for $items');
      }
      expect(coachItemsFromTag({'food_name': 'x'}), isNull);
      // Items alone are enough with the card on (R2-6).
      expect(
          coachItemsFromTag({
            'items': [
              {'name': 'Roti', 'calories': 210},
            ],
          })!
              .single
              .name,
          'Roti');
    });

    test('T7 kill switch: the flat item only, items ignored', () {
      debugCoachMealItemsCardDisabled = true;
      final out = coachItemsFromTag(_mediaExample)!;
      expect(out.single.name, 'Idli and Sambar');
      expect(out.single.calories, 270.0);
      expect(
          coachItemsFromTag({
            'items': [
              {'name': 'Roti', 'calories': 210},
            ],
          }),
          isNull);
    });

    test('T14 coachToolOverrides truncates like the dispatcher and never '
        'throws on a wrong type', () {
      expect(coachToolOverrides({'total_calories': 359.9, 'total_protein_g': 12.7}),
          (cals: 359, protein: 12));
      for (final bad in ['300', null, double.nan, <int>[], double.infinity]) {
        expect(
            coachToolOverrides({'total_calories': bad, 'total_protein_g': bad}),
            (cals: 0, protein: 0),
            reason: 'value $bad');
      }
    });

    test('mealTotals: override only when > 0; Atwater fallback; one rounding',
        () {
      const a = FoodItem(
          name: 'A', quantityG: 100, calories: 100.4, protein: 3.4,
          carbs: 0, fat: 0, fiber: 0);
      const b = FoodItem(
          name: 'B', quantityG: 100, calories: 0, protein: 2,
          carbs: 10, fat: 1, fiber: 0);
      final t = NutritionWriteService.mealTotals([a, b]);
      expect(t.kcal, (100.4 + b.kcalWithFallback).round());
      expect(t.protein, 5);
      expect(NutritionWriteService.mealTotals([a], overrideCals: 0).kcal, 100);
      expect(
          NutritionWriteService.mealTotals([a],
              overrideCals: 300, overrideProtein: 20),
          (kcal: 300, protein: 20));
    });

    test('T11 isStaleFood: only food, only past the hour, only with the card on',
        () {
      final f = _food('f', {}, createdAt: _t0);
      expect(f.isStaleFood(_t0.add(const Duration(minutes: 59))), isFalse);
      expect(f.isStaleFood(_t0.add(const Duration(minutes: 61))), isTrue);
      final water = PendingLogAction(
          id: 'w', type: LogActionType.water, data: const {'ml': 250},
          displayText: '250ml', createdAt: _t0);
      expect(water.isStaleFood(_t0.add(const Duration(days: 2))), isFalse);
      debugCoachMealItemsCardDisabled = true;
      expect(f.isStaleFood(_t0.add(const Duration(days: 2))), isFalse);
    });

    test('B-pass F3 coachTagUnusableItemCount: every skipped entry counts; '
        '0 with the card off or no list', () {
      final data = {
        'food_name': 'x',
        'calories_estimate': 99,
        'items': [
          {'name': 'Good', 'calories': 50},
          {'name': '  ', 'calories': 50},
          {'name': 'NoCal'},
          {'name': 'Str', 'calories': '160'},
          {'name': 'Neg', 'calories': -5},
          'junk',
        ],
      };
      expect(coachTagUnusableItemCount(data), 5);
      expect(coachTagUnusableItemCount(_mediaExample), 0);
      expect(coachTagUnusableItemCount({'food_name': 'x'}), 0);
      debugCoachMealItemsCardDisabled = true;
      expect(coachTagUnusableItemCount(data), 0);
    });

    test('B-pass F2 coachMealTypeOf: a String or null, never a throw', () {
      expect(coachMealTypeOf({'meal_type': 'lunch'}), 'lunch');
      for (final bad in [3, 2.5, <String>['lunch'], {'a': 1}, null, true]) {
        expect(coachMealTypeOf({'meal_type': bad}), isNull, reason: '$bad');
      }
      expect(coachMealTypeOf({}), isNull);
    });
  });

  // Fonts must be cached before any test mocks path_provider.
  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Text('a', style: AppTypography.mono),
        Text('b', style: AppTypography.monoXs),
        Text('c', style: AppTypography.bodySm),
        Text('d', style: AppTypography.body),
        Text('e', style: AppTypography.titleS),
        Text('f', style: AppTypography.bodyM),
      ]),
    ));
  });

  group('cards (real Hive)', () {
    final events = <String>[];

    setUp(() async {
      await nwsTestSetup();
      if (!Hive.isBoxOpen(HiveService.configBoxName)) {
        await Hive.openBox(HiveService.configBoxName);
      }
      SyncService.pausedForSimulation = true;
      CoachMealLog.debugBadgeCheck = () {};
      events.clear();
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => events.add(op);
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required String reason, Map<String, String>? extra}) =>
              events.add('nonfatal:$reason');
      setTestClockTo(_t0.add(const Duration(minutes: 2)));
    });

    tearDown(() async {
      debugCoachMealItemsCardDisabled = null;
      CoachMealLog.debugBadgeCheck = null;
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      SyncService.pausedForSimulation = false;
      resetTestClock();
      await nwsTestTeardown();
    });

    ProviderContainer container(List<PendingLogAction> seed) {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('u'),
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        pendingLogActionsProvider.overrideWith(() => _Seeded(seed)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> pumpCard(WidgetTester tester, ProviderContainer c,
        PendingLogAction action,
        {double width = 411}) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LogConfirmCard(action: action)),
          ),
        ),
      ));
    }

    LogConfirmCardTestHandle handleOf(WidgetTester tester) =>
        LogConfirmCardTestHandle(tester);

    testWidgets('T1/T2/T8 a food tag card shows each food and the total, '
        'never starts a timer, and logs both foods only on CONFIRM',
        (tester) async {
      final action = _food('t1', _mediaExample);
      final c = container([action]);
      await pumpCard(tester, c, action);

      expect(find.byKey(const Key('coach_food_card')), findsOneWidget);
      expect(find.text('Idli'), findsOneWidget);
      expect(find.text('Sambar'), findsOneWidget);
      expect(find.text('Total  270 kcal · 10g protein'), findsOneWidget);
      expect(find.text('BREAKFAST'), findsOneWidget,
          reason: 'no meal_type: the clock slot (10:02 IST)');
      expect(handleOf(tester).countdown.isAnimating, isFalse,
          reason: 'no countdown for a food card');

      await tester.pump(const Duration(seconds: 6));
      expect(_nlogRows(), isEmpty, reason: 'nothing saves without a tap');
      expect(action.isLogged, isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('coach_food_card_confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 2));

      final rows = _nlogRows();
      expect(rows, hasLength(1));
      final items = (rows.single['items'] as List).cast<Map>();
      expect(items.map((i) => i['name']), ['Idli', 'Sambar']);
      expect(items.map((i) => i['quantity_g']), [120.0, 150.0]);
      expect(rows.single['total_calories'], 270,
          reason: 'T10: the card total is the stored total');
      expect(rows.single['total_protein'], 10);
      expect(action.isLogged, isTrue);
    });

    testWidgets('T8 a remounted food card starts no timer either',
        (tester) async {
      final action = _food('t8', _mediaExample);
      final c = container([action]);
      await pumpCard(tester, c, action);
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, c, action);
      expect(handleOf(tester).countdown.isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(_nlogRows(), isEmpty);
    });

    testWidgets('T3 mirror: a water tag still auto-saves at 5 s',
        (tester) async {
      final action = PendingLogAction(
          id: 'w1', type: LogActionType.water, data: const {'ml': 250},
          displayText: '250ml water', createdAt: _t0);
      final c = container([action]);
      await pumpCard(tester, c, action);
      expect(find.byKey(const Key('coach_food_card')), findsNothing);
      // The 5 s timer runs (its save is the existing behaviour, pinned by the
      // write-claim and single-write suites; driving a timer-fired Hive write
      // inside fake time hangs the test).
      expect(handleOf(tester).countdown.isAnimating, isTrue);
      expect(handleOf(tester).countdown.duration, const Duration(seconds: 5));
    });

    testWidgets('T4/T9 kill switch through the real configBox: the old 5 s '
        'food card, one item', (tester) async {
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_coach_meal_items_card', true));
      final action = _food('t4', _mediaExample);
      final c = container([action]);
      await pumpCard(tester, c, action);
      expect(find.byKey(const Key('coach_food_card')), findsNothing);
      expect(handleOf(tester).countdown.isAnimating, isTrue,
          reason: 'the old food card counts down again');
      // Its save writes the ONE flat item (tapped, not timer-fired: see T3).
      await tester.runAsync(() async {
        await tester.tap(find.text('CONFIRM'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 2));
      final rows = _nlogRows();
      expect(rows, hasLength(1));
      expect(((rows.single['items'] as List).single as Map)['name'],
          'Idli and Sambar');
    });

    testWidgets('T9 an absent key means the card is on', (tester) async {
      expect(HiveService.instance.configBox.get('disable_coach_meal_items_card'),
          isNull);
      expect(coachMealItemsCardEnabled(), isTrue);
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_coach_meal_items_card', false));
      expect(coachMealItemsCardEnabled(), isTrue);
    });

    testWidgets('T11 a food card past its hour shows Expired, has no CONFIRM, '
        'and a late tap on a card built inside the hour writes nothing',
        (tester) async {
      final action = _food('t11', _mediaExample);
      final c = container([action]);
      setTestClockTo(_t0.add(const Duration(minutes: 61)));
      await pumpCard(tester, c, action);
      expect(find.text('EXPIRED: MEAL'), findsOneWidget);
      expect(find.byKey(const Key('coach_food_card_confirm')), findsNothing);

      // Built at 59 min, tapped at 61 min.
      final late = _food('t11b', _mediaExample);
      final c2 = container([late]);
      setTestClockTo(_t0.add(const Duration(minutes: 59)));
      await pumpCard(tester, c2, late);
      setTestClockTo(_t0.add(const Duration(minutes: 61)));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('coach_food_card_confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 1));
      expect(_nlogRows(), isEmpty);
      expect(find.text('This suggestion has expired.'), findsOneWidget);
      expect(late.isLogged, isFalse);
    });

    testWidgets('T11 a tap at 59 min logs on createdAt\'s IST day across '
        'midnight', (tester) async {
      // Created 23:50 IST on 2026-11-26, tapped 00:49 IST on 2026-11-27.
      final at = DateTime.utc(2026, 11, 26, 18, 20);
      final action = _food('mid', _mediaExample, createdAt: at);
      final c = container([action]);
      setTestClockTo(at.add(const Duration(minutes: 59)));
      await pumpCard(tester, c, action);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('coach_food_card_confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(seconds: 2));
      expect(_nlogRows().single['date'], '2026-11-26');
    });

    testWidgets('T11b the sweep drops a stale food card but never one whose '
        'save is running, nor a logged one, nor another type', (tester) async {
      final stale = _food('stale', _mediaExample);
      final running = _food('running', _mediaExample);
      final logged = _food('logged', _mediaExample)..isLogged = true;
      final water = PendingLogAction(
          id: 'w', type: LogActionType.water, data: const {'ml': 250},
          displayText: '250ml', createdAt: _t0);
      final c = container([stale, running, logged, water]);
      final hold = Completer<bool>();
      ConversationalLogHandler.debugSetInFlight('running', hold.future);
      addTearDown(() => ConversationalLogHandler.debugSetInFlight('running', null));

      // 60:01: a new reply arrives and sweeps.
      setTestClockTo(_t0.add(const Duration(minutes: 60, seconds: 1)));
      c.read(pendingLogActionsProvider.notifier).addActions(
          const [], c.read(_refProvider));
      final ids = c.read(pendingLogActionsProvider).map((a) => a.id).toList();
      expect(ids, ['running', 'logged', 'w'],
          reason: 'only the stale, idle, unlogged food card goes');
      expect(stale.isDismissed, isFalse,
          reason: 'removed, never dismissed (dismissed fades a mounted card)');

      // The held save finishes: markLogged still finds its action.
      hold.complete(true);
      ConversationalLogHandler.debugSetInFlight('running', null);
      c.read(pendingLogActionsProvider.notifier).markLogged('running');
      expect(running.isLogged, isTrue);

      // Inside the hour nothing goes.
      final fresh = _food('fresh', _mediaExample,
          createdAt: _t0.add(const Duration(minutes: 30)));
      final c2 = container([fresh]);
      c2.read(pendingLogActionsProvider.notifier).addActions(
          const [], c2.read(_refProvider));
      expect(c2.read(pendingLogActionsProvider).single.id, 'fresh');
    });

    testWidgets('T13 the food card lays out at 320 dp and 411 dp with a long '
        'name and four foods', (tester) async {
      final data = {
        'food_name': 'x',
        'calories_estimate': 1,
        'items': [
          for (var i = 0; i < 4; i++)
            {
              'name': 'Paneer butter masala with extra cream and kasuri methi $i',
              'quantity_g': 1250,
              'calories': 1234,
              'protein_g': 123,
              'carbs_g': 456,
              'fat_g': 78,
            },
        ],
      };
      for (final w in [320.0, 411.0]) {
        final action = _food('t13-$w', data);
        final c = container([action]);
        await pumpCard(tester, c, action, width: w);
        expect(tester.takeException(), isNull, reason: 'overflow at $w dp');
        expect(find.byKey(const Key('coach_meal_item_3')), findsOneWidget);
      }
    });

    testWidgets('B-pass F1 an expired food card keeps SKIP, and SKIP clears it',
        (tester) async {
      final action = _food('f1', _mediaExample);
      final c = container([action]);
      setTestClockTo(_t0.add(const Duration(minutes: 61)));
      await pumpCard(tester, c, action);
      expect(find.text('EXPIRED: MEAL'), findsOneWidget);
      expect(find.byKey(const Key('coach_food_card_confirm')), findsNothing);
      expect(find.byKey(const Key('coach_food_card_skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('coach_food_card_skip')));
      await tester.pump();
      expect(c.read(pendingLogActionsProvider), isEmpty);
      expect(_nlogRows(), isEmpty);
    });

    testWidgets('B-pass F1 a reply with NO tags still clears an expired card '
        '(dropStaleFood, public)', (tester) async {
      final stale = _food('s', _mediaExample);
      final c = container([stale]);
      setTestClockTo(_t0.add(const Duration(minutes: 61)));
      c.read(pendingLogActionsProvider.notifier).dropStaleFood();
      expect(c.read(pendingLogActionsProvider), isEmpty);
    });

    test('B-pass F1 every reply path sweeps before its tag guard', () {
      final src = File('lib/features/ai_coach/providers/ai_coach_provider.dart')
          .readAsStringSync();
      const sweep = 'ref.read(pendingLogActionsProvider.notifier).dropStaleFood();';
      expect(sweep.allMatches(src).length, 3,
          reason: 'media, send and the auth retry');
      for (final guard in [
        'if (aiResponse.actions.isNotEmpty) {',
        'if (retryResponse.actions.isNotEmpty) {',
      ]) {
        var at = src.indexOf(guard);
        expect(at, isNot(-1), reason: guard);
        while (at != -1) {
          final before = src.substring(0, at).trimRight();
          expect(before.endsWith(sweep), isTrue,
              reason: 'the line before $guard at offset $at sweeps');
          at = src.indexOf(guard, at + 1);
        }
      }
    });

    testWidgets('B-pass F2/F3 a tag with a non-String meal_type and a partial '
        'items list: one card on the clock slot, the skip reported',
        (tester) async {
      final c = container(const []);
      final data = <String, dynamic>{
        'meal_type': 3,
        'items': [
          {'name': 'Roti', 'calories': 210},
          {'name': 'Dal', 'calories': '150'},
        ],
      };
      c.read(pendingLogActionsProvider.notifier).addActions([
        {'action': 'log_food', 'data': data},
      ], c.read(_refProvider));
      final a = c.read(pendingLogActionsProvider).single;
      expect(a.displayText, 'Roti — Breakfast');
      expect(events, contains('coach_food_tag_items_partial'));
      await pumpCard(tester, c, a);
      expect(find.text('BREAKFAST'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T12 the media example through addActions: one food card, '
        'two foods; without items[] (the +50 shape) one item', (tester) async {
      final c = container(const []);
      final n = c.read(pendingLogActionsProvider.notifier);
      n.addActions([
        {'action': 'log_food', 'data': _mediaExample},
      ], c.read(_refProvider));
      final a = c.read(pendingLogActionsProvider).single;
      expect(a.type, LogActionType.food);
      expect(coachItemsFromTag(a.data)!.map((i) => i.name), ['Idli', 'Sambar']);
      expect(a.displayText, startsWith('Idli and Sambar'));

      final flat = Map<String, dynamic>.from(_mediaExample)..remove('items');
      expect(coachItemsFromTag(flat)!.single.name, 'Idli and Sambar');

      // An items-only tag gets a card named from its items.
      n.addActions([
        {
          'action': 'log_food',
          'data': {
            'items': [
              {'name': 'Roti', 'calories': 210},
              {'name': 'Dal', 'calories': 150},
            ],
          },
        },
      ], c.read(_refProvider));
      expect(c.read(pendingLogActionsProvider).last.displayText,
          startsWith('Roti · Dal'));
    });

    // ── the tool card ──────────────────────────────────────────────────

    Future<void> pumpTool(WidgetTester tester, ToolIntent intent) async {
      tester.view.physicalSize = const Size(411 * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [authUserIdTokenProvider.overrideWithValue('u')],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ToolConfirmCard(intent: intent)),
          ),
        ),
      ));
      await tester.pump();
    }

    Map<String, dynamic> parsed({Object? total, Object? protein}) => {
          'meal_type': null,
          'total_calories': total,
          'total_protein_g': protein,
          'confidence': 'high',
          'items': [
            {'name': 'Roti', 'calories': 210.0, 'protein_g': 6.0,
             'carbs_g': 36.0, 'fat_g': 4.0, 'fiber_g': 2.0},
            {'name': 'Dal', 'calories': 150.0, 'protein_g': 9.0,
             'carbs_g': 20.0, 'fat_g': 3.0, 'fiber_g': 4.0},
          ],
        };

    for (final (label, total, protein) in [
      ('fractional payload totals', 361.9, 15.6),
      ('payload total 0', 0, 0),
      ('wrong-typed totals', '361', null),
    ]) {
      testWidgets('T5/T10 tool card ($label): each food, the stored total, '
          'nothing written before APPLY', (tester) async {
        final intent = _mealIntent(parsed(total: total, protein: protein),
            createdAt: DateTime.now().toUtc());
        await pumpTool(tester, intent);
        expect(find.text('Roti'), findsOneWidget);
        expect(find.text('Dal'), findsOneWidget);
        expect(find.textContaining(' g'), findsNothing,
            reason: 'parser items have no grams');
        expect(_nlogRows(), isEmpty);

        final shown = find
            .byKey(const Key('coach_meal_total'))
            .evaluate()
            .single
            .widget as Text;

        final c = ProviderContainer(overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
        ]);
        addTearDown(c.dispose);
        final res = await tester.runAsync(() => ToolDispatcher.instance
            .execute(c.read(_refProvider), intent));
        // A wrong-typed total used to throw in the dispatcher (the intent
        // failed); now it is 0, so the items' sum is stored and shown.
        expect(res!.success, isTrue, reason: res.errorMessage);
        final row = _nlogRows().single;
        expect(shown.data,
            'Total  ${row['total_calories']} kcal · ${row['total_protein']}g protein');
      });
    }

    testWidgets('T6 tool card, kill switch: the old one-line summary',
        (tester) async {
      debugCoachMealItemsCardDisabled = true;
      await pumpTool(tester, _mealIntent(parsed(total: 360, protein: 15)));
      expect(find.text('Roti'), findsNothing);
      expect(find.text('Idli, Sambar — 360 kcal · 15g protein'),
          findsOneWidget);
    });
  });
}

/// Reaches the card's countdown through its test getter.
class LogConfirmCardTestHandle {
  LogConfirmCardTestHandle(this.tester);
  final WidgetTester tester;
  AnimationController get countdown {
    final state =
        tester.state<LogConfirmCardState>(find.byType(LogConfirmCard));
    return state.debugCountdown;
  }
}
