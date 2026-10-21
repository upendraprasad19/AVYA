// Flip batch card behaviour through the real `_ExerciseCard`
// (docs/plans/log-exercise-flip.md §6 "Card"): RE-OPEN (A1/A3/A4), the faded
// prefill (P1-P9c), the LOG-mode header hint (H1), semantics (SM1) and the
// layout at 320 dp (L1/L2).
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import 'card_harness.dart';

/// A field renders faded at 62% parchment; normal is opaque.
bool faded(WidgetTester tester, int i) =>
    tester.widget<TextField>(fieldAt(i)).style!.color!.a < 1.0;

String text(WidgetTester tester, int i) => controllerAt(tester, i).text;

Future<void> type(WidgetTester tester, int field, String value) async {
  await tester.enterText(fieldAt(field), value);
  await tester.pump();
}

const newUser = LastPerformanceData();

/// The Semantics node of a widget found by its text.
SemanticsData nodeOf(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

/// `Semantics(onTapHint:)` is carried as an overriding custom action.
bool hasReopenHint(SemanticsData node) =>
    node.customSemanticsActionIds?.contains(CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction.overridingAction(
                hint: WardroomCopy.activeReopenHint,
                action: SemanticsAction.tap))) ??
        false;

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('RE-OPEN (flip §1)', () {
    testWidgets('A1: tap LOGGED re-opens: unchecked, values kept, LOG again, '
        'SWAP back', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await type(tester, 0, '62.5');
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      expect(find.text(WardroomCopy.activeReopenSubline), findsOneWidget);
      // ⇄ is the header's swap icon since the swap/move batch (it was the
      // '⇄ SWAP' text chip); a done card shows ✓ DONE instead.
      expect(find.byIcon(Icons.swap_horiz), findsNothing);

      await tester.tap(find.text('LOGGED ✓'));
      await tester.pump();
      expect(h.reopenCalls, 1);
      expect(h.state.isExerciseDone(0), isFalse);
      expect(h.state.setInputValues['0-0']?.weight, 62.5);
      expect(text(tester, 0), '62.5');
      expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('A3: review mode: no re-open text, not a tappable button, no '
        'hint', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(
              exercises: [exercise()],
              isSaved: true,
              checkedSets: const {'0-0': true, '0-1': true, '0-2': true}),
          logMode: true);
      expect(find.text('LOGGED ✓'), findsOneWidget);
      expect(find.text(WardroomCopy.activeReopenSubline), findsNothing);
      final node = nodeOf(tester, find.text('LOGGED ✓'));
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      expect(hasReopenHint(node), isFalse);
      await tester.tap(find.text('LOGGED ✓'));
      await tester.pump();
      expect(h.reopenCalls, 0);
      handle.dispose();
    });

    testWidgets('A4: re-open then LOG = one more LOG call, all sets checked',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      await tester.tap(find.text('LOGGED ✓'));
      await tester.pump();
      expect(h.logCalls.length, 1, reason: 're-open never logs');
      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      expect(h.logCalls.length, 2);
      expect(h.state.isExerciseDone(0), isTrue);
    });
  });

  group('faded prefill (flip §2)', () {
    testWidgets('P1: new user: blanks are not faded; set 1 mirrors faded and '
        'is normal itself; clearing set 1 leaves blank, unmarked followers',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          lastPerf: newUser);
      expect([faded(tester, 0), faded(tester, 2), faded(tester, 4)],
          [false, false, false]);
      await type(tester, 0, '60');
      expect(faded(tester, 0), isFalse);
      expect([faded(tester, 2), faded(tester, 4)], [true, true]);
      await type(tester, 0, '');
      expect([text(tester, 2), text(tester, 4)], ['', '']);
      expect(h.state.suggestedInputs, isEmpty);
      expect([faded(tester, 2), faded(tester, 4)], [false, false]);
    });

    testWidgets('P2: returning user: weights faded, reps not; typing clears '
        'only that field', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      expect([faded(tester, 0), faded(tester, 2), faded(tester, 4)],
          [true, true, true]);
      expect([faded(tester, 1), faded(tester, 3), faded(tester, 5)],
          [false, false, false]);
      expect(h.state.suggestedInputs, {'0-0-weight', '0-1-weight', '0-2-weight'});
      await type(tester, 2, '62.5');
      expect([faded(tester, 0), faded(tester, 2), faded(tester, 4)],
          [true, false, true]);
    });

    testWidgets('P3: a real tap on a faded field selects all of it',
        (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tester.tap(fieldAt(2));
      await tester.pump();
      final sel = controllerAt(tester, 2).selection;
      expect([sel.baseOffset, sel.extentOffset], [0, text(tester, 2).length]);
      // A second tap after the double-tap window re-selects.
      await tester.pump(const Duration(milliseconds: 600));
      controllerAt(tester, 2).selection =
          const TextSelection.collapsed(offset: 1);
      await tester.tap(fieldAt(2));
      await tester.pump();
      final again = controllerAt(tester, 2).selection;
      expect([again.baseOffset, again.extentOffset],
          [0, text(tester, 2).length]);
    });

    testWidgets('P4: the subline reads PREFILLED until set 1 is typed; the '
        'followers stay faded', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      expect(find.text('1440 KG · PREFILLED'), findsOneWidget);
      await type(tester, 0, '62.5');
      expect(find.text('1460 KG LIFTED'), findsOneWidget);
      expect([faded(tester, 2), faded(tester, 4)], [true, true]);
    });

    testWidgets('P5: re-entry keeps a typed value normal and untouched sets '
        'faded', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await type(tester, 2, '62.5');
      await repumpCard(tester, h);
      expect(text(tester, 2), '62.5');
      expect(faded(tester, 2), isFalse);
      expect([faded(tester, 0), faded(tester, 4)], [true, true]);
    });

    testWidgets('P5b: a prefill cleared to blank stays blank after re-entry',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await type(tester, 2, '');
      await repumpCard(tester, h);
      expect(text(tester, 2), '');
      expect(find.text('Add weight'), findsOneWidget);
    });

    testWidgets('P6: flag OFF: no fade, no capture on a keystroke',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: false);
      expect([faded(tester, 0), faded(tester, 2)], [false, false]);
      await type(tester, 0, '70');
      expect(h.state.setInputValues['0-0']?.weight, isNot(70));
      expect(h.state.suggestedInputs, isEmpty);
    });

    testWidgets('P7: the fade survives a timer tick, − then +, a warm-up '
        'toggle', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      final n = h.container.read(activeWorkoutProvider.notifier);
      n.setElapsedSeconds(1);
      await tester.pump(const Duration(seconds: 1));
      expect(faded(tester, 2), isTrue);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump();
      expect(faded(tester, 2), isTrue);
      n.toggleWarmUp(0, 0);
      await tester.pump();
      expect(faded(tester, 2), isTrue);
    });

    testWidgets('P8: typing into a faded field keeps the same EditableText '
        'and focus', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await tester.tap(fieldAt(2));
      await tester.pump();
      final before = tester.state<EditableTextState>(
          find.descendant(of: fieldAt(2), matching: find.byType(EditableText)));
      tester.testTextInput.enterText('5');
      await tester.pump();
      tester.testTextInput.enterText('55');
      await tester.pump();
      final after = tester.state<EditableTextState>(
          find.descendant(of: fieldAt(2), matching: find.byType(EditableText)));
      expect(same(before).matches(after, {}), isTrue);
      expect(hasFocus(tester, 2), isTrue);
      expect(text(tester, 2), '55');
    });

    testWidgets('P9: after a re-init, mirror followers follow again (new '
        'user); history followers do not (returning user)', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          lastPerf: newUser);
      await type(tester, 0, '60');
      await repumpCard(tester, h);
      await type(tester, 0, '65');
      expect([text(tester, 2), text(tester, 4)], ['65', '65']);
      expect([faded(tester, 2), faded(tester, 4)], [true, true]);
    });

    testWidgets('P9 (returning user): history followers keep their value',
        (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await repumpCard(tester, h);
      await type(tester, 0, '65');
      expect([text(tester, 2), text(tester, 4)], ['60', '60']);
    });

    testWidgets('P9c: returning user types 62.5, re-init, then 65: the '
        'followers keep the suggested 60 (R6-02)', (tester) async {
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      await type(tester, 0, '62.5');
      expect([text(tester, 2), text(tester, 4)], ['60', '60']);
      await repumpCard(tester, h);
      await type(tester, 0, '65');
      expect([text(tester, 2), text(tester, 4)], ['60', '60']);
    });
  });

  group('header hint, semantics, layout', () {
    testWidgets('H1: a done, expanded card: LOG mode hides "Tap to edit '
        'values"; OFF shows it', (tester) async {
      ActiveWorkoutData done() => ActiveWorkoutData(
          exercises: [exercise()],
          checkedSets: const {'0-0': true, '0-1': true, '0-2': true});
      await pumpCard(tester, seed: done(), logMode: true);
      expect(find.text('LOGGED ✓'), findsOneWidget);
      expect(find.text('Tap to edit values'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, seed: done(), logMode: false);
      expect(find.text('Tap to edit values'), findsOneWidget);
    });

    testWidgets('SM1: LOG and LOGGED carry a tap action; labels; the fields '
        'say their unit and, faded, "Prefilled value"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      final log = nodeOf(tester, find.text('LOG 3 SETS ✓'));
      expect(log.hasAction(SemanticsAction.tap), isTrue);
      expect(log.label, 'LOG 3 SETS ✓. 1440 KG · PREFILLED');

      final weight = nodeOf(tester, fieldAt(0));
      expect(weight.label, contains('KG'));
      expect(weight.hint, contains(WardroomCopy.activePrefilledHint));
      final reps = nodeOf(tester, fieldAt(1));
      expect(reps.label, contains('REPS'));
      expect(reps.hint, isNot(contains(WardroomCopy.activePrefilledHint)));

      await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
      final logged = nodeOf(tester, find.text('LOGGED ✓'));
      expect(logged.hasAction(SemanticsAction.tap), isTrue);
      expect(logged.label, WardroomCopy.activeLoggedSemantics);
      expect(hasReopenHint(logged), isTrue);
      handle.dispose();
    });

    testWidgets('SM1: a blocked LOG still has a tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          lastPerf: newUser);
      expect(nodeOf(tester, find.text('Add weight'))
          .hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('SM1: a timed card says SEC; a blank field adds no label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(type: 'timed')]),
          logMode: true,
          lastPerf: newUser);
      await type(tester, 0, '45');
      expect(nodeOf(tester, fieldAt(0)).label, contains('SEC'));
      expect(nodeOf(tester, fieldAt(0)).label, isNot(contains('KG')));
      handle.dispose();
    });

    Future<void> narrow(WidgetTester tester, double scale) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('L1: 320 dp × 2.0, prefill from exercise.weight: LOG with '
        'PREFILLED and LOGGED with re-open do not overflow', (tester) async {
      await narrow(tester, 2.0);
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise(weight: '60kg')]),
          logMode: true,
          lastPerf: newUser);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('PREFILLED'), findsOneWidget);
      await tapWithRealIo(tester, find.textContaining('LOG 3 SETS'));
      expect(tester.takeException(), isNull);
      expect(find.text(WardroomCopy.activeReopenSubline), findsOneWidget);
    });

    testWidgets('L2: 320 dp × 1.5 with a history prefill: no overflow',
        (tester) async {
      await narrow(tester, 1.5);
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]), logMode: true);
      expect(tester.takeException(), isNull);
    });
  });
}
