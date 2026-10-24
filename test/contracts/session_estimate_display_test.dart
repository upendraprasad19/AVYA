// B2 Task 6b (docs/plans/2026-10-22-session-set-budget.md, Ruling 13): the
// session-length estimate that Train and Home DISPLAY follows the budget model
// when `enable_session_set_budget` is ON, and is the old `totalSets x 2.5` when
// it is OFF.
//
// One shared function prices a stored plan day for both screens, so the two can
// never disagree. Its literals below are computed by hand from the shipped
// library rows and the Q4 constants, not read back from the function:
//
//   Barbell Bench Press (E001, compound, rep range 5-8 -> H: overhead 120, work 23)
//     4 sets, rest 150:  1.2 x (120 + 4 x 23 + 3 x 150) = 1.2 x 662 = 794.4 s
//   Lateral Raise (E013, isolation -> I: overhead 45, work 47)
//     3 sets, rest 75:   1.2 x (45 + 3 x 47 + 2 x 75)  = 1.2 x 336 = 403.2 s
//   warm-up lead-in 180 s + cool-down walk 180 s (a 60-minute session's items)
//   total 1557.6 s = 25.96 min -> 26
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_estimate.dart';

import '../helpers/hive_test_setup.dart';

const _flag = 'enable_session_set_budget';

Map<String, dynamic> _ex(
  String id,
  String name,
  String loggingType,
  int sets,
  int rest, {
  Object? type = 'unset',
  String? repRange,
}) =>
    {
      'exercise_id': id,
      'exercise_name': name,
      'logging_type': loggingType,
      'sets': sets,
      'reps': '8-10',
      'rest_seconds': rest,
      if (type != 'unset') 'exercise_type': type,
      'rep_range': ?repRange,
    };

/// The shape `WarmupCooldownSelector._timedExercise` stores: one timed set whose
/// `reps` is the duration in seconds, no rest.
Map<String, dynamic> _timedItem(String name, int seconds) => {
      'exercise_id': name,
      'exercise_name': name,
      'logging_type': 'timed',
      'sets': 1,
      'reps': '${seconds}s',
      'rest_seconds': 0,
    };

