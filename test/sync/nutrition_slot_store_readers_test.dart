// OI-348 Landing 1a-ii — §5: the slot sync's bookkeeping keys in the per-user
// nutritionBox (ledger shards, cursor, meta, both skip indexes) must be
// invisible to every whole-box meal reader. Behavioural for the readers
// reachable without a widget tree (each must give the SAME answer with and
// without the keys); a forcing-function pin for every whole-box loop in lib/.
// Also: logMeal stamps an entry_id, editLog cannot re-identify or re-slot a
// row, and an undo of a meal that is already back is refused (§4.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

const _item = FoodItem(
  name: 'Dal',
  quantityG: 150,
  calories: 200,
  protein: 12,
  carbs: 30,
  fat: 4,
  fiber: 3,
);

Future<String> _log(DateTime d, String meal, FoodItem item) async {
  final r = await NutritionWriteService.instance.logMeal(
    date: d,
    mealType: meal,
    items: [item],
    source: NutritionWriteSource.manualSearch,
  );
  expect(r.success, isTrue);
  return r.logKey!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  test('every reachable reader answers the same with the bookkeeping keys',
      () async {
    final now = DateTime.now();
    final date = istDateStr(now);
    final k1 = await _log(now, 'lunch', _item);
    await _log(now, 'dinner',
        const FoodItem(name: 'Rice', quantityG: 200, calories: 260, protein: 5, carbs: 56, fat: 1, fiber: 1));
    final box = HiveService.instance.nutritionBox;

    Map<String, Object?> answers() {
      final repo = NutritionRepository.instance;
      return {
        'totalMacrosForDate':
            NutritionReadService.instance.totalMacrosForDate(now).toString(),
        'getCaloriesForDate': repo.getCaloriesForDate(date),
        'getNutritionDaysLoggedThisWeek': repo.getNutritionDaysLoggedThisWeek(),
        'getDailyMacros': repo.getDailyMacros(days: 30).toString(),
        'computeWeeklyReportData': repo.computeWeeklyReportData().toString(),
        'getWeeklyAverages': repo.getWeeklyAverages(weeks: 8).toString(),
        'getProteinDeficitStreak': repo.getProteinDeficitStreak(),
        'getWeekdayVsWeekendCalories':
            repo.getWeekdayVsWeekendCalories(weeks: 4).toString(),
      };
    }

    final before = answers();
    expect(before['getCaloriesForDate'], 460.0);

    final row = box.get(k1) as Map;
    // Exactly the shapes the engine writes (§4.4) and both skip indexes.
    await box.putAll({
      '$kNslotLedgerPrefix$date': {
        'lunch': {
          'rev': 3,
          'ua': '2026-11-23T04:30:12.345678+00:00',
          'e': {row['entry_id']: nslotSignature(row)},
        },
      },
      kNslotCursorKey: {
        'rows': {'ts': '2026-11-23T04:25:12.345678+00:00', 'row': 'r1'},
        'tombs': {'ts': '2026-11-23T04:25:12.345678+00:00', 'd': date, 'm': 'lunch'},
      },
      kNslotMetaKey: {
        'rebaselined': true,
        'full': 'legacy_seen',
        'inflight_since': '2026-11-23T04:00:00.000Z',
        'inflight_sigs': {row['entry_id']: nslotSignature(row)},
      },
      SyncSkipDomain.nslot.indexKey: {'$date lunch': 'fp'},
      SyncSkipDomain.nlog.indexKey: {'$date lunch': 'fp'},
    });
    expect(answers(), before);
  });

  test('logMeal stamps a fresh entry_id on every meal (§4.1)', () async {
    final now = DateTime.now();
    final a = await _log(now, 'lunch', _item);
    final b = await _log(now, 'lunch', _item); // the same food again
    final box = HiveService.instance.nutritionBox;
    final ia = (box.get(a) as Map)['entry_id'];
    final ib = (box.get(b) as Map)['entry_id'];
    expect(ia, isA<String>());
    expect(ib, isA<String>());
    expect(ia, isNot(ib));
  });

  test('editLog never re-identifies or re-slots a row (§4.1)', () async {
    final now = DateTime.now();
    final k = await _log(now, 'lunch', _item);
    final box = HiveService.instance.nutritionBox;
    final before = Map<String, dynamic>.from(box.get(k) as Map);
    final r = await NutritionWriteService.instance.editLog(logKey: k, updates: {
      'entry_id': 'forged',
      'id': 'nlog_x',
      'log_key': 'nlog_x',
      'date': '2001-01-01',
      'meal_type': 'dinner',
      'total_calories': 210,
    });
    expect(r.success, isTrue);
    final after = box.get(k) as Map;
    for (final f in NutritionWriteService.kEditLogProtectedKeys) {
      expect(after[f], before[f], reason: f);
    }
    expect(after['total_calories'], 210);
  });

  test('an undo of a meal a pull brought back is refused (§4.1, R9 F5)',
      () async {
    final now = DateTime.now();
    final k = await _log(now, 'lunch', _item);
    final box = HiveService.instance.nutritionBox;
    final row = Map<String, dynamic>.from(box.get(k) as Map);
    await NutritionWriteService.instance.deleteLog(logKey: k);
    // A pull puts the same entry back (another device still had it).
    await box.put('${k}_2', {...row, 'id': '${k}_2', 'log_key': '${k}_2'});
    final r =
        await NutritionWriteService.instance.restoreLastDeleted(expectedKey: k);
    expect(r.success, isFalse);
    final ids = [
      for (final key in box.keys)
        if (nslotIsMealRow(key, box.get(key))) (box.get(key) as Map)['entry_id'],
    ];
    expect(ids.where((i) => i == row['entry_id']), hasLength(1));
  });

  // ---- forcing function (presence only) ---------------------------------

  test('every whole-box nutrition loop in lib/ filters on date / nlog_ / '
      'saved-meal markers (the bookkeeping keys carry none)', () {
    final loop = RegExp(
        r'nutritionBox\s*\.\s*(values\b|keys\b|toMap\(\))');
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll(r'\', '/');
      if (p.contains('lib/core/services/sync/') ||
          p.endsWith('nutrition_write_service.dart') ||
          p.endsWith('nlog_key_migrator.dart') ||
          p.endsWith('saved_meal_key_migrator.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (!loop.hasMatch(lines[i])) continue;
        if (!lines[i].contains('for (')) {
          // `final entries = box.toMap();` then a loop below it.
          if (!lines[i].contains('toMap()')) continue;
        }
        final window = lines.skip(i).take(14).join('\n');
        final filtered = window.contains("['date']") ||
            window.contains("startsWith('nlog_')") ||
            window.contains("['is_saved_meal']") ||
            window.contains('nslotIsMealRow');
        found.add('$p:${i + 1}');
        expect(filtered, isTrue,
            reason: '$p:${i + 1} reads every nutritionBox value without a '
                'date / nlog_ / saved-meal filter: the slot sync keys would '
                'reach it');
      }
    }
    // A NEW whole-box reader must be looked at (and this count raised).
    expect(found.length, 17, reason: found.join('\n'));
  });
}
