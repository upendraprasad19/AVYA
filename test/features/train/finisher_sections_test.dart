// Unit 3C (OI-396, docs/plans/2026-11-16-generator-step3c-cardio-finisher.md §2.3): the FINISHER section on the screens.
//
// - Active workout: a keyed FINISHER section between the last exercise and the keyed COOL-DOWN, with its minutes
//   (`9 MIN`) beside the title and each row's own line (`3 rounds · 10`), never the timed renderer's digits.
// - Train's planned expansion: the same section and rows from the stored row, through the reader rule.
// - The locked-week preview line: `2 warm-up · 3 finisher · 3 cool-down exercises included`, shown for a
//   finisher-only day too.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/preview_plan_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/preview_workout_screen.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';

import 'log_exercise/card_harness.dart';

const _hiitRows = [
  ExerciseData(
      name: 'Burpees', sets: '3', reps: '10', loggingType: 'timed', category: 'finisher', detailText: '3 rounds · 10'),
  ExerciseData(
      name: 'Mountain Climbers',
      sets: '3',
      reps: '30s',
      loggingType: 'timed',
      category: 'finisher',
      detailText: '3 rounds · 30s'),
  ExerciseData(
      name: 'Jump Squats', sets: '3', reps: '10', loggingType: 'timed', category: 'finisher', detailText: '3 rounds · 10'),
];

const _walk = ExerciseData(name: 'Slow Walking', sets: '1', reps: '180', loggingType: 'timed');

final _storedHiit = [
  {'exercise_name': 'Burpees', 'logging_type': 'timed', 'sets': 3, 'reps': '10', 'rest_seconds': 0, 'duration_seconds': 120},
  {'exercise_name': 'Mountain Climbers', 'logging_type': 'timed', 'sets': 3, 'reps': '30s', 'rest_seconds': 0, 'duration_seconds': 120},
  {'exercise_name': 'Jump Squats', 'logging_type': 'timed', 'sets': 3, 'reps': '10', 'rest_seconds': 60, 'duration_seconds': 120},
];

