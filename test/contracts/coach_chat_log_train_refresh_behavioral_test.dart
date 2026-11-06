// OI-370 (diagnose: docs/diagnoses/2026-10-21-coach-chat-log-train-stale-*.md)
//
// After a coach chat log (CONFIRM · LOG WORKOUT -> submitWorkoutDraft) on a
// day already DONE, the Train tab's expanded day row must show the new
// exercise at once, with no reload: the chat path now invalidates the same
// workout batch as the ToolDispatcher path (invalidateWorkoutSurfaces), so
// `currentPlanProvider` (which the Train screen watches) rebuilds the row.
// Promoted from the scratch reproduction test/scratch_obs3/.
//
// ORDER IS LOAD-BEARING (card_harness.dart / zero_set_completion_behavioral_test):
// fonts render first with NO path_provider mock; Hive opens lazily in runAsync.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/riverpod_paused_count_collector.dart';
import '../helpers/workout_draft_seed.dart';

const _nb = ' ';
const kBenchDetail = '3${_nb}sets$_nb· 8${_nb}reps$_nb· 60.0${_nb}kg';

Directory? dir;

Future<void> renderFontsFirst(WidgetTester tester) async {
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
}

/// Seeds a plan whose week 1 contains today (a workout day), then performs
/// "step 1" (Active Workout FINISH -> COMPLETE) through the real writers:
/// two logExercise calls + markCompleted.
Future<void> seedPlanAndStep1() async {
  final wb = HiveService.instance.workoutBox;
  await wb.clear();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  await HiveService.instance.userBox
      .put('plan_start_date', istDateStr(monday));
  await wb.put('current_plan', {'focus': 'Test focus', 'name': 'Foundation'});
  for (int i = 0; i < 7; i++) {
    final d = monday.add(Duration(days: i));
    final isToday = istDateStr(d) == istDateStr(today);
    await wb.put('schedule_${istDateStr(d)}', {
      'date': istDateStr(d),
      'week': 1,
      'day_of_week': i,
      'type': isToday ? 'workout' : 'rest',
      'workout_name': isToday ? 'Push Day' : 'Rest Day',
      'workout_focus': 'Push',
      'status': 'planned',
      'exercises': isToday
          ? [
              {'exercise_name': 'Squat', 'sets': 3, 'reps': '5'},
              {'exercise_name': 'Barbell Row', 'sets': 3, 'reps': '8'},
            ]
          : <Map<String, dynamic>>[],
    });
  }
  for (final (name, w, r) in [('Squat', 80.0, 5), ('Barbell Row', 50.0, 8)]) {
    final res = await WorkoutWriteService.instance.logExercise(
      date: now,
      exerciseName: name,
      sets: [
        for (var i = 0; i < 3; i++)
          ExerciseSet(
              weightKg: w,
              reps: r,
              loggedAtMs: now.millisecondsSinceEpoch - 600000 + i),
      ],
      source: WriteSource.activeWorkout,
    );
    expect(res.success, isTrue, reason: res.errorMessage);
  }
  final done = await WorkoutWriteService.instance
      .markCompleted(date: now, workoutName: 'Push Day', durationSec: 1800);
  expect(done.success, isTrue);
}

WorkoutDraft benchDraft() => WorkoutDraft(
      id: 'wdraft_obs3',
      date: DateTime.now(),
      exercises: [
        DraftExercise(
          name: 'Bench Press',
          loggingType: 'weight_reps',
          sets: [for (var i = 0; i < 3; i++) DraftSet(weightKg: 60, reps: 8)],
        ),
      ],
    );

class _Harness {
  final ProviderContainer container;
  final ValueNotifier<bool> trainActive;
  final ValueNotifier<bool> coachMounted;
  WidgetRef? coachRef;
  _Harness(this.container, this.trainActive, this.coachMounted);
}

/// Pumps the real TrainScreen under a TickerMode switch (the go_router
/// StatefulShellRoute.indexedStack wraps inactive branches in
/// Offstage + TickerMode(enabled: false)), plus a Consumer standing in for
/// the coach card: it hands back the WidgetRef the chat path receives and can
/// be unmounted mid-submit.
Future<_Harness> pumpTrain(WidgetTester tester, List<Object> paused,
    {WorkoutDraft? seed}) async {
  final c = containerCollectingPausedCount(paused, [
    authUserIdTokenProvider.overrideWithValue('u'),
    if (seed != null)
      workoutDraftProvider.overrideWith(() => SeededWorkoutDraftNotifier(seed)),
  ]);
  addTearDown(c.dispose);
  final h = _Harness(c, ValueNotifier(true), ValueNotifier(true));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Stack(children: [
        ValueListenableBuilder<bool>(
          valueListenable: h.trainActive,
          builder: (_, on, child) => Offstage(
            offstage: !on,
            child: TickerMode(enabled: on, child: child!),
          ),
          child: const TrainScreen(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: h.coachMounted,
          builder: (_, on, _) => on
              ? Consumer(builder: (context, ref, _) {
                  h.coachRef = ref;
                  return const SizedBox.shrink();
                })
              : const SizedBox.shrink(),
        ),
      ]),
    ),
  ));
  await tester.pump(); // HiveTabScaffoldMixin post-frame isLoading flip
  await tester.pump();
  // Expand today's (DONE) row, as the founder had it. Plan starts Monday and
  // every day has a row, so today's index is weekday-1.
  final idx = DateTime.now().weekday - 1;
  expect(find.text('DONE'), findsWidgets, reason: 'step 1 left today DONE');
  c.read(expandedDayProvider.notifier).toggle(idx);
  await tester.pump();
  return h;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Lets the card's real saved-hold timer fire, then drains the Train screen.
