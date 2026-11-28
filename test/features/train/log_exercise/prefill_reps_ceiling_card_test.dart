// Card-level proof for diagnose 7c3e91: the REAL `_ExerciseCard` fills the reps
// boxes through `prefillReps`, so a stray stored 35 does not reach a plan of 8.
// Field order in a weight_reps row: KG, REPS (set 1 = fields 0 and 1).
//
// MUTATION: put `lastPerf.lastReps.toString()` back in `_initControllers` ->
// the first test fails.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import 'card_harness.dart';

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('a stray last value (35 on a plan of 8) is not prefilled',
      (tester) async {
    await pumpCard(tester,
        seed: ActiveWorkoutData(exercises: [exercise()]),
        logMode: true,
        lastPerf: const LastPerformanceData(lastWeight: 110, lastReps: 35));
    expect(controllerAt(tester, 1).text, '8');
    // The weight prefill is not touched by the reps rule.
    expect(controllerAt(tester, 0).text, '110');
  });

  testWidgets('the TRY line does not suggest the stray 35 back', (tester) async {
    await pumpCard(tester,
        seed: ActiveWorkoutData(exercises: [exercise()]),
        logMode: true,
        lastPerf: const LastPerformanceData(
            lastWeight: 110, lastReps: 35, suggestedWeight: 112.5));
    final tryText = find.byKey(const Key('exercise-try-line'));
    expect(tryText, findsOneWidget);
    expect(find.descendant(of: tryText, matching: find.text('TRY: 112.5KG × 8')),
        findsOneWidget);
    // The LAST line is the real history and still shows it.
    expect(find.textContaining('35'), findsWidgets);
  });

  testWidgets('an ordinary last value (10 on a plan of 8) is prefilled',
      (tester) async {
    await pumpCard(tester,
        seed: ActiveWorkoutData(exercises: [exercise()]),
        logMode: true,
        lastPerf: const LastPerformanceData(lastWeight: 60, lastReps: 10));
    expect(controllerAt(tester, 1).text, '10');
  });
}
