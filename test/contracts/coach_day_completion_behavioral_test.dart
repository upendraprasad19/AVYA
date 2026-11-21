// Coach workout parity 1b (OI-490; plan docs/plans/coach-workout-parity-1b.md
// rev 4, §5). Behavioural contract for the ONE coach-day completion rule
// (`decideCoachDay`, `lib/features/train/services/coach_day_completion.dart`)
// and its four doors: the typed all-logged backstop, the chat workout card,
// the completion tile's tap and Train's COMPLETE WORKOUT (the last two through
// `CoachDayCompletion.completeOnTap`).
//
// Founder decisions (2026-11-10): 2 — a coach-logged day is done only when
// every planned exercise is logged, or the user taps Complete; F — a
// forgotten (past) day stays not done; on the coach paths a rest, moved or
// no-plan day never counts. 1a counts every completion permanently, so each
// "+0" below is an over-count that could never be walked back.
//
// Real Hive (setUpHiveForTests); every write goes through the production
// writers. The Train surfaces: train_logged_so_far_behavioral_test.dart.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/coach_day_completion_behavioral_test.dart

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/completion_prompt_store.dart';
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
import 'package:icanbefitter/features/ai_coach/widgets/workout_log_confirm_card.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';
import 'package:icanbefitter/features/train/services/workout_completion_bookkeeping.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/workout_draft_seed.dart';

Directory? _dir;
final _calls = <CompletionBookkeepingCall>[];
final _events = <String>[];

DateTime get _now => DateTime.now();
String get _todayStr => istDateStr(_now);
DateTime get _yesterday => _now.subtract(const Duration(days: 1));
DateTime get _tomorrow => _now.add(const Duration(days: 1));

Future<void> _openFresh(WidgetTester tester) async {
  _dir ??= await tester.runAsync(setUpHiveForTests);
  await tester.runAsync(() async {
    if (HiveUserSession.currentOwnerFullId != kTestUserId) {
      await HiveUserSession.openForUser(kTestUserId);
    }
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox
        .put('progress', {'total_workouts_done': 0});
  });
}

int _total() =>
    ((HiveService.instance.userBox.get('progress') as Map?)?['total_workouts_done']
            as num?)
        ?.toInt() ??
    -1;

Future<void> _seedDay(
  DateTime day,
  List<String> exercises, {
  String type = 'workout',
  String status = 'planned',
  String workoutName = 'Push Day',
}) =>
    HiveService.instance.workoutBox.put(WorkoutWriteService.scheduleKey(day), {
      'date': istDateStr(day),
      'workout_name': workoutName,
      'status': status,
      'type': type,
      'exercises': [
        for (final e in exercises) {'exercise_name': e}
      ],
    });

Map? _row(DateTime day) =>
    HiveService.instance.workoutBox.get(WorkoutWriteService.scheduleKey(day))
        as Map?;

Map? _prompt(String dateStr) =>
    HiveService.instance.coachBox.get(CompletionPromptStore.keyFor(dateStr))
        as Map?;

bool _hasWlog(DateTime day) =>
    HiveService.instance.workoutBox.get(WorkoutWriteService.wlogKey(day))
        is Map;

Future<void> _log(DateTime day, String name) async {
  final r = await WorkoutWriteService.instance.logExercise(
    date: day,
    exerciseName: name,
    sets: [
      ExerciseSet(
          weightKg: 60,
          reps: 8,
          loggedAtMs: DateTime.now().millisecondsSinceEpoch),
    ],
    source: WriteSource.aiCoach,
  );
  expect(r.success, isTrue, reason: r.errorMessage);
}

/// The typed path exactly as `_executeLogSet` runs it: the log, then the
/// derived-completion decision for the payload's date.
Future<void> _typed(WidgetTester tester, DateTime day, String name) =>
    tester.runAsync(() async {
      final d = utcDateFromIstDateStr(istDateStr(day))!;
      await _log(d, name);
      await ToolDispatcher.instance
          .maybeCompleteScheduledDayForTest(d, istDateStr(day));
    });

