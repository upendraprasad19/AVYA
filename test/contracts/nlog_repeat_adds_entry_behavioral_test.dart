// OI-493 Landing B (plan docs/plans/oi493b-duplicate-meals.md, tests R1-R9):
// founder decision F4, "if we are logging same meal twice it should log
// twice". The same meal logged again the same IST day in the same slot is a
// SECOND entry, and nothing that writes an `nlog_` key overwrites one.
//
// Writer: lib/core/services/nutrition_write_service.dart logMeal (first free
//   occurrence key), restoreLastDeleted / restoreFoodLog (B2), moveMealLog
//   (B3); lib/core/services/nlog_key_migrator.dart (B4);
//   ConversationalLogHandler.executeAction (B6); SingleFlight (B7).
// Readers: NutritionReadService.totalMacrosForDate (the day's totals), the
//   nlog_ rows by key, mergeNutritionLogsBySlot / nutritionSlotUnion /
//   nutritionLocalSlotIsSuperset (cloud push and restore).
//
// Real Hive (nws_test_setup). Run under TZ=Asia/Kolkata and UTC.
//
// closes-diagnose: see docs/diagnoses/2026-11-12-same-meal-twice-*.md
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/nlog_key_migrator.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/single_flight.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_meal_log.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/log_food_modes/search_mode_body.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

const _rice = FoodItem(
  name: 'Rice',
  quantityG: 150,
  calories: 200,
  protein: 4,
  carbs: 44,
  fat: 0,
  fiber: 1,
);

final _day = DateTime(2026, 11, 12, 13);

Future<String> _log({
  List<FoodItem> items = const [_rice],
  String slot = 'lunch',
  int? overrideTotalCals,
  int? overrideTotalProtein,
}) async {
  final r = await NutritionWriteService.instance.logMeal(
    date: _day,
    mealType: slot,
    items: items,
    overrideTotalCals: overrideTotalCals,
    overrideTotalProtein: overrideTotalProtein,
    source: NutritionWriteSource.manualSearch,
  );
  expect(r.success, isTrue, reason: '${r.errorMessage}');
  return r.logKey!;
}

List<String> _nlogKeys() => HiveService.instance.nutritionBox.keys
    .map((k) => k.toString())
    .where((k) => k.startsWith('nlog_'))
    .toList()
  ..sort();

