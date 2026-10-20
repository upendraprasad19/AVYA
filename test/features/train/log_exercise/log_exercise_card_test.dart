// One-LOG-per-exercise card behaviour through the real `_ExerciseCard`
// (seam `debugExerciseCardHostForTest`). Plan
// docs/plans/active-workout-log-exercise.md §6 tests 4, 5, 7, 10, 11, 14, 16.
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';

import 'card_harness.dart';

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('flag OFF: the per-set path is unchanged', () {
    testWidgets('N interactive check tiles, no LOG, 28 px +/- appends blank',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: false);
      // 3 per-set check tiles + the 28 px `-` and `+` set buttons.
      expect(interactiveCheckTiles, findsNWidgets(5));
      expect(find.textContaining('LOG'), findsNothing);
      expect(find.textContaining('0kg'), findsOneWidget,
          reason: 'OFF meta line still prints the weight segment');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(8));
      expect(controllerAt(tester, 6).text, '');
      expect(controllerAt(tester, 7).text, '');
      expect(h.state.setInputValues.containsKey('0-3'), isFalse);
    });
  });

  group('flag ON', () {
    testWidgets('LOG row replaces the check taps; label + subline', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      // No per-set tile and no 28 px button: the ON stepper is 44 px.
      expect(interactiveCheckTiles, findsNothing);
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
      expect(find.text('1440 KG LIFTED'), findsOneWidget);
      expect(find.textContaining('0kg'), findsNothing,
          reason: 'LOG mode drops the placeholder weight (OI-352)');
    });

    testWidgets('one LOG tap = every set checked and captured', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tester.enterText(fieldAt(2), '62.5'); // set 2 weight, before LOG
      await tester.pump();
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      expect(h.logCalls, [
        {0, 1, 2}
      ]);
      expect(h.state.isExerciseDone(0), isTrue);
      expect(h.state.setInputValues['0-1']?.weight, 62.5);
      expect(h.state.setInputValues['0-0']?.reps, 8);
      expect(find.text('LOGGED ✓'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(3),
          reason: 'logged sets show a static tick');
    });

    testWidgets('blocked: neutral label, tap focuses the failing field; '
        'label is reactive with no timer tick', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          lastPerf: const LastPerformanceData());
      expect(find.text('Add weight'), findsOneWidget);
      await tester.tap(find.text('Add weight'));
      await tester.pump();
      expect(hasFocus(tester, 0), isTrue);
      expect(h.logCalls, isEmpty);

      await tester.enterText(fieldAt(0), '50');
      await tester.pump(); // one frame, no timer tick
      expect(find.text('Add weight'), findsOneWidget); // sets 2 and 3 blank
      await tester.tap(find.text('Add weight'));
      await tester.pump();
      expect(hasFocus(tester, 2), isTrue, reason: 'set 2 weight is next');

      await tester.enterText(fieldAt(2), '50');
      await tester.enterText(fieldAt(4), '50');
      await tester.pump();
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);

      await tester.enterText(fieldAt(5), '61');
      await tester.pump();
      expect(find.text('Fix reps'), findsOneWidget);
      await tester.tap(find.text('Fix reps'));
      await tester.pump();
      expect(hasFocus(tester, 5), isTrue);
    });

    testWidgets('weighted_bodyweight never blocks on weight', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(
              exercises: [exercise(type: 'weighted_bodyweight')]),
          logMode: true,
          lastPerf: const LastPerformanceData(lastReps: 10));
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
    });

    testWidgets('edit after LOG is saved on every keystroke; invalid edits '
        'keep the last valid value', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      // No blur, no LOG: what completeWorkout reads must already be updated.
      await tester.enterText(fieldAt(2), '70');
      expect(h.state.setInputValues['0-1']?.weight, 70);
      await tester.enterText(fieldAt(2), '');
      expect(h.state.setInputValues['0-1']?.weight, 70);
      await tester.enterText(fieldAt(3), '61');
      expect(h.state.setInputValues['0-1']?.reps, 8);
      await tester.pump();
      // The divergence is visible: the row asks to fix it instead of LOGGED.
      expect(find.text('LOGGED ✓'), findsNothing);
      expect(find.text('Add weight'), findsOneWidget);
      await tester.tap(find.text('Add weight'));
      await tester.pump();
      expect(hasFocus(tester, 2), isTrue);
      await tester.enterText(fieldAt(2), '70');
      await tester.enterText(fieldAt(3), '8');
      await tester.pump();
      expect(find.text('LOGGED ✓'), findsOneWidget);
    });

    testWidgets('review mode: a keystroke on a logged set records nothing',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(
              exercises: [exercise()],
              isSaved: true,
              checkedSets: const {'0-0': true, '0-1': true, '0-2': true}),
          logMode: true);
      final before = h.state.setInputValues['0-0'];
      await tester.enterText(fieldAt(0), '99');
      expect(h.state.setInputValues['0-0']?.weight, before?.weight);
    });

    testWidgets('+ seeds the new set field-for-field and captures it; it '
        'survives leaving and re-entering', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tester.enterText(fieldAt(4), '65');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump();
      expect(controllerAt(tester, 6).text, '65');
      expect(controllerAt(tester, 7).text, '8');
      expect(h.state.setInputValues['0-3']?.weight, 65);
      expect(find.text('LOG 4 SETS ✓'), findsOneWidget);

      // Leave and come back: the card restores only captured keys.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
                child: debugExerciseCardHostForTest(
                    exerciseIndex: 0, onLogExercise: (_) => throw 'unused')),
          ),
        ),
      ));
      await tester.pump();
      expect(controllerAt(tester, 6).text, '65');
    });

    testWidgets('- removes only the last set, disabled at 1; - while the last '
        'row is focused does not throw', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(sets: '2')]),
          logMode: true);
      await tester.tap(fieldAt(2));
      await tester.pump();
      expect(hasFocus(tester, 2), isTrue);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(h.state.exercises.first.sets, '1');
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(h.state.exercises.first.sets, '1');
    });

    testWidgets('all-warm-up exercise: LOG ✓ still logs it', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(
              exercises: [exercise(sets: '2')],
              warmUpSets: const {'0-0': true, '0-1': true}),
          logMode: true);
      await tapWithRealIo(tester, find.text('LOG ✓'));
      expect(h.state.isExerciseDone(0), isTrue);
    });

    testWidgets('review mode (isSaved): +, - and LOG do nothing',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()], isSaved: true),
          logMode: true);
      await tester.tap(find.text('LOG 3 SETS ✓'));
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(h.logCalls, isEmpty);
      expect(h.state.exercises.first.sets, '3');
    });
  });
}
