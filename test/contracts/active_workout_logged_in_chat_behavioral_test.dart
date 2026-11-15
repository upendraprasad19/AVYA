// Behavioral contract: coach workout parity 1c (OI-491). An exercise the coach
// already logged in chat opens DONE in Active Workout (LOGGED IN CHAT); a
// re-open adds sets and FINISH saves ONLY the new ones, appended to the coach's
// row. Plan: docs/plans/coach-workout-parity-1c.md (C1-C7, tests T1-T10).
//
// Writers: WorkoutWriteService.logExercise (coach and app sources, the sticky
//          `coach_logged` marker), moveExerciseLogs, ExlogKeyMigrator,
//          ActiveWorkoutNotifier.startWorkout (the chat snapshot),
//          reopenChatLogged / keepChatLogged, swapExercise / addExercise.
// Readers: loggedNameForPlannedExercise, chatLoggedEntryFor, isExerciseDone,
//          allExercisesLogged, workingSetCounts, finishGuard,
//          finishBlockedLine, completeWorkout (what is written).
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/active_workout_logged_in_chat_behavioral_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart'
    show finishBlockedLine;
import 'package:icanbefitter/features/train/services/chat_logged_exercises.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';
import 'package:icanbefitter/features/train/services/exercise_move_logic.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

import '../helpers/hive_test_setup.dart';