Map<String, dynamic> _row(String key) => Map<String, dynamic>.from(
    HiveService.instance.nutritionBox.get(key) as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <String>[];

  setUp(() async {
    await nwsTestSetup();
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      if (!Hive.isBoxOpen(name)) await Hive.openBox(name);
    }
    SyncService.pausedForSimulation = true;
    CoachMealLog.debugBadgeCheck = () {};
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
    await nwsTestTeardown();
  });

  group('R1/R2 a repeat adds an entry (B1)', () {
    test('R1 the same meal five times -> base, base_2 .. base_5; the day '
        'counts it five times', () async {
      final base = await _log();
      final second = await _log();
      final third = await _log();
      final fourth = await _log();
      final fifth = await _log();
      expect(second, '${base}_2');
      expect(third, '${base}_3');
      expect(fourth, '${base}_4',
          reason: 'the search keeps walking past every taken occurrence '
              '(B-pass seat B: a `while` -> `if` mutant survived at 3)');
      expect(fifth, '${base}_5');
      expect(_nlogKeys(),
          [base, '${base}_2', '${base}_3', '${base}_4', '${base}_5']);
      for (final k in _nlogKeys()) {
        expect(_row(k)['id'], k);
        expect(_row(k)['log_key'], k);
      }
      expect(NutritionReadService.instance.totalMacrosForDate(_day)['calories'],
          1000);
    });

    test('R1 a different slot or different grams is its own base key',
        () async {
      final lunch = await _log();
      final dinner = await _log(slot: 'dinner');
      final bigger = await _log(items: const [
        FoodItem(
            name: 'Rice',
            quantityG: 200,
            calories: 260,
            protein: 5,
            carbs: 58,
            fat: 0,
            fiber: 1),
      ]);
      expect({lunch, dinner, bigger}, hasLength(3));
      for (final k in [lunch, dinner, bigger]) {
        expect(NutritionWriteService.kNlogKeyShape.firstMatch(k)?.group(2),
            isNull,
            reason: 'none of them is an occurrence of another');
      }
    });

    test('R2 two un-awaited logMeal calls with equal input -> two rows',
        () async {
      final f1 = _log();
      final f2 = _log();
      final keys = await Future.wait([f1, f2]);
      expect(keys.toSet(), hasLength(2));
      expect(_nlogKeys(), hasLength(2));
      expect(NutritionReadService.instance.totalMacrosForDate(_day)['calories'],
          400);
    });
  });

  group('R3 UNDO (B2)', () {
    test('delete base, log again (takes base), UNDO via restoreLastDeleted '
        '-> both rows; UNDO lands on base_2', () async {
      final base = await _log();
      await NutritionWriteService.instance
          .deleteLog(logKey: base, allowUndo: true, writeAuditLog: false);
      final relogged = await _log();
      expect(relogged, base);
      final undo = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: base);
      expect(undo.success, isTrue);
      expect(undo.logKey, '${base}_2');
      expect(_nlogKeys(), [base, '${base}_2']);
      expect(_row('${base}_2')['id'], '${base}_2');
      expect(_row('${base}_2')['log_key'], '${base}_2');
      expect(NutritionReadService.instance.totalMacrosForDate(_day)['calories'],
          400);
    });

    test('the same via restoreFoodLog; the caller\'s map is not mutated',
        () async {
      final base = await _log();
      final stashed = _row(base);
      await NutritionWriteService.instance
          .deleteLog(logKey: base, allowUndo: false, writeAuditLog: false);
      await _log();
      final undo = await NutritionWriteService.instance.restoreFoodLog(stashed);
      expect(undo.success, isTrue);
      expect(undo.logKey, '${base}_2');
      expect(_nlogKeys(), [base, '${base}_2']);
      expect(_row('${base}_2')['id'], '${base}_2',
          reason: 'the restored row names its own key, or a later delete / '
              'edit / move would act on the other entry');
      expect(_row('${base}_2')['log_key'], '${base}_2');
      expect(stashed['id'], base, reason: 'the caller\'s copy is untouched');
      expect(stashed['log_key'], base);
    });

    test('UNDO with the key still free reuses it', () async {
      final base = await _log();
      await NutritionWriteService.instance
          .deleteLog(logKey: base, allowUndo: true, writeAuditLog: false);
      final undo = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: base);
      expect(undo.logKey, base);
      expect(_nlogKeys(), [base]);
    });

    test('restoreFoodLog is one-shot: the same copy restored twice writes one '
        'row', () async {
      final base = await _log();
      final stashed = _row(base);
      await NutritionWriteService.instance
          .deleteLog(logKey: base, allowUndo: false, writeAuditLog: false);
      final first = await NutritionWriteService.instance.restoreFoodLog(stashed);
      final second =
          await NutritionWriteService.instance.restoreFoodLog(stashed);
      expect(first.success, isTrue);
      expect(second.success, isFalse,
          reason: 'a second tap on the same UNDO must not add a copy');
      expect(_nlogKeys(), [base]);
    });

    test('the owner record keeps the last 16 deletes: an UNDO survives 15 '
        'later deletes and is refused after 16', () async {
      Future<String> logAndDelete(int i) async {
        final k = await _log(items: [
          FoodItem(
              name: 'Item $i',
              quantityG: 100,
              calories: 100,
              protein: 1,
              carbs: 1,
              fat: 1,
              fiber: 0),
        ]);
        await NutritionWriteService.instance
            .deleteLog(logKey: k, allowUndo: false, writeAuditLog: false);
        return k;
      }

      final a = await _log();
      final stashedA = _row(a);
      await NutritionWriteService.instance
          .deleteLog(logKey: a, allowUndo: false, writeAuditLog: false);
      for (var i = 0; i < 15; i++) {
        await logAndDelete(i);
      }
      expect(
          (await NutritionWriteService.instance.restoreFoodLog(stashedA))
              .success,
          isTrue,
          reason: 'A is the 16th most recent delete: still recorded');

      final b = await _log(slot: 'dinner');
      final stashedB = _row(b);
      await NutritionWriteService.instance
          .deleteLog(logKey: b, allowUndo: false, writeAuditLog: false);
      for (var i = 100; i < 116; i++) {
        await logAndDelete(i);
      }
      expect(
          (await NutritionWriteService.instance.restoreFoodLog(stashedB))
              .success,
          isFalse,
          reason: 'B fell out of the 16-entry record');
    });

    test('a taken legacy (non-occurrence-shape) key is restored in place, as '
        'before', () async {
      const legacyKey = 'nlog_1731247200000';
      final box = HiveService.instance.nutritionBox;
      final row = <String, dynamic>{
        'id': legacyKey,
        'date': '2026-11-12',
        'meal_type': 'lunch',
        'total_calories': 100,
        'items': [
          {'name': 'Tea', 'quantity_g': 100.0, 'calories': 100.0}
        ],
      };
      await box.put(legacyKey, row);
      await NutritionWriteService.instance
          .deleteLog(logKey: legacyKey, allowUndo: false, writeAuditLog: false);
      await box.put(legacyKey, {...row, 'total_calories': 999});
      final undo = await NutritionWriteService.instance.restoreFoodLog(row);
      expect(undo.logKey, legacyKey,
          reason: 'only occurrence-shape keys move to a free occurrence');
      expect(_nlogKeys(), [legacyKey]);
    });

    test('two deletes, then the FIRST snackbar\'s UNDO restores nothing; the '
        'second snackbar\'s UNDO still works', () async {
      final a = await _log();
      final b = await _log(slot: 'dinner');
      await NutritionWriteService.instance
          .deleteLog(logKey: a, allowUndo: true, writeAuditLog: false);
      await NutritionWriteService.instance
          .deleteLog(logKey: b, allowUndo: true, writeAuditLog: false);
      final first = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: a);
      expect(first.success, isFalse);
      expect(_nlogKeys(), isEmpty,
          reason: 'the first UNDO must not restore the second row');
      final second = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: b);
      expect(second.success, isTrue);
      expect(_nlogKeys(), [b]);
    });

    test('an owner change between delete and UNDO restores nothing on either '
        'path', () async {
      final a = await _log();
      final stashedA = _row(a);
      final b = await _log(slot: 'dinner');
      await NutritionWriteService.instance
          .deleteLog(logKey: a, allowUndo: false, writeAuditLog: false);
      await NutritionWriteService.instance
          .deleteLog(logKey: b, allowUndo: true, writeAuditLog: false);
      await HiveUserSession.openForUser(
          'other-user-87654321-aaaa-bbbb-cccc-dddddddddddd');
      final viaStash = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: b);
      final viaCopy =
          await NutritionWriteService.instance.restoreFoodLog(stashedA);
      expect(viaStash.success, isFalse);
      expect(viaCopy.success, isFalse);
      expect(_nlogKeys(), isEmpty,
          reason: 'nothing may be written into the other account\'s box');
    });

    test('a null owner (signed out) restores nothing', () async {
      final a = await _log();
      await NutritionWriteService.instance
          .deleteLog(logKey: a, allowUndo: true, writeAuditLog: false);
      await HiveUserSession.closeAll();
      expect(HiveUserSession.currentOwnerHash, isNull);
      await HiveUserSession.openForUser(
          'test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd');
      // Same user back: the recorded hash matches, so UNDO still works.
      final sameUser = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: a);
      expect(sameUser.success, isTrue);

      await NutritionWriteService.instance
          .deleteLog(logKey: a, allowUndo: true, writeAuditLog: false);
      await HiveUserSession.closeAll();
      final signedOut = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: a);
      expect(signedOut.success, isFalse);
      await HiveUserSession.openForUser(
          'test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd');
      final later = await NutritionWriteService.instance
          .restoreLastDeleted(expectedKey: a);
      expect(later.success, isFalse,
          reason: 'a refused restore drops the stash for good');
    });
  });

  group('R3b key shape', () {
    const base = 'nlog_2026-11-12_lunch_12345678';
    test('baseLogKey strips only a real occurrence suffix (an all-digit hash '
        'is kept)', () {
      expect(NutritionWriteService.baseLogKey('${base}_2'), base);
      expect(NutritionWriteService.baseLogKey('${base}_13'), base);
      expect(NutritionWriteService.baseLogKey(base), base);
      expect(NutritionWriteService.baseLogKey('nlog_1715000000000'),
          'nlog_1715000000000');
      expect(NutritionWriteService.kNlogKeyShape.hasMatch('nlog_1715000000000'),
          isFalse);
    });

    test('firstFreeLogKey', () {
      final taken = <String>{};
      expect(NutritionWriteService.firstFreeLogKey(taken.contains, base), base);
      taken.addAll({base, '${base}_2'});
      expect(NutritionWriteService.firstFreeLogKey(taken.contains, base),
          '${base}_3');
      taken.remove(base);
      expect(NutritionWriteService.firstFreeLogKey(taken.contains, base), base);
    });
  });

  group('R4 move (B3)', () {
    test('a move into a slot holding the same meal -> dest and dest_2, no '
        'source row', () async {
      final dinner = await _log(slot: 'dinner');
      final lunch = await _log();
      final moved = await NutritionWriteService.instance
          .moveMealLog(logKey: lunch, newMealType: 'dinner');
      expect(moved.logKey, '${dinner}_2');
      expect(_nlogKeys(), [dinner, '${dinner}_2']);
      expect(_row('${dinner}_2')['items'], hasLength(1));
      expect(NutritionReadService.instance.totalMacrosForDate(_day)['calories'],
          400);
    });
  });

  group('R5 migrator (B4)', () {
    test('current-shape rows are untouched; two equal legacy rows stay two',
        () async {
      final config = HiveService.instance.configBox;
      await config.delete('nlog_key_migration_v7');
      final base = await _log();
      final second = await _log();
      final box = HiveService.instance.nutritionBox;
      // A restored v5 row whose logged_at UTC day (11th) differs from its
      // IST day (12th): it must keep its key and its day.
      const restoredKey = 'nlog_2026-11-12_breakfast_0a1b2c3d';
      final restored = {
        'id': restoredKey,
        'log_key': restoredKey,
        'date': '2026-11-12',
        'meal_type': 'breakfast',
        'total_calories': 150,
        'items': [
          {'name': 'Poha', 'quantity_g': 100.0, 'calories': 150.0}
        ],
        'logged_at': '2026-11-11T20:00:00.000Z',
      };
      await box.put(restoredKey, restored);
      Map<String, dynamic> legacy(int ms) => {
            'note_tag': 'legacy-$ms',
            'date': '2026-11-10',
            'meal_type': 'dinner',
            'total_calories': 300,
            'items': [
              {'name': 'Dal', 'quantity_g': 200.0, 'calories': 300.0}
            ],
            'logged_at': '2026-11-10T14:00:00.000Z',
            'updated_at_ms': ms,
          };
      await box.put('nlog_1731247200000', legacy(1));
      await box.put('nlog_1731247260000', legacy(2));
      final before = {
        for (final k in [base, second, restoredKey]) k: _row(k),
      };

      await NlogKeyMigrator.runIfNeeded();

      for (final e in before.entries) {
        expect(_row(e.key), e.value, reason: '${e.key} must be left alone');
      }
      final keys = _nlogKeys();
      expect(keys, isNot(contains('nlog_1731247200000')));
      expect(keys, isNot(contains('nlog_1731247260000')));
      final rekeyed = keys.where((k) => !before.containsKey(k)).toList();
      expect(rekeyed, hasLength(2),
          reason: 'two equal legacy servings stay two entries');
      expect(NutritionWriteService.baseLogKey(rekeyed[1]), rekeyed[0]);
      expect(_row(rekeyed[0])['note_tag'], 'legacy-1',
          reason: 'oldest first: the older row takes the base key');
      expect(_row(rekeyed[1])['note_tag'], 'legacy-2');
      for (final k in rekeyed) {
        expect(_row(k)['id'], k);
        expect(NutritionWriteService.kNlogKeyShape.hasMatch(k), isTrue);
      }
      expect(config.get('nlog_key_migration_v7'), isTrue);
    });
  });

  group('R5b migrator idempotence (B4)', () {
    test('a run interrupted between a put and its delete only finishes the '
        'delete next time (no second copy)', () async {
      final config = HiveService.instance.configBox;
      await config.delete('nlog_key_migration_v7');
      final box = HiveService.instance.nutritionBox;
      final legacy = {
        'date': '2026-11-10',
        'meal_type': 'dinner',
        'total_calories': 300,
        'items': [
          {'name': 'Dal', 'quantity_g': 200.0, 'calories': 300.0}
        ],
        'logged_at': '2026-11-10T14:00:00.000Z',
      };
      await box.put('nlog_1731247200000', legacy);
      await NlogKeyMigrator.runIfNeeded();
      final copied = _nlogKeys().single;
      expect(_row(copied)['migrated_from'], 'nlog_1731247200000');

      // Simulate the crash: the old key is back (its delete never ran) and
      // the flag was never set.
      await box.put('nlog_1731247200000', legacy);
      await config.delete('nlog_key_migration_v7');
      await NlogKeyMigrator.runIfNeeded();
      expect(_nlogKeys(), [copied],
          reason: 'the re-run deletes the already-copied legacy key');
    });
  });

  group('R6 coach tag: one action, one write (B6)', () {
    testWidgets('two executeAction calls for one action share one save',
        (tester) async {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: Consumer(builder: (_, r, _) {
          ref = r;
          return const SizedBox();
        }),
      ));
      final action = PendingLogAction(
        id: 'tag-1',
        type: LogActionType.food,
        data: const {
          'food_name': 'Idli',
          'calories_estimate': 140,
          'protein_estimate': 4,
          'meal_type': 'breakfast',
        },
        displayText: 'Idli — Breakfast',
        createdAt: DateTime.utc(2026, 11, 12, 3),
      );
      final results = await tester.runAsync(() async {
        // Two handlers, as two card States would build them.
        final f1 = ConversationalLogHandler(ref).executeAction(action);
        final f2 = ConversationalLogHandler(ref).executeAction(action);
        expect(identical(f1, f2), isTrue,
            reason: 'the second caller gets the running save');
        return Future.wait([f1, f2]);
      });
      expect(results, [true, true], reason: 'events: $events');
      expect(_nlogKeys(), hasLength(1));
      expect(ConversationalLogHandler.debugInFlightCount, 0,
          reason: 'the entry is released when the save completes');

      // After completion the same action CAN run again (the map is not a
      // dedup); the card's isLogged flag is what stops a re-save.
      final again = await tester.runAsync(
          () => ConversationalLogHandler(ref).executeAction(action));
      expect(again, isTrue);
      expect(_nlogKeys(), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('R6b two different coach actions are never one flight', () {
    testWidgets('two actions with different ids save two meals at once',
        (tester) async {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: Consumer(builder: (_, r, _) {
          ref = r;
          return const SizedBox();
        }),
      ));
      PendingLogAction tag(String id, String food) => PendingLogAction(
            id: id,
            type: LogActionType.food,
            data: {
              'food_name': food,
              'calories_estimate': 140,
              'meal_type': 'breakfast',
            },
            displayText: '$food — Breakfast',
            createdAt: DateTime.utc(2026, 11, 12, 3),
          );
      final results = await tester.runAsync(() async {
        final f1 = ConversationalLogHandler(ref).executeAction(tag('a', 'Idli'));
        final f2 =
            ConversationalLogHandler(ref).executeAction(tag('b', 'Vada'));
        expect(identical(f1, f2), isFalse);
        return Future.wait([f1, f2]);
      });
      expect(results, [true, true]);
      expect(_nlogKeys(), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('R7 one tap, one entry (B7)', () {
    test('SingleFlight: same key skipped while in flight, other keys run, '
        'released after completion and after a throw', () async {
      final gate = Completer<int>();
      var calls = 0;
      final first = SingleFlight.run<int>('k', () {
        calls++;
        return gate.future;
      });
      final skipped = await SingleFlight.run<int>('k', () async {
        calls++;
        return 2;
      });
      expect(skipped, isNull);
      expect(await SingleFlight.run<int>('other', () async => 3), 3);
      gate.complete(1);
      expect(await first, 1);
      expect(calls, 1);
      expect(await SingleFlight.run<int>('k', () async => 4), 4);

      await expectLater(
          SingleFlight.run<int>('k', () async => throw StateError('x')),
          throwsStateError);
      expect(SingleFlight.isInFlight('k'), isFalse);
      expect(await SingleFlight.run<int>('k', () async => 5), 5);
    });

    test('AI-text saveMeal twice un-awaited -> one row; the second result is '
        'inFlight, not noState', () async {
      final c = ProviderContainer(overrides: [
        aiBreakdownProvider.overrideWith(_SeededBreakdown.new),
      ]);
      addTearDown(c.dispose);
      final n = c.read(aiBreakdownProvider.notifier);
      final f1 = n.saveMeal(mealType: 'lunch');
      final f2 = n.saveMeal(mealType: 'lunch');
      final r2 = await f2;
      final r1 = await f1;
      expect(r1.success, isTrue);
      expect(r2.isInFlight, isTrue);
      expect(r2.isNoState, isFalse);
      expect(_nlogKeys(), hasLength(1));
    });

    test('screen tap keys name the write identity: food, grams and slot',
        () {
      final dal = <String, dynamic>{'id': 'f1', 'name': 'Dal'};
      final base = searchTapFlightKey(dal, 150, 'lunch');
      expect(searchTapFlightKey(dal, 150, 'dinner'), isNot(base));
      expect(searchTapFlightKey(dal, 200, 'lunch'), isNot(base));
      expect(searchTapFlightKey({'id': 'f2', 'name': 'Dal'}, 150, 'lunch'),
          isNot(base),
          reason: 'two foods sharing a name are two writes');
      expect(searchTapFlightKey(dal, 150, 'lunch'), base);
      const stored = FoodItem(
          name: 'Dal',
          quantityG: 150,
          calories: 180,
          protein: 9,
          carbs: 25,
          fat: 3,
          fiber: 5);
      expect(recentTapFlightKey(stored, 'lunch'),
          isNot(recentTapFlightKey(stored, 'dinner')));
    });

    test('source pins: each screen site wraps its write in SingleFlight with '
        'the write identity', () {
      String src(String p) => File(p).readAsStringSync();
      final search = src(
          'lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart');
      expect(search, contains('SingleFlight.run<bool>(\n'
          '                searchTapFlightKey(item, qty, slot)'));
      expect(search, contains("'search|\${food['id'] ?? food['name']}|\$grams|\$slot'"));
      expect(search, contains('SingleFlight.run<bool>(\n'
          '                recentTapFlightKey(item, slot)'));
      expect(search, contains("'recent|\${stored.name}|"));
      expect(search, contains('if (ran == null) return; // the first tap'));
      final barcode =
          src('lib/features/nutrition/widgets/barcode_scan_sheet.dart');
      expect(barcode, contains("'barcode|\$name|\$grams|\$slot'"));
      expect(barcode, contains('if (result == null) return;'));
      final scan = src('lib/features/nutrition/widgets/scan_meal_section.dart');
      final scanRun = scan.indexOf("SingleFlight.run<WriteResult>('scan'");
      expect(scanRun, isNot(-1));
      expect(scan.indexOf('setState(() => _saving = true);'),
          greaterThan(scanRun),
          reason: 'the flight is taken BEFORE _saving is set');
      final capture = scan.indexOf(
          'final scanNotifier = ref.read(scanMealProvider.notifier);');
      expect(capture, isNot(-1));
      expect(capture, lessThan(scanRun),
          reason: 'the scan notifier is captured before the save awaits');
      final clear = scan.indexOf('if (result.success) scanNotifier.clear();');
      expect(clear, greaterThan(scanRun));
      expect(scan.indexOf('if (!mounted) return;', scanRun), greaterThan(clear),
          reason: 'an unmounted editor still clears its saved scan (B-pass)');
      final handler = src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      final weight = handler.substring(
          handler.indexOf('Future<bool> _logWeight('),
          handler.indexOf('Future<bool> _logFood('));
      expect(weight, contains('try {\n      ref.invalidate(weightHistoryProvider);'),
          reason: 'a refresh on a disposed ref never fails a stored weight');
      final provider =
          src('lib/features/nutrition/providers/nutrition_provider.dart');
      expect(provider, contains("'aitext', () => _saveMealOnce("));
    });
  });

  group('R8 a zero override falls back to the items (B8)', () {
    const meal = [
      FoodItem(
          name: 'Thali',
          quantityG: 400,
          calories: 300,
          protein: 20,
          carbs: 40,
          fat: 8,
          fiber: 6),
    ];
    test('override 0 -> the item sum; protein override 0 -> the item sum',
        () async {
      final k = await _log(
          items: meal, overrideTotalCals: 0, overrideTotalProtein: 0);
      expect(_row(k)['total_calories'], 300);
      expect(_row(k)['total_protein'], 20);
    });
    test('a positive override is kept', () async {
      final k = await _log(
          items: meal, overrideTotalCals: 450, overrideTotalProtein: 30);
      expect(_row(k)['total_calories'], 450);
      expect(_row(k)['total_protein'], 30);
    });
    test('a negative override falls back to the items too', () async {
      final k = await _log(
          items: meal, overrideTotalCals: -50, overrideTotalProtein: -5);
      expect(_row(k)['total_calories'], 300);
      expect(_row(k)['total_protein'], 20);
    });
    test('items all 0 with override 0 stays 0', () async {
      final k = await _log(items: const [
        FoodItem(
            name: 'Water',
            quantityG: 250,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0),
      ], overrideTotalCals: 0);
      expect(_row(k)['total_calories'], 0);
    });
  });

  group('R9 the cloud keeps two servings as two items (accepted residual)', () {
    test('push: base + base_2 -> one slot row with two items, 2x calories; '
        'restore on this device skips; a second device gets one row with two '
        'items', () async {
      final base = await _log();
      await _log();
      final rows = _nlogKeys().map(_row).toList();
      final pushed = mergeNutritionLogsBySlot(rows);
      expect(pushed, hasLength(1));
      expect(pushed.single['items'], hasLength(2));
      expect(pushed.single['total_calories'], 400);

      final cloudItems = pushed.single['items'] as List;
      final localItems = [
        for (final r in rows) ...(r['items'] as List),
      ];
      expect(nutritionLocalSlotIsSuperset(localItems, cloudItems), isTrue,
          reason: 'this device already holds both servings: no restore');
      final secondDevice = nutritionSlotUnion(const [], cloudItems);
      expect(secondDevice, hasLength(2),
          reason: 'a second device restores ONE row holding both servings');
      expect(base, isNotEmpty);
    });
  });
}

class _SeededBreakdown extends AiBreakdownNotifier {
  @override
  AiBreakdownData? build() => const AiBreakdownData(
        mealName: 'Rajma chawal',
        totalKcal: 520,
        items: [
          AiFoodItem(
            name: 'Rajma chawal',
            quantity: '1 plate',
            calories: 520,
            protein: '18g',
            carbs: '80g',
            fat: '10g',
            fiber: 9,
          ),
        ],
      );
}
