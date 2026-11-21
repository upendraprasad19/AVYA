// Coach workout parity 1a (OI-379) — END-TO-END: every completion door counts
// the workout the same way (plan `docs/plans/coach-workout-parity-1a.md` rev 4,
// §3 T3). Before 1a only Active Workout raised `total_workouts_done`; the chat
// card, the typed all-logged backstop and the completion-prompt tap marked the
// day and counted nothing.
//
// Each door runs for real: the chat card through `submitWorkoutDraft` with a
// WidgetRef from a mounted `WorkoutDraftSlot`, the typed backstop through
// `ToolDispatcher.maybeCompleteScheduledDayForTest`, the tap through
// `ChatHistoryNotifier.completeWorkoutFromPrompt`, Active Workout through
// `ActiveWorkoutNotifier.completeWorkout`. The recorder on `afterCompletion`
// proves which door reached the shared step and with which `newlyCompleted`.
//
// Every chat-card case uses a day whose planned exercises are ALL on the card,
// so each case means the same before and after slice 1b's stricter card rule.
//
// ORDER IS LOAD-BEARING (workout_log_confirm_card_saved_signal_test.dart): the
// first widget test renders every font family with NO path_provider mock; Hive
// opens lazily inside `runAsync` afterwards and closes in tearDownAll.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/coach_completion_counts_behavioral_test.dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/workout_draft_slot.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart'
    show userStatsProvider;
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';
import 'package:icanbefitter/features/train/services/workout_completion_bookkeeping.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/workout_draft_seed.dart';

const _userB = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';

Directory? _dir;
final _calls = <CompletionBookkeepingCall>[];
final _events = <String>[];

// ── Hive ────────────────────────────────────────────────────────────

Future<void> _openFresh(WidgetTester tester) async {
  _dir ??= await tester.runAsync(setUpHiveForTests);
  await tester.runAsync(() async {
    if (HiveUserSession.currentOwnerFullId != kTestUserId) {
      await HiveUserSession.openForUser(kTestUserId);
    }
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox.put('progress', {'total_workouts_done': 0});
  });
}

int _total() =>
    ((HiveService.instance.userBox.get('progress') as Map?)?['total_workouts_done']
            as num?)
        ?.toInt() ??
    -1;

DateTime get _today => DateTime.now();

Future<void> _seedDay(
  List<String> exercises, {
  String type = 'custom_template',
  String status = 'planned',
  String workoutName = 'Upper Body',
}) =>
    HiveService.instance.workoutBox.put(WorkoutWriteService.scheduleKey(_today), {
      'date': istDateStr(_today),
      'workout_name': workoutName,
      'status': status,
      'type': type,
      'exercises': [
        for (final e in exercises) {'exercise_name': e}
      ],
    });

// ── Doors ───────────────────────────────────────────────────────────

/// The chat card: a mounted slot seeded with [draft], then the REAL submit.
Future<_Slot> _pumpSlot(WidgetTester tester, WorkoutDraft draft) async {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    workoutDraftProvider.overrideWith(() => SeededWorkoutDraftNotifier(draft)),
  ]);
  addTearDown(c.dispose);
  final s = _Slot(c);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Consumer(builder: (context, ref, _) {
            s.ref = ref;
            return const SizedBox.shrink();
          }),
          const Expanded(child: WorkoutDraftSlot()),
        ]),
      ),
    ),
  ));
  await tester.pump();
  return s;
}

class _Slot {
  final ProviderContainer c;
  late WidgetRef ref;
  _Slot(this.c);
}

DraftExercise _lift(String name) => DraftExercise(
      name: name,
      loggingType: 'weight_reps',
      sets: [for (var i = 0; i < 3; i++) DraftSet(weightKg: 60, reps: 8)],
    );

/// A 60 s set that saves plus a -100 s set that is filtered: the day's
/// duration goes negative, so `markCompleted` refuses.
DraftExercise _badPlank() => DraftExercise(
    name: 'Plank',
    loggingType: 'timed',
    sets: [DraftSet(durationSecs: 60), DraftSet(durationSecs: -100)]);

WorkoutDraft _draft(List<DraftExercise> ex, String id) =>
    WorkoutDraft(id: id, exercises: ex, date: DateTime.now());

Future<DraftSubmitOutcome> _chatCard(WidgetTester tester, List<DraftExercise> ex,
    {String id = 'wdraft_a', Future<void> Function()? whileHeld}) async {
  final s = await _pumpSlot(tester, _draft(ex, id));
  final out = await tester.runAsync(() async {
    final f = submitWorkoutDraft(_draft(ex, id), s.ref);
    if (whileHeld != null) await whileHeld();
    return f;
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  return out!;
}

/// The typed all-logged backstop, exactly as `_executeLogSet` runs it.
Future<void> _coachLog(WidgetTester tester, String name) =>
    tester.runAsync(() async {
      final r = await WorkoutWriteService.instance.logExercise(
        date: _today,
        exerciseName: name,
        sets: [
          ExerciseSet(
              weightKg: 60,
              reps: 8,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch),
        ],
        source: WriteSource.aiCoach,
      );
      expect(r.success, isTrue);
      await ToolDispatcher.instance
          .maybeCompleteScheduledDayForTest(_today, istDateStr(_today));
    });

/// The completion-prompt tap.
Future<CoachTapResult> _tap(WidgetTester tester) async {
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => const Stream.empty()),
  ]);
  addTearDown(c.dispose);
  c.read(chatHistoryProvider);
  final n = c.read(chatHistoryProvider.notifier);
  return (await tester
      .runAsync(() => n.completeWorkoutFromPrompt(istDateStr(_today))))!;
}

