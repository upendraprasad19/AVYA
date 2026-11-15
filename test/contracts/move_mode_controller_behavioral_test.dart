// MoveModeController (docs/plans/active-workout-swap-move.md Task 4): every
// move-mode and hint decision the Active Workout screen makes, as plain Dart.
// The screen is a thin shell over these (it cannot be pumped in tests).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/move_mode_controller.dart';

ExerciseData ex(String name) => ExerciseData(
    name: name, sets: '3', reps: '8', weight: '0kg', rest: '90s',
    loggingType: 'weight_reps');

Map<String, bool> done(int i) => {for (var s = 0; s < 3; s++) '$i-$s': true};

List<String> names(List<ExerciseData> l) => [for (final e in l) e.name];

ActiveWorkoutData abcd({Map<String, bool> checked = const {}}) =>
    ActiveWorkoutData(
        exercises: [ex('A'), ex('B'), ex('C'), ex('D')], checkedSets: checked);

ActiveWorkoutData applied(ActiveWorkoutData d, ExerciseMoveResult r) =>
    d.copyWith(
      exercises: r.exercises,
      checkedSets: r.checkedSets,
      warmUpSets: r.warmUpSets,
      setInputValues: r.setInputValues,
      suggestedInputs: r.suggestedInputs,
    );

void main() {
  group('enter / cancel', () {
    test('enters on a movable exercise and toggles off on the source', () {
      final m = MoveModeController(hintSeen: true);
      expect(m.active, isFalse);
      expect(m.enter(abcd(), 2), isTrue);
      expect(m.active, isTrue);
      expect(m.sourceIndex, 2);
      expect(m.enter(abcd(), 2), isFalse, reason: 'second tap cancels');
      expect(m.active, isFalse);
      expect(m.sourceIndex, isNull);
    });

    test('refuses a done exercise, a lone candidate and grouping mode', () {
      final m = MoveModeController(hintSeen: true);
      expect(m.enter(abcd(checked: done(1)), 1), isFalse);
      expect(
          m.enter(
              ActiveWorkoutData(
                  exercises: [ex('A'), ex('B')], checkedSets: done(0)),
              1),
          isFalse);
      expect(m.enter(abcd().copyWith(isSupersetGroupMode: true), 0), isFalse);
      expect(m.active, isFalse);
    });

    test('cancel leaves move mode', () {
      final m = MoveModeController(hintSeen: true)..enter(abcd(), 0);
      m.cancel();
      expect(m.active, isFalse);
    });
  });

  group('place / undo', () {
    test('place returns the placement and leaves move mode', () {
      final m = MoveModeController(hintSeen: true)..enter(abcd(), 3);
      final p = m.place(abcd(), 1)!;
      expect(m.active, isFalse);
      expect((p.exerciseName, p.from, p.to), ('D', 3, 1));
      expect(names(p.result.exercises), ['A', 'D', 'B', 'C']);
    });

    test('an invalid place leaves move mode and returns null', () {
      final d = abcd(checked: done(1));
      final m = MoveModeController(hintSeen: true)..enter(d, 3);
      expect(m.place(d, 1), isNull, reason: 'done target');
      expect(m.active, isFalse);
      expect(MoveModeController(hintSeen: true).place(d, 0), isNull,
          reason: 'not in move mode');
    });

    test('undo restores exactly, with a done exercise in the vacated slot', () {
      final d = abcd(checked: done(2));
      final m = MoveModeController(hintSeen: true)..enter(d, 3);
      final p = m.place(d, 1)!;
      final moved = applied(d, p.result);
      expect(names(moved.exercises), ['A', 'D', 'B', 'C']);
      final back = m.undo(moved, p)!;
      expect(names(back.exercises), ['A', 'B', 'C', 'D']);
      expect(back.checkedSets, done(2));
    });

    test('undo refuses once the mover was completed or replaced', () {
      final d = abcd();
      final m = MoveModeController(hintSeen: true)..enter(d, 3);
      final p = m.place(d, 1)!;
      final moved = applied(d, p.result);
      expect(m.undo(moved.copyWith(checkedSets: done(1)), p), isNull,
          reason: 'the moved exercise is done now');
      final other = moved.copyWith(
          exercises: [...moved.exercises]..[1] = ex('Swapped In'));
      expect(m.undo(other, p), isNull, reason: 'another exercise sits there');
    });

    test('undo leaves a slot outside [to..from] and its sets untouched', () {
      final d = ActiveWorkoutData(
          exercises: [ex('A'), ex('B'), ex('C'), ex('D'), ex('E')]);
      final m = MoveModeController(hintSeen: true)..enter(d, 3);
      final p = m.place(d, 1)!; // A D B C E
      // Something happens to E (index 4, outside 1..3) before the UNDO.
      final edited =
          applied(d, p.result).copyWith(checkedSets: const {'4-0': true});
      final back = m.undo(edited, p)!;
      expect(names(back.exercises), ['A', 'B', 'C', 'D', 'E']);
      expect(back.checkedSets, {'4-0': true});
    });
  });

  group('hint', () {
    test('shown on a fresh session, never while moving', () {
      final m = MoveModeController(hintSeen: false);
      expect(m.showHint(abcd()), isTrue);
      m.enter(abcd(), 0);
      expect(m.showHint(abcd()), isFalse);
    });

    test('dismissHint reports true once, then never', () {
      final m = MoveModeController(hintSeen: false);
      expect(m.dismissHint(), isTrue);
      expect(m.dismissHint(), isFalse);
      expect(m.showHint(abcd()), isFalse);
      expect(MoveModeController(hintSeen: true).dismissHint(), isFalse,
          reason: 'already seen on this account: never re-persist');
    });

    test('a checked set retires the hint only if it was actually shown', () {
      final warm = abcd().copyWith(
          checkedSets: const {'0-0': true}, warmUpSets: const {'0-0': true});

      final neverShown = MoveModeController(hintSeen: false);
      expect(neverShown.shouldDismissHintOnData(warm), isFalse,
          reason: 'a one-exercise day must not burn the flag');

      final shown = MoveModeController(hintSeen: false);
      expect(shown.showHint(abcd()), isTrue);
      expect(shown.shouldDismissHintOnData(abcd()), isFalse,
          reason: 'nothing checked yet');
      expect(shown.shouldDismissHintOnData(warm), isTrue,
          reason: 'a warm-up counts as logged');
      shown.dismissHint();
      expect(shown.shouldDismissHintOnData(warm), isFalse);
    });
  });
}
