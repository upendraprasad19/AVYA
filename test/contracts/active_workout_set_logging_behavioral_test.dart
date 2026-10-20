// SoT concept `active_workout_set_logging` — behavioral contract for the
// one-LOG-per-exercise writer `ActiveWorkoutNotifier.logSets` and the screen's
// `LogExerciseController` (real notifier, fake monotonic clock).
// Plan docs/plans/active-workout-log-exercise.md §6 tests 2, 3, 6, 8, 9, 12,
// 13, 15.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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

ProviderContainer containerWith(ActiveWorkoutData seed) {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    activeWorkoutProvider.overrideWith(() => _SeededNotifier(seed)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('logSets (writer)', () {
    test('adds every given set in one state change and never unchecks', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('Bench')], checkedSets: const {'0-1': true}));
      var changes = 0;
      c.listen(activeWorkoutProvider, (_, _) => changes++);
      c.read(activeWorkoutProvider.notifier).logSets(0, {0, 1, 2});
      final s = c.read(activeWorkoutProvider);
      expect(s.checkedSets, {'0-0': true, '0-1': true, '0-2': true});
      expect(changes, 1);
      // A second call (double tap, no pump between) changes nothing: a toggle
      // loop here would UNCHECK every set.
      c.read(activeWorkoutProvider.notifier).logSets(0, {0, 1, 2});
      expect(c.read(activeWorkoutProvider).checkedSets.length, 3);
      expect(changes, 1);
    });

    test('bounds: bad exercise / set index is ignored, never a phantom set',
        () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Bench')]));
      final n = c.read(activeWorkoutProvider.notifier);
      final before = c.read(activeWorkoutProvider);
      n.logSets(5, {0});
      n.logSets(-1, {0});
      n.logSets(0, {3, 7, -1});
      n.logSets(0, {});
      expect(identical(c.read(activeWorkoutProvider), before), isTrue);
      n.logSets(0, {2, 9});
      expect(c.read(activeWorkoutProvider).checkedSets, {'0-2': true});
    });

    test('no-op on a saved or completed session', () {
      for (final seed in [
        ActiveWorkoutData(exercises: [ex('Bench')], isSaved: true),
        ActiveWorkoutData(exercises: [ex('Bench')], isComplete: true),
      ]) {
        final c = containerWith(seed);
        c.read(activeWorkoutProvider.notifier).logSets(0, {0, 1, 2});
        expect(c.read(activeWorkoutProvider).checkedSets, isEmpty);
      }
    });

    test('same checkedSets / completedSets / volume as N per-set toggles', () {
      for (final type in [
        'weight_reps',
        'bodyweight_reps',
        'timed',
        'cardio',
        'distance'
      ]) {
        const values = {
          '0-0': SetInputValues(weight: 60, reps: 8),
          '0-1': SetInputValues(weight: 60, reps: 7),
          '0-2': SetInputValues(weight: 60, reps: 6),
        };
        final seed = ActiveWorkoutData(
            exercises: [ex('A', type: type)], setInputValues: values);
        final a = containerWith(seed);
        final b = containerWith(seed);
        for (var i = 0; i < 3; i++) {
          a.read(activeWorkoutProvider.notifier).toggleSet(0, i);
        }
        b.read(activeWorkoutProvider.notifier).logSets(0, {0, 1, 2});
        final sa = a.read(activeWorkoutProvider);
        final sb = b.read(activeWorkoutProvider);
        expect(sb.checkedSets, sa.checkedSets, reason: type);
        expect(sb.completedSets, sa.completedSets, reason: type);
        expect(sb.liveVolumeKg, sa.liveVolumeKg, reason: type);
        expect(sb.isExerciseDone(0), isTrue, reason: type);
      }
    });

    test('warm-up sets are logged too, so the exercise becomes done; '
        'completedSets still excludes them', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('Bench')], warmUpSets: const {'0-0': true}));
      final toLog = setsToLog(
          exerciseIndex: 0,
          numSets: 3,
          checkedSets: c.read(activeWorkoutProvider).checkedSets);
      c.read(activeWorkoutProvider.notifier).logSets(0, toLog);
      final s = c.read(activeWorkoutProvider);
      expect(s.isExerciseDone(0), isTrue);
      expect(s.completedSets, 2);
    });

    test('interplay with removeLastSet / addSet / toggleSet', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('Bench')]));
      final n = c.read(activeWorkoutProvider.notifier);
      n.logSets(0, {0, 1, 2});
      n.removeLastSet(0);
      expect(c.read(activeWorkoutProvider).checkedSets, {'0-0': true, '0-1': true});
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      n.addSet(0);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isFalse);
      n.logSets(0, {2});
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      n.toggleSet(0, 1);
      expect(c.read(activeWorkoutProvider).isSetChecked(0, 1), isFalse);
    });

    test('swap wipes the logged sets of that slot, then LOG works (9b1e7a)',
        () async {
      // swapExercise resolves the logging type through exerciseBox.
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A'), ex('B')]));
      final n = c.read(activeWorkoutProvider.notifier);
      n.logSets(0, {0, 1, 2});
      n.logSets(1, {0});
      n.swapExercise(0, ex('Push Up', type: 'bodyweight_reps'));
      final s = c.read(activeWorkoutProvider);
      expect(s.isSetChecked(0, 0), isFalse);
      expect(s.isSetChecked(1, 0), isTrue);
      n.logSets(0, {0, 1, 2});
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
    });
  });

  group('LogExerciseController (real notifier, fake monotonic clock)', () {
    late Duration now;
    late LogExerciseController ctl;
    setUp(() {
      now = const Duration(seconds: 100);
      ctl = LogExerciseController(clock: () => now);
    });

    LogOutcome log(ProviderContainer c, int exIdx) {
      final s = c.read(activeWorkoutProvider);
      return ctl.log(
        exerciseIndex: exIdx,
        setIndexes: setsToLog(
            exerciseIndex: exIdx,
            numSets: int.parse(s.exercises[exIdx].sets),
            checkedSets: s.checkedSets),
        logSets: c.read(activeWorkoutProvider.notifier).logSets,
        readState: () => c.read(activeWorkoutProvider),
      );
    }

    test('LOG advances (clear focus); a second LOG inside 400 ms is ignored',
        () {
      final c = containerWith(
          ActiveWorkoutData(exercises: [ex('A'), ex('B'), ex('C')]));
      final first = log(c, 0);
      expect(first.kind, LogOutcomeKind.logged);
      expect(first.clearFocus, isTrue);
      // The next exercise's LOG lands under the same thumb.
      now += const Duration(milliseconds: 150);
      expect(log(c, 1).kind, LogOutcomeKind.ignored);
      expect(c.read(activeWorkoutProvider).isExerciseDone(1), isFalse);
      now += const Duration(milliseconds: 300);
      expect(log(c, 1).kind, LogOutcomeKind.logged);
      expect(c.read(activeWorkoutProvider).isExerciseDone(1), isTrue);
    });

    test('advance: the first non-done exercise from the top is next', () {
      final c = containerWith(
          ActiveWorkoutData(exercises: [ex('A'), ex('B'), ex('C')]));
      expect(log(c, 1).clearFocus, isTrue);
      final s = c.read(activeWorkoutProvider);
      final firstOpen = [
        for (var i = 0; i < s.exercises.length; i++)
          if (!s.isExerciseDone(i)) i
      ].first;
      expect(firstOpen, 0);
    });

    test('last exercise: logged and done, nothing else to advance to', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A')]));
      final o = log(c, 0);
      expect(o.kind, LogOutcomeKind.logged);
      expect(o.revealPartner, isNull);
      expect(c.read(activeWorkoutProvider).isExerciseDone(0), isTrue);
      expect(c.read(activeWorkoutProvider).isComplete, isFalse,
          reason: 'LOG never finishes the workout or opens a sheet');
    });

    test('superset: each exercise keeps its own LOG; the open partner is '
        'revealed (D2)', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A', group: 0), ex('B', group: 0), ex('C')]));
      final o = log(c, 0);
      expect(o.revealPartner, 1);
      expect(c.read(activeWorkoutProvider).isExerciseDone(1), isFalse);
    });

    test('noop: nothing to log, or a saved session', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A')],
          checkedSets: const {'0-0': true, '0-1': true, '0-2': true}));
      expect(log(c, 0).kind, LogOutcomeKind.noop);
      final saved =
          containerWith(ActiveWorkoutData(exercises: [ex('A')], isSaved: true));
      expect(log(saved, 0).kind, LogOutcomeKind.noop);
    });

    test('stale indexes (already logged / out of range) are a noop and never '
        'stamp the guard', () {
      final c = containerWith(ActiveWorkoutData(
          exercises: [ex('A'), ex('B')],
          checkedSets: const {'0-0': true, '0-1': true, '0-2': true}));
      final n = c.read(activeWorkoutProvider.notifier);
      for (final stale in [
        {5},
        {0}
      ]) {
        final o = ctl.log(
            exerciseIndex: 0,
            setIndexes: stale,
            logSets: n.logSets,
            readState: () => c.read(activeWorkoutProvider));
        expect(o.kind, LogOutcomeKind.noop);
      }
      now += const Duration(milliseconds: 100);
      expect(log(c, 1).kind, LogOutcomeKind.logged,
          reason: 'a noop must not arm the 400 ms guard');
    });

    test('a partial LOG (exercise not done) does not stamp the guard', () {
      final c = containerWith(ActiveWorkoutData(exercises: [ex('A'), ex('B')]));
      final n = c.read(activeWorkoutProvider.notifier);
      final o = ctl.log(
          exerciseIndex: 0,
          setIndexes: {0},
          logSets: n.logSets,
          readState: () => c.read(activeWorkoutProvider));
      expect(o.kind, LogOutcomeKind.logged);
      expect(o.clearFocus, isFalse);
      now += const Duration(milliseconds: 50);
      expect(log(c, 1).kind, LogOutcomeKind.logged);
    });

    test('frozen wall clock does not swallow LOG (monotonic seam)', () {
      // A clock that never moves (what `nowWall()` does under the dev clock
      // override) would ignore every LOG after the first advance forever; the
      // screen therefore feeds the controller a Stopwatch. Proven here with a
      // clock that keeps ticking even though no wall time is consulted.
      final c = containerWith(
          ActiveWorkoutData(exercises: [ex('A'), ex('B')]));
      log(c, 0);
      now += const Duration(seconds: 5);
      expect(log(c, 1).kind, LogOutcomeKind.logged);
    });
  });

  group('screen wiring (source, presence only — behaviour is above)', () {
    final screen = File('lib/features/train/screens/active_workout/screen.dart')
        .readAsStringSync();
    test('the screen delegates LOG to the controller on a monotonic clock', () {
      expect(screen.contains('_logController.log('), isTrue);
      expect(screen.contains('LogExerciseController(clock: () => _logClock.elapsed)'),
          isTrue);
      final start = screen.indexOf('final Stopwatch _logClock');
      final end = screen.indexOf('return outcome.kind;');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      expect(screen.substring(start, end).contains('nowWall('), isFalse,
          reason: 'the guard must never read the frozen-able wall clock');
    });
    test('the screen applies the outcome: clears focus, reveals the partner '
        '(presence only; the decision itself is tested on the controller)', () {
      final start = screen.indexOf('LogOutcomeKind _onLogExercise(');
      final end = screen.indexOf('return outcome.kind;');
      final body = screen.substring(start, end);
      expect(
          RegExp(r'if \(outcome\.clearFocus\) \{\s*setState\(\(\) \{\s*_focusedExerciseIndex = null;')
              .hasMatch(body),
          isTrue);
      expect(body.contains('final partner = outcome.revealPartner;'), isTrue);
      expect(body.contains('_scrollToExercise(partner)'), isTrue);
    });

    test('the flag is read once per build and only then passes the callback',
        () {
      expect(
          RegExp(r'final logMode = LogExerciseFlags\.logExerciseButtonEnabled;')
              .allMatches(screen)
              .length,
          1);
      expect(screen.contains('onLogExercise: logMode'), isTrue);
    });
  });
}