class _SeededActive extends ActiveWorkoutNotifier {
  _SeededActive(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

/// Active Workout: one saveable set of [exercise], then COMPLETE.
Future<void> _activeWorkout(WidgetTester tester,
    {String exercise = 'Bench Press',
    String dayName = 'Upper Body',
    Future<void> Function()? whileHeld}) async {
  final ex = ExerciseData(
      name: exercise,
      sets: '3',
      reps: '8',
      weight: '50kg',
      rest: '90s',
      loggingType: 'weight_reps');
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    activeWorkoutProvider.overrideWith(() => _SeededActive(ActiveWorkoutData(
          workoutDay: WorkoutDayData(dayNumber: 1, name: dayName, exercises: [ex]),
          exercises: [ex],
          checkedSets: const {'0-0': true},
          setInputValues: const {'0-0': SetInputValues(weight: 50, reps: 8)},
        ))),
  ]);
  addTearDown(c.dispose);
  await tester.runAsync(() async {
    final f = c.read(activeWorkoutProvider.notifier).completeWorkout();
    if (whileHeld != null) await whileHeld();
    await f;
  });
}

/// Seeds account B with a progress map, then reopens account A.
Future<void> _seedUserB(WidgetTester tester) => tester.runAsync(() async {
      await HiveUserSession.openForUser(_userB);
      await HiveService.instance.workoutBox.clear();
      await HiveService.instance.userBox
          .put('progress', {'total_workouts_done': 0});
      await HiveUserSession.openForUser(kTestUserId);
    });