Future<void> finish(WidgetTester tester, ProviderContainer c) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1600)));
  await tester.pump();
  expect(c.read(workoutDraftProvider), isNull,
      reason: 'the saved hold ended and cleared the draft');
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1)); // drain StreakBadge 400ms timer
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  tearDownAll(() async {
    if (dir != null) await tearDownHiveForTests(dir!);
  });

  Future<void> ensureHive(WidgetTester tester) async {
    dir ??= await tester.runAsync(setUpHiveForTests);
  }

  test('collector self-test: only the paused-count assertion is kept', () async {
    final paused = <Object>[];
    final forwarded = <Object>[];
    final handler = pausedCountHandler(paused, (e, _) => forwarded.add(e));
    final done = Completer<void>();
    runZonedGuarded(() {
      Future<void>(() => throw StateError('unrelated'));
      Future<void>(() => throw AssertionError(
          'actualPausedCount == expectedPausedCount'));
      Future<void>(() => done.complete());
    }, handler);
    await done.future;
    await Future<void>.delayed(Duration.zero);
    expect(forwarded.single, isA<StateError>(),
        reason: 'an unrelated error must reach the test zone');
    expect(paused.single, isA<AssertionError>());
  });

  for (final offstage in [false, true]) {
    final tag = offstage ? '[Train offstage]' : '[Train visible]';

    testWidgets('$tag CHAT path (submitWorkoutDraft): the expanded row shows '
        'the new exercise with no manual invalidate', (tester) async {
      await ensureHive(tester);
      await tester.runAsync(seedPlanAndStep1);
      final paused = <Object>[];
      final draft = benchDraft();
      final h = await pumpTrain(tester, paused, seed: draft);
      expect(find.text('Squat'), findsWidgets);
      expect(find.text(kBenchDetail), findsNothing);

      if (offstage) {
        h.trainActive.value = false; // switch to the Coach tab
        await settle(tester);
      }
      final outcome =
          await tester.runAsync(() => submitWorkoutDraft(draft, h.coachRef!));
      expect(outcome!.savedIndices, [0]);
      if (offstage) h.trainActive.value = true; // back to the Train tab
      await settle(tester);

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text(kBenchDetail), findsOneWidget,
          reason: 'the chat path refreshes the Train row itself');
      await finish(tester, h.container);
    });

    testWidgets('$tag TOOL path (log_set -> ToolDispatcher): the expanded row '
        'refreshes without reload', (tester) async {
      await ensureHive(tester);
      await tester.runAsync(seedPlanAndStep1);
      final paused = <Object>[];
      final h = await pumpTrain(tester, paused);
      final c = h.container;
      expect(find.text(kBenchDetail), findsNothing);

      if (offstage) {
        h.trainActive.value = false;
        await settle(tester);
      }
      final n = c.read(pendingToolIntentsProvider.notifier);
      final id = 'intent_obs3_${offstage ? 'off' : 'on'}';
      n.addIntents([
        ToolIntent(
          id: id,
          type: 'log_set',
          payload: const {
            'exerciseId': 'Bench Press',
            'weightKg': 60,
            'reps': 8,
            'sets': 3,
          },
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: 'LOG SET',
          createdAt: DateTime.now(),
        ),
      ]);
      final result = await tester.runAsync(() => n.confirm(id));
      expect(result!.success, isTrue, reason: result.errorMessage);
      if (offstage) h.trainActive.value = true;
      await settle(tester);

      expect(find.text(kBenchDetail), findsOneWidget,
          reason: 'ToolDispatcher invalidates currentPlanProvider');
      if (offstage) {
        // Tripwire for OI-378 (riverpod 3.2.1 upstream): when a Riverpod
        // bump fixes it, this goes red and the OI reopens.
        expect(paused, isNotEmpty,
            reason: 'the upstream paused-count assertion fired offstage');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('disposed card: the coach card unmounts mid-submit and the row '
      'still refreshes, the draft still clears', (tester) async {
    await ensureHive(tester);
    await tester.runAsync(seedPlanAndStep1);
    final paused = <Object>[];
    final draft = benchDraft();
    final h = await pumpTrain(tester, paused, seed: draft);
    final ref = h.coachRef!;

    late Future<DraftSubmitOutcome> f;
    await tester.runAsync(() async {
      f = submitWorkoutDraft(draft, ref);
      await Future<void>.delayed(Duration.zero);
    });
    h.coachMounted.value = false; // the card is gone (OI-232 channel switch)
    await tester.pump();
    final outcome = await tester.runAsync(() => f);
    expect(outcome!.savedIndices, [0], reason: 'no StateError on a dead ref');
    expect(h.container.read(workoutDraftProvider)?.status,
        DraftCardStatus.saved);
    await settle(tester);
    expect(find.text(kBenchDetail), findsOneWidget);
    await finish(tester, h.container);
  });
}
