import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';

// Week of Mon 21 – Sun 27 Sep 2026 (2026-09-21 is a Monday).
const mon = '2026-09-21';
const tue = '2026-09-22';
const wed = '2026-09-23';
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const sun = '2026-09-27';
const nextMon = '2026-09-28';

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned', int dow = 0}) =>
    {
      'date': date,
      'day_of_week': dow,
      'week': 2,
      'phase': 3,
      'week_character': 'working',
      'type': 'workout',
      'workout_name': name,
      'workout_focus': 'Back',
      'workout_day_index': 1,
      'exercises': [
        {'exercise_name': '$name A', 'sets': 3}
      ],
      'status': status,
      'completed_at': null,
      'is_swapped': false,
      'original_date': null,
      'source': 'plan_gen',
      'updated_at_ms': 1,
    };

Map<String, dynamic> rest(String date, {int dow = 6}) => {
      'date': date,
      'day_of_week': dow,
      'week': 2,
      'phase': 3,
      'week_character': 'working',
      'type': 'rest',
      'workout_name': 'Rest Day',
      'workout_focus': 'Recovery',
      'exercises': <Map<String, dynamic>>[],
      'status': 'rest',
      'completed_at': null,
      'is_swapped': false,
      'original_date': null,
    };

DaySwapRefusal? lock(String date, Map<String, dynamic>? row,
        {String today = thu, bool logged = false, String? inProgress}) =>
    DaySwapRules.lockOf(
        date: date,
        row: row,
        today: today,
        hasLoggedSets: logged,
        inProgressDate: inProgress);

