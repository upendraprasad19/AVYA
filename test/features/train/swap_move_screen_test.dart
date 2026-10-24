// ⇅ move through the REAL ActiveWorkoutScreen (docs/plans/
// active-workout-swap-move.md Task 6): enter, place, UNDO, cancel by the bar
// and by system back, the stale swap snackbar, and the first-use hint.
// Never pumpAndSettle here: the move-target glow and the hint ring repeat.
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/train/services/swap_move_hint.dart';

import 'log_exercise/card_harness.dart';

List<String> names(ScreenHarness h) =>
    [for (final e in h.state.exercises) e.name];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final three = [
  exercise(name: 'Bench Press'),
  exercise(name: 'Incline Press'),
  exercise(name: 'Triceps Pushdown'),
];

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('⇅ then a target places it; the toast names it; UNDO restores',
      (tester) async {
    final h = await pumpScreen(tester, exercises: three);

    await tester.tap(find.byIcon(Icons.swap_vert).at(2)); // Triceps
    await tester.pump();
    expect(
        find.text(WardroomCopy.activeMoveBarTemplate
            .replaceAll('{exercise}', 'Triceps Pushdown')),
        findsOneWidget);
    expect(find.text(WardroomCopy.activeMovingTag), findsOneWidget);
    expect(find.text(WardroomCopy.activeMoveHereUp), findsNWidgets(2));

    await tester.tap(find.text('Incline Press')); // whole header places
    await settle(tester);
    expect(names(h), ['Bench Press', 'Triceps Pushdown', 'Incline Press']);
    expect(find.text(WardroomCopy.activeMovingTag), findsNothing);
    expect(
        find.text(WardroomCopy.activeMovedTemplate
            .replaceAll('{exercise}', 'Triceps Pushdown')
            .replaceAll('{n}', '2')),
        findsOneWidget);

    await tester.tap(find.text(WardroomCopy.activeUndo));
    await settle(tester);
    expect(names(h), ['Bench Press', 'Incline Press', 'Triceps Pushdown']);
    await unmountScreen(tester);
  });

  testWidgets('Cancel and a second ⇅ leave move mode with nothing moved',
      (tester) async {
    final h = await pumpScreen(tester, exercises: three);

    await tester.tap(find.byIcon(Icons.swap_vert).at(1));
    await tester.pump();
    // WardChip upper-cases its label.
    await tester.tap(find.text(WardroomCopy.activeMoveCancel.toUpperCase()));
    await tester.pump();
    expect(find.text(WardroomCopy.activeMovingTag), findsNothing);

    await tester.tap(find.byIcon(Icons.swap_vert).at(1));
    await tester.pump();
    // The moving card's ⇅ (the bar's icon has no tooltip).
    await tester.tap(find.byTooltip(WardroomCopy.activeMoveExerciseLabel));
    await tester.pump();
    expect(find.text(WardroomCopy.activeMovingTag), findsNothing);
    expect(names(h), ['Bench Press', 'Incline Press', 'Triceps Pushdown']);
    await unmountScreen(tester);
  });

  testWidgets('UNDO while a new move is picked leaves move mode',
      (tester) async {
    final h = await pumpScreen(tester, exercises: three);
    await tester.tap(find.byIcon(Icons.swap_vert).at(2)); // Triceps
    await tester.pump();
    await tester.tap(find.text('Incline Press'));
    await settle(tester);
    expect(names(h), ['Bench Press', 'Triceps Pushdown', 'Incline Press']);

    await tester.tap(find.byIcon(Icons.swap_vert).at(2)); // Incline, slot 2
    await tester.pump();
    expect(find.text(WardroomCopy.activeMovingTag), findsOneWidget);

    await tester.tap(find.text(WardroomCopy.activeUndo));
    await settle(tester);
    expect(names(h), ['Bench Press', 'Incline Press', 'Triceps Pushdown']);
    // Slot 2 now holds Triceps: a kept index would silently move IT.
    expect(find.text(WardroomCopy.activeMovingTag), findsNothing);
    expect(find.textContaining('Tap where'), findsNothing);
    await unmountScreen(tester);
  });

  testWidgets('a moved superset member keeps its card State', (tester) async {
    State cardState(String name) => tester.state(find
        .ancestor(
            of: find.text(name),
            matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_ExerciseCard'))
        .first);

    await pumpScreen(tester, exercises: [
      exercise(name: 'Bench Press').copyWith(supersetGroup: () => 0),
      exercise(name: 'Incline Press').copyWith(supersetGroup: () => 0),
      exercise(name: 'Triceps Pushdown'),
    ]);
    final before = cardState('Incline Press'); // under a SUPERSET label
    await tester.tap(find.byIcon(Icons.swap_vert).at(1));
    await tester.pump();
    await tester.tap(find.text('Bench Press')); // now first: no label
    await settle(tester);
    // The keyed Column carries the State to the new slot; the label slot
    // flipping in front of the card does not rebuild it (Flutter matches
    // unkeyed children from both ends). Removing the key reddens this.
    expect(identical(cardState('Incline Press'), before), isTrue,
        reason: 'typed text lives in the card State');
    await unmountScreen(tester);
  });

  testWidgets('system back cancels move mode instead of leaving',
      (tester) async {
    await pumpScreen(tester, exercises: three);
    await tester.tap(find.byIcon(Icons.swap_vert).first);
    await tester.pump();
    expect(find.text(WardroomCopy.activeMovingTag), findsOneWidget);

    final popped = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popped, isTrue, reason: 'the PopScope handled it');
    expect(find.text(WardroomCopy.activeMovingTag), findsNothing);
    expect(find.text('Bench Press'), findsOneWidget, reason: 'still here');
    await unmountScreen(tester);
  });

  testWidgets('a move hides a still-showing snackbar before its own',
      (tester) async {
    await pumpScreen(tester, exercises: three);
    final ctx = tester.element(find.text('Bench Press'));
    ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Swapped "A" → "B"')));
    await tester.pump();
    expect(find.text('Swapped "A" → "B"'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.swap_vert).at(2));
    await tester.pump();
    await tester.tap(find.text('Bench Press'));
    await settle(tester);
    expect(find.text('Swapped "A" → "B"'), findsNothing,
        reason: 'an index-keyed swap UNDO must not survive a move');
    await unmountScreen(tester);
  });

  testWidgets('first workout: hint shows; Got it retires it for the account',
      (tester) async {
    await pumpScreen(tester, exercises: three, hintSeen: false);
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text(WardroomCopy.activeSwapMoveHintDismiss));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsNothing);
    expect(swapMoveHintSeen(), isTrue);
    await unmountScreen(tester);

    await pumpScreen(tester, exercises: three, hintSeen: null);
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsNothing,
        reason: 'never again on this account');
    await unmountScreen(tester);
  });

  testWidgets('the first logged set retires a hint that was shown',
      (tester) async {
    await pumpScreen(tester, exercises: three, hintSeen: false);
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsOneWidget);
    // The retire write runs in a post-frame callback, so that frame must run
    // in the real zone: a Hive write started under fake async never finishes
    // and the NEXT test's Hive call queues behind it forever.
    await tester.runAsync(() async {
      await tester.tap(find.text('LOG 3 SETS ✓'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsNothing);
    expect(swapMoveHintSeen(), isTrue);
    await unmountScreen(tester);
  });

  testWidgets('a one-exercise day never shows or retires the hint',
      (tester) async {
    await pumpScreen(tester, exercises: [exercise(name: 'Bench Press')], hintSeen: false);
    expect(find.text(WardroomCopy.activeSwapMoveHintTitle), findsNothing);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
    await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
    await tester.pump();
    expect(swapMoveHintSeen(), isFalse);
    await unmountScreen(tester);
  });
}
