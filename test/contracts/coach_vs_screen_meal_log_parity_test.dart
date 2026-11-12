// OI-493 Landing A (plan docs/plans/oi493-nutrition-parity.md section 4,
// P1-P9): a meal logged from the AI coach stores and counts the same as one
// logged on the Nutrition screen, whichever coach door it came through.
//
// Writer: lib/features/ai_coach/services/coach_meal_log.dart CoachMealLog.write
//   (called by ToolDispatcher._executeLogMealByText and
//   ConversationalLogHandler._logFood) -> NutritionWriteService.logMeal.
// Readers: the nlog_ row (date, meal_type, items[]), the coach snapshot
//   meals_today, NutritionReadService.shortMealDisplayName (delete title,
//   template default name), recentLoggedItems / relogItem (Search tab recent
//   list), the recent_deletes audit entry.
//
// Real Hive (nws_test_setup), the IST clock seam, and the real dispatcher and
// handler. Run under TZ=Asia/Kolkata, UTC and Asia/Tokyo: the slot is read
// from the device-local hour, the day from the IST date.
//
// closes-diagnose: see docs/diagnoses/2026-11-12-coach-meal-parity-*.md
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_meal_log.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/meal_slot_inference.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_modes/search_mode_body.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// Per-zone expectation for an instant whose IST day is 2026-11-12 in every
/// zone the suite runs under (P4).
const _p4Instant = '2026-11-12T07:30:00Z';
const _p4ByOffsetMinutes = {
  330: 'lunch', // Asia/Kolkata 13:00
  540: 'snacks', // Asia/Tokyo 16:30
  0: 'breakfast', // UTC 07:30
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final events = <String>[];
  var seq = 0;

  setUp(() async {
    await nwsTestSetup();
    // The shared boxes main.dart opens before runApp (the badge check reads
    // configBox); nws_test_setup opens only the user-scoped ones.
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      if (!Hive.isBoxOpen(name)) await Hive.openBox(name);
    }
    SyncService.pausedForSimulation = true;
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {String? message}) => events.add(op);
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required String reason, Map<String, String>? extra}) =>
            events.add('nonfatal:$reason');
  });

  tearDown(() async {
    CoachMealLog.debugBadgeCheck = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    SyncService.pausedForSimulation = false;
    resetTestClock();
    await nwsTestTeardown();
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// ConversationalLogHandler takes a WidgetRef, which is sealed: capture a
  /// real one from a Consumer bound to [c]. Hive I/O then runs in runAsync.
  Future<WidgetRef> captureRef(WidgetTester tester, ProviderContainer c) async {
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(builder: (_, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));
    return ref;
  }

  Future<bool> runTag(WidgetTester tester, ProviderContainer c,
      PendingLogAction action) async {
    final ref = await captureRef(tester, c);
    final ok = await tester.runAsync(
        () => ConversationalLogHandler(ref).executeAction(action));
    await tester.pumpWidget(const SizedBox());
    return ok ?? false;
  }

  List<Map<String, dynamic>> nlogRows() => HiveService
      .instance.nutritionBox
      .toMap()
      .entries
      .where((e) => e.key.toString().startsWith('nlog_') && e.value is Map)
      .map((e) => Map<String, dynamic>.from(e.value as Map))
      .toList();

  Map<String, dynamic> onlyRow() {
    final rows = nlogRows();
    expect(rows, hasLength(1), reason: 'exactly one meal row');
    return rows.single;
  }

  List<Map<String, dynamic>> itemsOf(Map<String, dynamic> row) =>
      (row['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// A server intent exactly as `ToolIntent.fromJson` builds it: a
  /// UTC-flagged `createdAt` from an ISO `Z` string.
  ToolIntent mealIntent({
    required DateTime createdAt,
    Map<String, dynamic> extra = const {},
    List<Map<String, dynamic>>? items,
  }) =>
      ToolIntent.fromJson({
        'id': 'meal_${seq++}',
        'type': 'log_meal_by_text',
        'confirmationClass': 'trivial',
        'previewSummary': 'Dal chawal',
        'createdAt': createdAt.toUtc().toIso8601String(),
        'payload': {
          'original_description': 'dal chawal 2 katoris',
          'date': null,
          'meal_type': null,
          'food_name': 'Dal chawal',
          'total_calories': 450,
          'total_protein_g': 18,
          'total_carbs_g': 60,
          'total_fat_g': 12,
          'serving_description': '2 katori dal + 1 katori chawal',
          'confidence': 'high',
          'items': items ??
              [
                {
                  'name': 'Dal',
                  'quantity': '2 katori',
                  'calories': 250,
                  'protein_g': 12,
                  'carbs_g': 30,
                  'fat_g': 6,
                  'fiber_g': 8,
                },
                {
                  'name': 'Chawal',
                  'quantity': '1 katori',
                  'calories': 200,
                  'protein_g': 6,
                  'carbs_g': 30,
                  'fat_g': 6,
                  'fiber_g': 1,
                },
              ],
          ...extra,
        },
      });

  Future<ToolExecutionResult> dispatch(ProviderContainer c, ToolIntent i) =>
      ToolDispatcher.instance.execute(c.read(_refProvider), i);

  /// A recent instant (the dispatcher refuses an intent over an hour old by
  /// the real clock), UTC-flagged like a server stamp.
  DateTime recentCreatedAt() =>
      DateTime.now().toUtc().subtract(const Duration(minutes: 1));

  // ── P1/P2/P3: the day is the IST day of the reported instant ──────────

  group('day', () {
    test(
        'P1 a meal reported at 01:00 IST (19:30Z the day before) logs on the '
        'IST day, in any host zone', () async {
      final at = DateTime.parse('2026-11-11T19:30:00Z');
      final r = await CoachMealLog.write(
          at: at,
          mealType: null,
          items: coachItemsFromParsedMeal(mealIntent(createdAt: at).payload));
      expect(r.success, isTrue);
      expect(onlyRow()['date'], '2026-11-12');
    });

    test(
        'P2 a meal reported at 23:55 IST and applied at 00:05 IST logs on the '
        'reporting day', () async {
      final at = DateTime.parse('2026-11-12T18:25:00Z'); // 23:55 IST
      setTestClockTo(DateTime.parse('2026-11-12T18:35:00Z')); // 00:05 IST
      final r = await CoachMealLog.write(
          at: at, mealType: 'dinner', items: coachItemsFromParsedMeal({}));
      expect(r.success, isTrue);
      expect(onlyRow()['date'], '2026-11-12');
    });

    test(
        'P1/P2 door: the tool logs on the intent createdAt day, not the apply '
        'clock (seam a day later)', () async {
      final c = container();
      final createdAt = recentCreatedAt();
      setTestClockTo(createdAt.add(const Duration(days: 1)));
      final res = await dispatch(c, mealIntent(createdAt: createdAt));
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(onlyRow()['date'], istDateStr(createdAt));
    });

    for (final (label, date) in [
      ('yesterday', 'Y'),
      ('tomorrow', 'T'),
      ('malformed', 'not-a-date'),
    ]) {
      test('P3 a payload date ($label) is ignored: the createdAt day wins',
          () async {
        final c = container();
        final createdAt = recentCreatedAt();
        final payloadDate = date == 'Y'
            ? istDateStr(createdAt.subtract(const Duration(days: 1)))
            : date == 'T'
                ? istDateStr(createdAt.add(const Duration(days: 1)))
                : date;
        final res = await dispatch(
            c, mealIntent(createdAt: createdAt, extra: {'date': payloadDate}));
        expect(res.success, isTrue, reason: res.errorMessage);
        final row = onlyRow();
        expect(row['date'], istDateStr(createdAt));
        expect(row['meal_type'], inferMealSlot(createdAt.toLocal()));
      });
    }
  });

  // ── P4: the slot follows the screen's clock rule on the local hour ────

  group('slot', () {
    test('P4 no meal_type at 07:30Z: the zone table, and the screen rule',
        () async {
      final at = DateTime.parse(_p4Instant);
      final r = await CoachMealLog.write(
          at: at, mealType: null, items: coachItemsFromParsedMeal({}));
      expect(r.success, isTrue);
      final row = onlyRow();
      expect(row['date'], '2026-11-12');
      expect(row['meal_type'], inferMealSlot(at.toLocal()),
          reason: 'the coach and the screen pick the same slot for an instant');
      final expected = _p4ByOffsetMinutes[at.toLocal().timeZoneOffset.inMinutes];
      if (expected != null) {
        expect(row['meal_type'], expected,
            reason: 'host offset ${at.toLocal().timeZoneOffset}');
      }
    });

    test('P4 a named slot is kept; an unknown one falls back to the clock',
        () {
      final at = DateTime.parse(_p4Instant);
      expect(resolveCoachMealSlot('Dinner', at), 'dinner');
      expect(resolveCoachMealSlot(' snacks ', at), 'snacks');
      expect(resolveCoachMealSlot('brunch', at), inferMealSlot(at.toLocal()));
      expect(resolveCoachMealSlot(null, at), inferMealSlot(at.toLocal()));
    });

    test('P4 door: the tool writes inferMealSlot(createdAt.toLocal())',
        () async {
      final c = container();
      final createdAt = recentCreatedAt();
      final res = await dispatch(c, mealIntent(createdAt: createdAt));
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(onlyRow()['meal_type'], inferMealSlot(createdAt.toLocal()));
    });

    test('P4 door: a named slot from the coach is written as named', () async {
      final c = container();
      final res = await dispatch(
          c,
          mealIntent(
              createdAt: recentCreatedAt(), extra: {'meal_type': 'dinner'}));
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(onlyRow()['meal_type'], 'dinner');
    });
  });

  // ── P5: the coach's parsed items are written like the AI-text tab ─────

  group('items', () {
    test('P5 two parsed items -> two items with fibre, saveMeal shape',
        () async {
      final c = container();
      final res = await dispatch(c, mealIntent(createdAt: recentCreatedAt()));
      expect(res.success, isTrue, reason: res.errorMessage);
      final coachRow = onlyRow();
      final coachItems = itemsOf(coachRow);
      expect(coachItems.map((i) => i['name']), ['Dal', 'Chawal']);
      expect(coachItems.map((i) => i['fiber']), [8.0, 1.0]);
      expect(coachItems.map((i) => i['quantity_g']), [100.0, 100.0]);
      expect(coachRow['total_fiber'], 9);
      expect(coachRow['total_calories'], 450);

      // The Nutrition screen's AI-text save of the same items.
      await HiveService.instance.nutritionBox
          .delete(coachRow['id'] as String);
      final notifier = c.read(aiBreakdownProvider.notifier);
      notifier.state = const AiBreakdownData(
        mealName: 'Dal chawal',
        totalKcal: 450,
        items: [
          AiFoodItem(
              name: 'Dal',
              quantity: '2 katori',
              calories: 250,
              protein: '12g',
              carbs: '30g',
              fat: '6g',
              fiber: 8),
          AiFoodItem(
              name: 'Chawal',
              quantity: '1 katori',
              calories: 200,
              protein: '6g',
              carbs: '30g',
              fat: '6g',
              fiber: 1),
        ],
      );
      final saved = await notifier.saveMeal(mealType: 'lunch');
      expect(saved.success, isTrue);
      final screenItems = itemsOf(onlyRow());
      expect(coachItems, screenItems,
          reason: 'the same items are stored field for field');
    });

    test('P5 no usable parsed item -> one item from the totals', () async {
      final c = container();
      final res = await dispatch(
          c,
          mealIntent(createdAt: recentCreatedAt(), items: [
            {'name': '', 'calories': 10},
            {'calories': 20},
          ]));
      expect(res.success, isTrue, reason: res.errorMessage);
      final items = itemsOf(onlyRow());
      expect(items, hasLength(1));
      expect(items.single['name'], 'Dal chawal');
      expect(items.single['calories'], 450.0);
      expect(items.single['protein'], 18.0);
      expect(items.single['quantity_g'], 100.0);
    });
  });

  // ── P6: the food tag writes the coach's own estimate ──────────────────

  group('tag', () {
    PendingLogAction? addTag(ProviderContainer c, Map<String, dynamic> data) {
      c.read(pendingLogActionsProvider.notifier).addActions([
        {'action': 'log_food', 'data': data},
      ], c.read(_refProvider), coverage: TypedLogCoverage.empty);
      final actions = c.read(pendingLogActionsProvider);
      return actions.isEmpty ? null : actions.last;
    }

    testWidgets('P6 the tag name and estimates are written (no database food)',
        (tester) async {
      final c = container();
      final action = addTag(c, {
        'food_name': 'Poha',
        'calories_estimate': 270,
        'protein_estimate': 6,
        'carbs_estimate': 45,
        'fat_estimate': 8,
        'quantity_g': 180,
        'meal_type': 'breakfast',
      });
      expect(action, isNotNull);
      expect(action!.displayText, 'Poha — Breakfast');
      final ok = await runTag(tester, c, action);
      expect(ok, isTrue);
      final row = onlyRow();
      expect(row['meal_type'], 'breakfast');
      final item = itemsOf(row).single;
      expect(item['name'], 'Poha');
      expect(item['calories'], 270.0);
      expect(item['protein'], 6.0);
      expect(item['carbs'], 45.0);
      expect(item['fat'], 8.0);
      expect(item['quantity_g'], 180.0);
    });

    test('P6 a tag with no calories shows no card and is counted', () {
      final c = container();
      final action = addTag(c, {'food_name': 'Roti', 'meal_type': 'lunch'});
      expect(action, isNull);
      expect(
          events.where((e) => e == 'coach_food_tag_dropped_no_calories'),
          hasLength(1));
    });

    testWidgets('P6 a card created at 23:59:58 IST that saves after midnight '
        'logs on the earlier day; the card shows the slot it writes',
        (tester) async {
      final c = container();
      setTestClockTo(DateTime.parse('2026-11-12T18:29:58Z')); // 23:59:58 IST
      final action = addTag(c, {'food_name': 'Kulfi', 'calories_estimate': 150});
      expect(action, isNotNull);
      setTestClockTo(DateTime.parse('2026-11-12T18:30:05Z')); // 00:00:05 IST
      final ok = await runTag(tester, c, action!);
      expect(ok, isTrue);
      final row = onlyRow();
      expect(row['date'], '2026-11-12');
      final slot = row['meal_type'] as String;
      expect(slot,
          inferMealSlot(DateTime.parse('2026-11-12T18:29:58Z').toLocal()));
      expect(action.displayText,
          'Kulfi — ${slot[0].toUpperCase()}${slot.substring(1)}');
    });
  });

  // ── P7: no AI-text allowance for a coach meal ─────────────────────────

  test('P7 a tool log leaves the AI-text counter unchanged', () async {
    final c = container();
    final counter = UsageCounterService.instance;
    final before = [
      counter.used(AppConstants.featureAiTextLogPro, false),
      counter.used(AppConstants.featureAiTextLogPro, true),
    ];
    final res = await dispatch(c, mealIntent(createdAt: recentCreatedAt()));
    expect(res.success, isTrue, reason: res.errorMessage);
    expect([
      counter.used(AppConstants.featureAiTextLogPro, false),
      counter.used(AppConstants.featureAiTextLogPro, true),
    ], before);
  });

  // ── P8: the badge check ───────────────────────────────────────────────

  group('badges', () {
    testWidgets('P8 both doors run the badge check once per stored meal',
        (tester) async {
      var calls = 0;
      CoachMealLog.debugBadgeCheck = () => calls++;
      final c = container();
      final res = (await tester.runAsync(
          () => dispatch(c, mealIntent(createdAt: recentCreatedAt()))))!;
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(calls, 1);
      c.read(pendingLogActionsProvider.notifier).addActions([
        {
          'action': 'log_food',
          'data': {'food_name': 'Chai', 'calories_estimate': 90},
        },
      ], c.read(_refProvider), coverage: TypedLogCoverage.empty);
      final ok =
          await runTag(tester, c, c.read(pendingLogActionsProvider).last);
      expect(ok, isTrue);
      expect(calls, 2);
    });

    test('P8 a throwing badge check still returns success, meal stored',
        () async {
      CoachMealLog.debugBadgeCheck = () => throw StateError('badge boom');
      final c = container();
      final res = await dispatch(c, mealIntent(createdAt: recentCreatedAt()));
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(nlogRows(), hasLength(1));
      expect(events, contains('nonfatal:coach_meal_log_badge_check'));
    });

    test('P8 the real badge check runs without failing the write', () async {
      final c = container();
      final res = await dispatch(c, mealIntent(createdAt: recentCreatedAt()));
      expect(res.success, isTrue, reason: res.errorMessage);
      expect(events, isNot(contains('nonfatal:coach_meal_log_badge_check')));
    });
  });

  // ── P9: readers take the name from items ──────────────────────────────

  group('readers', () {
    Future<Map<String, dynamic>> writeMeal(List<FoodItem> items,
        {String slot = 'lunch'}) async {
      final r = await NutritionWriteService.instance.logMeal(
        date: nowWall(),
        mealType: slot,
        items: items,
        source: NutritionWriteSource.manualSearch,
      );
      expect(r.success, isTrue);
      return Map<String, dynamic>.from(
          HiveService.instance.nutritionBox.get(r.logKey) as Map);
    }

    FoodItem item(String name, {double g = 100, double kcal = 100}) =>
        FoodItem(
            name: name,
            quantityG: g,
            calories: kcal,
            protein: 5,
            carbs: 10,
            fat: 3,
            fiber: 1);

    test('P9 meals_today, the display name and recent_deletes show the items',
        () async {
      final row = await writeMeal([item('Idli'), item('Sambar')]);
      expect(row.containsKey('food_name'), isFalse,
          reason: 'the writer keeps names in items[] only');

      final meals = AiCoachRepository.instance.mealsTodayForTest();
      final names = meals
          .expand((m) => (m['items'] as List).cast<Map>())
          .map((i) => i['name'])
          .toList();
      expect(names, ['Idli · Sambar']);

      expect(NutritionReadService.shortMealDisplayName(row), 'Idli · Sambar');

      final del = await NutritionWriteService.instance
          .deleteLog(logKey: row['id'] as String, allowUndo: false);
      expect(del.success, isTrue);
      final audit =
          (HiveService.instance.nutritionBox.get('recent_deletes') as List)
              .cast<Map>();
      expect(audit.first['food_name'], 'Idli · Sambar');

      // A legacy flat row (top-level name, no items[]) is still audited.
      await HiveService.instance.nutritionBox.put('nlog_legacy', {
        'id': 'nlog_legacy',
        'date': istTodayStr(),
        'meal_type': 'dinner',
        'food_name': 'Legacy khichdi',
        'total_calories': 300,
      });
      final del2 = await NutritionWriteService.instance
          .deleteLog(logKey: 'nlog_legacy', allowUndo: false);
      expect(del2.success, isTrue);
      final audit2 =
          (HiveService.instance.nutritionBox.get('recent_deletes') as List)
              .cast<Map>();
      expect(audit2.first['food_name'], 'Legacy khichdi');
    });

    test('P9 a 12-item name is cut to 80 runes; an emoji cut leaves no lone '
        'surrogate', () async {
      final row = await writeMeal(
          [for (var i = 0; i < 12; i++) item('Masala dosa number $i')]);
      final name = NutritionReadService.shortMealDisplayName(row);
      expect(name.runes.length, lessThanOrEqualTo(80));

      for (final cut in [79, 80]) {
        // An emoji (two UTF-16 units) straddling rune [cut - 1].
        final text = '${'a' * (cut - 1)}🍛🍛tail';
        final out = NutritionReadService.cutToRunes(text, cut);
        expect(out.runes.length, cut);
        expect(out.runes.last, '🍛'.runes.first);
        for (var i = 0; i < out.length; i++) {
          final u = out.codeUnitAt(i);
          final high = u >= 0xD800 && u <= 0xDBFF;
          final low = u >= 0xDC00 && u <= 0xDFFF;
          if (high) {
            expect(i + 1 < out.length, isTrue, reason: 'lone high surrogate');
            final next = out.codeUnitAt(i + 1);
            expect(next >= 0xDC00 && next <= 0xDFFF, isTrue);
            i++;
          } else {
            expect(low, isFalse, reason: 'lone low surrogate at $i');
          }
        }
      }
    });

    test('P9 recent list shows item names; relog writes the same item',
        () async {
      await writeMeal([item('Coach sentinel', g: 100, kcal: 210)]);
      await writeMeal([item('Real grams', g: 37.5, kcal: 120)], slot: 'dinner');
      await writeMeal([item('Old zero', g: 0, kcal: 80)], slot: 'snacks');
      // A malformed item next to a good one: the good one still shows.
      await HiveService.instance.nutritionBox.put('nlog_bad', {
        'id': 'nlog_bad',
        'date': istTodayStr(),
        'meal_type': 'snacks',
        'created_at': DateTime.now().toIso8601String(),
        'items': [
          {'name': 42},
          {'name': 'Survivor', 'quantity_g': 50, 'calories': 60},
        ],
      });

      final rows = nlogRows();
      final recent = recentLoggedItems(rows,
          cutoff: DateTime.now().subtract(const Duration(days: 7)));
      final names = recent.map((i) => i.name).toSet();
      expect(names,
          containsAll(['Coach sentinel', 'Real grams', 'Old zero', 'Survivor']));

      for (final stored in recent
          .where((i) => i.name != 'Survivor')
          .toList()) {
        final again = relogItem(stored);
        final r = await NutritionWriteService.instance.logMeal(
          date: nowWall(),
          mealType: 'snacks',
          items: [again],
          source: NutritionWriteSource.manualSearch,
        );
        expect(r.success, isTrue);
        final written = Map<String, dynamic>.from(
            ((HiveService.instance.nutritionBox.get(r.logKey) as Map)['items']
                    as List)
                .last as Map);
        expect(written['name'], stored.name);
        expect(written['quantity_g'],
            stored.quantityG > 0 ? stored.quantityG : 100.0);
        expect(written['calories'], stored.calories);
        expect(written['protein'], stored.protein);
        expect(written['fiber'], stored.fiber);
      }
    });
  });

  // ── B-pass mirrors (seats A and B, 2026-11-12) ────────────────────────

  group('B-pass mirrors', () {
    PendingLogAction? addTag(ProviderContainer c, Map<String, dynamic> data) {
      c.read(pendingLogActionsProvider.notifier).addActions([
        {'action': 'log_food', 'data': data},
      ], c.read(_refProvider), coverage: TypedLogCoverage.empty);
      final actions = c.read(pendingLogActionsProvider);
      return actions.isEmpty ? null : actions.last;
    }

    test('A1 any slot naming a snack is snacks, at any hour', () {
      // 13:30 IST and 20:00 IST: the clock would say lunch / dinner.
      for (final at in [
        DateTime.parse('2026-11-12T08:00:00Z'),
        DateTime.parse('2026-11-12T14:30:00Z'),
      ]) {
        expect(resolveCoachMealSlot('snack', at), 'snacks');
        expect(resolveCoachMealSlot('Evening snack', at), 'snacks');
        expect(resolveCoachMealSlot(' SNACKS ', at), 'snacks');
      }
    });

    test('B1 a failed write: the tool answers failure, no badge check, '
        'the failure is reported', () async {
      var badgeCalls = 0;
      CoachMealLog.debugBadgeCheck = () => badgeCalls++;
      final c = container();
      // The put throws on a closed box, so logMeal returns a failure.
      await HiveService.instance.nutritionBox.close();
      final res = await dispatch(c, mealIntent(createdAt: recentCreatedAt()));
      expect(res.success, isFalse);
      expect(res.errorMessage, 'Could not log that meal.');
      expect(badgeCalls, 0, reason: 'no badge check for a meal not stored');
      expect(events, contains('tool_dispatch_log_meal_by_text_failed'));
    });

    test('B1 CoachMealLog.write on a failed write returns the failure and '
        'skips the badge check', () async {
      var badgeCalls = 0;
      CoachMealLog.debugBadgeCheck = () => badgeCalls++;
      await HiveService.instance.nutritionBox.close();
      final r = await CoachMealLog.write(
          at: nowWall(), mealType: 'lunch', items: coachItemsFromParsedMeal({}));
      expect(r.success, isFalse);
      expect(badgeCalls, 0);
    });

    testWidgets('B2 a tag with no meal_type: the card shows the slot it writes '
        '(clock 07:30Z)', (tester) async {
      final c = container();
      final at = DateTime.parse(_p4Instant);
      setTestClockTo(at);
      final action = addTag(c, {'food_name': 'Rajma rice', 'calories_estimate': 420});
      expect(action, isNotNull);
      final ok = await runTag(tester, c, action!);
      expect(ok, isTrue);
      final slot = onlyRow()['meal_type'] as String;
      expect(slot, inferMealSlot(at.toLocal()));
      expect(action.displayText,
          'Rajma rice — ${slot[0].toUpperCase()}${slot.substring(1)}');
      final expected = _p4ByOffsetMinutes[at.toLocal().timeZoneOffset.inMinutes];
      if (expected != null) expect(slot, expected);
    });

    test('B6 a tag with negative calories shows no card; quantity 0 -> 100 g',
        () {
      final c = container();
      expect(addTag(c, {'food_name': 'X', 'calories_estimate': -50}), isNull);
      final item =
          coachItemFromTag({'food_name': 'Y', 'calories_estimate': 90, 'quantity_g': 0});
      expect(item!.quantityG, 100.0);
      final neg =
          coachItemFromTag({'food_name': 'Y', 'calories_estimate': 90, 'quantity_g': -5});
      expect(neg!.quantityG, 100.0);
    });

    test('B4 deleteLog audits exactly the food rows', () async {
      final box = HiveService.instance.nutritionBox;
      Future<String?> auditFor(String key, Map<String, dynamic> row) async {
        await box.delete('recent_deletes');
        await box.put(key, row);
        final r = await NutritionWriteService.instance
            .deleteLog(logKey: key, allowUndo: false);
        expect(r.success, isTrue, reason: key);
        final audit = box.get('recent_deletes') as List?;
        return audit == null ? null : (audit.first as Map)['food_name'] as String;
      }

      final today = istTodayStr();
      // items but no meal_type: not a food log
      expect(
          await auditFor('nlog_a', {
            'date': today,
            'items': [
              {'name': 'Oats'}
            ],
          }),
          isNull);
      // a meal_type and an EMPTY items[] and no name: not a food log
      expect(
          await auditFor('nlog_b', {
            'date': today,
            'meal_type': 'lunch',
            'items': <Map>[],
          }),
          isNull);
      // a legacy flat row named by `name`: audited
      expect(
          await auditFor('nlog_c', {
            'date': today,
            'meal_type': 'snacks',
            'name': 'Legacy chana',
            'total_calories': 150,
          }),
          'Legacy chana');
      // items with a meal_type: audited with the item names
      expect(
          await auditFor('nlog_d', {
            'date': today,
            'meal_type': 'dinner',
            'items': [
              {'name': 'Roti'},
              {'name': 'Dal'}
            ],
          }),
          'Roti · Dal');
    });

    test('B5 recent list: case-insensitive dedup, item order inside a meal, '
        'blank names skipped', () {
      final t = DateTime.now().toUtc();
      final rows = [
        {
          'created_at': t.toIso8601String(),
          'items': [
            {'name': 'Dal', 'quantity_g': 100, 'calories': 120},
            {'name': 'dal', 'quantity_g': 50, 'calories': 60},
            {'name': '   ', 'quantity_g': 10, 'calories': 5},
            {'name': 'Rice', 'quantity_g': 150, 'calories': 200},
          ],
        },
      ];
      final out = recentLoggedItems(rows,
          cutoff: t.subtract(const Duration(days: 14)));
      expect(out.map((i) => i.name), ['Dal', 'Rice'],
          reason: 'first-written item wins a tie; "dal" is a duplicate of '
              '"Dal"; a blank name is skipped');
      expect(out.first.quantityG, 100.0);
    });

    test('A5 the data export counts the exported rows, not the box length', () {
      final src = File('lib/features/profile/screens/profile/export_data.dart')
          .readAsStringSync();
      expect(src, isNot(contains('nutritionBox.length')));
      expect(src, contains("data['nutrition_logs_count'] = nutrition.length;"));
    });
  });
}