/// Today's row completed EARLY: `completed_at` is yesterday. The display read
/// (`getScheduleForDate`) demotes such a row to `planned`; the RAW row the
/// rule must be fed reads `completed`.
Future<void> _seedCompletedEarlyToday(List<String> exercises) async {
  await _seedDay(_now, exercises);
  final k = WorkoutWriteService.scheduleKey(_now);
  final r = Map<String, dynamic>.from(
      HiveService.instance.workoutBox.get(k) as Map)
    ..['status'] = 'completed'
    ..['completed_via'] = 'app'
    ..['completed_at'] = _yesterday.toUtc().toIso8601String();
  await HiveService.instance.workoutBox.put(k, r);
  await HiveService.instance.workoutBox.put(WorkoutWriteService.wlogKey(_now), {
    'type': 'workout_log',
    'date': _todayStr,
    'workout_name': 'Push Day',
  });
}

Future<CoachTapResult> _tapOn(WidgetTester tester, String date,
        {CompletionDoor door = CompletionDoor.trainTap}) async =>
    (await tester.runAsync(() =>
        CoachDayCompletion.instance.completeOnTap(date: date, door: door)))!;

// ── The chat card ─────────────────────────────────────────────────────────

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

DraftExercise _bad(String name) => DraftExercise(
    name: name,
    loggingType: 'weight_reps',
    sets: [DraftSet(weightKg: -5, reps: 8)]);

WorkoutDraft _draft(List<DraftExercise> ex, String id) =>
    WorkoutDraft(id: id, exercises: ex, date: DateTime.now());

