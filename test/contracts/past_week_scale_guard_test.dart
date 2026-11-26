// Scale guard for the Train past-week view (docs/plans/train-past-week-in-place.md D6, founder question:
// "a two-year user, will it hang?"). A synthetic two-year box: 730 schedule rows over 26 phases, ~4,000
// exlog_ rows (indexed like the writer does), 500 wlog_ rows. Absolute budget only (never a ratio: CI
// runners vary 2x): max(1000 ms, 10x the time measured on the 4-core VPS when this was written).
// The STRUCTURAL rule (no per-row whole-box read) is killed by the counting seam in
// train_past_week_in_place_behavioral_test.dart; this guards gross regressions of the two scans.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/past_week_scale_guard_test.dart

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

Directory? _dir;

/// Measured on the 4-core VPS (2026-11-26): see the diagnose-doc. Budget = max(1000, 10x measured).
const int _budgetMs = 1000;

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  testWidgets('two years of history: the strip scan and a full past-week build stay under budget',
      (tester) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    late String weekStartYmd;
    await tester.runAsync(() async {
      final wb = HiveService.instance.workoutBox;
      await wb.clear();
      final start = DateTime.utc(2024, 11, 4); // a Monday
      await HiveService.instance.userBox
          .put('progress', {'total_workouts_done': 300, 'current_phase': 27});
      await HiveService.instance.userBox
          .put('plan_start_date', _d(start.add(const Duration(days: 26 * 28))));
      await wb.put('current_plan', {'focus': 'x', 'name': 'Foundation'});
      final batch = <String, dynamic>{};
      var exlogs = 0;
      for (var i = 0; i < 26 * 28; i++) {
        final day = start.add(Duration(days: i));
        final ymd = _d(day);
        final phase = i ~/ 28 + 1;
        final workout = day.weekday != DateTime.sunday;
        batch['schedule_$ymd'] = {
          'date': ymd,
          'phase': phase,
          'week': (i % 28) ~/ 7 + 1,
          'type': workout ? 'workout' : 'rest',
          'status': workout ? (i % 3 == 0 ? 'completed' : 'planned') : 'rest',
          'workout_name': workout ? 'Day $i' : 'Rest Day',
          'exercises': workout && i % 5 != 0
              ? [
                  {'exercise_name': 'Squat', 'sets': 3, 'reps': '5'},
                  {'exercise_name': 'Row', 'sets': 3, 'reps': '8'},
                ]
              : <Map<String, dynamic>>[],
        };
        if (workout && exlogs < 4000) {
          final keys = <String>[];
          for (var k = 0; k < 6 && exlogs < 4000; k++) {
            final key = 'exlog_${ymd}_${k.toRadixString(16).padLeft(8, '0')}';
            batch[key] = {
              'exercise_name': 'Ex $k',
              'date': ymd,
              'set_number': 3,
              'weight_kg': 40.0,
              'reps_completed': 8,
            };
            keys.add(key);
            exlogs++;
          }
          batch['exercise_log_index_$ymd'] = keys;
        }
        if (i % 52 == 0) {
          batch['wlog_$ymd'] = {'workout_name': 'Logged $i', 'duration_seconds': 1800};
        }
      }
      await wb.putAll(batch);
      // The week under test: phase 20, first week, with all four row kinds.
      final s = start.add(const Duration(days: 19 * 28));
      weekStartYmd = _d(s);
      final w = <String, dynamic>{};
      Map<String, dynamic> row(int off, Map<String, dynamic> extra) => {
            'date': _d(s.add(Duration(days: off))),
            'phase': 20,
            'week': 1,
            'type': 'workout',
            'status': 'planned',
            ...extra,
          };
      for (final e in [
        (0, {'workout_name': 'Missed', 'exercises': [{'exercise_name': 'Squat'}]}),
        (1, {'status': 'completed', 'workout_name': 'Done', 'exercises': [{'exercise_name': 'Row'}]}),
        (2, {'exercises': <Map<String, dynamic>>[]}), // nameless, no exercises (logs seeded above)
        (3, {'status': 'completed', 'exercises': <Map<String, dynamic>>[]}),
        (4, {'type': 'rest', 'status': 'rest', 'workout_name': 'Rest Day'}),
      ]) {
        final r = row(e.$1, e.$2);
        w['schedule_${r['date']}'] = r;
      }
      await wb.putAll(w);
    });

    final svc = WorkoutScheduleReadService.instance;
    final sw = Stopwatch()..start();
    final blocks = svc.pastPhaseBlocksForDisplay(27);
    final stripMs = sw.elapsedMilliseconds;
    expect(blocks.length, greaterThan(20), reason: 'the fixture really spans many phases');

    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('u'),
    ]);
    addTearDown(c.dispose);
    final first = DateTime.parse(weekStartYmd);
    c.read(pastWeekSelectionProvider.notifier).select(PastWeekSelection(
          phaseNumber: 20,
          weekInPhase: 1,
          dates: [for (var i = 0; i < 7; i++) _d(first.add(Duration(days: i)))],
          phaseStart: weekStartYmd,
        ));
    sw
      ..reset()
      ..start();
    final days = c.read(pastWeekDaysProvider);
    final weekMs = sw.elapsedMilliseconds;
    expect(days, isNotNull);
    expect(days!.length, 7);
    // ignore: avoid_print
    print('SCALE strip=${stripMs}ms week=${weekMs}ms blocks=${blocks.length} rows=${days.length}');
    expect(stripMs, lessThan(_budgetMs), reason: 'pastPhaseBlocksForDisplay over 730 rows');
    expect(weekMs, lessThan(_budgetMs), reason: 'a full past-week build');
  });
}
