// Unit 3D-b (OI-175, d57; plan docs/plans/2026-11-16-generator-step3d-hold-weeks.md section 2.1): the two callers
// of the free-tier hold write, on real Hive.
//
// - PlanExpiredCard: written -> "Line held" + onRedoComplete + phase_1_cycle_repeat_started; a second tap ->
//   "Already holding this week." with no refresh and no second repeat event; noPlan -> the error snackbar.
// - keepTrainingPhase1 (graduation): after expiry the providers built before the tap read the hold after it
//   (currentPlanProvider / holdStatusProvider / todayWorkoutProvider, round 3 B-F2 and round 4 F2), then /train;
//   the screen popped during the write still refreshes them through the captured container (round 4 F1); a failed
//   write stays put with the error snackbar (H5).
//
// The service half (the guard, the covered rule, the outcomes) is test/contracts/hold_week_d57_behavioral_test.dart.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/app_events_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/keep_training_phase1_action.dart';
import 'package:icanbefitter/features/train/widgets/plan_expired_card.dart';

import 'log_exercise/card_harness.dart';

Map? _row(DateTime d) {
  final raw = HiveService.instance.workoutBox.get('schedule_${formatDateKey(d)}');
  return raw is Map ? raw : null;
}

int _events(String name) =>
    AppEventsService.debugCapture!.where((e) => e.event == name).length;

/// A 4-week plan from [start] (a Monday), each row carrying `src_week`.
Future<void> _seedPlan(DateTime start) async {
  await MigratedKey.write('plan_start_date', start.toIso8601String());
  await MigratedKey.write('plan_end_date', start.add(const Duration(days: 27)).toIso8601String());
  for (var week = 1; week <= 4; week++) {
    for (var d = 0; d < 7; d++) {
      final date = start.add(Duration(days: (week - 1) * 7 + d));
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'type': d == 6 ? 'rest' : 'workout',
          'date': formatDateKey(date),
          'week': week,
          'phase': 1,
          'src_week': week,
          'status': d == 6 ? 'rest' : 'planned',
          'exercises': const <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );
    }
  }
}

Future<void> _clearSchedule() async {
  final box = HiveService.instance.workoutBox;
  for (final k in box.keys.where((k) => k.toString().startsWith('schedule_')).toList()) {
    await box.delete(k);
  }
}

