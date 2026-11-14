// SoT concept `active_workout_exercise_order` — behavioral contract for the
// in-workout MOVE (docs/plans/active-workout-swap-move.md Task 1): the pure
// slide + remap `moveExerciseInSession` and its one writer
// `ActiveWorkoutNotifier.applyExerciseMove` (real notifier, seeded state).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/exercise_move_logic.dart';

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

/// Every set of exercise [i] checked (3 sets by default), so it is done.
Map<String, bool> doneSets(int i, {int sets = 3}) =>
    {for (var s = 0; s < sets; s++) '$i-$s': true};

List<String> names(List<ExerciseData> l) => [for (final e in l) e.name];

ActiveWorkoutData abcd({Map<String, bool> checked = const {}}) =>
    ActiveWorkoutData(
      exercises: [ex('A'), ex('B'), ex('C'), ex('D')],
      checkedSets: checked,
    );

/// Apply [r] onto [d] the way the notifier does, for pure round trips.
ActiveWorkoutData applied(ActiveWorkoutData d, ExerciseMoveResult r) =>
    d.copyWith(
      exercises: r.exercises,
      checkedSets: r.checkedSets,
      warmUpSets: r.warmUpSets,
      setInputValues: r.setInputValues,
      suggestedInputs: r.suggestedInputs,
    );