void main() {
  late Directory tempDir;
  late List<Map<String, dynamic>> library;
  late Map<String, Map<String, dynamic>> rowsById;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    library = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in library) {
      await HiveService.instance.exerciseBox.put(r['id'] as String, r);
    }
    rowsById = {for (final r in library) r['id'] as String: r};
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  Future<void> flagOn() => HiveService.instance.configBox.put(_flag, true);

  Map<String, dynamic> bench({int rest = 150}) =>
      _ex('E001', 'Barbell Bench Press', 'weight_reps', 4, rest);
  Map<String, dynamic> lateral() => _ex('E013', 'Lateral Raise', 'weight_reps', 3, 75);

  Map<String, dynamic> day({
    List<Map<String, dynamic>>? exercises,
    int lead = 180,
    int walk = 180,
  }) =>
      {
        'type': 'workout',
        'workout_name': 'Push A',
        'status': 'planned',
        'exercises': exercises ?? [bench(), lateral()],
        'warmup': [_timedItem('Light Jog', lead)],
        'cooldown': [_timedItem('Slow Walking', walk)],
      };

  group('the shared estimate (pure)', () {
    test('a bench + lateral raise day with a 180 s lead-in and walk is 1557.6 s, 26 min', () {
      expect(SessionBudget.estimateDaySecondsFromPlanDay(day(), rowsById),
          closeTo(1557.6, 1e-9));
      expect(SessionBudget.estimateDayMinutesFromPlanDay(day(), rowsById), 26);
    });

    test('the rest term counts: bench at 90 s rest is 3 x 60 x 1.2 = 216 s shorter', () {
      final a = SessionBudget.estimateDaySecondsFromPlanDay(day(), rowsById);
      final b = SessionBudget.estimateDaySecondsFromPlanDay(
          day(exercises: [bench(rest: 90), lateral()]), rowsById);
      expect(a - b, closeTo(216.0, 1e-9));
    });

    test('the warm-up and cool-down items count at their own seconds', () {
      final base = SessionBudget.estimateDaySecondsFromPlanDay(day(), rowsById);
      final longerLead = SessionBudget.estimateDaySecondsFromPlanDay(day(lead: 300), rowsById);
      expect(longerLead - base, closeTo(120.0, 1e-9));
      final shorterWalk = SessionBudget.estimateDaySecondsFromPlanDay(day(walk: 60), rowsById);
      expect(base - shorterWalk, closeTo(120.0, 1e-9));
      final noItems = {...day(), 'warmup': <dynamic>[], 'cooldown': <dynamic>[]};
      expect(SessionBudget.estimateDaySecondsFromPlanDay(noItems, rowsById),
          closeTo(1197.6, 1e-9));
    });

    test('adding one exercise raises the estimate by exactly its own exerciseSeconds', () {
      final plank = _ex('E054', 'Plank', 'timed', 3, 30); // timed -> B: 1.2 x (30 + 120 + 60)
      final before = SessionBudget.estimateDaySecondsFromPlanDay(day(), rowsById);
      final after = SessionBudget.estimateDaySecondsFromPlanDay(
          day(exercises: [bench(), lateral(), plank]), rowsById);
      expect(after - before, closeTo(252.0, 1e-9));
    });

    test('a user-added exercise with no library row is priced from its own type, rep range and logging type', () {
      double only(Map<String, dynamic> e) => SessionBudget.estimateDaySecondsFromPlanDay(
          {'exercises': [e], 'warmup': <dynamic>[], 'cooldown': <dynamic>[]}, rowsById);
      // isolation -> I: 1.2 x (45 + 3 x 47 + 2 x 60)
      expect(only(_ex('c1', 'My Curl', 'weight_reps', 3, 60, type: ['isolation'], repRange: '10-12')),
          closeTo(367.2, 1e-9));
      // no type -> ['compound']; no usable rep range -> M: 1.2 x (90 + 3 x 35 + 2 x 60)
      expect(only(_ex('c2', 'My Press', 'weight_reps', 3, 60)), closeTo(378.0, 1e-9));
      // compound with a 5-8 range -> H: 1.2 x (120 + 3 x 23 + 2 x 60)
      expect(only(_ex('c3', 'My Heavy', 'weight_reps', 3, 60, type: 'compound', repRange: '5-8')),
          closeTo(1.2 * (120 + 69 + 120), 1e-9));
    });

    test('rest and sets parse tolerantly: absent rest 60, absent sets 3, junk rest 75, "90s" 90', () {
      double only(Map<String, dynamic> e) => SessionBudget.estimateDaySecondsFromPlanDay(
          {'exercises': [e], 'warmup': <dynamic>[], 'cooldown': <dynamic>[]}, rowsById);
      Map<String, dynamic> raw(Object? rest, {Object? sets = 3}) => {
            'exercise_id': 'c9',
            'exercise_name': 'X',
            'logging_type': 'weight_reps',
            'exercise_type': ['isolation'],
            'sets': ?sets,
            'rest_seconds': ?rest,
          };
      double i(int rest) => 1.2 * (45 + 3 * 47 + 2 * rest);
      expect(only(raw(null)), closeTo(i(60), 1e-9)); // absent -> the parser's 60
      expect(only(raw('abc')), closeTo(i(75), 1e-9)); // junk -> 75
      expect(only(raw('90s')), closeTo(i(90), 1e-9)); // digits
      expect(only(raw(45.0)), closeTo(i(45), 1e-9)); // a JSON double
      expect(only(raw(60, sets: null)), closeTo(i(60), 1e-9)); // absent sets -> 3
    });

    test('a malformed day never throws: non-map entries are skipped, no lists means 0', () {
      expect(SessionBudget.estimateDaySecondsFromPlanDay(const {}, rowsById), 0.0);
      expect(
          SessionBudget.estimateDaySecondsFromPlanDay({
            'exercises': ['x', null, 3, bench()],
            'warmup': 'nope',
            'cooldown': null,
          }, rowsById),
          closeTo(794.4, 1e-9));
      expect(SessionBudget.estimateDayMinutesFromPlanDay(const {}, rowsById), 0);
    });

    test('a rep-based warm-up item (sets x B) is priced, not dropped', () {
      final d = {
        'exercises': <dynamic>[],
        'warmup': [
          {
            'exercise_id': 'Push Up',
            'exercise_name': 'Push Up',
            'logging_type': 'bodyweight_reps',
            'sets': 1,
            'reps': '10',
            'rest_seconds': 0,
          }
        ],
        'cooldown': <dynamic>[],
      };
      // B, one set, no rest: 1.2 x (30 + 40)
      expect(SessionBudget.estimateDaySecondsFromPlanDay(d, rowsById), closeTo(84.0, 1e-9));
    });
  });

  group('archetype agreement (the allocator, apply, titration and the display)', () {
    test('every shipped row prices at the archetype the engine keys by name, whether found by id or not', () {
      final archetypeByName = {
        for (final r in library) (r['name'] as String).toLowerCase(): SessionBudget.archetypeOfRow(r),
      };
      var multiType = 0;
      for (final r in library) {
        final types = (r['exercise_type'] as List?) ?? const [];
        final e = _ex(
          r['id'] as String,
          r['name'] as String,
          (r['logging_type'] as String?) ?? 'weight_reps',
          3,
          75,
          type: types.isEmpty ? null : types.first,
          repRange: r['rep_range'] as String?,
        );
        final byId = SessionBudget.archetypeOfPlanDayExercise(e, rowsById);
        expect(byId, archetypeByName[(r['name'] as String).toLowerCase()],
            reason: 'by id: ${r['id']} ${r['name']}');
        if (types.length > 1) {
          multiType++;
          continue; // a custom stores ONE type; a multi-type row is read whole by id
        }
        final noRow = SessionBudget.archetypeOfPlanDayExercise(e, const {});
        expect(noRow, byId, reason: 'fallback without a row: ${r['id']} ${r['name']}');
      }
      // ignore: avoid_print
      print('archetype agreement: ${library.length} rows, $multiType multi-type');
    });
  });

  group('Train and Home show the same minutes for the same day', () {
    Future<void> putToday(Map<String, dynamic> d) async {
      final today = DateTime.now();
      await HiveService.instance.workoutBox.put('schedule_${formatDateKey(today)}', d);
    }

    test('flag OFF: Train 7 sets x 2.5 = 18 min, Home 18, and no budget minutes are computed', () async {
      final d = day();
      await putToday(d);
      expect(budgetedDayMinutes(d), isNull);
      expect(workoutDayForDate(DateTime.now())!.estimatedDuration, '18 min');
      expect(homeCardMinutes(d), 18);
      expect(homeCardMinutes({'exercises': <dynamic>[]}), 45,
          reason: 'OFF Home keeps its 45 min placeholder for a day with no sets');
    });

    test('flag ON: Train and Home both read 26 min for the same stored day', () async {
      await flagOn();
      final d = day();
      await putToday(d);
      expect(budgetedDayMinutes(d), 26);
      expect(workoutDayForDate(DateTime.now())!.estimatedDuration, '26 min');
      expect(homeCardMinutes(d), 26);
    });

    /// A week whose Monday is the plan start, today's row being [d]: the shape
    /// `CurrentPlanNotifier.build` walks to build the Train week list.
    Future<void> seedWeekWith(Map<String, dynamic> d) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final wb = HiveService.instance.workoutBox;
      await HiveService.instance.userBox.put('plan_start_date', formatDateKey(monday));
      await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});
      for (var i = 0; i < 7; i++) {
        final date = monday.add(Duration(days: i));
        final isToday = formatDateKey(date) == formatDateKey(today);
        await wb.put('schedule_${formatDateKey(date)}', {
          ...(isToday
              ? d
              : {'type': 'rest', 'workout_name': 'Rest Day', 'exercises': <dynamic>[]}),
          'date': formatDateKey(date),
          'week': 1,
          'day_of_week': i,
          'status': 'planned',
        });
      }
    }

    WorkoutDayData weekListDay() {
      final c = ProviderContainer(overrides: [authUserIdTokenProvider.overrideWithValue('u')]);
      addTearDown(c.dispose);
      final plan = c.read(currentPlanProvider);
      expect(plan.hasPlan, isTrue);
      return plan.weeks.first.firstWhere((x) => x.name == 'PUSH A');
    }

    test('flag OFF: the Train week list keeps 7 sets x 2.5 = 18 min', () async {
      await seedWeekWith(day());
      expect(weekListDay().estimatedDuration, '18 min');
    });

    test('flag ON: the Train week list reads the same 26 min as the day card and Home', () async {
      await flagOn();
      await seedWeekWith(day());
      expect(weekListDay().estimatedDuration, '26 min');
    });

    test('flag ON: a day with no exercises falls back to the old numbers (Home 45)', () async {
      await flagOn();
      expect(budgetedDayMinutes({'exercises': <dynamic>[]}), isNull);
      expect(homeCardMinutes({'exercises': <dynamic>[]}), 45);
    });

    test('PRESENCE ONLY: the Home Today card takes its minutes from the shared function', () {
      // The card is built inside a screen, so its call site is pinned by source:
      // comments stripped, the shared call present, the old inline sum gone.
      String code(String path) => File(path)
          .readAsLinesSync()
          .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
          .join(' ');
      final src = code('lib/features/home/screens/home_screen.dart');
      expect(src.contains('homeCardMinutes(schedule)'), isTrue);
      expect(src.contains('totalSets * 2.5'), isFalse);
      final train = code('lib/features/train/providers/train_provider.dart');
      expect(RegExp(r'budgetMinutes: budgetedDayMinutes\(row\)').hasMatch(train), isTrue);
    });

    test('a rest day shows no estimate', () {
      expect(const WorkoutDayData(dayNumber: 1, name: 'REST', isRest: true).estimatedDuration, '');
    });
  });
}
