// Train past week in place (docs/plans/train-past-week-in-place.md, D2-D7). Pumps the REAL TrainScreen on
// real Hive: a past-phase week picked on the strip is listed by the SAME rows code as the current week
// (no "Completed history" sheet), missed days are the muted rows, a completed day expands inline, a missed
// day with logs opens the preview sheet, and the selection resets the way the plan says.
//
// Fixture: current phase 2 (rows from last Monday), ONE past group of 26 days that starts on a WEDNESDAY
// (so the chip's range must come from the group's first row, not from a Monday).
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/train_past_week_in_place_behavioral_test.dart

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_allowance_line.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart';
import 'package:icanbefitter/features/train/widgets/hold_chip_group.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';

import '../helpers/hive_test_setup.dart';

Directory? _dir;

DateTime get _todayNoon {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12);
}

DateTime get _lastMonday =>
    _todayNoon.subtract(Duration(days: _todayNoon.weekday - 1 + 7));

/// First row of the past group: a Wednesday, 40 days before the current phase starts (so it spans six
/// chips, W2 starts on a Wednesday too, and a row sits past day 28).
DateTime get _pastStart => _lastMonday.subtract(const Duration(days: 40));
DateTime _pastDay(int i) => _pastStart.add(Duration(days: i));
String _ymd(int i) => istDateStr(_pastDay(i));

const _months = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// The chip's own range text, computed here independently of `pastWeekRangeLabel`.
String _expectedRange([int week = 1]) {
  final a = _pastDay((week - 1) * 7);
  final b = _pastDay((week - 1) * 7 + 6);
  return a.month == b.month
      ? '${_months[a.month - 1]} ${a.day}–${b.day}'
      : '${_months[a.month - 1]} ${a.day}–${_months[b.month - 1]} ${b.day}';
}

Future<void> _log(DateTime day, String name) async {
  final r = await WorkoutWriteService.instance.logExercise(
    date: day,
    exerciseName: name,
    sets: [
      ExerciseSet(
          weightKg: 50, reps: 8, loggedAtMs: DateTime.now().millisecondsSinceEpoch),
    ],
    source: WriteSource.aiCoach,
  );
  expect(r.success, isTrue, reason: r.errorMessage);
}

Map<String, dynamic> _row(DateTime d, int week,
        {required String type,
        required String status,
        String? name,
        List<Map<String, dynamic>> exercises = const [],
        int? phase}) =>
    {
      'phase': ?phase,
      'date': istDateStr(d),
      'week': week,
      'day_of_week': d.weekday - 1,
      'type': type,
      'workout_name': ?name,
      'workout_focus': 'Push',
      'status': status,
      'exercises': exercises,
    };

