// Nutrition History v2 (plan docs/plans/nutrition-history-v2.md): the pure
// rules behind the header, runs, zero-state, calendar months, food families
// (3cfcc6), the new views and the monthly report. Diagnoses 60dc46, 3cfcc6.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/nutrition_history.dart';
import 'package:icanbefitter/features/nutrition/services/nutrition_history_views.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_common.dart';
import 'package:icanbefitter/features/nutrition/widgets/history/history_heatmap.dart';

const DayTarget _t =
    (calories: 2000, protein: 100, carbs: 250, fat: 60, assumed: false);

/// Continuous days from [from]; [day] returns null for an unlogged day.
List<JudgedDay> _days(String from, int n,
    NutritionDay? Function(int i, String key) day,
    {String today = '2099-01-01', DayTarget? target = _t}) {
  final start = parseDayKey(from)!;
  return judgeDays([
    for (var i = 0; i < n; i++)
      () {
        final key = dayKeyOf(start.add(Duration(days: i)));
        return day(i, key) ?? NutritionDay(date: key);
      }(),
  ], (_) => target, today);
}

NutritionDay _full(String key,
        {double kcal = 2000,
        double protein = 100,
        Map<String, double> pslots = const {}}) =>
    NutritionDay(
        date: key,
        logged: true,
        calories: kcal,
        protein: protein,
        proteinBySlot: pslots);

