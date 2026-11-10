// Coach workout parity 1b (OI-490; plan docs/plans/coach-workout-parity-1b.md
// rev 4, D3 + §5): Train shows a not-done day's logs and offers COMPLETE
// WORKOUT on today (founder decisions A + D; F: a past day stays not done).
// Pumps the REAL TrainScreen on real Hive. The rule and the tap path
// themselves: coach_day_completion_behavioral_test.dart.
//
// The plan spans two weeks: week 1 = LAST week (past days, so the cases run on
// any weekday, a Monday included), week 2 = this week (today).
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/train_logged_so_far_behavioral_test.dart

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

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
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../helpers/hive_test_setup.dart';

Directory? _dir;

DateTime get _todayNoon {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12);
}

DateTime get _thisMonday =>
    _todayNoon.subtract(Duration(days: _todayNoon.weekday - 1));
DateTime get _lastMonday => _thisMonday.subtract(const Duration(days: 7));

/// Last week: Mon = a COUNTED rest-type row (a template finished on a rest
/// day: Leg Press logged, completed); Tue = a rest row with a Plank log, not
/// done; Wed = Pull Day planned, Pull Up logged, never completed; the rest
/// plain rest. This week: today = Push Day (Squat, Barbell Row), the rest
/// plain rest.
Future<void> _seedWeeks({List<String> todayLogs = const []}) async {
  final wb = HiveService.instance.workoutBox;
  await wb.clear();
  await HiveService.instance.coachBox.clear();
  // One counted day already: last week's Leftover Legs (the 1a heal lifts
  // the count to the completed days on record, so the fixture agrees with it).
  await HiveService.instance.userBox
      .put('progress', {'total_workouts_done': 1});
  await HiveService.instance.userBox
      .put('plan_start_date', istDateStr(_lastMonday));
  await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});
  for (var w = 0; w < 2; w++) {
    for (var i = 0; i < 7; i++) {
      final d = _lastMonday.add(Duration(days: w * 7 + i));
      final isToday = istDateStr(d) == istDateStr(_todayNoon);
      final isPullDay = w == 0 && i == 2;
      final isLegs = w == 0 && i == 0;
      await wb.put('schedule_${istDateStr(d)}', {
        'date': istDateStr(d),
        'week': w + 1,
        'day_of_week': i,
        'type': (isToday || isPullDay) ? 'workout' : 'rest',
        'workout_name': isToday
            ? 'Push Day'
            : isPullDay
                ? 'Pull Day'
                : isLegs
                    ? 'Leftover Legs'
                    : 'Rest Day',
        'workout_focus': 'Push',
        'status': 'planned',
        'exercises': isToday
            ? [
                {'exercise_name': 'Squat', 'sets': 3, 'reps': '5'},
                {'exercise_name': 'Barbell Row', 'sets': 3, 'reps': '8'},
              ]
            : isPullDay
                ? [
                    {'exercise_name': 'Pull Up', 'sets': 3, 'reps': '8'},
                    {'exercise_name': 'Cable Row', 'sets': 3, 'reps': '10'},
                  ]
                : <Map<String, dynamic>>[],
      });
    }
  }
  await _log(_lastMonday, 'Leg Press');
  final legs = await WorkoutWriteService.instance.markCompleted(
      date: _lastMonday, workoutName: 'Leftover Legs', durationSec: 1800);
  expect(legs.success, isTrue);
  await _log(_lastMonday.add(const Duration(days: 1)), 'Plank');
  await _log(_lastMonday.add(const Duration(days: 2)), 'Pull Up');
  for (final n in todayLogs) {
    await _log(_todayNoon, n);
  }
}

Future<void> _log(DateTime day, String name) async {
  final r = await WorkoutWriteService.instance.logExercise(
    date: day,
    exerciseName: name,
    sets: [
      ExerciseSet(
          weightKg: 50,
          reps: 8,
          loggedAtMs: DateTime.now().millisecondsSinceEpoch),
    ],
    source: WriteSource.aiCoach,
  );
  expect(r.success, isTrue, reason: r.errorMessage);
}

int _total() =>
    ((HiveService.instance.userBox.get('progress') as Map?)?['total_workouts_done']
            as num?)
        ?.toInt() ??
    -1;

class _SeededActive extends ActiveWorkoutNotifier {
  _SeededActive(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

/// An Active Workout session in progress for [day] (null date allowed).
ActiveWorkoutData _session(DateTime? day) {
  final ex = ExerciseData(
      name: 'Squat',
      sets: '3',
      reps: '5',
      weight: '80kg',
      rest: '90s',
      loggingType: 'weight_reps');
  return ActiveWorkoutData(
    workoutDay: WorkoutDayData(
        dayNumber: 1, name: 'Push Day', date: day, exercises: [ex]),
    exercises: [ex],
  );
}

Future<ProviderContainer> _pumpTrain(WidgetTester tester,
    {double width = 1024, ActiveWorkoutData? session}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    if (session != null)
      activeWorkoutProvider.overrideWith(() => _SeededActive(session)),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: TrainScreen()),
  ));
  await tester.pump(); // HiveTabScaffoldMixin post-frame isLoading flip
  await tester.pump();
  return c;
}