Future<_Slot> _pumpSlot(WidgetTester tester, WorkoutDraft draft) async {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    authStateProvider.overrideWith((ref) => const Stream.empty()),
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

/// CONFIRM on a card holding [ex]: the REAL `submitWorkoutDraft`. Returns the
/// outcome and the container (the card state and the chat thread live there).
Future<(DraftSubmitOutcome, _Slot)> _card(
    WidgetTester tester, List<DraftExercise> ex,
    {String id = 'wdraft_a'}) async {
  final s = await _pumpSlot(tester, _draft(ex, id));
  final out = await tester.runAsync(() => submitWorkoutDraft(_draft(ex, id), s.ref));
  await tester.pump();
  return (out!, s);
}

Future<void> _unpump(WidgetTester tester) async {
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
    DraftSubmitDebug.clock = DateTime.now;
  });

  tearDown(() {
    WorkoutCompletionBookkeeping.debugReset();
    ErrorTelemetry.debugOnLogEventForTests = null;
    WorkoutDraftNotifier.savedHoldFor = WorkoutDraftNotifier.defaultSavedHoldFor;
    DraftSubmitDebug.clock = DateTime.now;
  });

  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  // ── 1. The rule, pure ──────────────────────────────────────────────────
  group('decideCoachDay (pure)', () {
    const today = '2026-06-10';
    CoachDayDecision decide(Map? row,
            {int logged = 0,
            bool wlog = false,
            String date = today}) =>
        decideCoachDay(
            rawRow: row,
            loggedCount: logged,
            hasWlog: wlog,
            dateStr: date,
            istToday: today);
    Map planned(List<String> ex,
            {String type = 'workout', String? status = 'planned'}) =>
        {
          'type': type,
          'status': ?status,
          'exercises': [
            for (final e in ex) {'exercise_name': e}
          ],
        };

    test('a date after IST today is future, even fully logged', () {
      expect(decide(planned(['A']), logged: 1, date: '2026-06-11'),
          CoachDayDecision.future);
      expect(decide(null, date: '2026-06-11'), CoachDayDecision.future);
    });
    test('no row is noPlan', () {
      expect(decide(null), CoachDayDecision.noPlan);
    });
    test('completed with a wlog_ is alreadyDone; without one, repairDone', () {
      expect(decide(planned(['A'], status: 'completed'), wlog: true),
          CoachDayDecision.alreadyDone);
      expect(decide(planned(['A'], status: 'completed')),
          CoachDayDecision.repairDone);
      // A completed REST-type row with no wlog_: repairDone (completed first,
      // as the backstop always checked).
      expect(decide(planned([], type: 'rest', status: 'completed')),
          CoachDayDecision.repairDone);
    });
    test('moved and dropped are terminal (only on the RAW row)', () {
      expect(decide(planned(['A'], status: 'moved'), logged: 1),
          CoachDayDecision.terminal);
      expect(decide(planned(['A'], status: 'dropped'), logged: 1),
          CoachDayDecision.terminal);
    });
    test('type rest is rest, even with logs', () {
      expect(decide(planned(['A'], type: 'rest'), logged: 1),
          CoachDayDecision.rest);
    });
    test('every planned exercise logged is completeNow; fewer is askToComplete',
        () {
      expect(decide(planned(['A', 'B']), logged: 2),
          CoachDayDecision.completeNow);
      expect(decide(planned(['A', 'B']), logged: 1),
          CoachDayDecision.askToComplete);
    });
    test('an empty non-rest plan never completes on its own (finding-4)', () {
      expect(decide(planned([]), logged: 0), CoachDayDecision.askToComplete);
    });
    test('paused / skipped / travel / missing status follow the counts', () {
      for (final st in ['paused', 'skipped', 'travel', null]) {
        expect(decide(planned(['A'], status: st), logged: 1),
            CoachDayDecision.completeNow,
            reason: 'status $st');
        expect(decide(planned(['A', 'B'], status: st), logged: 1),
            CoachDayDecision.askToComplete,
            reason: 'status $st');
      }
    });
    test('a non-done row of another non-workout type is NOT rest here '
        '(pinned divergence: Train\'s isRest is wider, and its button also '
        'requires !isRest)', () {
      expect(decide(planned(['A'], type: 'none'), logged: 1),
          CoachDayDecision.completeNow);
    });
  });

  // ── 2. The typed backstop ─────────────────────────────────────────────
  group('the typed all-logged backstop', () {
    testWidgets('a full-plan log_set dated TOMORROW never completes: +0',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_tomorrow, ['Bench Press']));
      await _typed(tester, _tomorrow, 'Bench Press');
      expect(_row(_tomorrow)!['status'], 'planned');
      expect(_hasWlog(utcDateFromIstDateStr(istDateStr(_tomorrow))!), isFalse);
      expect(_total(), 0);
      expect(_calls, isEmpty);
      expect(_prompt(istDateStr(_tomorrow)), isNull);
    });

    testWidgets('a partial log_set dated YESTERDAY writes no prompt and leaves '
        'the day unmarked (decision F)', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedDay(_yesterday, ['Bench Press', 'Barbell Row']));
      await _typed(tester, _yesterday, 'Bench Press');
      expect(_row(_yesterday)!['status'], 'planned');
      expect(_prompt(istDateStr(_yesterday)), isNull);
      expect(_total(), 0);
    });

    testWidgets('a FULL past day still completes when every planned exercise '
        'is logged (decision 2)', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_yesterday, ['Bench Press']));
      await _typed(tester, _yesterday, 'Bench Press');
      expect(_row(_yesterday)!['status'], 'completed');
      expect(_total(), 1);
    });

    testWidgets('a swapped exercise counts under its swapped_from name',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => HiveService.instance.workoutBox
              .put(WorkoutWriteService.scheduleKey(_now), {
            'date': _todayStr,
            'workout_name': 'Push Day',
            'status': 'planned',
            'type': 'workout',
            'exercises': [
              {'exercise_name': 'Dumbbell Press', 'swapped_from': 'Bench Press'},
            ],
          }));
      await _typed(tester, _now, 'Bench Press');
      expect(_row(_now)!['status'], 'completed');
      expect(_total(), 1);
    });

    testWidgets('an account change before the decision: nothing is read or '
        'written for the new account', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press']));
      await tester.runAsync(() async {
        await _log(_now, 'Bench Press');
        await ToolDispatcher.instance.maybeCompleteScheduledDayForTest(
            _now, _todayStr,
            expectedOwner: 'someone-else', ownerGiven: true);
      });
      expect(_events, contains('derived_completion_owner_changed'));
      expect(_row(_now)!['status'], 'planned');
      expect(_total(), 0);
    });
  });

  // ── A row completed early (the RAW read, not the display read) ────────
  // ── B-pass 2026-11-10 ────────────────────────────────────────────────
  group('B-pass fixes', () {
    testWidgets('the backstop: a FAILED mark leaves the day\'s tile open',
        (tester) async {
      await _openFresh(tester);
      // An empty plan-day name makes markCompleted refuse (non-empty rule).
      await tester.runAsync(() =>
          _seedDay(_now, ['Bench Press', 'Barbell Row'], workoutName: ' '));
      await _typed(tester, _now, 'Bench Press');
      expect(_prompt(_todayStr)!['resolved_at'], isNull, reason: 'partial');
      await _typed(tester, _now, 'Barbell Row');
      expect(_row(_now)!['status'], 'planned', reason: 'the mark failed');
      expect(_prompt(_todayStr)!['resolved_at'], isNull,
          reason: 'the tile is still the way to finish the day');
      expect(_total(), 0);
    });

    testWidgets('the backstop: a payload date that is not plain yyyy-MM-dd '
        'names the day by the parsed date, so today\'s partial still gets its '
        'tile', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      final d = utcDateFromIstDateStr(_todayStr)!;
      // An ISO date-time sorts AFTER today's yyyy-MM-dd on every day, so the
      // raw string read as a future day (an unpadded one only differs on
      // single-digit months or days).
      final payload = '${_todayStr}T00:00:00';
      await tester.runAsync(() async {
        await _log(d, 'Bench Press');
        await ToolDispatcher.instance
            .maybeCompleteScheduledDayForTest(d, payload);
      });
      expect(_prompt(_todayStr), isNotNull);
      expect(_prompt(_todayStr)!['logged_count'], 1);
    });

    testWidgets('the chat card: a throw after the mark still gives the card '
        'its completed state, never an escaped error', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press']));
      WorkoutCompletionBookkeeping.debugOnCall =
          (_) => throw StateError('bookkeeping fault');
      final (out, _) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.completed);
      expect(_row(_now)!['status'], 'completed');
    });

    testWidgets('markCompleted: a 0 s mark after a timed one keeps the '
        'stored duration; a real duration still replaces it', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press']));
      final d = utcDateFromIstDateStr(_todayStr)!;
      Future<void> mark(int sec) => tester.runAsync(() async {
            final r = await WorkoutWriteService.instance.markCompleted(
                date: d, workoutName: 'Push Day', durationSec: sec);
            expect(r.success, isTrue);
          });
      int dur() => ((HiveService.instance.workoutBox
              .get(WorkoutWriteService.wlogKey(d)) as Map)['duration_seconds']
          as num)
          .toInt();
      await mark(1500);
      await mark(0);
      expect(dur(), 1500);
      await mark(2400);
      expect(dur(), 2400);
    });
  });

  group('a day completed EARLY (completed_at before its date)', () {
    testWidgets('the backstop: a partial log_set writes no tile, +0',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedCompletedEarlyToday(['Bench Press', 'Barbell Row']));
      await _typed(tester, _now, 'Bench Press');
      expect(_prompt(_todayStr), isNull,
          reason: 'the RAW row is completed (the display read says planned)');
      expect(_row(_now)!['status'], 'completed');
      expect(_total(), 0);
      expect(_calls, isEmpty);
    });

    testWidgets('the chat card: a partial card reads the day as done, no tile',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedCompletedEarlyToday(['Bench Press', 'Barbell Row']));
      final (out, _) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.completed);
      expect(_prompt(_todayStr), isNull);
      expect(_total(), 0);
      expect(_calls, isEmpty);
      await _unpump(tester);
    });

    testWidgets('the tap: alreadyDone, nothing re-stamped', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() async {
        await _seedCompletedEarlyToday(['Bench Press', 'Barbell Row']);
        await _log(_now, 'Bench Press');
      });
      final res = await _tapOn(tester, _todayStr);
      expect(res, CoachTapResult.alreadyDone);
      expect(_row(_now)!['completed_via'], 'app');
      expect(_calls, isEmpty);
    });
  });

  // ── 3. The chat card ──────────────────────────────────────────────────
  group('the chat card', () {
    testWidgets('a partial planned day: no mark, the tile (in the chat thread '
        'at once), +0, the awaiting line, the long hold', (tester) async {
      await _openFresh(tester);
      Duration? hold;
      var asked = false;
      WorkoutDraftNotifier.savedHoldFor = (hasNote) {
        asked = hasNote;
        hold = const Duration(hours: 1);
        return hold!;
      };
      await tester.runAsync(
          () => _seedDay(_now, ['Bench Press', 'Barbell Row', 'Dip']));
      final draft = _draft([_lift('Bench Press')], 'wdraft_a');
      final s = await _pumpSlot(tester, draft);
      // The open chat screen has already built the thread: the tile must
      // reach it through the card's own refresh, not a first build.
      expect(
          s.c.read(chatHistoryProvider).where((m) => m.kind == 'completion_prompt'),
          isEmpty);
      final out = (await tester.runAsync(() => submitWorkoutDraft(draft, s.ref)))!;
      await tester.pump();
      expect(out.dayState, DraftDayState.awaitingComplete);
      expect(out.plannedCount, 3);
      expect(out.loggedCount, 1);
      expect(_row(_now)!['status'], 'planned');
      expect(_hasWlog(_now), isFalse);
      expect(_total(), 0);
      expect(_calls, isEmpty);
      final p = _prompt(_todayStr)!;
      expect(p['planned_count'], 3);
      expect(p['logged_count'], 1);
      expect(p['resolved_at'], isNull);
      expect(
          s.c.read(chatHistoryProvider).where((m) => m.kind == 'completion_prompt'),
          hasLength(1),
          reason: 'the tile shows at once, not on the next message');
      expect(s.c.read(workoutDraftProvider)!.status,
          DraftCardStatus.savedAwaitingComplete);
      expect(
          find.text("Saved 1 of 3. Log the rest, or tap Complete workout when "
              "you're done."),
          findsOneWidget);
      expect(asked, isTrue, reason: 'the line holds 4 s, not 1.5 s');
      await _unpump(tester);
    });

    testWidgets('every planned exercise: marked with the PLAN name, +1, the '
        'tile resolved', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row'],
          workoutName: 'Push Day'));
      await tester.runAsync(() => CompletionPromptStore.instance
          .write(dateStr: _todayStr, plannedCount: 2, loggedCount: 1));
      final (out, s) =
          await _card(tester, [_lift('Bench Press'), _lift('Barbell Row')]);
      expect(out.dayState, DraftDayState.completed);
      expect(_row(_now)!['status'], 'completed');
      expect(_row(_now)!['workout_name'], 'Push Day');
      expect(
          (HiveService.instance.workoutBox
              .get(WorkoutWriteService.wlogKey(_now)) as Map)['workout_name'],
          'Push Day',
          reason: 'the plan day keeps its name, not "Chat Workout"');
      expect(_total(), 1);
      expect(_prompt(_todayStr)!['resolved_at'], isNotNull);
      expect(s.c.read(workoutDraftProvider)!.status, DraftCardStatus.saved);
      await _unpump(tester);
    });

    testWidgets('names that match no planned exercise: 0 of N, the count-free '
        'line, no mark', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Barbell Bench Press']));
      final (out, _) = await _card(tester, [_lift('Bench')]);
      expect(out.dayState, DraftDayState.awaitingComplete);
      expect(out.loggedCount, 0);
      expect(find.text(WardroomCopy.coachWorkoutAwaitingNoCount), findsOneWidget);
      expect(_total(), 0);
      await _unpump(tester);
    });

    for (final c in const [
      ('a rest day', 'rest', 'planned'),
      ('a moved day', 'workout', 'moved'),
      ('a dropped day', 'workout', 'dropped'),
    ]) {
      testWidgets('${c.$1}: saved, never marked, no tile, +0, the not-counted '
          'line', (tester) async {
        await _openFresh(tester);
        await tester.runAsync(
            () => _seedDay(_now, ['Bench Press'], type: c.$2, status: c.$3));
        final (out, s) = await _card(tester, [_lift('Bench Press')]);
        expect(out.dayState, DraftDayState.notCounted);
        expect(_row(_now)!['status'], c.$3, reason: 'the row is untouched');
        expect(_hasWlog(_now), isFalse);
        expect(_prompt(_todayStr), isNull);
        expect(_total(), 0);
        expect(s.c.read(workoutDraftProvider)!.status,
            DraftCardStatus.savedNotCounted);
        expect(find.text(WardroomCopy.coachWorkoutNotCounted), findsOneWidget);
        await _unpump(tester);
      });
    }

    testWidgets('no plan row: saved, no row synthesised, +0', (tester) async {
      await _openFresh(tester);
      final (out, _) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.notCounted);
      expect(_row(_now), isNull, reason: 'no "logged" row is synthesised');
      expect(_hasWlog(_now), isFalse);
      expect(_total(), 0);
      await _unpump(tester);
    });

    testWidgets('a completed day with no wlog_ is re-marked (F5): the wlog_ '
        'appears, the count heals to 1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(
          () => _seedDay(_now, ['Squat'], status: 'completed'));
      final (out, _) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.completed);
      expect(_hasWlog(_now), isTrue);
      expect(_total(), 1);
      await _unpump(tester);
    });

    testWidgets('a partial card, then the rest typed: the backstop completes, '
        '+1 total', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      await _card(tester, [_lift('Bench Press')]);
      await _unpump(tester);
      expect(_total(), 0);
      await _typed(tester, _now, 'Barbell Row');
      expect(_row(_now)!['status'], 'completed');
      expect(_total(), 1);
      expect(_prompt(_todayStr)!['resolved_at'], isNotNull);
    });

    testWidgets('a partial card, then the tile tap: +1', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      await _card(tester, [_lift('Bench Press')]);
      await _unpump(tester);
      final r = await _tapOn(tester, _todayStr, door: CompletionDoor.coachTap);
      expect(r, CoachTapResult.completed);
      expect(_row(_now)!['completed_via'], 'tap');
      expect(_total(), 1);
    });

    testWidgets('one exercise fails: the decision runs on what saved; no '
        'not-marked line; the tile is up', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'X']));
      final (out, s) = await _card(tester, [_lift('Bench Press'), _bad('X')]);
      expect(out.failedIndices, [1]);
      expect(out.dayState, DraftDayState.awaitingComplete);
      final d = s.c.read(workoutDraftProvider)!;
      expect(d.status, DraftCardStatus.partial);
      expect(d.dayNotMarked, isFalse);
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsNothing);
      expect(_prompt(_todayStr), isNotNull);
      expect(_total(), 0);
      await _unpump(tester);
    });

    testWidgets('a saved awaiting card can be neither re-submitted nor edited',
        (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      final (_, s) = await _card(tester, [_lift('Bench Press')]);
      final n = s.c.read(workoutDraftProvider.notifier);
      final before = s.c.read(workoutDraftProvider)!;
      expect(isSavedDraftStatus(before.status), isTrue);
      expect(n.beginSubmit(before.id, DateTime.now()), isNull);
      n.updateSet(before.id, 0, 0, DraftSet(weightKg: 1, reps: 1));
      expect(identical(s.c.read(workoutDraftProvider), before), isTrue);
      await _unpump(tester);
    });

    testWidgets('a card whose first attempt was YESTERDAY (a retry after IST '
        'midnight): a partial is pastNotMarked, no tile, +0', (tester) async {
      await _openFresh(tester);
      final y = _yesterday;
      DraftSubmitDebug.clock = () => y;
      await tester.runAsync(() => _seedDay(y, ['Bench Press', 'Barbell Row']));
      final (out, s) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.pastNotMarked);
      expect(_prompt(istDateStr(y)), isNull);
      expect(_row(y)!['status'], 'planned');
      expect(_total(), 0);
      expect(s.c.read(workoutDraftProvider)!.status,
          DraftCardStatus.savedDayNotMarked);
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsOneWidget);
      await _unpump(tester);
    });

    testWidgets('a card whose first attempt was yesterday completing every '
        'planned exercise: completed on THAT day, +1', (tester) async {
      await _openFresh(tester);
      final y = _yesterday;
      DraftSubmitDebug.clock = () => y;
      await tester.runAsync(() => _seedDay(y, ['Bench Press']));
      final (out, _) = await _card(tester, [_lift('Bench Press')]);
      expect(out.dayState, DraftDayState.completed);
      expect(_row(y)!['status'], 'completed');
      expect(_total(), 1);
      await _unpump(tester);
    });
  });

  // ── 4. The tap path (tile + Train) ────────────────────────────────────
  group('completeOnTap', () {
    testWidgets('Train tap on a partial day: completed, +1, train_tap, door '
        'trainTap, no progress minted', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      await tester.runAsync(() => _log(_now, 'Bench Press'));
      final r = await _tapOn(tester, _todayStr);
      expect(r, CoachTapResult.completed);
      expect(_row(_now)!['status'], 'completed');
      expect(_row(_now)!['completed_via'], 'train_tap');
      expect(_total(), 1);
      expect([for (final c in _calls) c.door], [CompletionDoor.trainTap]);
    });

    testWidgets('no progress row: the tap writes no progress (only Active '
        'Workout mints)', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => HiveService.instance.userBox.delete('progress'));
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      await tester.runAsync(() => _log(_now, 'Bench Press'));
      expect(await _tapOn(tester, _todayStr), CoachTapResult.completed);
      expect(HiveService.instance.userBox.get('progress'), isNull);
    });

    for (final c in const [
      ('a moved RAW row', 'workout', 'moved', CoachTapResult.refusedNotCountable),
      ('a dropped row', 'workout', 'dropped',
          CoachTapResult.refusedNotCountable),
      ('a rest day', 'rest', 'planned', CoachTapResult.refusedNotCountable),
    ]) {
      testWidgets('${c.$1} is refused (${c.$4.name}): the row is untouched, +0',
          (tester) async {
        await _openFresh(tester);
        await tester.runAsync(
            () => _seedDay(_now, ['Bench Press'], type: c.$2, status: c.$3));
        await tester.runAsync(() => _log(_now, 'Bench Press'));
        expect(await _tapOn(tester, _todayStr), c.$4);
        expect(_row(_now)!['status'], c.$3);
        expect(_total(), 0);
      });
    }

    testWidgets('no row is refused: none is synthesised', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _log(_now, 'Bench Press'));
      expect(await _tapOn(tester, _todayStr), CoachTapResult.refusedNotCountable);
      expect(_row(_now), isNull);
      expect(_total(), 0);
    });

    testWidgets('no exercise log at all is refused', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press']));
      expect(await _tapOn(tester, _todayStr), CoachTapResult.refusedNoLogs);
      expect(_row(_now)!['status'], 'planned');
      expect(_total(), 0);
    });

    testWidgets('yesterday is refused (decision F) and its tile resolved; '
        'tomorrow is refused', (tester) async {
      await _openFresh(tester);
      final y = istDateStr(_yesterday);
      await tester.runAsync(() async {
        await _seedDay(_yesterday, ['Bench Press', 'Barbell Row']);
        await _log(utcDateFromIstDateStr(y)!, 'Bench Press');
        await HiveService.instance.coachBox.put(CompletionPromptStore.keyFor(y), {
          'kind': 'completion_prompt',
          'date': y,
          'planned_count': 2,
          'logged_count': 1,
          'created_at': DateTime.now().toIso8601String(),
          'resolved_at': null,
        });
      });
      expect(await _tapOn(tester, y, door: CompletionDoor.coachTap),
          CoachTapResult.refusedNotToday);
      expect(_row(_yesterday)!['status'], 'planned');
      expect(_prompt(y)!['resolved_at'], isNotNull);
      expect(await _tapOn(tester, istDateStr(_tomorrow)),
          CoachTapResult.refusedNotToday);
      expect(_total(), 0);
    });

    testWidgets('an already-done day: success, no write', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press']));
      await _typed(tester, _now, 'Bench Press');
      final wlog = Map.of(HiveService.instance.workoutBox
          .get(WorkoutWriteService.wlogKey(_now)) as Map);
      _calls.clear();
      expect(await _tapOn(tester, _todayStr), CoachTapResult.alreadyDone);
      expect(Map.of(HiveService.instance.workoutBox
          .get(WorkoutWriteService.wlogKey(_now)) as Map), wlog);
      expect(_calls, isEmpty);
      expect(_total(), 1);
    });

    testWidgets('canCompleteOnTap agrees with the tap', (tester) async {
      await _openFresh(tester);
      await tester.runAsync(() => _seedDay(_now, ['Bench Press', 'Barbell Row']));
      expect(CoachDayCompletion.instance.canCompleteOnTap(_todayStr), isFalse,
          reason: 'no log yet');
      await tester.runAsync(() => _log(_now, 'Bench Press'));
      expect(CoachDayCompletion.instance.canCompleteOnTap(_todayStr), isTrue);
      expect(CoachDayCompletion.instance.canCompleteOnTap(istDateStr(_yesterday)),
          isFalse);
      expect(await _tapOn(tester, _todayStr), CoachTapResult.completed);
      expect(CoachDayCompletion.instance.canCompleteOnTap(_todayStr), isFalse,
          reason: 'done');
    });

    test('each result maps to its approved line', () {
      expect(CoachTapResult.completed.message, WardroomCopy.coachTapCompleted);
      expect(CoachTapResult.alreadyDone.message, WardroomCopy.coachTapCompleted);
      expect(CoachTapResult.refusedNoLogs.message, WardroomCopy.coachTapNoLogs);
      expect(CoachTapResult.refusedNotToday.message,
          WardroomCopy.coachWorkoutDayNotMarked);
      expect(CoachTapResult.refusedNotCountable.message,
          WardroomCopy.coachWorkoutDayNotMarked);
      expect(CoachTapResult.failed.message, WardroomCopy.coachTapFailed);
      expect(CoachTapResult.completed.isSuccess, isTrue);
      expect(CoachTapResult.alreadyDone.isSuccess, isTrue);
      expect(CoachTapResult.refusedNoLogs.isSuccess, isFalse);
    });
  });

  // ── 5. The prompt row ─────────────────────────────────────────────────
  group('the prompt row', () {
    testWidgets('a past unresolved prompt is not rendered, and the chat build '
        'writes nothing', (tester) async {
      await _openFresh(tester);
      final y = istDateStr(_yesterday);
      final row = {
        'kind': 'completion_prompt',
        'date': y,
        'planned_count': 2,
        'logged_count': 1,
        'created_at': DateTime.now().toIso8601String(),
        'resolved_at': null,
      };
      await tester.runAsync(() => HiveService.instance.coachBox
          .put(CompletionPromptStore.keyFor(y), row));
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(chatHistoryProvider).where((m) => m.kind == 'completion_prompt'),
          isEmpty);
      expect(Map.of(_prompt(y)!), row, reason: 'build is a pure read');
    });

    testWidgets('writing today\'s prompt resolves an older open one',
        (tester) async {
      await _openFresh(tester);
      final y = istDateStr(_yesterday);
      await tester.runAsync(() async {
        await CompletionPromptStore.instance
            .write(dateStr: y, plannedCount: 2, loggedCount: 1);
        await CompletionPromptStore.instance
            .write(dateStr: _todayStr, plannedCount: 3, loggedCount: 1);
      });
      expect(_prompt(y)!['resolved_at'], isNotNull);
      expect(_prompt(_todayStr)!['resolved_at'], isNull);
    });

    testWidgets('the tile body is rank-neutral', (tester) async {
      expect(WardroomCopy.coachCompletionPromptBody, isNot(contains('Recruit')));
      expect(WardroomCopy.coachCompletionPromptBody,
          'Log more exercises, or complete the workout?');
    });
  });

  // `cardStateFor` covers the two new saved states (the card's `saved` set).
  test('cardStateFor maps the new statuses', () {
    WorkoutDraft d(DraftCardStatus s) =>
        WorkoutDraft(id: 'x', exercises: const [], date: DateTime(2026), status: s);
    expect(cardStateFor(d(DraftCardStatus.savedAwaitingComplete)),
        WorkoutCardState.savedAwaitingComplete);
    expect(cardStateFor(d(DraftCardStatus.savedNotCounted)),
        WorkoutCardState.savedNotCounted);
    expect(savedStatusFor(DraftDayState.pastNotMarked),
        DraftCardStatus.savedDayNotMarked);
    expect(savedStatusFor(DraftDayState.markFailed),
        DraftCardStatus.savedDayNotMarked);
  });
}