class _SeededNotifier extends ActiveWorkoutNotifier {
  _SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

ExerciseData ex(String name,
        {String sets = '3', String type = 'weight_reps', int? group}) =>
    ExerciseData(
      name: name,
      sets: sets,
      reps: '8',
      weight: '0kg',
      rest: '90s',
      loggingType: type,
      supersetGroup: group,
    );

ChatLoggedExercise chat(String name,
        {int coach = 1, int planned = 3, List<ExerciseSet>? sets}) =>
    ChatLoggedExercise(
      loggedName: name,
      loggingType: 'weight_reps',
      sets: sets ??
          [for (var i = 0; i < coach; i++) const ExerciseSet(weightKg: 60, reps: 8)],
      coachCount: coach,
      plannedSets: planned,
    );

/// A frozen copy of `loggedPlannedExerciseCount` as it was at 71f07c62 (the
/// differential oracle for the extraction, C1).
int frozenLoggedPlannedExerciseCount(DateTime date, Map row) {
  final box = HiveService.instance.workoutBox;
  bool hasLog(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    return box.get(WorkoutWriteService.exlogKey(date, name)) != null;
  }

  return plannedExercisesOf(row)
      .where(
        (ex) =>
            hasLog(ex['exercise_name'] as String?) ||
            hasLog(ex['swapped_from'] as String?),
      )
      .length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final events = <String>[];

  setUp(() async {
    dir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {
      if (op == 'active_workout_chat_snapshot_failed') events.add('$message');
    };
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ActiveWorkoutNotifier.debugBeforeMarkGate = null;
    SyncService.pausedForSimulation = false;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  DateTime day(String ist) => utcDateFromIstDateStr(ist)!;
  String today() => istTodayStr();
  String pastDay() =>
      istDateStr(DateTime.now().subtract(const Duration(days: 3)));

  // The writer's 60 s dedup reads the REAL clock: fixture sets are stamped
  // 120 s in the past so a later real set with the same values is kept.
  ExerciseSet set_(double kg, int reps) => ExerciseSet(
      weightKg: kg,
      reps: reps,
      loggedAtMs: DateTime.now().millisecondsSinceEpoch - 120000);

  Future<void> logAs(WriteSource source, String name, List<ExerciseSet> sets,
      {String? ist}) async {
    final r = await WorkoutWriteService.instance.logExercise(
      date: day(ist ?? today()),
      exerciseName: name,
      sets: sets,
      source: source,
    );
    expect(r.success, isTrue, reason: r.errorMessage);
  }

  Future<void> coachLog(String name, List<ExerciseSet> sets, {String? ist}) =>
      logAs(WriteSource.aiCoach, name, sets, ist: ist);

  Map<String, dynamic> storedRow(String name, {String? ist}) =>
      Map<String, dynamic>.from(HiveService.instance.workoutBox
          .get(WorkoutWriteService.exlogKey(day(ist ?? today()), name)) as Map);

  Future<void> putPlanRow(String ist, List<Map<String, dynamic>> exercises) =>
      HiveService.instance.workoutBox.put('schedule_$ist', {
        'date': ist,
        'status': 'planned',
        'workout_name': 'Push',
        'exercises': exercises,
      });

  ProviderContainer realContainer() {
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('u'),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ProviderContainer seeded(ActiveWorkoutData seed) {
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('u'),
      activeWorkoutProvider.overrideWith(() => _SeededNotifier(seed)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ProviderContainer started(List<ExerciseData> exercises, {DateTime? date}) {
    final c = realContainer();
    c.read(activeWorkoutProvider.notifier).startWorkout(WorkoutDayData(
          dayNumber: 1,
          name: 'Push',
          date: date ?? DateTime.now(),
          exercises: exercises,
        ));
    return c;
  }

  // ── T1: the lookup helper ─────────────────────────────────────────────
  group('T1 loggedNameForPlannedExercise', () {
    test('current-name hit; swapped_from hit; none', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      await coachLog('Dips', [set_(0, 10)]);
      final d = day(today());
      expect(loggedNameForPlannedExercise(d, {'exercise_name': 'Bench Press'}),
          'Bench Press');
      expect(
          loggedNameForPlannedExercise(
              d, {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'}),
          'Dips');
      expect(loggedNameForPlannedExercise(d, {'exercise_name': 'Squat'}),
          isNull);
    });

    test('lookup order: a current-name row failing accept falls to the '
        'swapped_from row', () async {
      await logAs(WriteSource.activeWorkout, 'Ring Dips', [set_(0, 9)]);
      await coachLog('Dips', [set_(0, 10)]);
      expect(
          loggedNameForPlannedExercise(day(today()),
              {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
              accept: isChatLoggedRow),
          'Dips');
    });

    test('case and whitespace go through exlogKey; another date is no hit; a '
        '1-set row of a 3-set plan is a hit', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      final d = day(today());
      expect(
          loggedNameForPlannedExercise(d, {'exercise_name': ' bench press '}),
          ' bench press ');
      expect(
          loggedNameForPlannedExercise(
              day(pastDay()), {'exercise_name': 'Bench Press'}),
          isNull);
      final e = chatLoggedEntryFor(d, {'exercise_name': 'Bench Press'},
          fallbackLoggingType: 'weight_reps', plannedSets: 3);
      expect(e, isNotNull);
      expect(e!.coachCount, 1);
    });

    test('loggedPlannedExerciseCount equals a frozen copy of the old body '
        '(differential), including a non-map value under a key', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      await logAs(WriteSource.activeWorkout, 'Squat', [set_(100, 5)]);
      await coachLog('Dips', [set_(0, 10)]);
      final d = day(today());
      // A non-Map value under an exlog key still counts as "has a log" in
      // the accept == null path (the old `!= null`, not `is Map`).
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Lunge'), 'legacy-scalar');
      final rows = <Map>[
        {
          'exercises': [
            {'exercise_name': 'Bench Press'},
            {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
            {'exercise_name': 'Squat'},
            {'exercise_name': 'Row'},
            {'exercise_name': 'Lunge'},
            {'exercise_name': ''},
            {'exercise_name': 'Curl', 'swapped_from': ' '},
          ],
        },
        {'exercises': <Map>[]},
        {
          'exercises': [
            {'exercise_name': 'Row', 'swapped_from': 'Bench Press'},
          ],
        },
      ];
      for (final r in rows) {
        expect(loggedPlannedExerciseCount(d, r),
            frozenLoggedPlannedExerciseCount(d, r));
      }
      expect(loggedPlannedExerciseCount(d, rows.first), 4);
    });

    test('a restored-shape row (type, no source, no marker) is not a chat row '
        'but IS counted by loggedPlannedExerciseCount', () async {
      final d = day(today());
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Bench Press'), {
        'exercise_name': 'Bench Press',
        'type': 'exercise_log',
        'date': today(),
        'set_number': 2,
        'weight_kg': 60.0,
      });
      expect(
          loggedNameForPlannedExercise(d, {'exercise_name': 'Bench Press'},
              accept: isChatLoggedRow),
          isNull);
      expect(
          loggedPlannedExerciseCount(d, {
            'exercises': [
              {'exercise_name': 'Bench Press'}
            ]
          }),
          1);
    });

    test('both rows chat-logged with different sets: the CURRENT name wins '
        'and its sets are the chips (B4-F1)', () async {
      await coachLog('Ring Dips', [set_(10, 6), set_(10, 6)]);
      await coachLog('Dips', [set_(0, 12)]);
      final e = chatLoggedEntryFor(day(today()),
          {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
          fallbackLoggingType: 'weight_reps', plannedSets: 3)!;
      expect(e.loggedName, 'Ring Dips');
      expect(e.coachCount, 2);
      expect(chatLoggedChips(e.sets).map((c) => c.weightKg), [10, 10]);
    });
  });

  // ── T2: the START snapshot ────────────────────────────────────────────
  group('T2 startWorkout snapshot', () {
    test('holds chat rows only; an app-written row opens plain', () async {
      await coachLog('Bench Press', [set_(60, 8), set_(60, 8)]);
      await logAs(WriteSource.activeWorkout, 'Squat', [set_(100, 5)]);
      final c = started([ex('Bench Press'), ex('Squat'), ex('Row')]);
      final s = c.read(activeWorkoutProvider);
      expect(s.loggedInChat.keys, ['bench press']);
      expect(s.loggedInChat['bench press']!.coachCount, 2);
      expect(s.loggedInChat['bench press']!.plannedSets, 3);
      expect(s.isExerciseDone(0), isTrue);
      expect(s.isExerciseDone(1), isFalse);
      expect(s.checkedSets, isEmpty);
      expect(s.setInputValues, isEmpty);
    });

    test('flag OFF gives {}; no rows gives {}', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      await HiveService.instance.configBox.put(LogExerciseFlags.key, false);
      expect(started([ex('Bench Press')]).read(activeWorkoutProvider)
          .loggedInChat, isEmpty);
      await HiveService.instance.configBox.delete(LogExerciseFlags.key);
      expect(started([ex('Row')]).read(activeWorkoutProvider).loggedInChat,
          isEmpty);
    });

    test('a past-dated day reads TODAY\'s rows and not the past plan row\'s '
        'swapped_from', () async {
      final past = pastDay();
      await putPlanRow(past, [
        {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
      ]);
      await coachLog('Dips', [set_(0, 10)]); // today, under the OLD name
      await coachLog('Bench Press', [set_(60, 8)]); // today
      final s = started([ex('Ring Dips'), ex('Bench Press')],
              date: day(past))
          .read(activeWorkoutProvider);
      expect(s.loggedInChat.keys, ['bench press']);
      expect(s.isExerciseDone(0), isFalse);
    });

    test('today\'s plan row maps a swapped_from chat log to the slot', () async {
      await putPlanRow(today(), [
        {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
      ]);
      await coachLog('Dips', [set_(0, 10)]);
      final s = started([ex('Ring Dips')]).read(activeWorkoutProvider);
      expect(s.loggedInChat['ring dips']!.loggedName, 'Dips');
    });

    test('day.date == null: empty swapped_from map, no throw, and the '
        'current-name row still maps', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      final c = realContainer();
      c.read(activeWorkoutProvider.notifier).startWorkout(
          WorkoutDayData(dayNumber: 1, name: 'Push', exercises: [ex('Bench Press')]));
      expect(c.read(activeWorkoutProvider).loggedInChat.keys, ['bench press']);
      expect(events, isEmpty);
    });

    test('a throwing rawScheduleRow gives {}, ONE outer event, and START '
        'still builds state', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      // A non-String key makes Map<String, dynamic>.from throw. The detraining
      // cut also walks schedule rows at START, before the snapshot: switch it
      // off so only the snapshot reads the broken row.
      await HiveService.instance.configBox
          .put('disable_session_detraining_cut', true);
      await HiveService.instance.workoutBox
          .put('schedule_${today()}', {1: 'bad key'});
      final s = started([ex('Bench Press')]).read(activeWorkoutProvider);
      expect(s.loggedInChat, isEmpty);
      expect(s.exercises.single.name, 'Bench Press');
      expect(s.workoutDay, isNotNull);
      expect(events.length, 1);
      expect(events.single, startsWith('outer:'));
    });

    test('per-row failure: the bad coach row FIRST is skipped, the good row '
        'still maps, ONE event rows=1', () async {
      final d = day(today());
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Bench Press'), {
        'exercise_name': 'Bench Press',
        'source': 'ai_coach',
        'sets': [
          {'weight_kg': 'bad', 'reps': 8}
        ],
      });
      await coachLog('Squat', [set_(100, 5)]);
      final s = started([ex('Bench Press'), ex('Squat')])
          .read(activeWorkoutProvider);
      expect(s.loggedInChat.keys, ['squat']);
      expect(s.isExerciseDone(0), isFalse);
      expect(events, ['rows=1']);
    });

    test('a duplicated stored name keeps one entry; a restored-shape row '
        'opens plain', () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      final d = day(today());
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Row'), {
        'exercise_name': 'Row',
        'type': 'exercise_log',
        'set_number': 3,
      });
      final s = started([ex('Bench Press'), ex('bench press'), ex('Row')])
          .read(activeWorkoutProvider);
      expect(s.exercises.length, 2);
      expect(s.loggedInChat.keys, ['bench press']);
      expect(s.isExerciseDone(1), isFalse);
    });

    test('a Red-day drop on a 3-set isolation exercise gives plannedSets 2',
        () async {
      await coachLog('Curl', [set_(10, 12)]);
      final c = realContainer();
      c.read(activeWorkoutProvider.notifier).startWorkout(
          WorkoutDayData(
            dayNumber: 1,
            name: 'Arms',
            date: DateTime.now(),
            exercises: [
              ExerciseData(
                  name: 'Curl', sets: '3', exerciseType: 'isolation'),
            ],
          ),
          readiness: ReadinessLevel.red);
      final s = c.read(activeWorkoutProvider);
      expect(s.exercises.single.sets, '2');
      expect(s.loggedInChat['curl']!.plannedSets, 2);
    });

    test('name normalisation: "Bench Press " finds the row keyed bench press',
        () async {
      await coachLog('bench press', [set_(60, 8)]);
      final s = started([ex('Bench Press ')]).read(activeWorkoutProvider);
      expect(s.isChatLogged(0), isTrue);
    });
  });

