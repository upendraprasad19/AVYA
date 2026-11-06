// SoT concept `exercise_name_unique_in_day` (OI-358).
//
// The Active Workout screen keys each card by exercise name and
// `WorkoutWriteService.exlogKey` saves one log row per name per date, so a day
// cannot hold a name twice. These tests drive the REAL writers against Hive:
//
//   session   ActiveWorkoutNotifier.addExercise / swapExercise / startWorkout
//   stored    SwapService.swapExerciseInDay (coach tool, coach sheet, injury)
//   planner   InjurySwapPlanner.plan (the substitutes it promises)
//   template  WorkoutRepository.createTemplate, assignTemplateToDate
//
// Readers: the screen tests in test/features/train/exercise_name_unique_screen_test.dart.
// Plan docs/plans/oi358-unique-exercise-names.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/exercise_name_identity.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/services/injury_swap_planner.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

class _Seeded extends ActiveWorkoutNotifier {
  _Seeded(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

ExerciseData ex(String name) => ExerciseData(
    name: name, sets: '3', reps: '8', weight: '0kg', rest: '90s');

ProviderContainer containerWith(ActiveWorkoutData seed) {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(() => _Seeded(seed)),
  ]);
  addTearDown(c.dispose);
  return c;
}

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

Map<String, dynamic> planned(String id, String name) => {
      'exercise_id': id,
      'exercise_name': name,
      'sets': 3,
      'reps': '8',
      'rest_seconds': 90,
      'logging_type': 'weight_reps',
    };

Future<void> putDay(String date, List<Map<String, dynamic>> exercises) =>
    HiveService.instance.workoutBox.put('schedule_$date', {
      'date': date,
      'type': 'workout',
      'workout_name': 'D',
      'status': 'planned',
      'exercises': exercises,
    });

List<String> dayNames(String date) {
  final row = HiveService.instance.workoutBox.get('schedule_$date') as Map;
  return (row['exercises'] as List)
      .map((e) => (e as Map)['exercise_name'] as String)
      .toList();
}

Map<String, dynamic> toolRow(String id, String name) => {
      'exerciseId': id,
      'exerciseName': name,
      'sets': 3,
      'reps': '10',
    };

Map<String, dynamic> toolDay(String name, List<Map<String, dynamic>> rows) =>
    {'dayName': name, 'exercises': rows};

List<Map> templateRows() => HiveService.instance.workoutBox.values
    .whereType<Map>()
    .where((m) => m['type'] == 'template')
    .toList();

