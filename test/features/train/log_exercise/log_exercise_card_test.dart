// One-LOG-per-exercise card behaviour through the real `_ExerciseCard`
// (seam `debugExerciseCardHostForTest`). Plan
// docs/plans/active-workout-log-exercise.md §6 tests 4, 5, 7, 10, 11, 14, 16;
// batch 2 (docs/plans/log-exercise-batch2.md §6) mirror tests 12-19.
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
      // History prefill (60 kg) is app-filled: the flip batch's subline.
      expect(find.text('1440 KG · PREFILLED'), findsOneWidget);
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
      // Batch 2 mirror: set 1's weight fills the blank sets 2 and 3.
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
      await tester.enterText(fieldAt(2), ''); // the user clears set 2
      await tester.pump();
      expect(find.text('Add weight'), findsOneWidget);
      await tester.tap(find.text('Add weight'));
      await tester.pump();
      expect(hasFocus(tester, 2), isTrue, reason: 'set 2 weight is next');

      await tester.enterText(fieldAt(2), '50');
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
              checkedSets: const {'0-0': true, '0-1': true, '0-2': true},
              // Seeded, so the check is not `null == null` (flip R4A-10).
              setInputValues: const {
                '0-0': SetInputValues(weight: 50, reps: 8),
                '0-1': SetInputValues(weight: 50, reps: 8),
                '0-2': SetInputValues(weight: 50, reps: 8),
              }),
          logMode: true);
      expect(h.state.setInputValues['0-0']?.weight, 50);
      await tester.enterText(fieldAt(0), '99');
      expect(h.state.setInputValues['0-0']?.weight, 50);
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

  group('batch 2 mirror (flag ON, new user unless stated)', () {
    const newUser = LastPerformanceData();
    Future<CardHarness> pumpNew(WidgetTester tester,
            {String type = 'weight_reps', bool logMode = true}) =>
        pumpCard(tester,
            seed: ActiveWorkoutData(exercises: [exercise(type: type)]),
            logMode: logMode,
            lastPerf: newUser);
    String text(WidgetTester tester, int i) => controllerAt(tester, i).text;
    Future<void> type(WidgetTester tester, int field, String value) async {
      await tester.enterText(fieldAt(field), value);
      await tester.pump();
    }

    testWidgets('12: set 1 fills the blank sets; LOG unblocked', (tester) async {
      await pumpNew(tester);
      expect(find.text('Add weight'), findsOneWidget);
      await type(tester, 0, '60');
      expect([text(tester, 2), text(tester, 4)], ['60', '60']);
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
    });

    testWidgets('13: followers keep following; a typed value is left alone',
        (tester) async {
      await pumpNew(tester);
      await type(tester, 0, '60');
      await type(tester, 4, '70'); // the user types set 3
      await type(tester, 0, '65');
      expect(text(tester, 2), '65');
      expect(text(tester, 4), '70');
    });

    testWidgets('14: editing set 1 REPS does not refill a cleared weight',
        (tester) async {
      await pumpNew(tester);
      await type(tester, 0, '60');
      await type(tester, 2, ''); // the user clears set 2's weight
      await type(tester, 1, '9'); // set 1 reps
      expect(text(tester, 2), '');
      expect(text(tester, 4), '60');
    });

    testWidgets('15: clearing set 1 clears its followers', (tester) async {
      await pumpNew(tester);
      await type(tester, 0, '60');
      await type(tester, 0, '');
      expect([text(tester, 2), text(tester, 4)], ['', '']);
    });

    testWidgets('16: timed and cardio mirror; bodyweight reps does not',
        (tester) async {
      await pumpNew(tester, type: 'timed');
      await type(tester, 0, '45');
      expect([text(tester, 1), text(tester, 2)], ['45', '45']);
    });

    testWidgets('16b: cardio mirrors duration and distance', (tester) async {
      await pumpNew(tester, type: 'cardio');
      await type(tester, 0, '20');
      await type(tester, 1, '5');
      expect([text(tester, 2), text(tester, 3), text(tester, 4), text(tester, 5)],
          ['20', '5', '20', '5']);
    });

    testWidgets('16c: bodyweight reps: nothing mirrors', (tester) async {
      await pumpNew(tester, type: 'bodyweight_reps');
      final before = text(tester, 1);
      await type(tester, 0, '12');
      expect(text(tester, 1), before);
    });

    testWidgets('17: a logged set is never written', (tester) async {
      await pumpNew(tester);
      await type(tester, 0, '60');
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(text(tester, 6), '60', reason: 'seeded from set 3');
      await type(tester, 0, '65');
      expect([text(tester, 2), text(tester, 4)], ['60', '60'],
          reason: 'sets 2 and 3 are logged');
      expect(text(tester, 6), '65', reason: 'the added set follows the chain');
    });

    testWidgets('18: - then + : the re-added set follows through the chain',
        (tester) async {
      await pumpNew(tester);
      await type(tester, 0, '60');
      await type(tester, 4, '70'); // set 3 typed by the user
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(text(tester, 4), '60', reason: 'seeded from set 2, a follower');
      await type(tester, 0, '65');
      expect(text(tester, 4), '65');
    });

    testWidgets('18 (returning user): a copy of a prefilled set never follows',
        (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await type(tester, 0, '65');
      expect([text(tester, 2), text(tester, 4), text(tester, 6)],
          ['60', '60', '60']);
    });

    testWidgets('18b: a warm-up moving the source re-baselines first',
        (tester) async {
      final h = await pumpNew(tester);
      await type(tester, 0, '60');
      await type(tester, 2, '70'); // set 2 typed
      h.container.read(activeWorkoutProvider.notifier).toggleWarmUp(0, 0);
      await tester.pump();
      await type(tester, 3, '9'); // set 2 reps: source moved, nothing mirrors
      expect(text(tester, 4), '60');
      await type(tester, 2, '75'); // the new source's weight changes
      expect(text(tester, 4), '75');
    });

    testWidgets('18c: after a warm-up moves the source, a ONE-digit entry '
        'mirrors (B-pass finding 2)', (tester) async {
      final h = await pumpNew(tester);
      h.container.read(activeWorkoutProvider.notifier).toggleWarmUp(0, 0);
      await tester.pump();
      await type(tester, 2, '8'); // set 2 is the source now; one keystroke
      expect(text(tester, 4), '8');
      expect(text(tester, 0), '', reason: 'the warm-up set is not a target');
    });

    testWidgets('18d: + on a one-set exercise follows the source '
        '(B-pass finding 3)', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(sets: '1')]),
          logMode: true,
          lastPerf: newUser);
      await type(tester, 0, '60');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(text(tester, 2), '60', reason: 'seeded from set 1, the source');
      await type(tester, 0, '65');
      expect(text(tester, 2), '65', reason: 'the copy of the source follows');
    });

    testWidgets('19: flag OFF never mirrors (weight and timed)', (tester) async {
      await pumpNew(tester, logMode: false);
      await type(tester, 0, '60');
      expect([text(tester, 2), text(tester, 4)], ['', '']);
    });

    testWidgets('19b: flag OFF never mirrors a timed duration', (tester) async {
      await pumpNew(tester, type: 'timed', logMode: false);
      await type(tester, 0, '45');
      expect([text(tester, 1), text(tester, 2)], ['', '']);
    });
  });
}
