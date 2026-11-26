// Diagnose d7b3f1: the weekly Insights cards put a day's meals on the wrong
// bar.
//
// `WeeklyNutritionNotifier` took "Monday" as `now - (weekday - 1) days`, which
// keeps the current time of day, then indexed a row with
// `date.difference(weekStart).inDays` (truncating). At any time other than
// exactly midnight every day after Monday landed one bar early: Tuesday merged
// into Monday and Sunday's bar stayed empty. The index is now the calendar-day
// difference between two IST date keys (`weekIndexOfDateKey`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

import '../sync/sync_domain_skip_harness.dart';

Map<String, dynamic> _meal(String date, double kcal) => {
      'date': date,
      'meal_type': 'lunch',
      'total_calories': kcal,
      'total_protein': 10.0,
    };

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
  });
  tearDown(() => h.tearDown());

  test('every day of the current IST week lands on its own bar', () async {
    final todayKey = istDateStr(DateTime.now());
    final today = DateTime.parse('${todayKey}T00:00:00Z');
    final monday = today.subtract(Duration(days: today.weekday - 1));
    String key(DateTime d) => d.toIso8601String().substring(0, 10);

    // One meal per day from Monday up to today, each with its own calories.
    final box = HiveService.instance.nutritionBox;
    for (var i = 0; i < today.weekday; i++) {
      final d = key(monday.add(Duration(days: i)));
      await box.put('nlog_${d}_lunch_aaaaaaaa', _meal(d, 100.0 * (i + 1)));
    }
    // Last Sunday and next Monday are outside the week.
    final lastSunday = key(monday.subtract(const Duration(days: 1)));
    await box.put('nlog_${lastSunday}_lunch_aaaaaaaa', _meal(lastSunday, 9000));

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final week = c.read(weeklyNutritionProvider);

    final expected = [
      for (var i = 0; i < 7; i++) i < today.weekday ? 100.0 * (i + 1) : 0.0,
    ];
    expect(week.calories, expected);
  });
}