void main() {
  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    SwapService.debugOnPlanPushForTests = () {};
  });

  tearDown(() async {
    SwapService.debugOnPlanPushForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    await tearDownHiveForTests(dir);
  });

  group('the rule', () {
    test('exerciseNameKey groups names exactly as exlogKey does', () {
      final date = DateTime.utc(2099, 1, 6);
      const names = [
        'Bench Press',
        'bench press',
        ' Bench Press ',
        'BENCH PRESS',
        'Bench  Press',
        'Incline Press',
      ];
      for (final a in names) {
        for (final b in names) {
          expect(
            exerciseNameKey(a) == exerciseNameKey(b),
            WorkoutWriteService.exlogKey(date, a) ==
                WorkoutWriteService.exlogKey(date, b),
            reason: 'if these disagree, two cards the guard allowed could '
                'still save to one log row: "$a" vs "$b"',
          );
        }
      }
    });

    test('exerciseRowName reads both shapes and calls a blank row nameless', () {
      expect(exerciseRowName({'exercise_name': 'A', 'name': 'B'}), 'A');
      expect(exerciseRowName({'name': 'B'}), 'B');
      expect(exerciseRowName({'exercise_name': '', 'name': 'B'}), 'B');
      expect(exerciseRowName({'exercise_name': '  ', 'name': ''}), isNull);
      expect(exerciseRowName({}), isNull);
    });

    test('firstPerExerciseName keeps the first, keeps order, keeps nameless', () {
      final rows = <Map<String, Object?>>[
        {'exercise_name': 'A', 'pos': 0},
        {'pos': 1},
        {'exercise_name': 'B', 'pos': 2},
        {'exercise_name': 'a ', 'pos': 3},
        {'pos': 4},
      ];
      expect(
        firstPerExerciseName(rows, exerciseRowName).map((r) => r['pos']),
        [0, 1, 2, 4],
      );
    });
  });

  group('session writers', () {
    test('addExercise refuses a name in the session and changes nothing', () {
      for (final same in ['Bench', 'BENCH', ' bench ']) {
        final seed = ActiveWorkoutData(
            exercises: [ex('Bench'), ex('Row')],
            checkedSets: const {'0-0': true});
        final c = containerWith(seed);
        final result = c.read(activeWorkoutProvider.notifier).addExercise(ex(same));
        expect(result, SessionExerciseChange.nameTaken, reason: same);
        expect(identical(c.read(activeWorkoutProvider), seed), isTrue,
            reason: 'a refusal must not write state');
      }
    });

    test('addExercise appends a new name', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Bench')]));
      expect(c.read(activeWorkoutProvider.notifier).addExercise(ex('Row')),
          SessionExerciseChange.applied);
      expect(c.read(activeWorkoutProvider).exercises.map((e) => e.name),
          ['Bench', 'Row']);
    });

    test('swapExercise refuses a name in ANOTHER slot and keeps that slot state',
        () {
      final seed = ActiveWorkoutData(
        exercises: [ex('Bench'), ex('Row')],
        checkedSets: const {'1-0': true},
      );
      final c = containerWith(seed);
      final result =
          c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('bench'));
      expect(result, SessionExerciseChange.nameTaken);
      expect(identical(c.read(activeWorkoutProvider), seed), isTrue,
          reason: 'the swap wipes per-slot state, a refusal must not');
    });

    test('swapExercise allows the same slot, which is what an UNDO does', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Bench'), ex('Row')]));
      expect(c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('Row')),
          SessionExerciseChange.applied);
      expect(c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('Curl')),
          SessionExerciseChange.applied);
      expect(c.read(activeWorkoutProvider).exercises.map((e) => e.name),
          ['Bench', 'Curl']);
    });

    test('a bad slot is invalidSlot, never nameTaken', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Bench')]));
      final n = c.read(activeWorkoutProvider.notifier);
      expect(n.swapExercise(5, ex('Bench')), SessionExerciseChange.invalidSlot);
      expect(n.swapExercise(-1, ex('Bench')), SessionExerciseChange.invalidSlot);
    });
  });

  group('startWorkout, the last line', () {
    WorkoutDayData day(List<ExerciseData> exercises) =>
        WorkoutDayData(dayNumber: 1, name: 'D', exercises: exercises);

    test('keeps the first of each name, in order, and logs a count only', () {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {
        if (op == 'active_workout_duplicate_name_dropped') events.add('$message');
      };
      final c = containerWith(const ActiveWorkoutData());
      addTearDown(c.read(activeWorkoutProvider.notifier).cancelWorkout);
      c.read(activeWorkoutProvider.notifier).startWorkout(day([
        ex('Bench'),
        ex('Row'),
        ex('bench'),
        ex('Curl'),
        ex('Row'),
      ]));
      expect(c.read(activeWorkoutProvider).exercises.map((e) => e.name),
          ['Bench', 'Row', 'Curl']);
      expect(events, ['dropped=2'], reason: 'one event, a count, no exercise name');
    });

    test('a clean day logs nothing and is unchanged', () {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {message}) => events.add(op);
      final c = containerWith(const ActiveWorkoutData());
      addTearDown(c.read(activeWorkoutProvider.notifier).cancelWorkout);
      c
          .read(activeWorkoutProvider.notifier)
          .startWorkout(day([ex('Bench'), ex('Row')]));
      expect(c.read(activeWorkoutProvider).exercises.length, 2);
      expect(events, isNot(contains('active_workout_duplicate_name_dropped')));
    });
  });

  group('swapExerciseInDay (coach swap, coach sheet, injury swap)', () {
    const date = '2099-01-06';

    setUp(() async {
      final box = HiveService.instance.exerciseBox;
      await box.put('E1', {'id': 'E1', 'name': 'Bench Press'});
      await box.put('E2', {'id': 'E2', 'name': 'Goblet Squat'});
    });

    test('a target whose NAME is in another slot is refused, nothing written',
        () async {
      await putDay(date, [planned('Z9', 'bench press '), planned('Z8', 'Row')]);
      final before = jsonEncode(HiveService.instance.workoutBox.get('schedule_$date'));
      await expectLater(
        engine.swapExerciseInDay(
            date: date, fromExerciseId: 'Z8', toExerciseId: 'E1'),
        throwsA(isA<SwapExerciseException>()
            .having((e) => e.code, 'code', 'exercise_already_in_workout')
            .having((e) => e.message, 'message', contains('Bench Press'))),
      );
      expect(jsonEncode(HiveService.instance.workoutBox.get('schedule_$date')),
          before);
    });

    test('a new name still swaps', () async {
      await putDay(date, [planned('Z9', 'Row'), planned('Z8', 'Curl')]);
      await engine.swapExerciseInDay(
          date: date, fromExerciseId: 'Z8', toExerciseId: 'E2');
      expect(dayNames(date), ['Row', 'Goblet Squat']);
    });

    test('the slot being replaced does not count against itself', () async {
      await putDay(date, [planned('E1', 'Bench Press'), planned('Z8', 'Row')]);
      await engine.swapExerciseInDay(
          date: date, fromExerciseId: 'E1', toExerciseId: 'E1');
      expect(dayNames(date), ['Bench Press', 'Row']);
    });
  });

  group('InjurySwapPlanner', () {
    final planner = InjurySwapPlanner.instance;
    final today = istDateStr(DateTime.now());
    final tomorrow = istDateStr(DateTime.now().add(const Duration(days: 1)));

    Map<String, dynamic> legRow(String id, String muscle) => {
          'id': id,
          'name': id,
          'category': 'legs',
          'primary_muscles': [muscle],
        };

    Map<String, dynamic> hit(String id) => {
          ...planned(id, id),
          'category': 'legs',
          'primary_muscles': ['quads'],
        };

    setUp(() async {
      final box = HiveService.instance.exerciseBox;
      await box.put('Squat', legRow('Squat', 'quads'));
      await box.put('Lunge', legRow('Lunge', 'quads'));
      await box.put('Calf Raise', legRow('Calf Raise', 'calves'));
      await box.put('Hamstring Curl', legRow('Hamstring Curl', 'hamstrings'));
    });

    test('two affected exercises of one category get DIFFERENT substitutes',
        () async {
      await putDay(today, [hit('Squat'), hit('Lunge')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      expect(swaps.map((s) => s.fromName), ['Squat', 'Lunge']);
      expect(swaps.map((s) => s.toName).toSet().length, 2,
          reason: 'both used to get the same first match');
    });

    test('rows with no muscle data take the same rule (the library-lookup branch)',
        () async {
      await putDay(today, [planned('Squat', 'Squat'), planned('Lunge', 'Lunge')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      expect(swaps.map((s) => s.fromName), ['Squat', 'Lunge']);
      expect(swaps.map((s) => s.toName).toSet().length, 2);
    });

    test('a substitute already in the day is skipped', () async {
      await putDay(today, [hit('Squat'), planned('Calf Raise', 'calf raise')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      expect(swaps.single.toName, 'Hamstring Curl');
    });

    test('one substitute may repeat on another date', () async {
      await putDay(today, [hit('Squat')]);
      await putDay(tomorrow, [hit('Squat')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 2);
      expect(swaps.map((s) => s.date), [today, tomorrow]);
      expect(swaps[0].toName, swaps[1].toName,
          reason: 'the taken set is per date, not per plan');
    });

    test('nothing left means no swap, and the day still applies cleanly',
        () async {
      await HiveService.instance.exerciseBox.delete('Hamstring Curl');
      await putDay(today, [hit('Squat'), hit('Lunge')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      expect(swaps.length, 1, reason: 'one substitute, two exercises to place');
      await engine.swapExerciseInDay(
        date: today,
        fromExerciseId: swaps.single.fromId,
        toExerciseId: swaps.single.toId,
      );
      expect(dayNames(today).toSet().length, 2);
    });

    test('every planned swap executes: the preview promises nothing the guard refuses',
        () async {
      await putDay(today, [hit('Squat'), hit('Lunge')]);
      final swaps =
          await planner.plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      for (final s in swaps) {
        await engine.swapExerciseInDay(
            date: s.date, fromExerciseId: s.fromId, toExerciseId: s.toId);
      }
      final names = dayNames(today);
      expect(names.toSet().length, names.length);
      expect(names, isNot(contains('Squat')));
    });
  });

  group('createTemplate (coach)', () {
    final repo = WorkoutRepository.instance;

    test('a repeat on day 2 of 2 writes NO day at all', () async {
      await expectLater(
        repo.createTemplate(name: 'Split', days: [
          toolDay('Push', [toolRow('E1', 'Bench'), toolRow('E2', 'Press')]),
          toolDay('Pull', [toolRow('E3', 'Row'), toolRow('E4', ' row')]),
        ]),
        throwsA(isA<CreateTemplateException>()
            .having((e) => e.code, 'code', 'duplicate_exercise')
            .having((e) => e.message, 'message',
                allOf(contains('row'), contains('Pull')))),
      );
      expect(templateRows(), isEmpty, reason: 'no partial multi-day template');
    });

    test('one name on two different days is fine', () async {
      await repo.createTemplate(name: 'Split', days: [
        toolDay('A', [toolRow('E1', 'Bench')]),
        toolDay('B', [toolRow('E1', 'Bench')]),
      ]);
      expect(templateRows().length, 2);
    });

    test('a row the write loop would skip cannot refuse', () async {
      await repo.createTemplate(name: 'Skips', days: [
        toolDay('A', [
          toolRow('E1', 'Bench'),
          toolRow('', 'Bench'), // the loop drops an empty id
        ]),
      ]);
      final row = templateRows().single;
      expect((row['exercises'] as List).length, 1);
    });
  });

  group('assignTemplateToDate (all three routes pass through it)', () {
    final date = DateTime(2099, 3, 4);
    final key = formatDateKey(date);

    Future<void> assign(List<Map<String, dynamic>> exercises) async {
      await HiveService.instance.workoutBox.put('tmpl_t1', {
        'id': 'tmpl_t1',
        'type': 'template',
        'name': 'Saved',
        'exercises': exercises,
      });
      await WorkoutScheduleService.instance.assignTemplateToDate('tmpl_t1', date);
    }

    test('a template saved with a repeat schedules with the first of each',
        () async {
      await assign([
        {'exercise_name': 'Bench', 'sets': 4},
        {'name': 'Row', 'sets': 3},
        {'name': 'bench ', 'sets': 2},
      ]);
      expect(dayNames(key), ['Bench', 'Row']);
      final row = HiveService.instance.workoutBox.get('schedule_$key') as Map;
      expect(((row['exercises'] as List).first as Map)['sets'], 4,
          reason: 'the FIRST copy survives, not the last');
    });

    test('two nameless rows both survive: nameless is not an identity', () async {
      await assign([
        {'sets': 3},
        {'sets': 4},
        {'exercise_name': 'Row', 'sets': 3},
      ]);
      expect(dayNames(key), ['Unknown', 'Unknown', 'Row']);
    });
  });
}