void main() {
  group('exercise move (pure)', () {
    test('slide up lands the mover at the target index, others shift down', () {
      final r = moveExerciseInSession(abcd(), from: 3, to: 1)!;
      expect(names(r.exercises), ['A', 'D', 'B', 'C']);
    });

    test('slide down lands the mover at the target index, others shift up', () {
      final r = moveExerciseInSession(abcd(), from: 0, to: 2)!;
      expect(names(r.exercises), ['B', 'C', 'A', 'D']);
    });

    test('adjacent move', () {
      final r = moveExerciseInSession(abcd(), from: 2, to: 1)!;
      expect(names(r.exercises), ['A', 'C', 'B', 'D']);
    });

    test('null for from==to, out of range, done mover, done target', () {
      expect(moveExerciseInSession(abcd(), from: 1, to: 1), isNull);
      expect(moveExerciseInSession(abcd(), from: 4, to: 1), isNull);
      expect(moveExerciseInSession(abcd(), from: 0, to: -1), isNull);
      final cDone = abcd(checked: doneSets(2));
      expect(moveExerciseInSession(cDone, from: 2, to: 0), isNull,
          reason: 'a done exercise is locked');
      expect(moveExerciseInSession(cDone, from: 3, to: 2), isNull,
          reason: 'a done exercise is not a target');
    });

    test('set state follows the exercise (partly logged)', () {
      final d = ActiveWorkoutData(
        exercises: [ex('A'), ex('B'), ex('C'), ex('D')],
        checkedSets: const {'3-0': true, '1-0': true},
        warmUpSets: const {'3-1': true},
        setInputValues: const {'3-0': SetInputValues(weight: 40, reps: 10)},
        suggestedInputs: const {'3-0-weight', '1-2-duration'},
        reopenedExercises: const {'B'},
      );
      final typed = d.setInputValues['3-0'];
      final r = moveExerciseInSession(d, from: 3, to: 1)!;
      expect(names(r.exercises), ['A', 'D', 'B', 'C']);
      expect(r.checkedSets, {'1-0': true, '2-0': true});
      expect(r.warmUpSets, {'1-1': true});
      expect(r.setInputValues.keys, ['1-0']);
      expect(identical(r.setInputValues['1-0'], typed), isTrue);
      expect(r.suggestedInputs, {'1-0-weight', '2-2-duration'});
      // reopenedExercises is keyed by NAME: a move never touches it.
      expect(applied(d, r).reopenedExercises, {'B'});
    });

    test('a done exercise in between keeps its order and its sets', () {
      final d = abcd(checked: doneSets(1));
      final r = moveExerciseInSession(d, from: 3, to: 0)!;
      expect(names(r.exercises), ['D', 'A', 'B', 'C']);
      expect(r.checkedSets, doneSets(2));
    });

    test('superset tag travels with the mover, the partner is untouched', () {
      final d = ActiveWorkoutData(exercises: [
        ex('Bench'),
        ex('Incline', group: 0),
        ex('OHP'),
        ex('Row', group: 0),
      ]);
      final r = moveExerciseInSession(d, from: 3, to: 1)!;
      expect(names(r.exercises), ['Bench', 'Row', 'Incline', 'OHP']);
      expect([for (final e in r.exercises) e.supersetGroup], [null, 0, 0, null]);
    });

    test('duplicate names are moved by index, never by name (OI-358)', () {
      final d = ActiveWorkoutData(
        exercises: [ex('A', sets: '3'), ex('A', sets: '4'), ex('B')],
        checkedSets: const {'0-0': true},
      );
      final r = moveExerciseInSession(d, from: 2, to: 0)!;
      expect(names(r.exercises), ['B', 'A', 'A']);
      // B, then the 3-set A, then the 4-set A: the two A's kept their order.
      expect([for (final e in r.exercises) e.sets], ['3', '3', '4']);
      expect(r.checkedSets, {'1-0': true},
          reason: 'the first A carried its check to index 1');
    });

    test('targets, candidates and roles', () {
      final d = abcd(checked: doneSets(2));
      expect(moveTargets(d, 0), [1, 3]);
      expect(moveTargets(d, 2), isEmpty, reason: 'a done exercise cannot move');
      expect(hasMoveCandidates(d), isTrue);
      final oneLeft = ActiveWorkoutData(
        exercises: [ex('A'), ex('B')],
        checkedSets: doneSets(0),
      );
      expect(hasMoveCandidates(oneLeft), isFalse);
      expect(moveRoleFor(d, 0, 0), MoveRole.source);
      expect(moveRoleFor(d, 0, 1), MoveRole.target);
      expect(moveRoleFor(d, 0, 2), MoveRole.none, reason: 'done');
      expect(moveRoleFor(d, null, 1), MoveRole.none);
      expect(moveRoleFor(d, 9, 1), MoveRole.none, reason: 'stale source');
    });

    test('undo is the exact inverse', () {
      final d = ActiveWorkoutData(
        exercises: [ex('A'), ex('B'), ex('C'), ex('D')],
        checkedSets: const {'3-0': true, '1-1': true},
        warmUpSets: const {'0-0': true},
        setInputValues: const {'3-0': SetInputValues(weight: 20, reps: 5)},
        suggestedInputs: const {'2-1-weight'},
      );
      final moved = applied(d, moveExerciseInSession(d, from: 3, to: 1)!);
      final back = moveExerciseInSession(moved,
          from: 1, to: 3, requireMovable: false)!;
      expect(names(back.exercises), names(d.exercises));
      expect(back.checkedSets, d.checkedSets);
      expect(back.warmUpSets, d.warmUpSets);
      expect(back.setInputValues, d.setInputValues);
      expect(back.suggestedInputs, d.suggestedInputs);
    });

    test('undo still works when a done exercise sits in the vacated slot', () {
      // Up: D 3→1 pushes done C into slot 3.
      final up = abcd(checked: doneSets(2));
      final upMoved = applied(up, moveExerciseInSession(up, from: 3, to: 1)!);
      expect(names(upMoved.exercises), ['A', 'D', 'B', 'C']);
      expect(moveExerciseInSession(upMoved, from: 1, to: 3), isNull,
          reason: 'the default eligibility would refuse the inverse');
      final upBack = moveExerciseInSession(upMoved,
          from: 1, to: 3, requireMovable: false)!;
      expect(names(upBack.exercises), ['A', 'B', 'C', 'D']);
      expect(upBack.checkedSets, doneSets(2));

      // Down: A 0→2 pulls done B into slot 0.
      final down = ActiveWorkoutData(
        exercises: [ex('A'), ex('B'), ex('C')],
        checkedSets: doneSets(1),
      );
      final downMoved =
          applied(down, moveExerciseInSession(down, from: 0, to: 2)!);
      expect(names(downMoved.exercises), ['B', 'C', 'A']);
      expect(moveExerciseInSession(downMoved, from: 2, to: 0), isNull);
      final downBack = moveExerciseInSession(downMoved,
          from: 2, to: 0, requireMovable: false)!;
      expect(names(downBack.exercises), ['A', 'B', 'C']);
      expect(downBack.checkedSets, doneSets(1));
    });

    test('moveUndoApplicable', () {
      final d = abcd();
      expect(moveUndoApplicable(d, exerciseName: 'B', movedTo: 1), isTrue);
      expect(moveUndoApplicable(d, exerciseName: 'D', movedTo: 1), isFalse,
          reason: 'another exercise sits there now');
      expect(
          moveUndoApplicable(abcd(checked: doneSets(1)),
              exerciseName: 'B', movedTo: 1),
          isFalse,
          reason: 'the mover was completed since');
      expect(moveUndoApplicable(d, exerciseName: 'B', movedTo: 9), isFalse);
      expect(moveUndoApplicable(d, exerciseName: 'B', movedTo: -1), isFalse);
    });
  });

  group('applyExerciseMove (notifier)', () {
    test('one state change; refuses a wrong-length result', () {
      final c = containerWith(abcd());
      final n = c.read(activeWorkoutProvider.notifier);
      var changes = 0;
      c.listen(activeWorkoutProvider, (_, _) => changes++);
      final r = moveExerciseInSession(c.read(activeWorkoutProvider),
          from: 3, to: 1)!;
      expect(n.applyExerciseMove(r), isTrue);
      expect(changes, 1);
      expect(names(c.read(activeWorkoutProvider).exercises),
          ['A', 'D', 'B', 'C']);

      final before = c.read(activeWorkoutProvider);
      final short = ExerciseMoveResult(
        basedOn: before,
        exercises: [ex('A')],
        checkedSets: const {},
        warmUpSets: const {},
        setInputValues: const {},
        suggestedInputs: const {},
      );
      expect(n.applyExerciseMove(short), isFalse);
      expect(identical(c.read(activeWorkoutProvider), before), isTrue);
    });

    test('refuses a result computed before a later change (no silent revert)',
        () {
      final c = containerWith(abcd());
      final n = c.read(activeWorkoutProvider.notifier);
      final r = moveExerciseInSession(c.read(activeWorkoutProvider),
          from: 3, to: 1)!;
      n.toggleSet(0, 0); // same length, so a length check cannot see it
      final before = c.read(activeWorkoutProvider);
      expect(before.isSetChecked(0, 0), isTrue);
      expect(n.applyExerciseMove(r), isFalse);
      expect(identical(c.read(activeWorkoutProvider), before), isTrue,
          reason: 'the toggle must survive');
      expect(names(c.read(activeWorkoutProvider).exercises),
          ['A', 'B', 'C', 'D']);
    });

    test('clears superset-grouping mode in the same change', () {
      final c = containerWith(ActiveWorkoutData(
        exercises: [ex('A'), ex('B'), ex('C')],
        isSupersetGroupMode: true,
        supersetGroupingSourceIndex: 2,
      ));
      final r = moveExerciseInSession(c.read(activeWorkoutProvider),
          from: 2, to: 0)!;
      expect(c.read(activeWorkoutProvider.notifier).applyExerciseMove(r),
          isTrue);
      final s = c.read(activeWorkoutProvider);
      expect(s.isSupersetGroupMode, isFalse);
      expect(s.supersetGroupingSourceIndex, isNull);
    });

    test('refuses in review mode and after completion', () {
      for (final seed in [
        abcd().copyWith(isSaved: true),
        abcd().copyWith(isComplete: true),
      ]) {
        final c = containerWith(seed);
        final before = c.read(activeWorkoutProvider);
        final r = moveExerciseInSession(before, from: 3, to: 1)!;
        expect(c.read(activeWorkoutProvider.notifier).applyExerciseMove(r),
            isFalse);
        expect(identical(c.read(activeWorkoutProvider), before), isTrue);
      }
    });

    test('refuses while an un-awaited completeWorkout is saving', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final c = containerWith(ActiveWorkoutData(
        exercises: [ex('Race A'), ex('Race B'), ex('Race C')],
        checkedSets: const {'0-0': true, '0-1': true, '0-2': true},
        setInputValues: const {
          '0-0': SetInputValues(weight: 50, reps: 8),
          '0-1': SetInputValues(weight: 50, reps: 8),
          '0-2': SetInputValues(weight: 50, reps: 8),
        },
      ));
      final n = c.read(activeWorkoutProvider.notifier);
      fakeAsync((_) {
        final r = moveExerciseInSession(c.read(activeWorkoutProvider),
            from: 2, to: 1)!;
        n.completeWorkout(); // the finish dialog does not await it either
        expect(n.isCompleting, isTrue);
        final before = c.read(activeWorkoutProvider);
        expect(n.applyExerciseMove(r), isFalse);
        expect(identical(c.read(activeWorkoutProvider), before), isTrue);
        // Never flushed: the save's awaits stay parked in the fake zone.
      });
    });

    test('session-only: the stored schedule row is not reordered', () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));
      final date = DateTime(2026, 10, 21);
      final key = 'schedule_${istDateStr(date)}';
      final row = <String, dynamic>{
        'exercises': [
          for (final n in ['A', 'B', 'C', 'D']) {'exercise_name': n},
        ],
      };
      await HiveService.instance.workoutBox.put(key, row);
      final stored = HiveService.instance.workoutBox.get(key).toString();

      final c = containerWith(ActiveWorkoutData(
        workoutDay: WorkoutDayData(
            dayNumber: 1,
            name: 'Push',
            date: date,
            exercises: [ex('A'), ex('B'), ex('C'), ex('D')]),
        exercises: [ex('A'), ex('B'), ex('C'), ex('D')],
      ));
      final r = moveExerciseInSession(c.read(activeWorkoutProvider),
          from: 3, to: 0)!;
      expect(c.read(activeWorkoutProvider.notifier).applyExerciseMove(r),
          isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(HiveService.instance.workoutBox.get(key).toString(), stored);
    });
  });
}
