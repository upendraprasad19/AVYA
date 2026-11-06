// SoT concept `exercise_name_unique_in_day` (OI-358): the REAL Active Workout
// screen and its REAL sheets, through `pumpScreen`. The writer contract lives in
// test/contracts/exercise_name_unique_in_day_behavioral_test.dart.
//
// On `main` the first three tests throw "Multiple widgets used the same
// GlobalKey": each one's guard is the only thing between it and that exception.
@Timeout(Duration(minutes: 6))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/create_custom_exercise_sheet.dart';

import 'log_exercise/card_harness.dart';

const _bench = 'Barbell Bench Press';
const _row = 'Seated Cable Row';
const _curl = 'Barbell Curl';
const _press = 'Overhead Press';
const _custom = 'Zercher Hold';

Map<String, dynamic> _lib(String id, String name) => {
      'id': id,
      'name': name,
      'category': 'Push',
      'primary_muscles': ['Chest'],
      'logging_type': 'weight_reps',
    };

final _library = [
  _lib('E1', _bench),
  _lib('E2', _row),
  _lib('E3', _curl),
  _lib('E4', _press),
];

const _takenTag = WardroomCopy.activeAlreadyInWorkoutTag;

String _takenMessage(String name) => WardroomCopy.activeAlreadyInWorkoutTemplate
    .replaceAll('{exercise}', name);