Future<void> _seed() async {
  final wb = HiveService.instance.workoutBox;
  await wb.clear();
  await HiveService.instance.coachBox.clear();
  await HiveService.instance.userBox
      .put('progress', {'total_workouts_done': 1, 'current_phase': 2});
  await HiveService.instance.userBox
      .put('plan_start_date', istDateStr(_lastMonday));
  await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});

  // Current phase: two weeks from last Monday; today is a workout.
  for (var i = 0; i < 14; i++) {
    final d = _lastMonday.add(Duration(days: i));
    final isToday = istDateStr(d) == istDateStr(_todayNoon);
    await wb.put(
        'schedule_${istDateStr(d)}',
        _row(d, i ~/ 7 + 1,
            type: isToday ? 'workout' : 'rest',
            status: 'planned',
            name: isToday ? 'Push Day' : 'Rest Day',
            exercises: isToday
                ? [
                    {'exercise_name': 'Squat', 'sets': 3, 'reps': '5'},
                  ]
                : const []));
  }

  // The past group: 40 rows, filler rest except the first week.
  for (var i = 0; i < 40; i++) {
    final d = _pastDay(i);
    await wb.put('schedule_${istDateStr(d)}',
        _row(d, i ~/ 7 + 1, phase: 1, type: 'rest', status: 'rest', name: 'Rest Day'));
  }
  // i0: a completed workout with its own name + one exercise.
  await wb.put(
      'schedule_${_ymd(0)}',
      _row(_pastDay(0), 1, phase: 1, type: 'workout', status: 'planned', name: 'Pull Day', exercises: [
        {'exercise_name': 'Pull Up', 'sets': 3, 'reps': '8'},
      ]));
  await _log(_pastDay(0), 'Pull Up');
  final done = await WorkoutWriteService.instance
      .markCompleted(date: _pastDay(0), workoutName: 'Pull Day', durationSec: 1800);
  expect(done.success, isTrue);
  // i1: completed; the row says "Push", the session log says "Pull + Core" (the log wins for a done day).
  await wb.put(
      'schedule_${_ymd(1)}',
      _row(_pastDay(1), 1, phase: 1, type: 'workout', status: 'planned', name: 'Push', exercises: [
        {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8'},
        {'exercise_name': 'Dip', 'sets': 3, 'reps': '10'},
      ]));
  await _log(_pastDay(1), 'Bench Press');
  final both = await WorkoutWriteService.instance
      .markCompleted(date: _pastDay(1), workoutName: 'Pull + Core', durationSec: 1800);
  expect(both.success, isTrue);
  await wb.put(
      'schedule_${_ymd(1)}',
      _row(_pastDay(1), 1, phase: 1, type: 'workout', status: 'completed', name: 'Push', exercises: [
        {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8'},
        {'exercise_name': 'Dip', 'sets': 3, 'reps': '10'},
      ]));
  // i2 also has a stray session-log name; a NOT-done day keeps its own row name over it.
  await wb.put('wlog_${_ymd(2)}', {'workout_name': 'Other Name', 'date': _ymd(2)});
  // i5: a dropped row never shows (the same visibility rules as the current week).
  await wb.put('schedule_${_ymd(5)}',
      _row(_pastDay(5), 1, phase: 1, type: 'workout', status: 'dropped', name: 'Dropped Day'));
  // i2: a planned day that never happened (3 exercises, no logs).
  await wb.put(
      'schedule_${_ymd(2)}',
      _row(_pastDay(2), 1, phase: 1, type: 'workout', status: 'planned', name: 'Leg Day', exercises: [
        {'exercise_name': 'Back Squat', 'sets': 3, 'reps': '5'},
        {'exercise_name': 'Lunge', 'sets': 3, 'reps': '8'},
        {'exercise_name': 'Leg Curl', 'sets': 3, 'reps': '10'},
      ]));
  // i3: restored, never completed: no name, no exercises, three logs.
  await wb.put('schedule_${_ymd(3)}',
      _row(_pastDay(3), 1, phase: 1, type: 'workout', status: 'planned'));
  for (final n in ['Bench Press', 'Barbell Row', 'Curl']) {
    await _log(_pastDay(3), n);
  }
  // i4: a completed day whose schedule row lost its name; the wlog row has it; two logs.
  await _log(_pastDay(4), 'Overhead Press');
  await _log(_pastDay(4), 'Dip');
  final p = await WorkoutWriteService.instance
      .markCompleted(date: _pastDay(4), workoutName: 'Push Day', durationSec: 1800);
  expect(p.success, isTrue);
  await wb.put('schedule_${_ymd(4)}', {
    'date': _ymd(4),
    'week': 1,
    'type': 'workout',
    'status': 'completed',
  });
}


Future<ProviderContainer> _pump(WidgetTester tester,
    {List<String>? countCalls}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1024, 2400);
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    if (countCalls != null)
      pastDayLoggedCountReaderProvider.overrideWithValue((d) {
        countCalls.add(d);
        return {_ymd(3): 3, _ymd(4): 2}[d] ?? 0;
      }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: TrainScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return c;
}

final _chip = find.byKey(const ValueKey('past-1-w1'));

Future<void> _pickPast(WidgetTester tester) async {
  await tester.ensureVisible(_chip);
  await tester.pump();
  await tester.tap(_chip);
  await tester.pump();
  await tester.pump();
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Text('a', style: AppTypography.h1),
        Text('a', style: AppTypography.h2),
        Text('b', style: AppTypography.h3),
        Text('c', style: AppTypography.mono),
        Text('d', style: AppTypography.monoXs),
        Text('e', style: AppTypography.bodySm),
        Text('f', style: AppTypography.body),
        Text('g', style: AppTypography.numeric),
      ]),
    ));
  });

  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  Future<void> open(WidgetTester tester) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    await tester.runAsync(_seed);
  }

  final label = find.byKey(const ValueKey('past-week-label'));

  testWidgets('a past week is listed by the Train rows: names, counts, no footer',
      (tester) async {
    await open(tester);
    final calls = <String>[];
    await _pump(tester, countCalls: calls);
    expect(label, findsNothing);
    await _pickPast(tester);

    // The label is built from the group's FIRST row (a Wednesday) and the chip's own range.
    final text = tester.widget<Text>(find.descendant(of: label, matching: find.byType(Text)));
    expect(text.data, 'PHASE I · WEEK 1 · ${_expectedRange()}');

    // Six rows (the dropped one is hidden): completed (own name), completed (the log's name beats the
    // row's), missed, nameless-with-logs, completed nameless row, rest.
    expect(find.text('PULL DAY'), findsOneWidget);
    expect(find.text('PULL + CORE'), findsOneWidget);
    expect(find.text('PUSH'), findsNothing, reason: 'a done day follows the session log, not the row');
    expect(find.text('DROPPED DAY'), findsNothing);
    expect(find.text('LEG DAY'), findsOneWidget, reason: 'a NOT-done day keeps its own name over a wlog');
    expect(find.text('OTHER NAME'), findsNothing);
    expect(find.text('WORKOUT'), findsOneWidget, reason: 'the nameless never-completed day');
    expect(find.text('PUSH DAY'), findsOneWidget,
        reason: 'a completed row that lost its name follows the wlog row');
    expect(find.text('1 EX'), findsOneWidget); // Pull Day: its stored exercise
    expect(find.text('3 EX'), findsNWidgets(2)); // Leg Day: 3 stored; WORKOUT: 3 logged
    expect(find.text('2 EX'), findsNWidgets(2)); // Pull + Core: 2 stored; Push Day: 2 logged
    expect(find.text('Rest'), findsOneWidget, reason: 'the one not-done rest row');

    // The allowance line belongs to the current week only.
    expect(find.byType(DaySwapAllowanceLine), findsNothing);

    // The count was read ONLY for the two days that store no exercises AND hold logs.
    expect(calls.toSet(), {_ymd(3), _ymd(4)});
    expect(calls.length, 2, reason: 'once each, no per-row scan');
    await _done(tester);
  });

  testWidgets('a completed past day expands inline; a missed day with logs opens the preview sheet '
      'without the empty PLANNED EXERCISES block', (tester) async {
    await open(tester);
    await _pump(tester);
    await _pickPast(tester);

    await tester.tap(find.text('PULL DAY'));
    await tester.pump();
    expect(find.text('Pull Up'), findsWidgets, reason: 'the logged exercise, inline');

    await tester.tap(find.text('PULL DAY')); // collapse
    await tester.pump();

    await tester.ensureVisible(find.text('WORKOUT'));
    await tester.tap(find.text('WORKOUT'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsWidgets);
    expect(find.text('Barbell Row'), findsWidgets);
    expect(find.text(WardroomCopy.trainLoggedChip), findsWidgets);
    expect(find.text('PLANNED EXERCISES'), findsNothing);
    expect(find.text('No exercises scheduled'), findsNothing);
    await _done(tester);
  });

  testWidgets('a missed day with NO logs still opens its plan (PLANNED EXERCISES)', (tester) async {
    await open(tester);
    await _pump(tester);
    await _pickPast(tester);
    await tester.ensureVisible(find.text('LEG DAY'));
    await tester.tap(find.text('LEG DAY'));
    await tester.pumpAndSettle();
    expect(find.text('PLANNED EXERCISES'), findsWidgets);
    expect(find.text('Back Squat'), findsWidgets);
    await _done(tester);
  });

  group('selection lifecycle', () {
    testWidgets('the lit chip again clears the view', (tester) async {
      await open(tester);
      final c = await _pump(tester);
      await _pickPast(tester);
      expect(c.read(pastWeekSelectionProvider), isNotNull);
      await tester.ensureVisible(_chip);
      await tester.tap(_chip);
      await tester.pump();
      expect(c.read(pastWeekSelectionProvider), isNull);
      expect(label, findsNothing);
      await _done(tester);
    });

    testWidgets('a current-week pick, an invalidation and a pick collapsing the expanded row all reset',
        (tester) async {
      await open(tester);
      final c = await _pump(tester);
      await _pickPast(tester);
      expect(label, findsOneWidget);
      c.read(selectedWeekProvider.notifier).select(1);
      await tester.pump();
      expect(c.read(pastWeekSelectionProvider), isNull);
      expect(label, findsNothing);

      await _pickPast(tester);
      expect(c.read(pastWeekSelectionProvider), isNotNull);
      c.invalidate(selectedWeekProvider);
      await tester.pump();
      expect(c.read(pastWeekSelectionProvider), isNull);

      c.read(expandedDayProvider.notifier).toggle(3);
      expect(c.read(expandedDayProvider), 3);
      await _pickPast(tester);
      expect(c.read(expandedDayProvider), isNull, reason: 'a pick collapses the expanded index');
      await _done(tester);
    });

    testWidgets('a selection with no rows shows the empty line', (tester) async {
      await open(tester);
      final c = await _pump(tester);
      c.read(pastWeekSelectionProvider.notifier).select(PastWeekSelection(
          phaseNumber: 1, weekInPhase: 3, dates: const [], phaseStart: _ymd(0)));
      await tester.pump();
      await tester.pump();
      expect(find.text(WardroomCopy.trainPastWeekEmpty), findsOneWidget);
      expect(label, findsOneWidget);
      await _done(tester);
    });

    testWidgets('signed out ("<anon>") yields no past list', (tester) async {
      await open(tester);
      final c = await _pump(tester);
      await _pickPast(tester);
      expect(c.read(pastWeekDaysProvider), isNotNull);
      final anon = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('<anon>'),
      ]);
      addTearDown(anon.dispose);
      anon.read(pastWeekSelectionProvider.notifier).select(PastWeekSelection(
          phaseNumber: 1, weekInPhase: 1, dates: [_ymd(0)], phaseStart: _ymd(0)));
      expect(anon.read(pastWeekDaysProvider), isNull);
      await _done(tester);
    });
  });

  testWidgets('W2 of a group that starts on a Wednesday: label and chip range come from the FIRST row',
      (tester) async {
    await open(tester);
    await _pump(tester);
    final w2 = find.byKey(const ValueKey('past-1-w2'));
    await tester.ensureVisible(w2);
    await tester.pump();
    await tester.tap(w2);
    await tester.pump();
    await tester.pump();
    final text = tester.widget<Text>(find.descendant(of: label, matching: find.byType(Text)));
    expect(text.data, 'PHASE I \u00b7 WEEK 2 \u00b7 ${_expectedRange(2)}');
    expect(_expectedRange(2), isNot(_expectedRange(1)));
    expect(find.descendant(of: w2, matching: find.text(_expectedRange(2))), findsOneWidget,
        reason: "the chip's own range text is the same one");
    final sem = tester.getSemantics(w2);
    expect(sem.label, contains(_expectedRange(2).replaceAll('\u2013', ' to ').toLowerCase()
        .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase())));
    await _done(tester);
  });

  testWidgets('a malformed date is skipped and reported; every other row still renders',
      (tester) async {
    await open(tester);
    final events = <String>[];
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) => events.add('$op ${message ?? ''}');
    addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);
    final c = await _pump(tester);
    c.read(pastWeekSelectionProvider.notifier).select(PastWeekSelection(
        phaseNumber: 1,
        weekInPhase: 1,
        dates: ['bogus', _ymd(0), _ymd(2)],
        phaseStart: _ymd(0)));
    await tester.pump();
    await tester.pump();
    expect(find.text('PULL DAY'), findsOneWidget);
    expect(find.text('LEG DAY'), findsOneWidget);
    expect(events.where((e) => e.startsWith('past_week_row_skipped')).length, 1);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('a chip whose rows are all hidden shows the empty line', (tester) async {
    await open(tester);
    final c = await _pump(tester);
    c.read(pastWeekSelectionProvider.notifier).select(PastWeekSelection(
        phaseNumber: 1, weekInPhase: 1, dates: [_ymd(5)], phaseStart: _ymd(0)));
    await tester.pump();
    await tester.pump();
    expect(find.text(WardroomCopy.trainPastWeekEmpty), findsOneWidget);
    await _done(tester);
  });

  testWidgets('a completion refreshes the picked past week (currentPlanProvider invalidation)',
      (tester) async {
    await open(tester);
    final c = await _pump(tester);
    await _pickPast(tester);
    expect(find.text('LEG DAY'), findsOneWidget);
    await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_${_ymd(2)}',
        _row(_pastDay(2), 1, phase: 1, type: 'workout', status: 'planned', name: 'Renamed Day')));
    c.invalidate(currentPlanProvider);
    // An invalidation is lazy: the rebuild lands on the next frame, the timed pump flushes it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('RENAMED DAY'), findsOneWidget);
    expect(find.text('LEG DAY'), findsNothing);
    await _done(tester);
  });

  testWidgets('the screen reads as the CURRENT week: a stale picked week gives no "Viewing Week" card, '
      'and the allowance line is back on the current list', (tester) async {
    await open(tester);
    final c = await _pump(tester);
    c.read(selectedWeekProvider.notifier).select(1);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Viewing Week'), findsOneWidget, reason: 'sanity: week 1 (not this week) shows the card');
    await _pickPast(tester);
    expect(find.textContaining('Viewing Week'), findsNothing);
    expect(find.byType(DaySwapAllowanceLine), findsNothing);
    expect(find.text('PUSH DAY'), findsWidgets,
        reason: "today's hero (Push Day) is back, plus the past list's own PUSH DAY row");
    await _done(tester);
  });

  testWidgets('a HOLDING user: the H chip stays lit, the hero still shows, the past list opens',
      (tester) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    await tester.runAsync(() async {
      await _seed();
      final wb = HiveService.instance.workoutBox;
      // Phase rows end yesterday-ish; this week and the next are a covered hold (week = 4 + ordinal).
      final thisMonday = _lastMonday.add(const Duration(days: 7));
      await MigratedKey.write('plan_start_date', istDateStr(_lastMonday));
      await MigratedKey.write(
          'plan_end_date', istDateStr(thisMonday.add(const Duration(days: 13))));
      for (var i = 0; i < 14; i++) {
        final d = thisMonday.add(Duration(days: i));
        await wb.put(
            'schedule_${istDateStr(d)}',
            {
              ..._row(d, 5,
                  type: 'workout', status: 'planned', name: 'Hold Workout', exercises: [
                {'exercise_name': 'Squat', 'sets': 3, 'reps': '5'},
              ]),
              'is_hold': true,
              'hold_ordinal': i ~/ 7 + 1,
            });
      }
    });
    final c = await _pump(tester);
    expect(tester.widget<HoldChipGroup>(find.byType(HoldChipGroup)).todayHoldOrdinal, isNotNull,
        reason: 'fixture sanity: today is covered by a hold');
    await _pickPast(tester);
    expect(c.read(pastWeekSelectionProvider), isNotNull);
    expect(tester.widget<HoldChipGroup>(find.byType(HoldChipGroup)).todayHoldOrdinal, isNotNull,
        reason: 'the H chip means "you are here" and stays lit');
    expect(find.textContaining('HOLDING'), findsWidgets, reason: 'the hero row still reads as the hold week');
    expect(find.text('START'), findsOneWidget, reason: "the hero still offers today's workout");
    expect(find.text('PULL DAY'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('the picked past chip is selected for assistive tech; no W chip is lit', (tester) async {
    await open(tester);
    await _pump(tester);
    await _pickPast(tester);
    final sem = tester.getSemantics(_chip);
    expect(sem.flagsCollection.isSelected, Tristate.isTrue);
    expect(sem.label, startsWith('Phase I week 1, '));
    expect(tester.widget<WeekSelector>(find.byType(WeekSelector)).selectedWeek, 0,
        reason: 'no W chip in any phase group is lit while a past week is shown');
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
        findsWidgets, reason: 'the label line is a live region');
    await _done(tester);
  });
}
