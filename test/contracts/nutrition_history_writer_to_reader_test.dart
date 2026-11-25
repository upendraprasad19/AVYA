// SoT `nutrition_history` (derived, nothing stored): the daily series and its
// aggregates behind the Nutrition History screen
// (lib/features/nutrition/services/nutrition_history.dart), fed by
// `NutritionWriteService.logMeal` rows. A day here must always equal
// `NutritionReadService.totalMacrosForDate`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_history_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/nutrition/services/nutrition_history.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../sync/sync_domain_skip_harness.dart';

Map<String, dynamic> _meal(String date, double kcal,
        {String slot = 'lunch', double protein = 0, List<Map>? items}) =>
    {
      'date': date,
      'meal_type': slot,
      'total_calories': kcal,
      'total_protein': protein,
      'total_carbs': 10.0,
      'total_fat': 5.0,
      'total_fiber': 2.0,
      if (items != null) 'items': items,
    };

const DayTarget _t =
    (calories: 2000, protein: 100, carbs: 250, fat: 60, assumed: false);

NutritionDay _day(String date, double kcal, {double protein = 100, int water = 0}) =>
    NutritionDay(
        date: date, logged: true, calories: kcal, protein: protein, waterMl: water);

/// [n] consecutive days from [from], calories by [kcal] (null = not logged).
List<JudgedDay> _judged(String from, int n, double? Function(int i, String day) kcal,
    {String today = '2099-01-01', double protein = 100}) {
  final start = parseDayKey(from)!;
  return judgeDays([
    for (var i = 0; i < n; i++)
      () {
        final key = dayKeyOf(start.add(Duration(days: i)));
        final v = kcal(i, key);
        return v == null ? NutritionDay(date: key) : _day(key, v, protein: protein);
      }(),
  ], (_) => _t, today);
}

