// SoT concept `active_workout_set_logging`, flip batch
// (docs/plans/log-exercise-flip.md §6): RE-OPEN and the guard windows on the
// real `LogExerciseController` (fake monotonic clock), the new notifier writers
// (`recordCardEdit`, `unlogSets(reopened:)`, the `_completing` guard on
// `logSets`, `suggestedInputs` cleanup), the ONE save predicate against the
// real `completeWorkout` (U-D1b), and the zero-set block (OI-361, U-E1).
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

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

ProviderContainer containerWith(ActiveWorkoutData seed) {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    activeWorkoutProvider.overrideWith(() => _SeededNotifier(seed)),
  ]);
  addTearDown(c.dispose);
  return c;
}

const _v = SetInputValues(weight: 50, reps: 8);

Map<String, bool> _checked(int ex, Iterable<int> sets) =>
    {for (final s in sets) '$ex-$s': true};

Map<String, SetInputValues> _values(int ex, Iterable<int> sets) =>
    {for (final s in sets) '$ex-$s': _v};

void main() {
  group('RE-OPEN and guard windows (controller, fake clock)', () {
    late Duration now;
    late LogExerciseController ctl;
    setUp(() {
      now = Duration.zero;
      ctl = LogExerciseController(clock: () => now);
    });

    LogOutcome logAll(ProviderContainer c, int exIdx) {
      final n = int.tryParse(c.read(activeWorkoutProvider).exercises[exIdx].sets) ?? 3;
      return ctl.log(
        exerciseIndex: exIdx,
        setIndexes: {for (var i = 0; i < n; i++) i},
        logSets: c.read(activeWorkoutProvider.notifier).logSets,
        readState: () => c.read(activeWorkoutProvider),
      );
    }

    LogOutcome reopen(ProviderContainer c, int exIdx) => ctl.reopen(
          exerciseIndex: exIdx,
          readState: () => c.read(activeWorkoutProvider),
          unlogSets: c.read(activeWorkoutProvider.notifier).unlogSets,
        );

    test('R1: a re-open inside kReopenGuard after an advancing LOG is ignored',
        () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A'), ex('B')]));
      expect(logAll(c, 0).kind, LogOutcomeKind.logged);
      now = const Duration(milliseconds: 1000);
      expect(reopen(c, 0).kind, LogOutcomeKind.ignored);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      now = const Duration(milliseconds: 1300);
      expect(reopen(c, 0).kind, LogOutcomeKind.reopened);
      final s = c.read(activeWorkoutProvider);
      expect(s.isExerciseDone(0), isFalse);
      expect(s.checkedSets.keys.where((k) => k.startsWith('0-')), isEmpty);
      expect(s.reopenedExercises, {'A'});
    });

    test('R2: a LOG inside kRevealGuard after a re-open is ignored', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A'), ex('B')]));
      logAll(c, 0);
      now = const Duration(milliseconds: 1300);
      expect(reopen(c, 0).kind, LogOutcomeKind.reopened);
      now = const Duration(milliseconds: 1800); // 500 ms after the re-open
      expect(logAll(c, 0).kind, LogOutcomeKind.ignored);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isFalse);
      now = const Duration(milliseconds: 2100); // 800 ms after
      expect(logAll(c, 0).kind, LogOutcomeKind.logged);
    });

    test('R3: re-open of a NOT-done exercise is a noop and unchecks nothing',
        () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')], checkedSets: _checked(0, [1])));
      expect(reopen(c, 0).kind, LogOutcomeKind.noop);
      final s = c.read(activeWorkoutProvider);
      expect(s.isSetChecked(0, 1), isTrue);
      expect(s.reopenedExercises, isEmpty);
    });

    test('R4: after a LOG that reveals a superset partner, a LOG inside 700 ms '
        'is ignored; with no partner the 400 ms window applies', () {
      final paired = containerWith(ActiveWorkoutData(
          exercises: [ex('A', group: 0), ex('B', group: 0), ex('C')]));
      expect(logAll(paired, 0).revealPartner, 1);
      now = const Duration(milliseconds: 550);
      expect(logAll(paired, 2).kind, LogOutcomeKind.ignored);

      now = Duration.zero;
      ctl = LogExerciseController(clock: () => now);
      final single = containerWith(ActiveWorkoutData(exercises: [ex('A'), ex('C')]));
      expect(logAll(single, 0).revealPartner, isNull);
      now = const Duration(milliseconds: 550);
      expect(logAll(single, 1).kind, LogOutcomeKind.logged);
    });

    test('a re-open in review mode is a noop', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')],
          checkedSets: _checked(0, [0, 1, 2]),
          isSaved: true));
      expect(reopen(c, 0).kind, LogOutcomeKind.noop);
    });
  });

  group('recordCardEdit (the card writer)', () {
    test('values and marks land in ONE state change; clear removes', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A')]));
      final n = c.read(activeWorkoutProvider.notifier);
      var changes = 0;
      c.listen(activeWorkoutProvider, (_, _) => changes++);
      n.recordCardEdit(0,
          values: {0: _v, 1: _v}, mark: {'0-1-weight', '0-2-weight'});
      expect(changes, 1);
      final s = c.read(activeWorkoutProvider);
      expect(s.setInputValues.keys, containsAll(['0-0', '0-1']));
      expect(s.suggestedInputs, {'0-1-weight', '0-2-weight'});
      n.recordCardEdit(0, clear: {'0-1-weight'});
      expect(c.read(activeWorkoutProvider).suggestedInputs, {'0-2-weight'});
      expect(changes, 2);
    });

    test('no write when nothing changes (same values, known marks, absent '
        'clears) or in review mode', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')],
          setInputValues: _values(0, [0]),
          suggestedInputs: const {'0-1-weight'}));
      final n = c.read(activeWorkoutProvider.notifier);
      final before = c.read(activeWorkoutProvider);
      n.recordCardEdit(0,
          values: {0: const SetInputValues(weight: 50, reps: 8)},
          mark: {'0-1-weight'},
          clear: {'0-2-weight'});
      expect(identical(c.read(activeWorkoutProvider), before), isTrue);

      final saved = containerWith(
          ActiveWorkoutData(exercises: [ex('A')], isSaved: true));
      final sBefore = saved.read(activeWorkoutProvider);
      saved
          .read(activeWorkoutProvider.notifier)
          .recordCardEdit(0, values: {0: _v}, mark: {'0-0-weight'});
      expect(identical(saved.read(activeWorkoutProvider), sBefore), isTrue);
    });
  });

  group('unlogSets(reopened:)', () {
    test('a re-open records the name; an UNDO does not', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B')],
          checkedSets: {..._checked(0, [0, 1, 2]), ..._checked(1, [0, 1, 2])}));
      final n = c.read(activeWorkoutProvider.notifier);
      expect(n.unlogSets(1, {0, 1, 2}, exerciseName: 'B'), isTrue);
      expect(c.read(activeWorkoutProvider).reopenedExercises, isEmpty);
      expect(n.unlogSets(0, {0, 1, 2}, exerciseName: 'A', reopened: true),
          isTrue);
      expect(c.read(activeWorkoutProvider).reopenedExercises, {'A'});
    });
  });

  group('suggestedInputs cleanup (three-part keys)', () {
    const all = {
      '0-0-weight', '0-1-duration',
      '1-0-weight', '1-0-duration', '1-0-distance', '1-2-weight',
      '2-0-weight', '2-1-duration', '2-1-distance',
    };

    test('swapExercise drops only the slot\'s keys', () async {
      final dir = await setUpHiveForTests(); // swap resolves the library type
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B'), ex('C')], suggestedInputs: all));
      c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('Z'));
      expect(c.read(activeWorkoutProvider).suggestedInputs,
          {'0-0-weight', '0-1-duration', '2-0-weight', '2-1-duration', '2-1-distance'});
    });

    test('removeExercise (the middle of three) re-indexes keeping the field',
        () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B'), ex('C')], suggestedInputs: all));
      c.read(activeWorkoutProvider.notifier).removeExercise(1);
      expect(c.read(activeWorkoutProvider).suggestedInputs, {
        '0-0-weight', '0-1-duration',
        '1-0-weight', '1-1-duration', '1-1-distance',
      });
    });

    test('removeLastSet drops every field key of the removed set', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B'), ex('C')], suggestedInputs: all));
      c.read(activeWorkoutProvider.notifier).removeLastSet(1); // set 2 of B
      final s = c.read(activeWorkoutProvider).suggestedInputs;
      expect(s.contains('1-2-weight'), isFalse);
      expect(s, containsAll(['1-0-weight', '1-0-duration', '1-0-distance']));
    });

    test('copyWith (the 1×/s timer path) keeps both session sets', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')],
          suggestedInputs: const {'0-0-weight'},
          reopenedExercises: const {'A'}));
      c.read(activeWorkoutProvider.notifier).setElapsedSeconds(42);
      final s = c.read(activeWorkoutProvider);
      expect(s.suggestedInputs, {'0-0-weight'});
      expect(s.reopenedExercises, {'A'});
    });

    test('startWorkout clears both', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')],
          suggestedInputs: const {'0-0-weight'},
          reopenedExercises: const {'A'}));
      fakeAsync((_) {
        c.read(activeWorkoutProvider.notifier).startWorkout(
            WorkoutDayData(dayNumber: 1, name: 'Next', exercises: [ex('N')]));
        final s = c.read(activeWorkoutProvider);
        expect(s.suggestedInputs, isEmpty);
        expect(s.reopenedExercises, isEmpty);
      });
    });
  });

  group('a failed save does not leave LOG dead (B-pass 2)', () {
    test('completeWorkout throws (no Hive): _completing resets, LOG works',
        () async {
      final c = containerWith(ActiveWorkoutData(
        exercises: [ex('Fail A'), ex('Fail B')],
        checkedSets: _checked(0, [0]),
        setInputValues: _values(0, [0]),
      ));
      final n = c.read(activeWorkoutProvider.notifier);
      await expectLater(n.completeWorkout(), throwsA(anything));
      expect(n.isCompleting, isFalse);
      n.logSets(1, {0, 1, 2});
      expect(c.read(activeWorkoutProvider).isExerciseDone(1), isTrue);
    });
  });

  group('re-open marks leave with their exercise (B-pass 4)', () {
    test('swapExercise drops the outgoing name', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B')], reopenedExercises: const {'A', 'B'}));
      c.read(activeWorkoutProvider.notifier).swapExercise(0, ex('Z'));
      expect(c.read(activeWorkoutProvider).reopenedExercises, {'B'});
    });

    test('removeExercise drops the removed name', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B')], reopenedExercises: const {'A', 'B'}));
      c.read(activeWorkoutProvider.notifier).removeExercise(1);
      expect(c.read(activeWorkoutProvider).reopenedExercises, {'A'});
    });
  });

  group('logSets while a save runs (R4B-11)', () {
    test('a LOG during an un-awaited completeWorkout changes nothing',
        () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(
        exercises: [ex('Save A'), ex('Save B')],
        checkedSets: _checked(0, [0, 1, 2]),
        setInputValues: _values(0, [0, 1, 2]),
      ));
      final n = c.read(activeWorkoutProvider.notifier);
      fakeAsync((_) {
        n.completeWorkout();
        expect(n.isCompleting, isTrue);
        final before = c.read(activeWorkoutProvider);
        n.logSets(1, {0, 1, 2});
        expect(identical(c.read(activeWorkoutProvider), before), isTrue);
      });
    });
  });

  // U-D1: the fixture every FINISH-guard assertion shares. A logged (3/3),
  // B untouched, C "done" with every set a warm-up, D `+` after LOG (3 of 4),
  // E one checked key BEYOND its template count (made by the unbounded
  // toggleSet), F re-opened and never logged again.
  ActiveWorkoutData fixture() => ActiveWorkoutData(
        exercises: [
          ex('Parity A'),
          ex('Parity B'),
          ex('Parity C'),
          ex('Parity D', sets: '4'),
          ex('Parity E'),
          ex('Parity F'),
        ],
        checkedSets: {
          ..._checked(0, [0, 1, 2]),
          ..._checked(2, [0, 1, 2]),
          ..._checked(3, [0, 1, 2]),
          ..._checked(4, [0, 1, 2, 3]),
        },
        warmUpSets: _checked(2, [0, 1, 2]),
        setInputValues: {
          ..._values(0, [0, 1, 2]),
          ..._values(2, [0, 1, 2]),
          ..._values(3, [0, 1, 2]),
          ..._values(4, [0, 1, 2, 3]),
          ..._values(5, [0, 1, 2]),
        },
        suggestedInputs: const {'5-0-weight', '5-1-weight', '5-2-weight'},
        reopenedExercises: const {'Parity F'},
      );

  group('the ONE save predicate (U-D1)', () {
    test('saveableSetIndexes / workingSetCounts / finishGuard on the fixture',
        () {
      final d = fixture();
      expect(d.saveableSetIndexes(0), [0, 1, 2]);
      expect(d.saveableSetIndexes(1), isEmpty);
      expect(d.saveableSetIndexes(2), isEmpty, reason: 'warm-ups never save');
      expect(d.saveableSetIndexes(3), [0, 1, 2]);
      expect(d.saveableSetIndexes(4), [0, 1, 2, 3],
          reason: 'a checked key beyond the template count is saved');
      expect(d.saveableSetIndexes(5), isEmpty);
      expect(d.hasSaveableSet, isTrue);

      final counts = workingSetCounts(d);
      expect(counts.saved, 10);
      expect(counts.total, 3 + 3 + 0 + 4 + 3 + 3);

      final g = finishGuard(d);
      expect(g.reopenedUnsaved, ['Parity F']);
      expect(g.typedUnsaved, isEmpty);
      expect(g.skipped, ['Parity B', 'Parity C']);
      expect([for (final p in g.partial) '${p.name} ${p.saved}/${p.working}'],
          ['Parity D 3/4']);
    });
  });

  group('U-D1b: parity with the REAL completeWorkout', () {
    test('what completeWorkout writes is exactly saveableSetIndexes', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final seed = fixture();
      final c = containerWith(seed);
      await c.read(activeWorkoutProvider.notifier).completeWorkout();

      final saved = <String, int>{};
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys) {
        if (!k.toString().startsWith('exlog_')) continue;
        final raw = box.get(k) as Map;
        saved[raw['exercise_name'] as String] = (raw['sets'] as List).length;
      }
      // Absolute: A 3, D 3 (of 4), E 4 (one beyond the template); B, C, F
      // (untouched, all warm-up, re-opened) are not written.
      expect(saved, {'Parity A': 3, 'Parity D': 3, 'Parity E': 4});
      // And it equals the shared predicate.
      expect(saved, {
        for (var i = 0; i < seed.exercises.length; i++)
          if (seed.saveableSetIndexes(i).isNotEmpty)
            seed.exercises[i].name: seed.saveableSetIndexes(i).length,
      });
    });
  });

  group('U-E1: zero saveable sets never complete (OI-361)', () {
    Future<
        ({
          ProviderContainer c,
          Map<String, dynamic> progressBefore,
        })> run(ActiveWorkoutData seed) async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final before =
          Map<String, dynamic>.from(UserRepository.instance.getProgress() ?? {});
      final c = containerWith(seed);
      await c.read(activeWorkoutProvider.notifier).completeWorkout();
      return (c: c, progressBefore: before);
    }

    bool anyLog(String prefix) => HiveService.instance.workoutBox.keys
        .any((k) => k.toString().startsWith(prefix));

    for (final entry in {
      'nothing checked': ActiveWorkoutData(
          exercises: [ex('Zero A')], setInputValues: _values(0, [0, 1, 2])),
      'only warm-ups checked': ActiveWorkoutData(
          exercises: [ex('Zero A')],
          checkedSets: _checked(0, [0, 1]),
          warmUpSets: _checked(0, [0, 1]),
          setInputValues: _values(0, [0, 1, 2])),
      'a checked set with no captured values': ActiveWorkoutData(
          exercises: [ex('Zero A')], checkedSets: _checked(0, [0])),
    }.entries) {
      test('${entry.key}: no wlog/exlog, counters untouched, not complete',
          () async {
        final r = await run(entry.value);
        final s = r.c.read(activeWorkoutProvider);
        expect(s.isComplete, isFalse);
        expect(s.isSaved, isFalse);
        expect(r.c.read(activeWorkoutProvider.notifier).isCompleting, isFalse,
            reason: 'the guard returns before the save starts');
        expect(anyLog('wlog_'), isFalse);
        expect(anyLog('exlog_'), isFalse);
        expect(
            (UserRepository.instance.getProgress() ?? {})['total_workouts_done'],
            r.progressBefore['total_workouts_done']);
      });
    }

    test('one saveable set completes and counts the workout', () async {
      final r = await run(ActiveWorkoutData(
          exercises: [ex('One A')],
          checkedSets: _checked(0, [0]),
          setInputValues: _values(0, [0])));
      expect(r.c.read(activeWorkoutProvider).isComplete, isTrue);
      expect(anyLog('exlog_'), isTrue);
      expect(
          (UserRepository.instance.getProgress() ?? {})['total_workouts_done'],
          ((r.progressBefore['total_workouts_done'] as int?) ?? 0) + 1);
    });

    test('the guard runs before the timer cancel: the session timer keeps '
        'running after a refused completeWorkout (R7-03)', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Timer A')]));
      final n = c.read(activeWorkoutProvider.notifier);
      fakeAsync((fa) {
        n.startWorkout(
            WorkoutDayData(dayNumber: 1, name: 'T', exercises: [ex('Timer A')]));
        expect(fa.periodicTimerCount, 1);
        n.completeWorkout(); // zero saveable sets: refused
        expect(fa.periodicTimerCount, 1);
        // Discriminates: with one saveable set the same call cancels it.
        n.recordCardEdit(0, values: {0: _v});
        n.logSets(0, {0});
        n.completeWorkout();
        expect(fa.periodicTimerCount, 0);
      });
    });

    test('review mode (isSaved) still marks complete', () async {
      final r = await run(
          ActiveWorkoutData(exercises: [ex('Review A')], isSaved: true));
      expect(r.c.read(activeWorkoutProvider).isComplete, isTrue);
    });
  });

  test('(the fixture key format matches the provider)', () {
    expect(suggestedKey(5, 0, SetField.weight), '5-0-weight');
    expect(File('lib/features/train/providers/train_provider.dart').existsSync(),
        isTrue);
  });
}