int get _todayIdx => _todayNoon.weekday - 1;

Future<void> _expand(WidgetTester tester, ProviderContainer c, int idx) async {
  c.read(expandedDayProvider.notifier).toggle(idx);
  await tester.pump();
}

Future<void> _week(WidgetTester tester, ProviderContainer c, int w) async {
  c.read(selectedWeekProvider.notifier).select(w);
  await tester.pump();
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

const _dayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// The week row's status chip with [label] (the screen shows "TODAY" in
/// other places too).
Finder _chip(String label) =>
    find.descendant(of: find.byType(WardChip), matching: find.text(label));

/// Runs [body] collecting every RenderFlex overflow as "source message".
/// The test font is wider than DM Sans, so some pre-existing Train sections
/// overflow at 360 dp in tests; the 360 dp case compares against its own
/// no-logs baseline instead of asserting zero.
Future<List<String>> _overflows(Future<void> Function() body) async {
  final out = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final msg = d.exceptionAsString();
    if (msg.contains('overflowed')) {
      final at = RegExp(r'lib/[^\s:]+\.dart:\d+').firstMatch(d.toString());
      out.add('${at?.group(0) ?? '?'} $msg');
    } else {
      prev?.call(d);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prev;
  }
  return out;
}

Finder _rowLabel(int idx) => find.text(_dayLabels[idx]);

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

  Future<void> open(WidgetTester tester, {List<String> todayLogs = const []}) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    await tester.runAsync(() => _seedWeeks(todayLogs: todayLogs));
  }

  group('today', () {
    testWidgets('a partial day: IN PROGRESS, LOGGED SO FAR, COMPLETE '
        'WORKOUT; the tap completes it, +1, train_tap', (tester) async {
      await open(tester, todayLogs: ['Squat']);
      final c = await _pumpTrain(tester);
      expect(_chip(WardroomCopy.trainInProgressChip), findsOneWidget);
      expect(_chip('TODAY'), findsNothing);
      await _expand(tester, c, _todayIdx);
      expect(find.text(WardroomCopy.trainLoggedSoFar), findsOneWidget);
      expect(find.text('Squat'), findsWidgets);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at 1024 dp');

      // DONE also appears elsewhere on the screen (the hero row once the day
      // is done), so count the chips instead of expecting exactly one.
      final doneBefore = _chip('DONE').evaluate().length;
      await tester.ensureVisible(find.text(WardroomCopy.trainCompleteWorkout));
      await tester.runAsync(() async {
        await tester.tap(find.text(WardroomCopy.trainCompleteWorkout));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final row = HiveService.instance.workoutBox
          .get(WorkoutWriteService.scheduleKey(_todayNoon)) as Map;
      expect(row['status'], 'completed');
      expect(row['completed_via'], 'train_tap');
      expect(_total(), 2, reason: 'one more completed day');
      expect(find.text(WardroomCopy.coachTapCompleted), findsOneWidget);
      expect(_chip(WardroomCopy.trainInProgressChip), findsNothing);
      expect(_chip('DONE').evaluate().length, greaterThan(doneBefore),
          reason: "today's row shows DONE after the tap");
      await _done(tester);
    });

    testWidgets('no logs: the current row (TODAY, Start, no LOGGED SO FAR, no '
        'COMPLETE WORKOUT)', (tester) async {
      await open(tester);
      final c = await _pumpTrain(tester);
      expect(_chip('TODAY'), findsOneWidget);
      expect(_chip(WardroomCopy.trainInProgressChip), findsNothing);
      await _expand(tester, c, _todayIdx);
      expect(find.text(WardroomCopy.trainLoggedSoFar), findsNothing);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsNothing);
      expect(find.text('START WORKOUT'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('at 360 dp the expanded partial row adds no overflow over its '
        'own no-logs baseline, and COMPLETE WORKOUT is on screen',
        (tester) async {
      await open(tester);
      late ProviderContainer c;
      final baseline = await _overflows(() async {
        c = await _pumpTrain(tester, width: 360);
        await _expand(tester, c, _todayIdx);
      });
      await tester.runAsync(() => _log(_todayNoon, 'Squat'));
      final withLogs = await _overflows(() async {
        c.invalidate(currentPlanProvider);
        await tester.pump();
        await tester.pump();
      });
      final added = [...withLogs];
      for (final b in baseline) {
        added.remove(b);
      }
      expect(added, isEmpty, reason: '1b adds no overflow at 360 dp');
      final btn = find.text(WardroomCopy.trainCompleteWorkout);
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      final r = tester.getRect(btn);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
      await _done(tester);
    });

    testWidgets('at 360 dp and text scale 2.0 COMPLETE WORKOUT scales down to '
        'fit its row (a WardButton label neither wraps nor ellipsizes)',
        (tester) async {
      await open(tester, todayLogs: ['Squat']);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final btn = find.text(WardroomCopy.trainCompleteWorkout);
      // Pre-existing sections overflow at this scale in the test font; only
      // the button's own box is asserted.
      await _overflows(() async {
        final c = await _pumpTrain(tester, width: 360);
        await _expand(tester, c, _todayIdx);
        await tester.ensureVisible(btn);
        await tester.pump();
      });
      expect(btn, findsOneWidget);
      final r = tester.getRect(btn);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360 - 14 + 0.5),
          reason: 'inside the expansion (right padding 14)');
      await _done(tester);
    });

    testWidgets('every planned exercise logged but never marked: the button '
        'still shows (completeNow)', (tester) async {
      await open(tester, todayLogs: ['Squat', 'Barbell Row']);
      final c = await _pumpTrain(tester);
      expect(_chip(WardroomCopy.trainInProgressChip), findsOneWidget);
      await _expand(tester, c, _todayIdx);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsOneWidget);
      await _done(tester);
    });

    testWidgets('an Active Workout session in progress FOR TODAY hides the '
        'button (RESUME is there)', (tester) async {
      await open(tester, todayLogs: ['Squat']);
      final c = await _pumpTrain(tester, session: _session(_todayNoon));
      await _expand(tester, c, _todayIdx);
      expect(find.text(WardroomCopy.trainLoggedSoFar), findsOneWidget);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsNothing);
      expect(find.text('RESUME WORKOUT'), findsWidgets);
      await _done(tester);
    });

    for (final c in [
      ('a stale session from yesterday',
          _todayNoon.subtract(const Duration(days: 1))),
      ('a session with no date', null),
    ]) {
      testWidgets('${c.$1} does not hide the button', (tester) async {
        await open(tester, todayLogs: ['Squat']);
        final pc = await _pumpTrain(tester, session: _session(c.$2));
        await _expand(tester, pc, _todayIdx);
        expect(find.text(WardroomCopy.trainCompleteWorkout), findsOneWidget);
        await _done(tester);
      });
    }
  });

  group('last week', () {
    testWidgets('a COUNTED rest-type row is DONE, named, and a tap expands its '
        'logs (not the rest sheet)', (tester) async {
      await open(tester);
      final c = await _pumpTrain(tester);
      await _week(tester, c, 1);
      expect(find.text('LEFTOVER LEGS'), findsOneWidget,
          reason: 'a counted rest-type row shows its name, not "Rest"');
      expect(_chip('DONE'), findsOneWidget);
      await tester.tap(_rowLabel(0));
      await tester.pump();
      expect(find.text('Leg Press'), findsOneWidget);
      expect(find.text('🧘 Rest Day — Recovery'), findsNothing);
      await _done(tester);
    });

    testWidgets('a NOT-done rest row with logs: LOGGED, and a tap shows them '
        'with the not-counted line, no Complete', (tester) async {
      await open(tester);
      final c = await _pumpTrain(tester);
      await _week(tester, c, 1);
      expect(_chip(WardroomCopy.trainLoggedChip), findsOneWidget);
      await tester.tap(_rowLabel(1));
      await tester.pump();
      expect(find.text('Plank'), findsOneWidget);
      expect(find.text(WardroomCopy.trainRestNotCounted), findsOneWidget);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsNothing);
      expect(find.text('🧘 Rest Day — Recovery'), findsNothing);
      await _done(tester);
    });

    testWidgets('a rest row with NO logs still opens the rest sheet',
        (tester) async {
      await open(tester);
      final c = await _pumpTrain(tester);
      await _week(tester, c, 1);
      await tester.tap(_rowLabel(3));
      await tester.pumpAndSettle();
      expect(find.text('🧘 Rest Day — Recovery'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('a past planned day never completed: its sheet shows the logs '
        'under LOGGED above the plan; no Complete', (tester) async {
      await open(tester);
      final c = await _pumpTrain(tester);
      await _week(tester, c, 1);
      await tester.tap(_rowLabel(2));
      await tester.pumpAndSettle();
      // Scoped to the sheet: the week list shows a LOGGED chip too, and Pull
      // Up is also a planned exercise.
      final sheet = find.byType(DraggableScrollableSheet);
      expect(sheet, findsOneWidget);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      expect(inSheet(find.text(WardroomCopy.trainLoggedChip)), findsOneWidget,
          reason: 'the sheet heading reads LOGGED');
      expect(inSheet(find.byType(ExpandedExerciseLogRow)), findsOneWidget,
          reason: 'the Pull Up log row above the plan');
      expect(inSheet(find.text('PLANNED EXERCISES')), findsOneWidget);
      expect(find.text(WardroomCopy.trainCompleteWorkout), findsNothing);
      final row = HiveService.instance.workoutBox.get(WorkoutWriteService
          .scheduleKey(_lastMonday.add(const Duration(days: 2)))) as Map;
      expect(row['status'], 'planned', reason: 'decision F: stays not done');
      await _done(tester);
    });
  });
}