void main() {
  group('calendar helpers', () {
    test('weekIndexOfDateKey: Monday 0 .. Sunday 6, outside the week null', () {
      const today = '2026-11-25'; // a Wednesday
      expect(weekIndexOfDateKey('2026-11-23', today), 0);
      expect(weekIndexOfDateKey('2026-11-24', today), 1);
      expect(weekIndexOfDateKey('2026-11-25', today), 2);
      expect(weekIndexOfDateKey('2026-11-29', today), 6);
      expect(weekIndexOfDateKey('2026-11-22', today), isNull);
      expect(weekIndexOfDateKey('2026-11-30', today), isNull);
      expect(weekIndexOfDateKey('junk', today), isNull);
      // A Monday and a Sunday as "today".
      expect(weekIndexOfDateKey('2026-11-23', '2026-11-23'), 0);
      expect(weekIndexOfDateKey('2026-11-23', '2026-11-29'), 0);
    });

    test('a day key is strict: ten characters and a real date (B-pass F3)', () {
      expect(parseDayKey('2026-11-25'), DateTime.utc(2026, 11, 25));
      for (final bad in const [
        '2026-13-45', '2026-02-30', '2026/11/25', '20261125',
        '2026-11-25T10:00', '2026-11-2', '', 'junk-junk-',
      ]) {
        expect(parseDayKey(bad), isNull, reason: bad);
        expect(weekIndexOfDateKey(bad, '2026-11-25'), isNull, reason: bad);
      }
      // A row whose date is not a day key is counted nowhere (the day reader
      // matches a day key by equality, so it never counted it either).
      final days = buildNutritionDays([
        _meal('2026-11-25T10:00', 500),
        _meal('2026-13-45', 500),
      ], const {}, fromDay: '2026-11-25', toDay: '2027-12-31');
      expect(days.every((d) => !d.logged), isTrue);
      expect(firstMealDay([_meal('2026-13-45', 1), _meal('0001/01/01', 1)]),
          isNull);
    });

    test('weekend and Monday come from the key', () {
      expect(isWeekendDayKey('2026-11-28'), isTrue); // Saturday
      expect(isWeekendDayKey('2026-11-29'), isTrue);
      expect(isWeekendDayKey('2026-11-27'), isFalse);
      expect(mondayOfDayKey('2026-11-29'), '2026-11-23');
      expect(mondayOfDayKey('2026-11-23'), '2026-11-23');
    });
  });

  group('buildNutritionDays', () {
    test('continuous range, gaps unlogged, totals and slots summed', () {
      final days = buildNutritionDays([
        _meal('2026-11-01', 500, slot: 'breakfast', protein: 30),
        _meal('2026-11-01', 700, slot: 'Lunch', protein: 40),
        _meal('2026-11-01', 100, slot: 'snack'),
        _meal('2026-11-03', 900, slot: 'dinner'),
        _meal('2026-10-31', 999), // before the range
        _meal('2026-11-04', 999), // after the range
      ], {
        '2026-11-02': 1500,
      }, fromDay: '2026-11-01', toDay: '2026-11-03');

      expect(days.map((d) => d.date),
          ['2026-11-01', '2026-11-02', '2026-11-03']);
      expect(days.map((d) => d.logged), [true, false, true]);
      expect((days[0].calories, days[0].protein, days[0].fiber), (1300, 70, 6));
      expect(days[0].caloriesBySlot,
          {'breakfast': 500.0, 'lunch': 700.0, 'snacks': 100.0});
      expect(days[0].caloriesBySlot.values.reduce((a, b) => a + b),
          days[0].calories);
      expect((days[1].calories, days[1].waterMl), (0, 1500));
    });

    test('non-meal rows never make a day logged', () {
      final days = buildNutritionDays([
        // A saved meal carrying a date (never counted).
        {..._meal('2026-11-01', 800), 'is_saved_meal': true},
        // A legacy one-day target override: has a date, no meal_type, no totals.
        {'date': '2026-11-01', 'delta_kcal': -200, 'reason': 'x', 'expires_at': 'y'},
        'a string',
        ['a list'],
      ], const {}, fromDay: '2026-11-01', toDay: '2026-11-01');
      expect((days.single.logged, days.single.calories), (false, 0));
    });

    test('firstMealDay ignores non-meal rows', () {
      expect(
          firstMealDay([
            {'date': '2026-01-01', 'delta_kcal': 1},
            {..._meal('2026-02-01', 1), 'is_saved_meal': true},
            _meal('2026-03-05', 1),
            _meal('2026-03-02', 1),
          ]),
          '2026-03-02');
      expect(firstMealDay(const []), isNull);
    });
  });

  group('dayStatusOf', () {
    const today = '2026-11-25';
    DayStatus s(double kcal, double protein, {String date = '2026-11-10', DayTarget? t = _t}) =>
        dayStatusOf(_day(date, kcal, protein: protein), t, today);

    test('boundaries of the on-target rule', () {
      expect(s(2000, 100), DayStatus.onTarget);
      expect(s(2200, 90), DayStatus.onTarget, reason: 'exactly +10 % and 90 %');
      expect(s(1800, 90), DayStatus.onTarget, reason: 'exactly -10 %');
      expect(s(2201, 100), DayStatus.over);
      expect(s(1799, 100), DayStatus.under);
      expect(s(2000, 89.9), DayStatus.lowProtein,
          reason: 'calories fine, protein short: never "under" (B-pass F8)');
      expect(DayStatus.lowProtein.isComplete, isTrue);
      expect(s(2201, 10), DayStatus.over);
    });

    test('today, partial, not logged, no target', () {
      expect(s(2000, 100, date: today), DayStatus.inProgress);
      expect(s(499, 100), DayStatus.partial);
      expect(s(500, 100), DayStatus.under, reason: 'exactly 25 % is complete');
      expect(dayStatusOf(const NutritionDay(date: '2026-11-10'), _t, today),
          DayStatus.notLogged);
      expect(dayStatusOf(const NutritionDay(date: today), _t, today),
          DayStatus.notLogged, reason: 'today with nothing logged');
      expect(s(299, 100, t: null), DayStatus.partial);
      expect(s(300, 100, t: null), DayStatus.logged);
    });
  });

  group('aggregates use complete days only', () {
    const today = '2026-11-08';
    // Mon 2 Nov .. Sun 8 Nov (today). Tue is unlogged, Wed is a snack day.
    final days = judgeDays([
      _day('2026-11-02', 2000),
      const NutritionDay(date: '2026-11-03'),
      _day('2026-11-04', 120),
      _day('2026-11-05', 2400),
      _day('2026-11-06', 1600, protein: 50),
      _day('2026-11-07', 2000),
      _day('2026-11-08', 300),
    ], (_) => _t, today);

    test('statuses', () {
      expect(days.map((j) => j.status), [
        DayStatus.onTarget,
        DayStatus.notLogged,
        DayStatus.partial,
        DayStatus.over,
        DayStatus.under,
        DayStatus.onTarget,
        DayStatus.inProgress,
      ]);
    });

    test('average and rolling average skip unlogged, partial and today', () {
      final avg = averageOf(days, NutritionMetric.calories, today);
      expect((avg.avg, avg.n), (2000, 4));
      final roll = rollingAverage(days, NutritionMetric.calories, today);
      expect(roll, [2000, 2000, 2000, 2200, 2000, 2000, 2000]);
      expect(rollingAverage(days, NutritionMetric.calories, today, window: 1),
          [2000, null, null, 2400, 1600, 2000, null]);
    });

    test('weekly bucket: sample size and macro shares', () {
      final w = weeklyBuckets(days).single;
      expect((w.monday, w.completeDays, w.avgCalories), ('2026-11-02', 4, 2000));
      expect(w.proteinShare, 1.0, reason: 'only protein grams in the fixture');
      final mixed = weeklyBuckets(judgeDays([
        const NutritionDay(
            date: '2026-11-02', logged: true, calories: 2000,
            protein: 100, carbs: 200, fat: 50),
      ], (_) => _t, today)).single;
      // 400 + 800 + 450 kcal.
      expect(mixed.proteinShare, closeTo(400 / 1650, 1e-9));
      expect(mixed.carbShare, closeTo(800 / 1650, 1e-9));
      expect(mixed.fatShare, closeTo(450 / 1650, 1e-9));
    });

    test('hit-rate and runs: today never breaks a run, a gap does', () {
      final cal = hitStats(days, HitKind.calories, today);
      expect((cal.counted, cal.hits, cal.bestRun, cal.currentRun), (4, 2, 1, 1));
      final pro = hitStats(days, HitKind.protein, today);
      expect((pro.counted, pro.hits, pro.bestRun, pro.currentRun), (4, 3, 1, 1));

      final streak = _judged('2026-11-02', 6, (i, _) => 2000, today: '2026-11-07');
      final s = hitStats(streak, HitKind.calories, '2026-11-07');
      expect((s.counted, s.bestRun, s.currentRun), (5, 5, 5));
    });

    test('water is judged against the current water target, today excluded', () {
      final water = judgeDays([
        _day('2026-11-05', 2000, water: 3000),
        _day('2026-11-06', 2000, water: 1000),
        const NutritionDay(date: '2026-11-07', waterMl: 2500),
        _day('2026-11-08', 2000, water: 9000),
      ], (_) => _t, today);
      final s = hitStats(water, HitKind.water, today, waterTargetMl: 2500);
      expect((s.counted, s.hits, s.bestRun, s.currentRun), (3, 2, 1, 1));
      expect(averageOf(water, NutritionMetric.water, today).n, 3);
    });

    test('no target: nothing is judged', () {
      final none = judgeDays([_day('2026-11-02', 2000)], (_) => null, today);
      expect(none.single.status, DayStatus.logged);
      expect(hitStats(none, HitKind.calories, today).counted, 0);
      expect(averageOf(none, NutritionMetric.calories, today).n, 1);
    });

    test('patterns', () {
      final ww = weekdayWeekend(days);
      expect((ww.a, ww.aDays, ww.b, ww.bDays), (2000, 3, 2000, 1));
      final tr = trainingVsRest(days, {'2026-11-05', '2026-11-04'});
      expect((tr.a, tr.aDays, tr.bDays), (2400, 1, 3));
      expect(tr.b, closeTo(1866.67, 0.01));
      final slots = slotAverages(judgeDays([
        const NutritionDay(
            date: '2026-11-02', logged: true, calories: 2000,
            caloriesBySlot: {'lunch': 1500, 'snacks': 500}),
      ], (_) => _t, today));
      expect(slots,
          {'breakfast': 0.0, 'lunch': 1500.0, 'dinner': 0.0, 'snacks': 500.0});
    });
  });

  group('top foods', () {
    test('grouping, plural fold, digit-led names, rows without items', () {
      Map i(String name, {double p = 0, double c = 0}) =>
          {'name': name, 'protein': p, 'calories': c};
      final foods = topFoods([
        _meal('2026-11-01', 1, items: [i('Egg', p: 6, c: 70), i('7 Up', c: 150)]),
        _meal('2026-11-02', 1, items: [i('eggs ', p: 12, c: 140), i('Roti x2', c: 200)]),
        _meal('2026-11-03', 1, items: [i('Egg', p: 6, c: 70), i('roti (2 pieces)', c: 200)]),
        _meal('2026-11-04', 1, items: [i('5 Star Bar', c: 100)]),
        _meal('2026-11-05', 1), // no items[]
        _meal('2026-12-01', 1, items: [i('Egg')]), // out of range
        {..._meal('2026-11-02', 1, items: [i('Egg')]), 'is_saved_meal': true},
      ], fromDay: '2026-11-01', toDay: '2026-11-30');

      expect(foods.mealsWithoutItems, 1);
      expect([for (final f in foods.mostLogged) (f.name, f.count)], [
        ('Egg', 3),
        ('Roti x2', 2),
        ('5 Star Bar', 1),
        ('7 Up', 1),
      ]);
      expect(foods.mostLogged.first.protein, 24);
      expect(foods.topProtein.map((f) => f.name), ['Egg']);
      expect(foodNameKey('7 Up'), '7 up');
      expect(foodNameKey('  Paneer   Tikka (150 g) '), 'paneer tikka');
    });
  });

  group('insight lines, each side of its threshold', () {
    // 2026-11-02 is a Monday. Weekday kcal [wk], weekend kcal [we].
    List<JudgedDay> weeks(int n, double wk, double we) => _judged(
        '2026-11-02', n, (i, day) => isWeekendDayKey(day) ? we : wk);

    test('weekend vs weekday: sample and effect', () {
      // 14 days: 10 weekdays, 4 weekend days.
      expect(nutritionInsights(weeks(14, 2000, 2150), const {}, '2099-01-01'),
          contains('You eat about 150 kcal more on weekends.'));
      expect(nutritionInsights(weeks(14, 2000, 2149), const {}, '2099-01-01'),
          isNot(contains(startsWith('You eat about'))));
      expect(nutritionInsights(weeks(14, 2000, 1800), const {}, '2099-01-01'),
          contains('You eat about 200 kcal less on weekends.'));
      // 13 days: only 3 weekend days.
      expect(nutritionInsights(weeks(13, 2000, 2500), const {}, '2099-01-01'),
          isNot(contains(startsWith('You eat about'))));
    });

    test('training vs rest: 5 days each and 150 kcal', () {
      List<String> run(int training, double gap) {
        final days = _judged('2026-11-02', 10, (i, _) => i < training ? 2000 + gap : 2000);
        final set = {for (var i = 0; i < training; i++) days[i].date};
        return nutritionInsights(days, set, '2099-01-01');
      }

      expect(run(5, 150), contains('You eat about 150 kcal more on training days.'));
      expect(run(5, 149), isNot(contains(contains('training days'))));
      expect(run(4, 400), isNot(contains(contains('training days'))));
    });

    test('protein now vs first month: 14 days each and 10 g', () {
      List<String> run(double later) => nutritionInsights(
          judgeDays([
            for (var i = 0; i < 60; i++)
              _day(dayKeyOf(DateTime.utc(2026, 1, 1).add(Duration(days: i))), 2000,
                  protein: i < 30 ? 100 : later),
          ], (_) => _t, '2099-01-01'),
          const {},
          '2099-01-01');
      expect(run(110),
          contains('Your protein is up about 10 g a day since your first month.'));
      expect(run(109), isNot(contains(contains('since your first month'))));
      expect(run(85),
          contains('Your protein is down about 15 g a day since your first month.'));
    });

    test('logging consistency: 10 points', () {
      List<String> run(int recentLogged) => nutritionInsights(
          _judged('2026-01-01', 60,
              (i, _) => (i < 30 ? i < 15 : i - 30 < recentLogged) ? 2000 : null),
          const {},
          '2099-01-01');
      expect(run(18), contains('You logged 60% of the last 30 days, up from 50%.'));
      expect(run(17), isNot(contains(startsWith('You logged'))));
      expect(run(12), contains('You logged 40% of the last 30 days, down from 50%.'));
    });

    test('best protein run: 5 days', () {
      List<String> run(int n) => nutritionInsights(
          _judged('2026-11-02', n, (i, _) => 2000), const {}, '2099-01-01');
      expect(run(5), contains('Your best protein run is 5 days in a row.'));
      expect(run(4), isNot(contains(startsWith('Your best protein run'))));
    });

    test('never more than four lines', () {
      final days = judgeDays([
        for (var i = 0; i < 70; i++)
          () {
            final key = dayKeyOf(DateTime.utc(2026, 1, 5).add(Duration(days: i)));
            if (i >= 10 && i < 30) return NutritionDay(date: key);
            return _day(key, isWeekendDayKey(key) ? 2600 : 2000,
                protein: i < 30 ? 95 : 130);
          }(),
      ], (_) => _t, '2099-01-01');
      final training = {
        for (final j in days)
          if (isWeekendDayKey(j.date)) j.date,
      };
      expect(nutritionInsights(days, training, '2099-01-01').length,
          lessThanOrEqualTo(kMaxInsights));
    });
  });

  group('on real Hive', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      h.server.clear();
      DietStrategyFlags.debugEnabledOverride = false;
    });
    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
      await h.tearDown();
    });

    const rice = FoodItem(
        name: 'Rice', quantityG: 150, calories: 200, protein: 4, carbs: 44, fat: 0, fiber: 1);
    const dal = FoodItem(
        name: 'Dal', quantityG: 200, calories: 240, protein: 14, carbs: 30, fat: 6, fiber: 8);

    Future<void> log(DateTime date, String slot, List<FoodItem> items) async {
      final r = await NutritionWriteService.instance.logMeal(
          date: date, mealType: slot, items: items,
          source: NutritionWriteSource.manualSearch);
      expect(r.success, isTrue, reason: '${r.errorMessage}');
    }

    test('every day of the series equals totalMacrosForDate, with the other '
        'row kinds of the box present', () async {
      final now = DateTime.now();
      final d0 = now, d2 = now.subtract(const Duration(days: 2));
      final d5 = now.subtract(const Duration(days: 5));
      await log(d5, 'breakfast', [rice]);
      await log(d5, 'dinner', [rice, dal]);
      await log(d2, 'lunch', [dal]);
      await log(d2, 'lunch', [dal]); // the same meal twice is two entries
      await log(d0, 'snacks', [rice]);

      final box = HiveService.instance.nutritionBox;
      final k2 = istDateStr(d2);
      await box.putAll({
        'meal_template_1': {..._meal(k2, 800), 'is_saved_meal': true},
        'target_override_$k2': {'date': k2, 'delta_kcal': -300, 'expires_at': 'x'},
        '$kNslotLedgerPrefix$k2': {
          'lunch': {'rev': 3, 'ua': '2026-11-23T04:30:12Z', 'e': {'id': 'sig'}},
        },
        kNslotCursorKey: {
          'rows': {'ts': '2026-11-23T04:25:12Z', 'row': 'r1'},
        },
        kNslotMetaKey: {'rebaselined': true, 'full': 'legacy_seen'},
      });
      await HiveService.instance.healthBox.put('water_ml_$k2', 1750);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final data = c.read(nutritionHistoryProvider);

      expect(data.fromDay, istDateStr(d5));
      expect(data.days.length, 6);
      expect(data.daysLogged, 3);
      for (var i = 0; i < data.days.length; i++) {
        final day = data.days[i].day;
        final truth = NutritionReadService.instance
            .totalMacrosForDate(d5.add(Duration(days: i)));
        expect(
            (day.calories, day.protein, day.carbs, day.fat, day.fiber),
            (
              truth['calories'], truth['protein'], truth['carbs'],
              truth['fat'], truth['fiber'],
            ),
            reason: day.date);
      }
      expect(data.days[3].day.calories, 480, reason: 'two dal lunches');
      expect(data.days[3].day.waterMl, 1750);
      expect(data.days.last.status, DayStatus.inProgress);
      expect(data.hasTargets, isFalse);
      expect(data.foods.mostLogged.map((f) => (f.name, f.count)),
          [('Dal', 3), ('Rice', 3)]);
    });

    test('targets: days before the first entry are assumed; a meal log, a '
        'target change and a restore tick each rebuild the data', () async {
      final now = DateTime.now();
      await log(now.subtract(const Duration(days: 3)), 'lunch', [dal]);
      await ProfileWriteService.instance.updateProfile({
        'daily_calories': 2000, 'protein_grams': 100, 'carb_grams': 250, 'fat_grams': 60,
      });

      final c = ProviderContainer();
      addTearDown(c.dispose);
      var data = c.read(nutritionHistoryProvider);
      expect(data.hasTargets, isTrue);
      expect(data.firstTargetDay, data.todayKey);
      expect((data.days.first.target!.calories, data.days.first.target!.assumed),
          (2000, true));
      expect(data.days.last.target!.assumed, isFalse);
      expect(data.days.first.status, DayStatus.partial, reason: '240 of 2000 kcal');

      // An older entry: the first day is then judged against ITS target.
      await HiveService.instance.userBox.put(TargetHistoryService.boxKey, [
        {
          'from': data.fromDay, 'calories': 300, 'protein': 10, 'carbs': 30,
          'fat': 5, 'strategy': 'balanced', 'at_ms': 1,
        },
        ...TargetHistoryService.read().map((e) => e.toMap()),
      ]);
      c.invalidate(macroTargetsProvider);
      data = c.read(nutritionHistoryProvider);
      expect((data.days.first.target!.calories, data.days.first.target!.assumed),
          (300, false));
      expect(data.days.first.status, DayStatus.under, reason: '240 vs 300 kcal');

      await log(now.subtract(const Duration(days: 1)), 'dinner', [rice]);
      c.invalidate(dailyNutritionProvider);
      expect(c.read(nutritionHistoryProvider).daysLogged, 2);
    });

    test('one garbled old row cannot stretch the series past ten years; a zero '
        'calorie target judges nothing (B-pass F4, F7)', () {
      final data = buildNutritionHistoryData(
        inputs: (
          rows: [_meal('1970-01-01', 500), _meal('2026-11-20', 1900, protein: 100)],
          waterByDay: const {},
          trainingDays: const {},
          onboardingDay: null,
          targets: const [
            TargetEntry(
                from: '2026-01-01', calories: 0, protein: 100, carbs: 0,
                fat: 0, strategy: 'balanced', atMs: 1),
          ],
        ),
        todayKey: '2026-11-25',
        waterTargetMl: 0,
        weights: const [],
      );
      expect(data.days.length, kHistoryMaxDays);
      expect(data.days.last.date, '2026-11-25');
      final logged = data.days.firstWhere((j) => j.date == '2026-11-20');
      expect((logged.target, logged.status), (null, DayStatus.logged));
    });

    test('the inputs carry the onboarding day when it is the earliest', () async {
      await HiveService.instance.userBox.put('profile', {
        'onboarding_completed_at': '2026-08-12T03:00:00.000Z',
      });
      final inputs = NutritionRepository.instance.loadHistoryInputs();
      expect(inputs.onboardingDay, '2026-08-12');
      final data = buildNutritionHistoryData(
          inputs: inputs, todayKey: '2026-08-20', waterTargetMl: 0, weights: const []);
      expect((data.fromDay, data.days.length, data.isEmpty), ('2026-08-12', 9, true));
    });

    test('730 days of four meals build well inside a frame budget', () async {
      final rows = <Object?>[
        for (var i = 0; i < 730; i++)
          for (final slot in kMealSlots)
            _meal(dayKeyOf(DateTime.utc(2025, 1, 1).add(Duration(days: i))), 500,
                slot: slot, protein: 25, items: [
              {'name': 'Food ${i % 40}', 'protein': 25, 'calories': 500},
            ]),
      ];
      final sw = Stopwatch()..start();
      final data = buildNutritionHistoryData(
        inputs: (
          rows: rows,
          waterByDay: const {},
          trainingDays: const {},
          onboardingDay: '2025-01-01',
          targets: [
            const TargetEntry(
                from: '2025-01-01', calories: 2000, protein: 100, carbs: 250,
                fat: 60, strategy: 'balanced', atMs: 1),
          ],
        ),
        todayKey: '2026-12-31',
        waterTargetMl: 2500,
        weights: const [],
      );
      sw.stop();
      expect(data.days.length, 730);
      expect(sw.elapsedMilliseconds, lessThan(400));
    });
  });
}