void main() {
  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await renderFontsFirst(tester);
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        for (final s in [AppTypography.titleS, AppTypography.bodyM, AppTypography.buttonLabel])
          Text('x', style: s),
      ]),
    ));
  });
  tearDownAll(closeHive);

  // Real today (todayWorkoutProvider reads DateTime.now(), not the seam):
  // plan_start = the Monday five weeks before this week's Monday, so today
  // is past plan_end and the hold lands on this week.
  late DateTime thisMonday;
  late DateTime start;

  Future<void> seedRealToday(WidgetTester tester) async {
    await ensureHive(tester);
    await tester.runAsync(() async {
      AppEventsService.debugCapture = [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      thisMonday = today.subtract(Duration(days: today.weekday - 1));
      start = thisMonday.subtract(const Duration(days: 35));
      await _seedPlan(start);
    });
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.runAsync(() async {
      WorkoutScheduleWriteService.debugHoldRowWrite = null;
      AppEventsService.debugCapture = null;
      await _clearSchedule();
    });
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('$what never happened');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('PlanExpiredCard: written -> snackbar + refresh + the repeat event; '
      'a second tap -> "Already holding", no second event', (tester) async {
    await seedRealToday(tester);
    var refreshed = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanExpiredCard(onRedoComplete: () => refreshed++),
          ),
        ),
      ),
    ));
    await tester.pump();
    final pill = find.text('Hold the line — another week');
    expect(pill, findsOneWidget);
    expect(find.text('Run Week 4 again'), findsNothing, reason: 'the OFF layout is deleted');

    await tapWithRealIo(tester, pill);
    await waitFor(tester, () => refreshed == 1, 'the hold write');
    await tester.pump();
    expect(find.text('Line held. Another week on the board.'), findsOneWidget);
    expect(_events('phase_1_cycle_repeat_started'), 1);
    expect(_row(thisMonday)!['hold_ordinal'], 1);

    await tester.pump(const Duration(seconds: 4)); // the snackbar leaves
    await tapWithRealIo(tester, pill);
    await waitFor(tester, () => find.text('Already holding this week.').evaluate().isNotEmpty,
        'the already-holding snackbar');
    expect(refreshed, 1, reason: 'nothing written, nothing to refresh');
    expect(_events('phase_1_cycle_repeat_started'), 1);
    expect(_events('phase_1_day_29_redo_week_4_tapped'), 2,
        reason: 'the stored tap event name is kept');
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('PlanExpiredCard: noPlan -> the error snackbar, no repeat event', (tester) async {
    await seedRealToday(tester);
    await tester.runAsync(() => MigratedKey.delete('plan_start_date'));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PlanExpiredCard(onRedoComplete: () {}))),
      ),
    ));
    await tester.pump();
    await tapWithRealIo(tester, find.text('Hold the line — another week'));
    await waitFor(tester, () => find.text("Couldn't schedule again. Please try again.").evaluate().isNotEmpty,
        'the error snackbar');
    expect(_events('phase_1_cycle_repeat_started'), 0);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  Widget graduationHost(void Function(WidgetRef ref) capture) {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'grad',
            builder: (_, _) => Scaffold(
              body: Consumer(builder: (context, ref, _) {
                capture(ref);
                return TextButton(
                  onPressed: () => keepTrainingPhase1(context, ref),
                  child: const Text('KEEP TRAINING PHASE 1'),
                );
              }),
            ),
          ),
        ],
      ),
      GoRoute(path: '/train', builder: (_, _) => const Scaffold(body: Text('train tab'))),
    ], initialLocation: '/grad');
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('graduation tap after expiry: providers built before the tap read the hold after it '
      '(round 3 B-F2, round 4 F2), then /train', (tester) async {
    await seedRealToday(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: graduationHost((_) {}),
    ));
    await tester.pump();
    // Built BEFORE the tap: no hold, no row today.
    expect(container.read(holdStatusProvider).isHolding, isFalse);
    expect(container.read(todayWorkoutProvider), isNull);
    expect(container.read(selectedWeekProvider).week, 4);
    // B-pass seat B F5: a pick made before the tap, so the selected-week
    // invalidation is observable (it resets the pick to the default week).
    container.read(selectedWeekProvider.notifier).select(2);
    expect(container.read(selectedWeekProvider).picked, isTrue);

    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await waitFor(tester, () => find.text('train tab').evaluate().isNotEmpty, 'navigation to /train');
    expect(container.read(holdStatusProvider).isHolding, isTrue);
    expect(container.read(holdStatusProvider).todayHoldOrdinal, 1);
    expect(container.read(todayWorkoutProvider)?['is_hold'], isTrue,
        reason: 'Home\'s today card watches only the auth token: it must be invalidated');
    expect(container.read(selectedWeekProvider).picked, isFalse,
        reason: 'the hold\'s H chip is "you are here": the old pick is cleared');
    expect(container.read(selectedWeekProvider).week, 4);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('graduation: the screen popped during the write still refreshes the providers '
      '(round 4 F1, the container captured before the await)', (tester) async {
    await seedRealToday(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gate = Completer<void>();
    WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async {
      await gate.future;
      return WorkoutWriteService.instance.upsertScheduled(
          date: date, entry: entry, source: WriteSource.schedSwap);
    };
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: graduationHost((_) {}),
    ));
    await tester.pump();
    expect(container.read(holdStatusProvider).isHolding, isFalse);
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await tester.pump();
    // Pop the graduation screen while the write waits.
    final navContext = tester.element(find.text('KEEP TRAINING PHASE 1'));
    GoRouter.of(navContext).go('/');
    await tester.pumpAndSettle();
    expect(find.text('KEEP TRAINING PHASE 1'), findsNothing);
    gate.complete();
    await waitFor(tester, () => container.read(holdStatusProvider).isHolding,
        'the refresh through the captured container');
    expect(find.text('home'), findsOneWidget, reason: 'an unmounted screen does not navigate');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('graduation: a failed write stays put with the error snackbar (H5)', (tester) async {
    await seedRealToday(tester);
    WorkoutScheduleWriteService.debugHoldRowWrite =
        (date, entry) async => WriteResult.fail('disk full');
    await tester.pumpWidget(ProviderScope(child: graduationHost((_) {})));
    await tester.pump();
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await waitFor(tester, () => find.text("Couldn't schedule again. Please try again.").evaluate().isNotEmpty,
        'the error snackbar');
    expect(find.text('train tab'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  // ── B-pass seat B F1: every outcome arm of both callers ──

  const errorText = "Couldn't schedule again. Please try again.";

  testWidgets('graduation: alreadyHolding -> the snackbar and /train, nothing written', (tester) async {
    await seedRealToday(tester);
    await tester.runAsync(() => WorkoutScheduleWriteService.instance.holdWeek());
    expect(_row(thisMonday)!['hold_ordinal'], 1);
    await tester.pumpWidget(ProviderScope(child: graduationHost((_) {})));
    await tester.pump();
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await waitFor(tester, () => find.text('train tab').evaluate().isNotEmpty, 'navigation to /train');
    expect(find.text('Already holding this week.'), findsOneWidget);
    expect(_row(thisMonday.add(const Duration(days: 7))), isNull, reason: 'no second hold');
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('graduation: noPlan -> the error snackbar, stays put', (tester) async {
    await seedRealToday(tester);
    await tester.runAsync(() => MigratedKey.delete('plan_start_date'));
    await tester.pumpWidget(ProviderScope(child: graduationHost((_) {})));
    await tester.pump();
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await waitFor(tester, () => find.text(errorText).evaluate().isNotEmpty, 'the error snackbar');
    expect(find.text('train tab'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('graduation: a write that THROWS -> failed: the error snackbar, stays put', (tester) async {
    await seedRealToday(tester);
    WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async => throw StateError('io');
    await tester.pumpWidget(ProviderScope(child: graduationHost((_) {})));
    await tester.pump();
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await waitFor(tester, () => find.text(errorText).evaluate().isNotEmpty, 'the error snackbar');
    expect(find.text('train tab'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  /// Starts a hold whose row writes wait on [gate], so the next call is inFlight.
  Future<Future<HoldWeekOutcome>> startGatedHold(WidgetTester tester, Completer<void> gate) async {
    WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async {
      await gate.future;
      return WorkoutWriteService.instance.upsertScheduled(
          date: date, entry: entry, source: WriteSource.schedSwap);
    };
    late Future<HoldWeekOutcome> first;
    await tester.runAsync(() async {
      first = WorkoutScheduleWriteService.instance.holdWeek();
    });
    return first;
  }

  testWidgets('graduation: inFlight -> nothing (no snackbar, no navigation)', (tester) async {
    await seedRealToday(tester);
    final gate = Completer<void>();
    final first = await startGatedHold(tester, gate);
    await tester.pumpWidget(ProviderScope(child: graduationHost((_) {})));
    await tester.pump();
    await tapWithRealIo(tester, find.text('KEEP TRAINING PHASE 1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('train tab'), findsNothing);
    expect(find.text('KEEP TRAINING PHASE 1'), findsOneWidget);
    // The gate was made in the fake-async zone: its completion runs on a pump,
    // so poll with waitFor (which pumps), never `runAsync(() => first)`.
    HoldWeekOutcome? firstOutcome;
    unawaited(first.then((o) => firstOutcome = o));
    gate.complete();
    await waitFor(tester, () => firstOutcome != null, 'the first hold to finish');
    expect(firstOutcome, HoldWeekOutcome.written);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('PlanExpiredCard: failed -> the error snackbar, no refresh, no repeat event', (tester) async {
    await seedRealToday(tester);
    WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async => WriteResult.fail('disk full');
    var refreshed = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PlanExpiredCard(onRedoComplete: () => refreshed++))),
      ),
    ));
    await tester.pump();
    await tapWithRealIo(tester, find.text('Hold the line — another week'));
    await waitFor(tester, () => find.text(errorText).evaluate().isNotEmpty, 'the error snackbar');
    expect(refreshed, 0);
    expect(_events('phase_1_cycle_repeat_started'), 0);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });

  testWidgets('PlanExpiredCard: inFlight -> nothing (no snackbar, no refresh, no event)', (tester) async {
    await seedRealToday(tester);
    final gate = Completer<void>();
    final first = await startGatedHold(tester, gate);
    var refreshed = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PlanExpiredCard(onRedoComplete: () => refreshed++))),
      ),
    ));
    await tester.pump();
    await tapWithRealIo(tester, find.text('Hold the line — another week'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsNothing);
    expect(refreshed, 0);
    expect(_events('phase_1_cycle_repeat_started'), 0);
    // The gate was made in the fake-async zone: its completion runs on a pump,
    // so poll with waitFor (which pumps), never `runAsync(() => first)`.
    HoldWeekOutcome? firstOutcome;
    unawaited(first.then((o) => firstOutcome = o));
    gate.complete();
    await waitFor(tester, () => firstOutcome != null, 'the first hold to finish');
    expect(firstOutcome, HoldWeekOutcome.written);
    await tester.pumpWidget(const SizedBox());
    await cleanUp(tester);
  });
}