void main() {
  group('runs (60dc46)', () {
    test('a sparse logger keeps a protein run across unlogged days', () {
      // A full on-target day every third day: the old rule broke on every gap.
      final days = _days('2026-10-01', 30,
          (i, k) => i % 3 == 0 ? _full(k) : null, today: '2026-10-31');
      final s = hitStats(days, HitKind.protein, '2026-10-31');
      expect((s.counted, s.hits, s.bestRun, s.currentRun), (10, 10, 10, 10));
    });

    test('a full day that misses still breaks the run', () {
      final days = _days('2026-10-01', 5,
          (i, k) => _full(k, protein: i == 2 ? 40 : 100), today: '2026-10-06');
      final s = hitStats(days, HitKind.protein, '2026-10-06');
      expect((s.bestRun, s.currentRun), (2, 2));
    });

    test('a run whose last full day is over 7 days old is not current', () {
      List<JudgedDay> at(String today) => _days(
          '2026-10-01', 3, (i, k) => _full(k), today: today);
      // Last counted day 2026-10-03.
      expect(hitStats(at('2026-10-10'), HitKind.protein, '2026-10-10').currentRun,
          3, reason: '7 days later is still current');
      expect(hitStats(at('2026-10-11'), HitKind.protein, '2026-10-11').currentRun,
          0, reason: '8 days later is stale');
      expect(hitStats(at('2026-10-11'), HitKind.protein, '2026-10-11').bestRun, 3);
    });

    test('water keeps the break rule and no recency bound', () {
      final days = judgeDays([
        const NutritionDay(date: '2026-10-01', logged: true, calories: 2000,
            protein: 100, waterMl: 3000),
        const NutritionDay(date: '2026-10-02'),
        const NutritionDay(date: '2026-10-03', logged: true, calories: 2000,
            protein: 100, waterMl: 3000),
      ], (_) => _t, '2026-12-31');
      final s = hitStats(days, HitKind.water, '2026-12-31', waterTargetMl: 2500);
      expect((s.hits, s.bestRun, s.currentRun), (2, 1, 1));
    });
  });

  group('header (U1) and logging run (U3)', () {
    test('last 30 days includes today and never exceeds 30', () {
      final days = _days('2026-10-01', 40, (i, k) => _full(k),
          today: '2026-11-09');
      final s = journeyStats(days);
      expect((s.logged, s.logged30), (40, 30));
      expect(journeyStats(days.sublist(10)).logged30, isNull,
          reason: '30 days or fewer repeats days logged');
    });

    test('avg protein over full days of the window only', () {
      final days = _days('2026-10-01', 40,
          (i, k) => _full(k, protein: i < 10 ? 50 : 120), today: '2099-01-01');
      expect(journeyStats(days).avgProtein30, 120);
    });

    test('logging run counts back from today or yesterday', () {
      final today = '2026-10-10';
      final days = _days('2026-10-01', 10,
          (i, k) => (i == 4 || i == 9) ? null : _full(k), today: today);
      final r = loggingRun(days, today);
      expect((r.current, r.best, r.todayLogged), (4, 4, false));
      expect(loggingRunLine(r),
          'Logged 4 days in a row. Log today to make it 5.');
      final logged = _days('2026-10-01', 10, (i, k) => i == 4 ? null : _full(k),
          today: today);
      expect(loggingRunLine(loggingRun(logged, today)),
          'Logged 5 days in a row, today included.');
      final one = _days('2026-10-01', 10, (i, k) => i == 9 ? _full(k) : null,
          today: today);
      expect(loggingRunLine(loggingRun(one, today)),
          'Logged 1 day, today included.');
      final none = _days('2026-10-01', 10, (i, k) => i < 5 ? _full(k) : null,
          today: today);
      expect(loggingRunLine(loggingRun(none, today)),
          'Log a meal today to start a logging run. Best: 5.');
    });
  });

  group('zero-state (U4)', () {
    test('calories: majority under, over and a tie', () {
      List<JudgedDay> d(List<double> kcal) => _days('2026-10-01', kcal.length,
          (i, k) => _full(k, kcal: kcal[i]), today: '2099-01-01');
      expect(hitZeroReason(d([1500, 1500, 2600]), HitKind.calories, '2099-01-01'),
          startsWith('Most of your full days were under'));
      expect(hitZeroReason(d([2600, 2600, 1500]), HitKind.calories, '2099-01-01'),
          startsWith('Most of your full days were over'));
      expect(
          hitZeroReason(
              d([1500, 1500, 2600, 2600]), HitKind.calories, '2099-01-01'),
          startsWith('Your full days landed both under and over'));
      expect(hitZeroReason(d([1500, 1500]), HitKind.calories, '2099-01-01'),
          isNull, reason: 'fewer than 3 counted days');
      expect(hitZeroReason(d([1500, 1500, 2000]), HitKind.calories, '2099-01-01'),
          isNull, reason: 'a hit exists');
    });

    test('protein line uses the current target', () {
      final days = _days('2026-10-01', 3, (i, k) => _full(k, protein: 60),
          today: '2099-01-01');
      expect(hitZeroReason(days, HitKind.protein, '2099-01-01'),
          'Your full days averaged 60 g; 90% of your current target is 90 g. '
          'Hit 90 g tomorrow to start a run.');
      expect(hitZeroReason(days, HitKind.water, '2099-01-01'), isNull);
    });
  });

  group('calendar months (U6)', () {
    test('blocks per month; a month starting Sunday; tap mapping', () {
      // 2026-11-29 is a Sunday; Dec 2026 starts Tuesday.
      final days = _days('2026-11-29', 5, (i, k) => _full(k));
      final b = monthBlocks(days, (_) => 10);
      expect([for (final x in b) (x.label, x.firstRow, x.start, x.length)],
          [('Nov', 6, 0, 2), ('Dec', 1, 2, 3)]);
      const step = kHeatCell + kHeatGap;
      const y0 = kHeatLabelRow;
      expect(monthBlockIndexAt(b, 5, y0 + 6 * step + 5), 0);
      expect(monthBlockIndexAt(b, b[1].x + 5, y0 + step + 5), 2);
      expect(monthBlockIndexAt(b, b[0].x + b[0].width + 3, y0 + step + 5),
          isNull, reason: 'the gap between months');
    });

    test('the year joins the first block and January across a year', () {
      final days = _days('2026-12-30', 4, (i, k) => _full(k));
      final b = monthBlocks(days, (s) => s.length * 6.0);
      expect([for (final x in b) x.label], ['Dec 2026', 'Jan 2027']);
      expect(b.first.width, 'Dec 2026'.length * 6.0,
          reason: 'a 2-day block widens to its label');
      // The empty part of a widened block is not a cell.
      expect(monthBlockIndexAt(b, b.first.width - 1, kHeatLabelRow + 5), isNull);
    });

    test('low protein is red, over stays amber', () {
      expect(statusColor(DayStatus.lowProtein), AppColors.bad);
      expect(statusColor(DayStatus.over), AppColors.warn);
    });
  });

  group('food families (3cfcc6)', () {
    String? fam(String n) => foodFamilyOf(n).$2;
    test('three wheys are one family; order and guards', () {
      expect(fam('Whey protein powder'), 'Whey');
      expect(fam('Whey Protein Isolate'), 'Whey');
      expect(fam('whey protein (1 scoop)'), 'Whey');
      expect(fam('chana dal'), 'Dal');
      expect(fam('dal makhani'), 'Dal');
      expect(fam('almond milk'), 'Almond');
      expect(fam('whey in almond milk'), 'Almond');
      expect(fam('chicken biryani with egg'), 'Chicken');
      expect(fam('Boiled eggs'), 'Egg');
      expect(fam('oats with milk'), 'Oats');
      expect(fam('egg free paneer'), 'Paneer');
      expect(foodFamilyOf('coconut milk'), (true, null));
      for (final n in ['eggplant', 'eggless cake', 'milkshake', 'buttermilk',
          'whey-free bar']) {
        expect(fam(n), isNull, reason: n);
      }
    });

    test('kinds, share and concentration', () {
      Map<String, Object> meal(String day, List<(String, double)> items) => {
            'date': day,
            'meal_type': 'lunch',
            'total_protein': items.fold<double>(0.0, (s, e) => s + e.$2),
            'items': [
              for (final (n, p) in items) {'name': n, 'protein': p}
            ],
          };
      final rows = [
        meal('2026-10-01', [('Whey protein powder', 25), ('Egg', 6)]),
        meal('2026-10-02', [('Whey protein isolate', 27), ('Eggs', 12)]),
        meal('2026-10-03', [('Whey protein', 24), ('Paneer bhurji', 18)]),
        meal('2026-10-04', [('Rice', 4), ('Banana', 1), ('Bananas', 2)]),
        meal('2026-10-05', [('Apple', 0.5), ('Roti', 3)]),
      ];
      final f = topFoods(rows, fromDay: '2026-10-01', toDay: '2026-10-05');
      final whey = f.topProtein.first;
      expect((whey.name, whey.kinds, whey.isFamily), ('Whey', 3, true));
      final egg = f.topProtein.firstWhere((s) => s.name == 'Egg');
      expect(egg.kinds, 1, reason: 'Egg and Eggs are one kind');
      final total = 25 + 6 + 27 + 12 + 24 + 18 + 4 + 1 + 2 + 0.5 + 3;
      expect(whey.proteinShare, closeTo(76 / total, 1e-9));
      expect(f.concentration, isNotNull);
      expect(f.concentration!.foods, 1, reason: 'whey alone is over 60%');
    });
  });

  group('new views', () {
    test('protein by meal: averages, the line, the 30 g cap', () {
      final days = _days('2026-10-01', 3,
          (i, k) => _full(k, protein: 60, pslots: const {
                'breakfast': 5, 'lunch': 25, 'dinner': 30, 'snacks': 0,
              }));
      expect(slotProteinAverages(days)['breakfast'], 5);
      expect(slotProteinLine(days),
          'Breakfast is your lowest-protein meal. Adding 30 g there gets you '
          'to 90% of your current 100 g target.');
      expect(slotProteinAverages(days.sublist(1)), isEmpty);
    });

    test('weekday rates need 4 days and a 30-point gap', () {
      // 2026-10-05 is a Monday. 5 weeks: Mondays hit, Tuesdays miss.
      final days = _days('2026-10-05', 35, (i, k) {
        final wd = i % 7;
        if (wd == 0) return _full(k);
        if (wd == 1) return _full(k, protein: 40);
        return null;
      });
      final r = weekdayProtein(days, '2099-01-01');
      expect((r[0].counted, r[0].hits, r[1].hits), (5, 5, 0));
      expect(weekdayLine(r),
          'Mon is your strongest protein day (100%); Tue drops to 0%.');
      final short = weekdayProtein(days.sublist(0, 21), '2099-01-01');
      expect(weekdayLine(short), isNull, reason: '3 Mondays only');
    });

    test('on-target vs low-protein needs 3 days each side', () {
      List<JudgedDay> d(int low) => _days('2026-10-01', 3 + low,
          (i, k) => _full(k, protein: i < 3 ? 100 : 50, pslots: {
                'breakfast': i < 3 ? 30 : 5,
              }));
      expect(onTargetVsLowProtein(d(2)), isNull);
      final c = onTargetVsLowProtein(d(3))!;
      expect((c.onTarget['breakfast'], c.low['breakfast'], c.nOn, c.nLow),
          (30.0, 5.0, 3, 3));
    });
  });

  group('monthly report (U13)', () {
    test('6 calendar months, empty months, so far, year folds', () {
      // 2025-03-01 .. 2026-11-15: 21 months.
      final from = parseDayKey('2025-03-01')!;
      final n = parseDayKey('2026-11-15')!.difference(from).inDays + 1;
      final days = _days('2025-03-01', n, (i, k) {
        if (k.startsWith('2026-08')) return null; // an empty month
        return i % 2 == 0 ? _full(k) : null;
      }, today: '2026-11-15');
      final rows = monthlyRows(days, const [], '2026-11-15');
      expect([for (final r in rows) r.label], [
        'Nov 2026 (so far)', 'Oct 2026', 'Sep 2026', 'Aug 2026', 'Jul 2026',
        'Jun 2026', 'Jan-May 2026', 'Mar-Dec 2025',
      ]);
      expect(rows[3].empty, isTrue);
      expect(rows[0].arrow, 0, reason: 'no arrow on the month so far');
      expect(rows.last.isYear, isTrue);
      expect(rows.last.months, hasLength(10));
    });

    test('weight: anchors, since, within, dash', () {
      final days = _days('2026-01-01', 120, (i, k) => _full(k),
          today: '2026-04-30');
      final rows = monthlyRows(days, const [
        ('2026-01-05', 80.0),
        ('2026-01-25', 79.0),
        ('2026-03-20', 78.0),
      ], '2026-04-30');
      final byKey = {for (final r in rows) r.key: r};
      expect(byKey['2026-01']!.weightChange, -1.0);
      expect(byKey['2026-01']!.weightNote, 'within Jan');
      expect(byKey['2026-02']!.weightChange, isNull);
      expect(byKey['2026-03']!.weightChange, -1.0);
      expect(byKey['2026-03']!.weightNote, 'since Jan');
      expect(byKey['2026-04']!.weightChange, isNull);
    });
  });

  test('weight change text never shows a signed zero (B-pass P3-2)', () {
    expect(weightChangeText(-0.04), '0.0 kg');
    expect(weightChangeText(0.04), '0.0 kg');
    expect(weightChangeText(-0.06), '−0.1 kg');
    expect(weightChangeText(1.25), '+1.3 kg');
    expect(weightChangeText(null), '—');
  });

  test('chart bounds include the target and widen a flat series', () {
    expect(chartBounds([1850, 2240], target: 2300, step: 100),
        (lo: 1800.0, hi: 2300.0));
    expect(chartBounds([2000, 2000], step: 100), (lo: 1900.0, hi: 2100.0));
  });
}