  // ── T3: the sticky marker and the second START ────────────────────────
  group('T3 marker and second START', () {
    test('chain coach, app, app, then START: X opens DONE with 3 chips',
        () async {
      await coachLog('Bench Press', [set_(60, 8), set_(60, 8)]);
      final c = started([ex('Bench Press'), ex('Squat')]);
      final n = c.read(activeWorkoutProvider.notifier);
      expect(n.reopenChatLogged(0, 'Bench Press'), isTrue);
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '1');
      n.logSets(0, {0});
      n.recordSetValues(0, 0, const SetInputValues(weight: 65, reps: 6));
      n.logSets(1, {0});
      n.recordSetValues(1, 0, const SetInputValues(weight: 100, reps: 5));
      await n.completeWorkout();
      final row = storedRow('Bench Press');
      expect((row['sets'] as List).length, 3);
      expect(row['coach_logged'], isTrue);
      expect(row['source'], 'active_workout');
      final again = started([ex('Bench Press'), ex('Squat')])
          .read(activeWorkoutProvider);
      expect(again.isChatLoggedDone(0), isTrue);
      expect(again.loggedInChat['bench press']!.coachCount, 3);
      expect(again.isChatLogged(1), isFalse);
    });

    test('(a) a MARKED row with an app source survives a plain re-log',
        () async {
      await coachLog('Bench Press', [set_(60, 8)]);
      await logAs(WriteSource.editSheet, 'Bench Press', [set_(70, 5)]);
      await logAs(WriteSource.activeWorkout, 'Bench Press', [set_(75, 4)]);
      final row = storedRow('Bench Press');
      expect(row['source'], 'active_workout');
      expect(row['coach_logged'], isTrue);
    });

    test('(b) a pre-ship row with source ai_coach and NO marker opens DONE, '
        'and a re-log sets the marker', () async {
      final d = day(today());
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Bench Press'), {
        'exercise_name': 'Bench Press',
        'source': 'ai_coach',
        'date': today(),
        'sets': [
          {'weight_kg': 60.0, 'reps': 8, 'logged_at_ms': 1}
        ],
        'set_number': 1,
      });
      expect(started([ex('Bench Press')]).read(activeWorkoutProvider)
          .isChatLoggedDone(0), isTrue);
      await logAs(WriteSource.activeWorkout, 'Bench Press', [set_(70, 5)]);
      expect(storedRow('Bench Press')['coach_logged'], isTrue);
    });

    test('(c) an ai_coach write onto an app-written row sets the marker on '
        'the STORED row right away', () async {
      await logAs(WriteSource.activeWorkout, 'Bench Press', [set_(60, 8)]);
      expect(storedRow('Bench Press').containsKey('coach_logged'), isFalse);
      await coachLog('Bench Press', [set_(70, 5)]);
      expect(storedRow('Bench Press')['coach_logged'], isTrue);
    });

    test('a row written only by Train / Active Workout has no marker and '
        'opens plain', () async {
      await logAs(WriteSource.activeWorkout, 'Bench Press', [set_(60, 8)]);
      expect(storedRow('Bench Press').containsKey('coach_logged'), isFalse);
      expect(started([ex('Bench Press')]).read(activeWorkoutProvider)
          .isChatLogged(0), isFalse);
    });
  });

  // ── T4: derived reads ─────────────────────────────────────────────────
  group('T4 derived reads', () {
    test('isExerciseDone: true, false after reopen, true after keep', () {
      final c = seeded(ActiveWorkoutData(
          exercises: [ex('X'), ex('Y')], loggedInChat: {'x': chat('X')}));
      final n = c.read(activeWorkoutProvider.notifier);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      expect(n.reopenChatLogged(0, 'X'), isTrue);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isFalse);
      expect(n.keepChatLogged(0, 'X'), isTrue);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '3');
    });

    test('allExercisesLogged; workingSetCounts chat-done counts coachCount on '
        'both sides; a fully chat day is N/N with no saveable set', () {
      final full = ActiveWorkoutData(
          exercises: [ex('X'), ex('Z')],
          loggedInChat: {'x': chat('X', coach: 2), 'z': chat('Z', coach: 3)});
      expect(allExercisesLogged(full), isTrue);
      expect(workingSetCounts(full), (saved: 5, total: 5));
      expect(workingProgress(workingSetCounts(full)), 1.0);
      expect(full.hasSaveableSet, isFalse);

      final mixed = ActiveWorkoutData(
          exercises: [ex('X'), ex('Y')], loggedInChat: {'x': chat('X', coach: 2)});
      expect(workingSetCounts(mixed), (saved: 2, total: 5));
    });

    test('workingSetCounts: a re-opened chat exercise adds its new rows to '
        'total and its saved rows to saved, coach on both sides', () {
      final s = ActiveWorkoutData(
        exercises: [ex('X', sets: '2')],
        loggedInChat: {'x': chat('X', coach: 1)},
        reopenedExercises: const {'X'},
        checkedSets: const {'0-0': true},
        setInputValues: const {'0-0': SetInputValues(weight: 60, reps: 8)},
      );
      expect(workingSetCounts(s), (saved: 2, total: 3));
    });

    test('finishGuard: a chat-done exercise is listed nowhere; a re-opened '
        'one with 0 new sets is not "Not saved"; a typed value still lists it',
        () {
      final done = finishGuard(ActiveWorkoutData(
          exercises: [ex('X')], loggedInChat: {'x': chat('X')}));
      expect(done.reopenedUnsaved, isEmpty);
      expect(done.skipped, isEmpty);
      expect(done.typedUnsaved, isEmpty);

      final reopened = finishGuard(ActiveWorkoutData(
          exercises: [ex('X', sets: '2')],
          loggedInChat: {'x': chat('X')},
          reopenedExercises: const {'X'}));
      expect(reopened.reopenedUnsaved, isEmpty);
      expect(reopened.skipped, isEmpty);

      final typed = finishGuard(ActiveWorkoutData(
          exercises: [ex('X', sets: '2')],
          loggedInChat: {'x': chat('X')},
          reopenedExercises: const {'X'},
          setInputValues: const {'0-0': SetInputValues(weight: 70, reps: 5)}));
      expect(typed.typedUnsaved, ['X']);

      // A chat-done exercise is skipped at the TOP of the loop: even a stale
      // typed value under its index (no row is shown for it) lists nothing.
      final staleTyped = finishGuard(ActiveWorkoutData(
          exercises: [ex('X')],
          loggedInChat: {'x': chat('X')},
          setInputValues: const {'0-0': SetInputValues(weight: 70, reps: 5)}));
      expect(staleTyped.typedUnsaved, isEmpty);
      expect(staleTyped.skipped, isEmpty);

      final nonChat = finishGuard(const ActiveWorkoutData(
          exercises: [ExerciseData(name: 'Y')], reopenedExercises: {'Y'}));
      expect(nonChat.reopenedUnsaved, ['Y']);
    });

    test('canMoveExercise false for a chat-done exercise; a chat-done '
        'superset partner is skipped by supersetPartnerToReveal', () {
      final s = ActiveWorkoutData(
          exercises: [ex('X', group: 0), ex('Y', group: 0), ex('Z')],
          loggedInChat: {'y': chat('Y')});
      expect(canMoveExercise(s, 1), isFalse);
      expect(supersetPartnerToReveal(s, 0), isNull);
    });

    test('the LOG outcome treats a chat-done partner as done', () {
      final c = seeded(ActiveWorkoutData(
          exercises: [ex('X', group: 0), ex('Y', group: 0)],
          loggedInChat: {'y': chat('Y')}));
      final ctl = LogExerciseController(clock: () => Duration.zero);
      final out = ctl.log(
        exerciseIndex: 0,
        setIndexes: {0, 1, 2},
        logSets: c.read(activeWorkoutProvider.notifier).logSets,
        readState: () => c.read(activeWorkoutProvider),
      );
      expect(out.kind, LogOutcomeKind.logged);
      expect(out.revealPartner, isNull);
    });
  });

  // ── T5: re-open and keep ──────────────────────────────────────────────
  group('T5 re-open and keep', () {
    ActiveWorkoutData two({Set<String> reopened = const {}}) =>
        ActiveWorkoutData(
          exercises: [ex('X'), ex('Z')],
          loggedInChat: {'x': chat('X'), 'z': chat('Z')},
          reopenedExercises: reopened,
        );

    test('row count: 3 planned / 1 coach gives 2; 3/3 gives 1; 2/5 gives 1',
        () {
      for (final (planned, coach, rows) in [(3, 1, 2), (3, 3, 1), (2, 5, 1)]) {
        final c = seeded(ActiveWorkoutData(
            exercises: [ex('X', sets: '$planned')],
            loggedInChat: {'x': chat('X', coach: coach, planned: planned)}));
        expect(c.read(activeWorkoutProvider.notifier).reopenChatLogged(0, 'X'),
            isTrue);
        expect(c.read(activeWorkoutProvider).exercises[0].sets, '$rows');
        expect(c.read(activeWorkoutProvider).reopenedExercises, {'X'});
      }
    });

    test('an empty per-set list with set_number 2: coachCount 2, no chips, '
        'row count and N/N use 2', () async {
      final d = day(today());
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(d, 'Plank'), {
        'exercise_name': 'Plank',
        'source': 'ai_coach',
        'set_number': 2,
        'logging_type': 'timed',
      });
      final c = started([ex('Plank', type: 'timed')]);
      final s = c.read(activeWorkoutProvider);
      final e = s.loggedInChat['plank']!;
      expect(e.coachCount, 2);
      expect(chatLoggedChips(e.sets), isEmpty);
      expect(workingSetCounts(s), (saved: 2, total: 2));
      c.read(activeWorkoutProvider.notifier).reopenChatLogged(0, 'Plank');
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '1');
    });

    test('keepChatLogged clears warmUpSets, setInputValues and '
        'suggestedInputs for the index, and restores sets', () {
      final c = seeded(ActiveWorkoutData(
        exercises: [ex('X', sets: '2'), ex('Y')],
        loggedInChat: {'x': chat('X')},
        reopenedExercises: const {'X'},
        warmUpSets: const {'0-1': true, '1-0': true},
        setInputValues: const {
          '0-0': SetInputValues(weight: 70, reps: 5),
          '1-0': SetInputValues(weight: 1, reps: 1),
        },
        suggestedInputs: const {'0-0-weight', '1-0-weight'},
      ));
      expect(c.read(activeWorkoutProvider.notifier).keepChatLogged(0, 'X'),
          isTrue);
      final s = c.read(activeWorkoutProvider);
      expect(s.exercises[0].sets, '3');
      expect(s.reopenedExercises, isEmpty);
      expect(s.warmUpSets, {'1-0': true});
      expect(s.setInputValues.keys, ['1-0']);
      expect(s.suggestedInputs, {'1-0-weight'});
    });

    test('hasCheckedRow reads only its own index: a checked row of exercise '
        '10 or 11 does not make exercise 1 checked (B-pass S1-F1)', () {
      final names = [for (var i = 0; i < 12; i++) 'E$i'];
      final c = seeded(ActiveWorkoutData(
        exercises: [for (final n in names) ex(n)],
        loggedInChat: {'e1': chat('E1')},
        reopenedExercises: const {'E1'},
        checkedSets: const {'10-0': true, '11-1': true},
      ));
      final s = c.read(activeWorkoutProvider);
      expect(hasCheckedRow(s, 1), isFalse);
      expect(hasCheckedRow(s, 10), isTrue);
      expect(hasCheckedRow(s, 11), isTrue);
      expect(c.read(activeWorkoutProvider.notifier).keepChatLogged(1, 'E1'),
          isTrue);
      expect(c.read(activeWorkoutProvider).reopenedExercises, isEmpty);
    });

    group('reopenChatLogged guards (each alone refuses, state unchanged)', () {
      void refuses(ProviderContainer c, int i, String name) {
        final before = c.read(activeWorkoutProvider);
        expect(c.read(activeWorkoutProvider.notifier).reopenChatLogged(i, name),
            isFalse);
        final after = c.read(activeWorkoutProvider);
        expect(identical(before, after), isTrue);
      }

      test('out-of-range index returns false, not a RangeError', () {
        final c = seeded(two());
        refuses(c, -1, 'X');
        refuses(c, 2, 'X');
      });
      test('saved', () {
        refuses(seeded(ActiveWorkoutData(
            exercises: [ex('X')], loggedInChat: {'x': chat('X')}, isSaved: true)),
            0, 'X');
      });
      test('complete', () {
        refuses(seeded(ActiveWorkoutData(
            exercises: [ex('X')], loggedInChat: {'x': chat('X')},
            isComplete: true)),
            0, 'X');
      });
      test('wrong name: passed X (chat, not re-opened), slot holds Z (chat, '
          'not re-opened)', () {
        final c = seeded(two());
        refuses(c, 1, 'X');
        expect(c.read(activeWorkoutProvider).reopenedExercises, isEmpty);
      });
      test('non-chat slot', () {
        refuses(seeded(ActiveWorkoutData(exercises: [ex('Y')])), 0, 'Y');
      });
      test('already re-opened', () {
        refuses(seeded(two(reopened: {'X'})), 0, 'X');
      });
    });

    group('keepChatLogged guards (each alone refuses, state unchanged)', () {
      void refuses(ProviderContainer c, int i, String name) {
        final before = c.read(activeWorkoutProvider);
        expect(c.read(activeWorkoutProvider.notifier).keepChatLogged(i, name),
            isFalse);
        expect(identical(before, c.read(activeWorkoutProvider)), isTrue);
      }

      test('out-of-range index', () {
        final c = seeded(two(reopened: {'X', 'Z'}));
        refuses(c, -1, 'X');
        refuses(c, 2, 'X');
      });
      test('saved', () {
        refuses(seeded(ActiveWorkoutData(
            exercises: [ex('X')], loggedInChat: {'x': chat('X')},
            reopenedExercises: const {'X'}, isSaved: true)), 0, 'X');
      });
      test('complete', () {
        refuses(seeded(ActiveWorkoutData(
            exercises: [ex('X')], loggedInChat: {'x': chat('X')},
            reopenedExercises: const {'X'}, isComplete: true)), 0, 'X');
      });
      test('wrong name: passed X (chat, re-opened), slot holds Z (chat, '
          're-opened, no checked set)', () {
        refuses(seeded(two(reopened: {'X', 'Z'})), 1, 'X');
      });
      test('non-chat: a non-chat name that IS in reopenedExercises', () {
        refuses(seeded(const ActiveWorkoutData(
            exercises: [ExerciseData(name: 'Y')], reopenedExercises: {'Y'})),
            0, 'Y');
      });
      test('not re-opened', () {
        refuses(seeded(two()), 0, 'X');
      });
      test('a checked row (a warm-up counts)', () {
        refuses(seeded(ActiveWorkoutData(
            exercises: [ex('X', sets: '2')], loggedInChat: {'x': chat('X')},
            reopenedExercises: const {'X'},
            checkedSets: const {'0-0': true},
            warmUpSets: const {'0-0': true})), 0, 'X');
      });
    });

    test('_completing: while a save runs, both methods refuse with state '
        'untouched (R6A-F1)', () async {
      await coachLog('X1', [set_(60, 8)]);
      await coachLog('X2', [set_(40, 8)]);
      final c = started([ex('X1'), ex('X2'), ex('Y')]);
      final n = c.read(activeWorkoutProvider.notifier);
      expect(n.reopenChatLogged(0, 'X1'), isTrue);
      n.logSets(2, {0});
      n.recordSetValues(2, 0, const SetInputValues(weight: 100, reps: 5));
      final gate = Completer<void>();
      ActiveWorkoutNotifier.debugBeforeMarkGate = gate;
      final f = n.completeWorkout();
      expect(n.isCompleting, isTrue);
      final before = c.read(activeWorkoutProvider);
      expect(n.reopenChatLogged(1, 'X2'), isFalse);
      expect(n.keepChatLogged(0, 'X1'), isFalse);
      expect(identical(before, c.read(activeWorkoutProvider)), isTrue);
      gate.complete();
      await f;
    });

    test('a successful chat re-open stamps the guard: a second reopen inside '
        'kReopenGuard is ignored', () {
      var now = Duration.zero;
      final ctl = LogExerciseController(clock: () => now);
      final c = seeded(two());
      LogOutcome reopen(int i) => ctl.reopen(
            exerciseIndex: i,
            readState: () => c.read(activeWorkoutProvider),
            unlogSets: c.read(activeWorkoutProvider.notifier).unlogSets,
            reopenChatLogged:
                c.read(activeWorkoutProvider.notifier).reopenChatLogged,
          );
      expect(reopen(0).kind, LogOutcomeKind.reopened);
      now = const Duration(milliseconds: 200);
      expect(reopen(1).kind, LogOutcomeKind.ignored);
      expect(c.read(activeWorkoutProvider).reopenedExercises, {'X'});
    });

    test('LogExerciseController.reopen without the callback: a chat-done '
        'exercise is a noop (no sets to uncheck), as before', () {
      final ctl = LogExerciseController(clock: () => Duration.zero);
      final c = seeded(two());
      final out = ctl.reopen(
        exerciseIndex: 0,
        readState: () => c.read(activeWorkoutProvider),
        unlogSets: c.read(activeWorkoutProvider.notifier).unlogSets,
      );
      expect(out.kind, LogOutcomeKind.noop);
    });

    test('logSets / toggleSet on a chat-done exercise leave state untouched',
        () {
      final c = seeded(two());
      final n = c.read(activeWorkoutProvider.notifier);
      final before = c.read(activeWorkoutProvider);
      n.logSets(0, {0, 1});
      expect(identical(before, c.read(activeWorkoutProvider)), isTrue);
      n.toggleSet(0, 0);
      expect(identical(before, c.read(activeWorkoutProvider)), isTrue);
    });
  });

  // ── T6: swap / add ────────────────────────────────────────────────────
  group('T6 swap and add', () {
    test('swap AWAY from a re-opened X gives an unmapped Y X\'s plannedSets; '
        'UNDO gives X DONE with plannedSets', () {
      final c = seeded(ActiveWorkoutData(
          exercises: [ex('X')], loggedInChat: {'x': chat('X', planned: 4)}));
      final n = c.read(activeWorkoutProvider.notifier);
      n.reopenChatLogged(0, 'X');
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '3');
      n.swapExercise(0, ex('Y', sets: '5'));
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '4');
      n.swapExercise(0, ex('X', sets: '9'));
      final s = c.read(activeWorkoutProvider);
      expect(s.exercises[0].sets, '4');
      expect(s.isChatLoggedDone(0), isTrue);
    });

    test('swap TO a mapped name and add of a mapped name are DONE with sets '
        '== plannedSets; a re-pick of the same slot is DONE', () {
      final c = seeded(ActiveWorkoutData(
          exercises: [ex('A')],
          loggedInChat: {'x': chat('X', planned: 4), 'w': chat('W', planned: 2)}));
      final n = c.read(activeWorkoutProvider.notifier);
      n.swapExercise(0, ex('X', sets: '9'));
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '4');
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(0), isTrue);
      n.addExercise(ex('W', sets: '7'));
      expect(c.read(activeWorkoutProvider).exercises[1].sets, '2');
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(1), isTrue);
      n.swapExercise(0, ex('X', sets: '9'));
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(0), isTrue);
    });

    test('introduced name: swap/add of a name NOT in the snapshot that has a '
        'coach row today opens DONE; a miss stays plain', () async {
      await coachLog('Dips', [set_(0, 10)]);
      await coachLog('Curl', [set_(10, 12)]);
      final c = started([ex('Bench Press')]);
      final n = c.read(activeWorkoutProvider.notifier);
      n.swapExercise(0, ex('Dips'));
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(0), isTrue);
      n.addExercise(ex('Curl', sets: '4'));
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(1), isTrue);
      expect(c.read(activeWorkoutProvider).exercises[1].sets, '4');
      n.addExercise(ex('Row'));
      expect(c.read(activeWorkoutProvider).isChatLogged(2), isFalse);
    });

    test('a name logged today but introduced with the flag OFF stays plain',
        () async {
      await coachLog('Dips', [set_(0, 10)]);
      final c = started([ex('Bench Press')]);
      await HiveService.instance.configBox.put(LogExerciseFlags.key, false);
      c.read(activeWorkoutProvider.notifier).swapExercise(0, ex('Dips'));
      expect(c.read(activeWorkoutProvider).isChatLogged(0), isFalse);
    });

    test('introduced-name plannedSets come from the OVERRIDDEN sets (B4-F7)',
        () async {
      await coachLog('X', [set_(60, 8)]);
      await coachLog('Y', [set_(40, 8)]);
      final c = started([ex('X', sets: '3')]);
      final n = c.read(activeWorkoutProvider.notifier);
      n.reopenChatLogged(0, 'X');
      expect(c.read(activeWorkoutProvider).exercises[0].sets, '2');
      n.swapExercise(0, ex('Y', sets: '5'));
      final s = c.read(activeWorkoutProvider);
      expect(s.loggedInChat['y']!.plannedSets, 3);
      expect(s.exercises[0].sets, '3');
    });

    test('a 1 s timer tick keeps loggedInChat (copyWith threads it)',
        () async {
      await coachLog('X', [set_(60, 8)]);
      final c = started([ex('X')]);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final s = c.read(activeWorkoutProvider);
      expect(s.elapsedSeconds, greaterThanOrEqualTo(1));
      expect(s.loggedInChat.keys, ['x']);
    });
  });

  // ── T7: FINISH writes no double entry ─────────────────────────────────
  group('T7 FINISH', () {
    test('(a) the chat row is byte-identical after the real save', () async {
      await coachLog('X', [set_(60, 8), set_(60, 8)]);
      final c = started([ex('X'), ex('Y')]);
      final before = storedRow('X');
      final n = c.read(activeWorkoutProvider.notifier);
      n.logSets(1, {0});
      n.recordSetValues(1, 0, const SetInputValues(weight: 100, reps: 5));
      await n.completeWorkout();
      expect(c.read(activeWorkoutProvider).isSaved, isTrue);
      expect(storedRow('X'), before);
      expect((storedRow('Y')['sets'] as List).length, 1);
    });

    test('(b) re-opened with 2 new sets: the coach\'s set (deep-equal) then 2; '
        'set_number 3', () async {
      await coachLog('X', [set_(60, 8)]);
      final coachSet = (storedRow('X')['sets'] as List).single;
      final c = started([ex('X'), ex('Y')]);
      final n = c.read(activeWorkoutProvider.notifier);
      expect(n.reopenChatLogged(0, 'X'), isTrue);
      n.logSets(0, {0, 1});
      n.recordSetValues(0, 0, const SetInputValues(weight: 62.5, reps: 8));
      n.recordSetValues(0, 1, const SetInputValues(weight: 65, reps: 6));
      await n.completeWorkout();
      final row = storedRow('X');
      final sets = row['sets'] as List;
      expect(sets.length, 3);
      expect(sets.first, coachSet);
      expect([for (final s in sets.skip(1)) (s as Map)['weight_kg']],
          [62.5, 65.0]);
      expect(row['set_number'], 3);
    });

    test('(c) mixed day: chat X untouched, session Y saved', () async {
      await coachLog('X', [set_(60, 8)]);
      final c = started([ex('X'), ex('Y'), ex('Z')]);
      final before = storedRow('X');
      final n = c.read(activeWorkoutProvider.notifier);
      n.logSets(1, {0, 1});
      n.recordSetValues(1, 0, const SetInputValues(weight: 100, reps: 5));
      n.recordSetValues(1, 1, const SetInputValues(weight: 100, reps: 5));
      await n.completeWorkout();
      expect(storedRow('X'), before);
      expect((storedRow('Y')['sets'] as List).length, 2);
    });

    test('(d) every exercise chat-logged: completeWorkout is a no-op',
        () async {
      await coachLog('X', [set_(60, 8)]);
      await coachLog('Y', [set_(40, 8)]);
      final c = started([ex('X'), ex('Y')]);
      final bx = storedRow('X');
      await c.read(activeWorkoutProvider.notifier).completeWorkout();
      expect(c.read(activeWorkoutProvider).isSaved, isFalse);
      expect(storedRow('X'), bx);
    });
  });

  // ── T8: residual pins ─────────────────────────────────────────────────
  group('T8 residuals', () {
    test('R3: a swapped_from match: re-open + FINISH writes a SECOND row under '
        'the slot\'s name; a second START opens the slot DONE with the '
        'original name\'s sets', () async {
      await putPlanRow(today(), [
        {'exercise_name': 'Ring Dips', 'swapped_from': 'Dips'},
      ]);
      await coachLog('Dips', [set_(0, 10)]);
      final c = started([ex('Ring Dips', type: 'bodyweight_reps')]);
      final n = c.read(activeWorkoutProvider.notifier);
      n.reopenChatLogged(0, 'Ring Dips');
      n.logSets(0, {0});
      n.recordSetValues(0, 0, const SetInputValues(reps: 9));
      await n.completeWorkout();
      expect((storedRow('Ring Dips')['sets'] as List).length, 1);
      expect((storedRow('Dips')['sets'] as List).length, 1);
      final again =
          started([ex('Ring Dips', type: 'bodyweight_reps')]).read(activeWorkoutProvider);
      expect(again.isChatLoggedDone(0), isTrue);
      expect(again.loggedInChat['ring dips']!.loggedName, 'Dips');
    });

    test('R4: an Active Workout append drops a coach note', () async {
      final r = await WorkoutWriteService.instance.logExercise(
        date: day(today()),
        exerciseName: 'X',
        sets: [set_(60, 8)],
        source: WriteSource.aiCoach,
        notes: 'felt heavy',
      );
      expect(r.success, isTrue);
      await logAs(WriteSource.activeWorkout, 'X', [set_(65, 6)]);
      expect(storedRow('X').containsKey('notes'), isFalse);
    });

    test('R5: liveVolumeKg counts only this session\'s sets', () {
      final s = ActiveWorkoutData(
        exercises: [ex('X', sets: '1')],
        loggedInChat: {'x': chat('X', coach: 2)},
        reopenedExercises: const {'X'},
        checkedSets: const {'0-0': true},
        setInputValues: const {'0-0': SetInputValues(weight: 50, reps: 10)},
      );
      expect(s.liveVolumeKg, 500);
    });

    test('R7: a session crossing 00:00 IST: snapshot for D, introduced-name '
        'read for D+1; new sets save to D+1; nothing written twice', () async {
      final d = istTodayStr();
      final d1 = istDateStr(DateTime.now().add(const Duration(days: 1)));
      await coachLog('X', [set_(60, 8)], ist: d);
      await coachLog('Y', [set_(40, 8)], ist: d1);
      final c = started([ex('X'), ex('A')]);
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(0), isTrue);
      setTestClockTo(DateTime.now().add(const Duration(days: 1)));
      final n = c.read(activeWorkoutProvider.notifier);
      n.swapExercise(1, ex('Y'));
      expect(c.read(activeWorkoutProvider).isChatLoggedDone(1), isTrue);
      n.addExercise(ex('B'));
      n.logSets(2, {0});
      n.recordSetValues(2, 0, const SetInputValues(weight: 30, reps: 10));
      final xBefore = storedRow('X', ist: d);
      final yBefore = storedRow('Y', ist: d1);
      await n.completeWorkout();
      expect(storedRow('X', ist: d), xBefore);
      expect(storedRow('Y', ist: d1), yBefore);
      expect((storedRow('B', ist: d1)['sets'] as List).length, 1);
    });

    test('R8: an identical real set within 60 s of the chat log is dropped by '
        'the writer dedup', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await coachLog('X',
          [ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: now - 10000)]);
      await logAs(WriteSource.activeWorkout, 'X',
          [ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: now)]);
      expect((storedRow('X')['sets'] as List).length, 1);
    });
  });

  // ── T9: the blocked FINISH line ───────────────────────────────────────
  group('T9 finishBlockedLine', () {
    test('every live exercise chat-done gives the F3 line', () {
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('X'), ex('Z')],
              loggedInChat: {'x': chat('X'), 'z': chat('Z')})),
          WardroomCopy.activeFinishAllLoggedInChat);
    });

    test('chat X + session Y with only warm-ups gives the F4 mixed line', () {
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('X'), ex('Y')],
              loggedInChat: {'x': chat('X')},
              checkedSets: const {'1-0': true},
              warmUpSets: const {'1-0': true})),
          WardroomCopy.activeFinishNoNewSets);
    });

    test('one un-done non-chat exercise, the others chat-done: F4', () {
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('X'), ex('Z'), ex('Y')],
              loggedInChat: {'x': chat('X'), 'z': chat('Z')})),
          WardroomCopy.activeFinishNoNewSets);
    });

    test('a single re-opened X with 0 new sets: F4; X and Y both re-opened: '
        'F4', () {
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('X')],
              loggedInChat: {'x': chat('X')},
              reopenedExercises: const {'X'})),
          WardroomCopy.activeFinishNoNewSets);
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('X'), ex('Y')],
              loggedInChat: {'x': chat('X'), 'y': chat('Y')},
              reopenedExercises: const {'X', 'Y'})),
          WardroomCopy.activeFinishNoNewSets);
    });

    test('X swapped out or removed (its entry stays) leaving a non-chat '
        'warm-up-only day: the OLD line', () {
      expect(
          finishBlockedLine(ActiveWorkoutData(
              exercises: [ex('Y')],
              loggedInChat: {'x': chat('X')},
              checkedSets: const {'0-0': true},
              warmUpSets: const {'0-0': true})),
          WardroomCopy.activeFinishZeroSetBlocked);
    });

    test('no chat exercise, or an empty list: the OLD line', () {
      expect(finishBlockedLine(ActiveWorkoutData(exercises: [ex('Y')])),
          WardroomCopy.activeFinishZeroSetBlocked);
      expect(finishBlockedLine(const ActiveWorkoutData()),
          WardroomCopy.activeFinishZeroSetBlocked);
    });
  });

  // ── T10: the marker carriers ──────────────────────────────────────────
  group('T10 marker carriers', () {
    Future<void> putRow(String ist, String name, Map<String, dynamic> extra,
        {String? key}) {
      return HiveService.instance.workoutBox
          .put(key ?? WorkoutWriteService.exlogKey(day(ist), name), {
        'exercise_name': name,
        'date': ist,
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 50.0, 'reps': 5, 'logged_at_ms': 1}
        ],
        'set_number': 1,
        'workout_log_id': 'wlog_$ist',
        ...extra,
      });
    }

    test('editLog keeps coach_logged', () async {
      await coachLog('X', [set_(60, 8)]);
      final key = WorkoutWriteService.exlogKey(day(today()), 'X');
      final r = await WorkoutWriteService.instance.editLog(
        logKey: key,
        updates: {
          'sets': [
            {'weight_kg': 70.0, 'reps': 5}
          ],
        },
        source: WriteSource.editSheet,
      );
      expect(r.success, isTrue, reason: r.errorMessage);
      expect(storedRow('X')['coach_logged'], isTrue);
    });

    Future<Map<String, dynamic>> moveOnto(
        Map<String, dynamic> existingExtra, Map<String, dynamic> movedExtra) async {
      final from = pastDay();
      final to = today();
      await putRow(to, 'X', existingExtra);
      await putRow(from, 'X', movedExtra);
      await WorkoutWriteService.instance.moveExerciseLogs(
        fromDate: from,
        toDate: to,
      );
      return storedRow('X');
    }

    test('move collision: marked existing + unmarked moved keeps it', () async {
      final r = await moveOnto({'coach_logged': true}, const {});
      expect(r['coach_logged'], isTrue);
    });

    test('move collision: unmarked existing + marked moved sets it', () async {
      final r = await moveOnto(const {}, {'coach_logged': true});
      expect(r['coach_logged'], isTrue);
    });

    test('move collision: only a source ai_coach (no marker) sets it',
        () async {
      final r = await moveOnto(const {}, {'source': 'ai_coach'});
      expect(r['coach_logged'], isTrue);
    });

    test('move collision: neither side gives no key', () async {
      final r = await moveOnto(const {'source': 'active_workout'},
          const {'source': 'active_workout'});
      expect(r.containsKey('coach_logged'), isFalse);
    });

    Future<Map<String, dynamic>> migrateGroup(
        List<Map<String, dynamic>> extras) async {
      final ist = today();
      final box = HiveService.instance.workoutBox;
      var ms = 1000;
      var i = 0;
      for (final e in extras) {
        // Rogue (non-canonical) keys for the same name and date form a group.
        await putRow(ist, 'X', {...e, 'updated_at_ms': ms += 1000},
            key: 'exlog_${ist}_rogue${i++}');
      }
      expect(box.keys.where((k) => '$k'.contains('rogue')).length,
          extras.length);
      await ExlogKeyMigrator.runIfNeeded();
      return storedRow('X');
    }

    test('migrator: a 3-member group whose marked member is in the MIDDLE '
        'keeps the marker', () async {
      final r = await migrateGroup([
        const {},
        const {'coach_logged': true},
        const {},
      ]);
      expect(r['coach_logged'], isTrue);
      expect((r['sets'] as List).length, 3);
    });

    test('migrator: the marked member is the base (last): the marker survives',
        () async {
      final r = await migrateGroup([
        const {},
        const {},
        const {'coach_logged': true},
      ]);
      expect(r['coach_logged'], isTrue);
    });

    test('migrator: a source ai_coach member (no marker) sets it', () async {
      final r = await migrateGroup([
        const {'source': 'ai_coach'},
        const {},
      ]);
      expect(r['coach_logged'], isTrue);
    });
  });
}