void main() {
  // The Train screen (the preview-sheet group) renders more styles than the card harness warms up, so
  // this file renders every AppTypography style before Hive's path_provider mock exists.
  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await renderFontsFirst(tester);
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        for (final s in [
          AppTypography.display,
          AppTypography.titleM,
          AppTypography.titleS,
          AppTypography.bodyL,
          AppTypography.bodyM,
          AppTypography.buttonLabel,
          AppTypography.displayItalicAccent,
          AppTypography.dmSansFamily(),
          AppTypography.frauncesFamily(),
        ])
          Text('x', style: s),
      ]),
    ));
  });
  tearDownAll(closeHive);

  group('active workout', () {
    testWidgets('FINISHER sits between the exercises and the cool-down, keyed, with its minutes and its own rows',
        (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: 'Bench Press'), exercise(name: 'Barbell Row')], seed: (base) {
        return ActiveWorkoutData(
          workoutDay: WorkoutDayData(
            dayNumber: 1,
            name: 'Flip Day',
            exercises: base.exercises,
            finisher: _hiitRows,
            finisherSeconds: 540,
            cooldown: const [_walk],
          ),
          exercises: base.exercises,
        );
      });
      await scrollToFinish(tester);
      expect(find.byKey(const ValueKey('finisher_section')), findsOneWidget);
      expect(find.byKey(const ValueKey('cooldown_section')), findsOneWidget);
      expect(find.text('FINISHER'), findsOneWidget);
      expect(find.text('9 MIN'), findsOneWidget);
      expect(find.text('3 rounds · 10'), findsNWidgets(2));
      expect(find.text('3 rounds · 30s'), findsOneWidget);
      expect(find.textContaining('50m'), findsNothing);
      final finisherY = tester.getTopLeft(find.byKey(const ValueKey('finisher_section'))).dy;
      final cooldownY = tester.getTopLeft(find.byKey(const ValueKey('cooldown_section'))).dy;
      expect(finisherY, lessThan(cooldownY));
      await unmountScreen(tester);
    });

    testWidgets('no finisher: no section, the cool-down still shows', (tester) async {
      await pumpScreen(tester, exercises: [exercise(name: 'Bench Press')], seed: (base) {
        return ActiveWorkoutData(
          workoutDay: WorkoutDayData(dayNumber: 1, name: 'Flip Day', exercises: base.exercises, cooldown: const [_walk]),
          exercises: base.exercises,
        );
      });
      await scrollToFinish(tester);
      expect(find.byKey(const ValueKey('finisher_section')), findsNothing);
      expect(find.byKey(const ValueKey('cooldown_section')), findsOneWidget);
      await unmountScreen(tester);
    });
  });

  group('Train planned expansion', () {
    testWidgets('today\'s stored finisher shows as a FINISHER section with its minutes and rows', (tester) async {
      await ensureHive(tester);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      await tester.runAsync(() async {
        final wb = HiveService.instance.workoutBox;
        await wb.clear();
        await HiveService.instance.userBox.put('plan_start_date', istDateStr(monday));
        await HiveService.instance.userBox.put('profile', {'primary_goal': 'lose_fat', 'injuries': ['none']});
        await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});
        for (var i = 0; i < 7; i++) {
          final d = monday.add(Duration(days: i));
          final isToday = istDateStr(d) == istDateStr(today);
          await wb.put('schedule_${istDateStr(d)}', {
            'date': istDateStr(d),
            'week': 1,
            'day_of_week': i,
            'type': isToday ? 'workout' : 'rest',
            'workout_name': isToday ? 'Upper' : 'Rest Day',
            'workout_focus': 'Push',
            'status': 'planned',
            'exercises': isToday
                ? [
                    {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8'},
                  ]
                : <Map<String, dynamic>>[],
            if (isToday) 'finisher': _storedHiit,
          });
        }
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1024, 2400);
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [authUserIdTokenProvider.overrideWithValue('u')]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: TrainScreen())));
      await tester.pump();
      await tester.pump();
      c.read(expandedDayProvider.notifier).toggle(today.weekday - 1);
      await tester.pump();
      final section = find.byKey(const ValueKey('finisher_section'));
      await tester.ensureVisible(section);
      expect(find.descendant(of: section, matching: find.text('FINISHER')), findsOneWidget);
      expect(find.descendant(of: section, matching: find.text('9 MIN')), findsOneWidget);
      await tester.tap(find.descendant(of: section, matching: find.text('FINISHER')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: section, matching: find.textContaining('3 rounds · 10')), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Train preview sheet (another day of the week; B-pass seat B F3)', () {
    testWidgets('a planned day\'s stored finisher shows as a FINISHER section above the COOL-DOWN, with its minutes and rows',
        (tester) async {
      await ensureHive(tester);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      // Any day of this week but today (today's row expands inline instead of opening the sheet).
      final other = today.weekday == DateTime.wednesday ? monday : monday.add(const Duration(days: 2));
      await tester.runAsync(() async {
        final wb = HiveService.instance.workoutBox;
        await wb.clear();
        await HiveService.instance.userBox.put('plan_start_date', istDateStr(monday));
        await HiveService.instance.userBox.put('profile', {'primary_goal': 'lose_fat', 'injuries': ['none']});
        await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});
        for (var i = 0; i < 7; i++) {
          final d = monday.add(Duration(days: i));
          final isOther = istDateStr(d) == istDateStr(other);
          await wb.put('schedule_${istDateStr(d)}', {
            'date': istDateStr(d),
            'week': 1,
            'day_of_week': i,
            'type': isOther ? 'workout' : 'rest',
            'workout_name': isOther ? 'Finisher Day' : 'Rest Day',
            'workout_focus': 'Push',
            'status': 'planned',
            'exercises': isOther
                ? [
                    {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8'},
                  ]
                : <Map<String, dynamic>>[],
            if (isOther) 'finisher': _storedHiit,
            if (isOther) 'cooldown': [
              {'exercise_name': 'Slow Walking', 'logging_type': 'timed', 'sets': 1, 'reps': '180', 'duration_seconds': 180},
            ],
          });
        }
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1024, 2400);
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [authUserIdTokenProvider.overrideWithValue('u')]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: TrainScreen())));
      await tester.pump();
      await tester.pump();
      // The week row shows the day's name in capitals.
      await tester.tap(find.text('FINISHER DAY'));
      await tester.pumpAndSettle();
      final section = find.byKey(const ValueKey('finisher_section'));
      expect(section, findsOneWidget);
      expect(find.descendant(of: section, matching: find.text('FINISHER')), findsOneWidget);
      expect(find.descendant(of: section, matching: find.text('9 MIN')), findsOneWidget);
      final finisherY = tester.getTopLeft(section).dy;
      final cooldownY = tester.getTopLeft(find.text('COOL-DOWN').last).dy;
      expect(finisherY, lessThan(cooldownY), reason: 'after the lifts, before the cool-down');
      await tester.tap(find.descendant(of: section, matching: find.text('FINISHER')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: section, matching: find.textContaining('3 rounds · 10')), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the locked-week preview line', () {
    Future<void> pumpPreview(WidgetTester tester, Map<String, dynamic> workout) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [previewPlanProvider.overrideWith((ref, key) async => workout)],
        child: const MaterialApp(home: PreviewWorkoutScreen(phaseNumber: 'II', week: 5, day: 1)),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('warm-up, finisher and cool-down counts in one line', (tester) async {
      await ensureHive(tester);
      await pumpPreview(tester, {
        'name': 'Upper',
        'focus_text': 'x',
        'exercises': <Map<String, dynamic>>[],
        'warmup_count': 2,
        'finisher_count': 3,
        'cooldown_count': 3,
      });
      expect(find.text('2 warm-up · 3 finisher · 3 cool-down exercises included'), findsOneWidget);
    });

    testWidgets('a finisher-only day still shows the line', (tester) async {
      await ensureHive(tester);
      await pumpPreview(tester, {
        'name': 'Upper',
        'focus_text': 'x',
        'exercises': <Map<String, dynamic>>[],
        'warmup_count': 0,
        'finisher_count': 1,
        'cooldown_count': 0,
      });
      expect(find.text('1 finisher exercise included'), findsOneWidget, reason: 'one exercise in all: singular');
    });
  });
}