List<String> _doors() => [
      for (final c in _calls) '${c.door.name}:${c.newlyCompleted}',
    ];

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
      ]),
    ));
  });

  setUp(() {
    _calls.clear();
    _events.clear();
    WorkoutCompletionBookkeeping.debugReset();
    WorkoutCompletionBookkeeping.debugOnCall = _calls.add;
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {String? message}) => _events.add(op);
    WorkoutDraftNotifier.savedHoldFor = (_) => const Duration(hours: 1);
    DraftSubmitDebug.debugSubmitGate = null;
    DraftSubmitDebug.debugBeforeMarkGate = null;
    ActiveWorkoutNotifier.debugBeforeMarkGate = null;
  });

  tearDown(() {
    WorkoutCompletionBookkeeping.debugReset();
    ErrorTelemetry.debugOnLogEventForTests = null;
    WorkoutDraftNotifier.savedHoldFor = WorkoutDraftNotifier.defaultSavedHoldFor;
    DraftSubmitDebug.debugSubmitGate = null;
    DraftSubmitDebug.debugBeforeMarkGate = null;
    ActiveWorkoutNotifier.debugBeforeMarkGate = null;
  });

  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  group('the chat card', () {
    testWidgets('CONFIRM completing the day counts it once', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      final out = await _chatCard(tester, [_lift('Bench Press')]);
      expect(out.dayMarked, isTrue);
      expect(_total(), 1);
      expect(_doors(), ['chatCard:true']);
    });

    testWidgets('a second CONFIRM the same day never reaches the mark: +1 total',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _chatCard(tester, [_lift('Bench Press')], id: 'wdraft_a');
      await _chatCard(tester, [_lift('Bench Press')], id: 'wdraft_b');
      expect(_total(), 1);
      expect(_doors(), ['chatCard:true']);
    });

    testWidgets('a completed status with no wlog_ is re-marked: newlyCompleted '
        'false, the heal counts the day: +1 total', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedDay(['Bench Press'], status: 'completed'));
      await _chatCard(tester, [_lift('Bench Press')]);
      expect(_total(), 1);
      expect(_doors(), ['chatCard:false']);
    });

    testWidgets('a failed markCompleted counts nothing', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Plank']));
      final out = await _chatCard(tester, [_badPlank()]);
      expect(out.dayMarked, isFalse);
      expect(_total(), 0);
      expect(_calls, isEmpty);
    });

    for (final where in const ['submit', 'mark']) {
      testWidgets('an account change at the $where gate writes nothing to the '
          'new account', (tester) async {
        await _openFresh(tester);
        await _seedUserB(tester);
        await tester.runAsync(() => _seedDay(['Bench Press']));
        // Created in the REAL zone: a Completer made in the fake-async test
        // zone completes through that zone's microtask queue, which never
        // runs inside runAsync, so the held submit would never resume.
        final gate = (await tester.runAsync(() async => Completer<void>()))!;
        if (where == 'submit') {
          DraftSubmitDebug.debugSubmitGate = gate;
        } else {
          DraftSubmitDebug.debugBeforeMarkGate = gate;
        }
        await _chatCard(tester, [_lift('Bench Press')], whileHeld: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await HiveUserSession.openForUser(_userB);
          gate.complete();
        });
        expect(HiveUserSession.currentOwnerFullId, _userB);
        expect(_total(), 0, reason: 'account B\'s count is untouched');
        // Coach workout parity 1b: the card now stops at its own owner check,
        // BEFORE the day decision reads (and could write the prompt or the
        // mark into) account B's boxes; the 1a bookkeeping guard is behind it.
        expect(_events, contains('chat_card_owner_changed'));
        expect(
            HiveService.instance.workoutBox.keys.where((k) =>
                '$k'.startsWith('schedule_') || '$k'.startsWith('wlog_')),
            isEmpty,
            reason: 'no day row is written into account B');
        expect(
            HiveService.instance.coachBox.keys
                .where((k) => '$k'.startsWith('completion_prompt_')),
            isEmpty,
            reason: 'no completion tile is written into account B');
      });
    }

    testWidgets('the Profile count (userStatsProvider) reads the new total',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _chatCard(tester, [_lift('Bench Press')]);
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('u'),
      ]);
      addTearDown(c.dispose);
      expect(c.read(userStatsProvider).totalWorkouts, 1);
    });
  });

  group('the typed all-logged backstop and the prompt tap', () {
    testWidgets('typed all-logged auto: +1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _coachLog(tester, 'Bench Press');
      expect(_total(), 1);
      expect(_doors(), ['coachAuto:true']);
    });

    testWidgets('prompt tap on a partial day: +1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press', 'Row']));
      await _coachLog(tester, 'Bench Press');
      expect(_total(), 0, reason: 'a partial day is not done');
      final r = await _tap(tester);
      expect(r, CoachTapResult.completed);
      expect(_total(), 1);
      expect(_doors(), ['coachTap:true']);
    });

    testWidgets('auto, then a stale tap: +1 total', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _coachLog(tester, 'Bench Press');
      await _tap(tester);
      expect(_total(), 1);
      expect(_doors(), ['coachAuto:true']);
    });

    testWidgets('a failed markCompleted (auto and tap) counts nothing',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press'], workoutName: '  '));
      await _coachLog(tester, 'Bench Press');
      expect(_total(), 0);
      await tester.runAsync(
          () => _seedDay(['Bench Press', 'Row'], workoutName: '  '));
      final r = await _tap(tester);
      expect(r, CoachTapResult.failed);
      expect(_total(), 0);
      expect(_calls, isEmpty);
    });
  });

  group('Active Workout', () {
    testWidgets('a second session the same day: +1 total (was +2)',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _activeWorkout(tester);
      await _activeWorkout(tester, exercise: 'Row');
      expect(_total(), 1);
      expect(_doors(), ['activeWorkout:true', 'activeWorkout:false']);
    });

    testWidgets('Active Workout, then the chat card: +1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _activeWorkout(tester);
      await _chatCard(tester, [_lift('Bench Press')]);
      expect(_total(), 1);
      expect(_doors(), ['activeWorkout:true']);
    });

    testWidgets('the chat card, then Active Workout: +1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(['Bench Press']));
      await _chatCard(tester, [_lift('Bench Press')]);
      await _activeWorkout(tester);
      expect(_total(), 1);
      expect(_doors(), ['chatCard:true', 'activeWorkout:false']);
    });

    for (final row in const [
      ('rest', 'planned'),
      ('custom_template', 'paused'),
      ('custom_template', 'moved'),
    ]) {
      testWidgets('a ${row.$1}/${row.$2} today-row still counts: +1',
          (tester) async {
        await _openFresh(tester);
        await tester.runAsync(
            () => _seedDay(['Bench Press'], type: row.$1, status: row.$2));
        await _activeWorkout(tester);
        expect(_total(), 1);
        expect(_doors(), ['activeWorkout:true']);
      });
    }

    testWidgets('a failed markCompleted counts nothing', (tester) async {
      await _openFresh(tester);
      await _activeWorkout(tester, dayName: '  ');
      expect(_total(), 0);
      expect(_calls, isEmpty);
      expect(_events, contains('active_workout_mark_completed_failed'));
    });

    testWidgets('an account change before the mark writes nothing to the new '
        'account', (tester) async {
      await _openFresh(tester);
      await _seedUserB(tester);
      // Created in the REAL zone: a Completer made in the fake-async test
      // zone completes through that zone's microtask queue, which never
      // runs inside runAsync, so the held submit would never resume.
      final gate = (await tester.runAsync(() async => Completer<void>()))!;
      ActiveWorkoutNotifier.debugBeforeMarkGate = gate;
      await _activeWorkout(tester, whileHeld: () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await HiveUserSession.openForUser(_userB);
        gate.complete();
      });
      expect(HiveUserSession.currentOwnerFullId, _userB);
      expect(_total(), 0, reason: 'account B\'s count is untouched');
      expect(_events, contains('completion_bookkeeping_owner_changed'));
    });
  });
}