Future<ScreenHarness> _pump(WidgetTester tester, List<String> names) async {
  await ensureHive(tester);
  await tester.runAsync(() => HiveService.instance.customBox.clear());
  return pumpScreen(tester,
      exercises: [for (final n in names) exercise(name: n)],
      libraryRows: _library);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _names(ScreenHarness h) =>
    h.state.exercises.map((e) => e.name).toList();

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Future<void> _openAddPicker(WidgetTester tester) async {
  final add = find.text('+ ADD EXERCISE').first;
  await tester.ensureVisible(add);
  await tester.pump();
  await tester.tap(add);
  await _settle(tester);
}

Future<void> _openSwapSheet(WidgetTester tester, int cardIndex) async {
  await tester.tap(find.byIcon(Icons.swap_horiz).at(cardIndex));
  await _settle(tester);
}

/// Fills the name on the open CreateCustomExerciseSheet and saves it for real.
Future<void> _createCustom(WidgetTester tester, String name) async {
  await tester.enterText(
      find.descendant(
          of: find.byType(BottomSheet).last, matching: find.byType(TextField)).first,
      name);
  await tester.pump();
  await tester.ensureVisible(_inSheet(find.text('SAVE')));
  await tester.pump();
  await tapWithRealIo(tester, _inSheet(find.text('SAVE')));
  // The sheet closes, and onCreated runs, only after the real write.
  final sheet = find.byType(CreateCustomExerciseSheet);
  await pumpUntilRealIoDone(tester, () => sheet.evaluate().isEmpty,
      what: 'saving the custom exercise');
  await _settle(tester);
}

/// The swap sheet's own "+ ADD EXERCISE": create a custom, auto-swap it in.
Future<void> _swapToNewCustom(WidgetTester tester, int cardIndex, String name) async {
  await _openSwapSheet(tester, cardIndex);
  await tester.tap(_inSheet(find.text('+ ADD EXERCISE')));
  await _settle(tester);
  await _createCustom(tester, name);
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('the crash itself', () {
    testWidgets('A: adding a name in the session', (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      h.notifier.addExercise(exercise(name: _bench));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_names(h), [_bench, _row]);
    });

    testWidgets('B: swapping into a name in another slot', (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      h.notifier.swapExercise(1, exercise(name: _bench));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_names(h), [_bench, _row]);
    });

    testWidgets('C: starting a stored day that already holds a name twice',
        (tester) async {
      final h = await _pump(tester, [_row]);
      h.notifier.startWorkout(WorkoutDayData(dayNumber: 1, name: 'D', exercises: [
        exercise(name: _bench),
        exercise(name: _bench),
        exercise(name: _row),
      ]));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_names(h), [_bench, _row]);
      h.notifier.cancelWorkout();
      await tester.pump();
    });
  });

  group('Add picker', () {
    testWidgets('a name in the session is shown, findable and cannot be tapped',
        (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _openAddPicker(tester);
      expect(_inSheet(find.text(_takenTag)), findsNWidgets(2));

      await tester.enterText(_inSheet(find.byType(TextField)).first, 'bench');
      await _settle(tester);
      expect(_inSheet(find.text(_bench)), findsOneWidget,
          reason: 'greyed, not hidden: the user must see why');

      await tester.tap(_inSheet(find.text(_bench)));
      await _settle(tester);
      expect(_names(h), [_bench, _row]);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'nothing happened');
    });

    testWidgets('a new name still adds and closes the sheet', (tester) async {
      final h = await _pump(tester, [_bench]);
      await _openAddPicker(tester);
      await tester.tap(_inSheet(find.text(_curl)));
      await _settle(tester);
      expect(_names(h), [_bench, _curl]);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('create-custom named like a session exercise: refused with a message',
        (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _openAddPicker(tester);
      await tester.tap(_inSheet(find.text('+ CREATE CUSTOM')));
      await _settle(tester);
      await _createCustom(tester, _bench);

      expect(_names(h), [_bench, _row]);
      expect(find.text(_takenMessage(_bench)), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing, reason: 'the picker closed');
      expect(
          HiveService.instance.customBox.values
              .whereType<Map>()
              .any((m) => m['name'] == _bench),
          isTrue,
          reason: 'the custom row stays: it is a library item the user asked for');
      expect(tester.takeException(), isNull);
    });
  });

  group('Swap sheet', () {
    testWidgets('another slot name is dead on the row body and has no SELECT',
        (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _openSwapSheet(tester, 0);
      expect(_inSheet(find.text(_row)), findsOneWidget);
      expect(_inSheet(find.text(_takenTag)), findsOneWidget);

      await tester.tap(_inSheet(find.text(_row)));
      await _settle(tester);
      expect(_names(h), [_bench, _row]);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'nothing happened');

      expect(_inSheet(find.text('SELECT')), findsNWidgets(2),
          reason: 'the other two library rows keep SELECT');
    });

    testWidgets('a new name still swaps', (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _openSwapSheet(tester, 1);
      await tester.tap(_inSheet(find.text('SELECT')).first);
      await _settle(tester);
      expect(_names(h)[0], _bench);
      expect(_names(h)[1], isNot(_row));
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a custom row of the OUTGOING exercise is greyed too', (tester) async {
      final h = await _pump(tester, [_custom, _row]);
      await tester.runAsync(() => HiveService.instance.customBox.put(
          'custom_exercise_c1',
          {'id': 'c1', 'name': _custom, 'type': 'exercise', 'category': 'Push'}));
      await _openSwapSheet(tester, 0);
      // The sheet's header shows the outgoing name in the same text, and the
      // custom section sits below the fold of a lazy list. Search brings the
      // row into the tree; the second match is the row, not the header.
      await tester.enterText(_inSheet(find.byType(TextField)).first, 'zercher');
      await _settle(tester);
      expect(_inSheet(find.text(_custom)), findsNWidgets(2),
          reason: 'the header and the row');
      expect(_inSheet(find.text(_takenTag)), findsOneWidget);
      expect(_inSheet(find.text('SELECT')), findsNothing);

      await tester.tap(_inSheet(find.text(_custom)).last);
      await _settle(tester);
      expect(_names(h), [_custom, _row]);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'nothing happened');
    });

    testWidgets('auto-swap into a session name: message, no UNDO', (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _swapToNewCustom(tester, 1, _bench);
      expect(_names(h), [_bench, _row]);
      expect(find.text(_takenMessage(_bench)), findsOneWidget);
      expect(find.text('UNDO'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('swap UNDO', () {
    testWidgets('still restores in the plain case', (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _swapToNewCustom(tester, 1, _custom);
      expect(_names(h), [_bench, _custom]);
      await tester.tap(find.text('UNDO'));
      await _settle(tester);
      expect(_names(h), [_bench, _row]);
    });

    testWidgets('finds its slot after a removal shifted the indexes', (tester) async {
      final h = await _pump(tester, [_bench, _row, _curl]);
      await _swapToNewCustom(tester, 1, _custom);
      expect(_names(h), [_bench, _custom, _curl]);

      h.notifier.removeExercise(0);
      await tester.pump();
      expect(_names(h), [_custom, _curl]);

      await tester.tap(find.text('UNDO'));
      await _settle(tester);
      expect(_names(h), [_row, _curl],
          reason: 'the captured index 1 would have overwritten $_curl');
    });

    testWidgets('after the outgoing name was added back: message, no change',
        (tester) async {
      final h = await _pump(tester, [_bench, _row]);
      await _swapToNewCustom(tester, 1, _custom);
      h.notifier.addExercise(exercise(name: _row));
      await tester.pump();
      expect(_names(h), [_bench, _custom, _row]);

      await tester.tap(find.text('UNDO'));
      await _settle(tester);
      expect(_names(h), [_bench, _custom, _row]);
      expect(find.text(_takenMessage(_row)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