void main() {
  group('week math', () {
    test('mondayOf: Sunday belongs to the week that started six days earlier',
        () {
      expect(DaySwapRules.mondayOf(sun), mon);
      expect(DaySwapRules.mondayOf(mon), mon);
      expect(DaySwapRules.mondayOf(nextMon), nextMon);
    });

    test('mondayOf crosses a year boundary', () {
      // 2027-01-01 is a Friday.
      expect(DaySwapRules.mondayOf('2027-01-01'), '2026-12-28');
    });

    test('weekDates lists Monday..Sunday', () {
      expect(DaySwapRules.weekDates(thu), [mon, tue, wed, thu, fri, sat, sun]);
    });

    test('utcDate and format round-trip', () {
      expect(DaySwapRules.format(DaySwapRules.utcDate('2026-02-28')),
          '2026-02-28');
      expect(DaySwapRules.addDays('2026-02-28', 1), '2026-03-01');
    });
  });

  group('pairRefusal', () {
    test('same date', () {
      expect(DaySwapRules.pairRefusal(fri, fri), DaySwapRefusal.sameDay);
    });
    test('Sunday and the next Monday are different weeks', () {
      expect(DaySwapRules.pairRefusal(sun, nextMon),
          DaySwapRefusal.differentWeek);
    });
    test('Monday and Sunday of one week pair', () {
      expect(DaySwapRules.pairRefusal(mon, sun), isNull);
    });
  });

  group('lockOf', () {
    test('planned today and rest later are movable; custom_template too', () {
      expect(lock(thu, workout(thu, 'Pull')), isNull);
      expect(lock(sun, rest(sun)), isNull);
      expect(
          lock(fri, {...workout(fri, 'Mine'), 'type': 'custom_template'}),
          isNull);
    });

    test('completed wins over past (DONE, not PAST)', () {
      expect(lock(mon, workout(mon, 'Push', status: 'completed')),
          DaySwapRefusal.completed);
    });

    test('paused wins over past', () {
      expect(lock(mon, workout(mon, 'Push', status: 'paused')),
          DaySwapRefusal.paused);
    });

    test('past', () {
      expect(lock(wed, workout(wed, 'Legs')), DaySwapRefusal.past);
    });

    test('a past day with logged sets reads PAST (past is checked first)', () {
      expect(lock(wed, workout(wed, 'Legs'), logged: true),
          DaySwapRefusal.past);
    });

    test('logged sets on today lock it as started', () {
      expect(lock(thu, workout(thu, 'Pull'), logged: true),
          DaySwapRefusal.started);
    });

    test('the in-progress date is started, even a future one', () {
      expect(lock(fri, workout(fri, 'Pull'), inProgress: fri),
          DaySwapRefusal.started);
    });

    test('travel / moved / dropped / skipped', () {
      expect(lock(fri, workout(fri, 'X', status: 'travel')),
          DaySwapRefusal.travel);
      expect(lock(fri, workout(fri, 'X', status: 'moved')),
          DaySwapRefusal.rescheduled);
      expect(lock(fri, workout(fri, 'X', status: 'dropped')),
          DaySwapRefusal.rescheduled);
      expect(lock(fri, workout(fri, 'X', status: 'skipped')),
          DaySwapRefusal.skipped);
    });

    test('no row, status none, and an unknown status are noRow', () {
      expect(lock(fri, null), DaySwapRefusal.noRow);
      expect(lock(fri, workout(fri, 'X', status: 'none')),
          DaySwapRefusal.noRow);
      expect(lock(fri, workout(fri, 'X', status: 'bogus')),
          DaySwapRefusal.noRow);
    });

    test('labels and codes', () {
      expect(DaySwapRefusal.completed.label, 'DONE');
      expect(DaySwapRefusal.started.label, 'STARTED');
      expect(DaySwapRefusal.paused.label, 'PAUSED');
      expect(DaySwapRefusal.past.label, 'PAST');
      expect(DaySwapRefusal.travel.label, 'TRAVEL');
      expect(DaySwapRefusal.rescheduled.label, 'RESCHEDULED');
      expect(DaySwapRefusal.skipped.label, 'SKIPPED');
      expect(DaySwapRefusal.noRow.label, isNull);
      expect(DaySwapRefusal.allowanceSpent.label, isNull);
      expect(DaySwapRefusal.noRow.code, 'no_row');
      expect(DaySwapRefusal.allowanceSpent.code, 'allowance_spent');
      expect(DaySwapRefusal.completed.code, 'completed');
    });
  });

  group('field partition (spec §5.4)', () {
    test('every content key moves and every identity key stays', () {
      final a = {
        ...workout(fri, 'Pull + Core', dow: 4),
        'template_id': 'tpl-1',
        'warmup': ['w'],
        'cooldown': ['c'],
        'finisher': ['f'],
        'generated_via': 'coach',
        'shortened_via': 'ai_coach',
        'rescheduled_from': '2026-09-20',
        'is_hold': false,
        'hold_ordinal': null,
        'reason': null,
      };
      final b = {
        ...workout(sat, 'Legs + Core', dow: 5),
        'week_character': 'deload',
        'is_hold': true,
        'hold_ordinal': 2,
        'reason': 'hold',
      };
      final w = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: a,
          rowB: b,
          displacedA: null,
          displacedB: null,
          nowMs: 777);

      // Content of A now sits on B's date.
      for (final k in [
        'type',
        'workout_name',
        'workout_focus',
        'exercises',
        'warmup',
        'cooldown',
        'finisher',
        'workout_day_index',
        'template_id',
        'generated_via',
        'shortened_via',
        'rescheduled_from',
        'status',
      ]) {
        expect(w.rowB[k], a[k], reason: 'content key $k must move to B');
      }
      // B's identity stays on B.
      for (final k in DaySwapRules.identityKeys) {
        if (k == 'date') continue;
        expect(w.rowB[k], b[k], reason: 'identity key $k must stay on B');
      }
      expect(w.rowB['date'], sat);
      // Old write stamps never travel (swapScheduledDays re-stamps).
      expect(w.rowB.containsKey('source'), isFalse);
      expect(w.rowB.containsKey('updated_at_ms'), isFalse);
      // A gets B's content (a workout without a template).
      expect(w.rowA['workout_name'], 'Legs + Core');
      expect(w.rowA.containsKey('template_id'), isFalse);
      expect(w.rowA['week_character'], 'working');
    });

    test('a rest day and a workout trade type AND status', () {
      final w = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sun,
          rowA: workout(fri, 'Pull'),
          rowB: rest(sun),
          displacedA: null,
          displacedB: null,
          nowMs: 1);
      expect(w.rowA['type'], 'rest');
      expect(w.rowA['status'], 'rest');
      expect(w.rowB['type'], 'workout');
      expect(w.rowB['status'], 'planned');
    });
  });

  group('markers (spec §5.4)', () {
    test('first swap marks both rows with their origin and one stamp', () {
      final w = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: workout(fri, 'Pull'),
          rowB: workout(sat, 'Legs'),
          displacedA: null,
          displacedB: null,
          nowMs: 42);
      expect(w.rowA['is_swapped'], isTrue);
      expect(w.rowA['original_date'], sat);
      expect(w.rowB['is_swapped'], isTrue);
      expect(w.rowB['original_date'], fri);
      expect(w.rowA['arranged_at_ms'], 42);
      expect(w.rowB['arranged_at_ms'], 42);
    });

    test('moving swapped content again keeps its FIRST origin', () {
      final first = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: workout(fri, 'Pull'),
          rowB: workout(sat, 'Legs'),
          displacedA: null,
          displacedB: null,
          nowMs: 1);
      // Pull is now on Saturday; move it on to Sunday.
      final second = DaySwapRules.buildSwap(
          dateA: sat,
          dateB: sun,
          rowA: first.rowB,
          rowB: rest(sun),
          displacedA: null,
          displacedB: null,
          nowMs: 2);
      expect(second.rowB['workout_name'], 'Pull');
      expect(second.rowB['original_date'], fri);
    });

    test('swap-back removes the markers and keeps a NEW arranged_at_ms', () {
      final first = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: workout(fri, 'Pull'),
          rowB: workout(sat, 'Legs'),
          displacedA: null,
          displacedB: null,
          nowMs: 1);
      final back = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: first.rowA,
          rowB: first.rowB,
          displacedA: null,
          displacedB: null,
          nowMs: 2);
      expect(back.rowA['workout_name'], 'Pull');
      expect(back.rowA.containsKey('is_swapped'), isFalse);
      expect(back.rowA.containsKey('original_date'), isFalse);
      expect(back.rowB.containsKey('is_swapped'), isFalse);
      expect(back.rowA['arranged_at_ms'], 2);
      expect(back.rowB['arranged_at_ms'], 2);
    });

    test('isMoved: swapped and not completed', () {
      expect(DaySwapRules.isMoved({'is_swapped': true, 'status': 'planned'}),
          isTrue);
      expect(
          DaySwapRules.isMoved({'is_swapped': true, 'status': 'completed'}),
          isFalse);
      expect(DaySwapRules.isMoved(workout(fri, 'X')), isFalse);
      expect(DaySwapRules.isMoved(null), isFalse);
    });
  });

  group('displaced_ backups follow their content (spec §5.4)', () {
    final backupA = workout(fri, 'Generated Pull');

    test('only A has a backup: it moves to B, re-dated, and A loses it', () {
      final w = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: {...workout(fri, 'My Template'), 'template_id': 't1'},
          rowB: workout(sat, 'Legs', dow: 5),
          displacedA: backupA,
          displacedB: null,
          nowMs: 1);
      expect(w.displacedA, isNull);
      expect(w.displacedB!['workout_name'], 'Generated Pull');
      expect(w.displacedB!['date'], sat);
      expect(w.displacedB!['day_of_week'], 5);
      expect(w.displacedB!['original_date'], fri);
      expect(w.displacedB!.containsKey('arranged_at_ms'), isFalse);
    });

    test('both have backups: they exchange', () {
      final backupB = workout(sat, 'Generated Legs');
      final w = DaySwapRules.buildSwap(
          dateA: fri,
          dateB: sat,
          rowA: {...workout(fri, 'T1'), 'template_id': 't1'},
          rowB: {...workout(sat, 'T2'), 'template_id': 't2'},
          displacedA: backupA,
          displacedB: backupB,
          nowMs: 1);
      expect(w.displacedA!['workout_name'], 'Generated Legs');
      expect(w.displacedA!['date'], fri);
      expect(w.displacedB!['workout_name'], 'Generated Pull');
      expect(w.displacedB!['date'], sat);
    });
  });

  group('three rest days in a row (spec §5.6)', () {
    Map<String, Map<String, dynamic>?> week(List<String> kinds) => {
          for (var i = 0; i < 7; i++)
            DaySwapRules.weekDates(mon)[i]: kinds[i] == 'R'
                ? rest(DaySwapRules.weekDates(mon)[i])
                : kinds[i] == '-'
                    ? null
                    : workout(DaySwapRules.weekDates(mon)[i], 'W$i'),
        };

    RestRunWarning? warn(List<String> kinds, String a, String b) =>
        DaySwapRules.restRunWarning(
            weekDates: DaySwapRules.weekDates(mon),
            rows: week(kinds),
            dateA: a,
            dateB: b);

    test('a swap that CREATES a run warns with the run dates', () {
      // Mon W, Tue R, Wed W, Thu R, Fri R, Sat W, Sun W — swap Tue<->Wed.
      final w = warn(['W', 'R', 'W', 'R', 'R', 'W', 'W'], tue, wed);
      expect(w, isNotNull);
      expect(w!.runDates, [wed, thu, fri]);
    });

    test('a swap that EXTENDS a run warns with the whole run', () {
      // Tue-Thu already rest; swap Fri(W) <-> Sat(R) extends it to Fri.
      final w = warn(['W', 'R', 'R', 'R', 'W', 'R', 'W'], fri, sat);
      expect(w!.runDates, [tue, wed, thu, fri]);
    });

    test('a pre-existing run the swap does not touch does not warn', () {
      expect(warn(['W', 'R', 'R', 'R', 'W', 'W', 'W'], sat, sun), isNull);
    });

    test('a missing row is not a rest day', () {
      // If Monday's missing row counted as rest, swapping Wed(W)<->Thu(R)
      // would create Mon-Tue-Wed and warn. It must not.
      expect(warn(['-', 'R', 'W', 'R', 'W', 'W', 'W'], wed, thu), isNull);
    });
  });
}
