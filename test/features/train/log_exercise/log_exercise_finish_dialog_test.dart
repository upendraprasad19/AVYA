// The FINISH dialog through the REAL `ActiveWorkoutScreen` (docs/plans/
// log-exercise-flip.md §6 "Dialog"; `_showFinishDialog` is a part-file
// function): the LOG-mode guard lines (U-D2..U-D4), the OFF dialog (U-D5), and
// the zero-set block on both paths (U-E2, U-E2b, U-E2c; OI-361).
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/active_workout_persistence.dart';

import 'card_harness.dart';

const _v = SetInputValues(weight: 60, reps: 8);

/// Exercise [ex] fully logged (every template set checked with values).
ActiveWorkoutData Function(ActiveWorkoutData) logged(Iterable<int> exs,
        {Iterable<String> reopened = const []}) =>
    (b) => b.copyWith(
          checkedSets: {
            for (final e in exs)
              for (var s = 0; s < 3; s++) '$e-$s': true,
          },
          setInputValues: {
            for (final e in exs)
              for (var s = 0; s < 3; s++) '$e-$s': _v,
          },
          reopenedExercises: reopened.toSet(),
        );

Color? colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// The dialog's MIN field (the cards behind it have TextFields too).
Finder get dialogMinutes => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .first;

Finder get completeButton => find.widgetWithText(TextButton, 'COMPLETE');

bool completeEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(completeButton).onPressed != null;

bool dialogScrollable(WidgetTester tester) =>
    tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable;

String skippedLine(String names) =>
    WardroomCopy.activeFinishSkippedTemplate.replaceAll('{names}', names);
String reopenedLine(String names) =>
    WardroomCopy.activeFinishReopenedTemplate.replaceAll('{names}', names);
String typedLine(String names) =>
    WardroomCopy.activeFinishTypedTemplate.replaceAll('{names}', names);

Future<void> narrow(WidgetTester tester,
    {double width = 320, double scale = 1.0, double keyboard = 0}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('LOG mode guard lines (flip §3)', () {
    testWidgets('U-D2: re-opened and typed in warn, skipped in textDim',
        (tester) async {
      await pumpScreen(tester,
          exercises: [
            exercise(name: 'Bench Press'),
            exercise(name: 'Row'),
            exercise(name: 'Curl'),
            exercise(name: 'Squat'),
          ],
          seed: (b) {
            final l = logged([0, 1], reopened: ['Row'])(b);
            // Row re-opened: unchecked, values kept. Curl typed, unlogged.
            return l.copyWith(
              checkedSets: {
                for (var s = 0; s < 3; s++) '0-$s': true,
              },
              setInputValues: {
                ...l.setInputValues,
                '2-0': const SetInputValues(weight: 40, reps: 8),
              },
            );
          },
          lastPerf: const LastPerformanceData());
      await openFinish(tester);
      expect(colorOf(tester, reopenedLine('Row')), AppColors.warn);
      expect(colorOf(tester, typedLine('Curl')), AppColors.warn);
      expect(colorOf(tester, skippedLine('Squat')), AppColors.textDim);
      expect(completeEnabled(tester), isTrue);
      await unmountScreen(tester);
    });

    testWidgets('U-D3: 12 long names at 320 dp × 2.0 with the keyboard up: '
        'no overflow, the first name shown, +7 more', (tester) async {
      await narrow(tester, scale: 2.0, keyboard: 300);
      final names = [
        for (var i = 1; i <= 12; i++) 'Very Long Exercise Name Number $i',
      ];
      await pumpScreen(tester,
          exercises: [
            exercise(name: 'Logged One'),
            for (final n in names) exercise(name: n),
          ],
          seed: logged([0]),
          lastPerf: const LastPerformanceData());
      // The screen's own FINISH/CANCEL buttons overflow at 320 dp × 2.0
      // (pre-existing, not this dialog): lay them out and take that report
      // first, so the check below sees only the dialog.
      await scrollToFinish(tester);
      tester.takeException();
      await openFinish(tester);
      expect(tester.takeException(), isNull);
      final line = skippedLine(
          '${names.take(5).join(', ')}'
          '${WardroomCopy.activeFinishMoreTemplate.replaceAll('{n}', '7')}');
      expect(find.text(line), findsOneWidget);
      expect(
          tester.renderObject<RenderParagraph>(find.text(line)).didExceedMaxLines,
          isFalse,
          reason: 'the names are never cut (R5B-01)');
      expect(dialogScrollable(tester), isTrue);
      await unmountScreen(tester);
    });

    testWidgets('U-D4: nothing logged: the block line, no lists, COMPLETE '
        'disabled and a tap leaves the dialog open', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')]);
      await openFinish(tester);
      expect(find.text(WardroomCopy.activeFinishZeroSetBlocked),
          findsOneWidget);
      expect(find.textContaining('Nothing to save for'), findsNothing);
      expect(completeEnabled(tester), isFalse);
      await tester.tap(completeButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Complete Workout?'), findsOneWidget);
      expect(h.state.isComplete, isFalse);
      await unmountScreen(tester);
    });

    testWidgets('U-E2c: blocked with a re-opened exercise: the block line and '
        'the re-opened line; no skipped line (R7-04)', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: (b) => b.copyWith(
              setInputValues: {for (var s = 0; s < 3; s++) '0-$s': _v},
              reopenedExercises: {'Bench Press'}));
      await openFinish(tester);
      expect(find.text(WardroomCopy.activeFinishZeroSetBlocked),
          findsOneWidget);
      expect(find.text(reopenedLine('Bench Press')), findsOneWidget);
      expect(find.textContaining('Nothing to save for'), findsNothing);
      expect(completeEnabled(tester), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('U-E2b: the state loses its last saveable set while the '
        'dialog is open: COMPLETE closes it and completes nothing (R7-05, B-pass 7)', (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press')],
          seed: (b) => logged([0])(b).copyWith(elapsedSeconds: 125));
      await tester.runAsync(() => ActiveWorkoutPersistence.writeState(
          exerciseName: 'Bench Press',
          currentSet: 3,
          totalSets: 3,
          weight: 60,
          repsTarget: 8,
          repsCompleted: 8,
          rpeHistory: const [],
          restRemainingSecs: null));
      await openFinish(tester);
      expect(completeEnabled(tester), isTrue);
      h.notifier.unlogSets(0, {0, 1, 2}, exerciseName: 'Bench Press');
      await tester.enterText(dialogMinutes, '9');
      await tester.runAsync(() async {
        await tester.tap(completeButton);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Complete Workout?'), findsNothing,
          reason: 'the dialog closes instead of a dead COMPLETE (B-pass 7)');
      expect(h.state.isComplete, isFalse);
      expect(h.state.elapsedSeconds, 125,
          reason: 'the edited duration is not applied');
      expect(HiveService.instance.workoutBox.get('active_session'), isNotNull,
          reason: 'the coach snapshot is not cleared');
      await unmountScreen(tester);
    });
  });

  group('flag OFF (per-set path)', () {
    testWidgets('U-D5: the old count line, no guard lines, not scrollable; '
        'at 380 dp the MIN : SEC label sits on the fields\' line',
        (tester) async {
      // 380 dp under the test font: the row uses 247 of 252 px with spacing 0,
      // so spacing 6 (4 gaps, +24 px) wraps the label (R6-01 moved this off
      // 360 dp, where the old Row already overflowed).
      await narrow(tester, width: 380);
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: logged([0]),
          logMode: false);
      await openFinish(tester);
      expect(find.text('3/6 sets logged'), findsOneWidget);
      expect(find.textContaining('Nothing to save for'), findsNothing);
      expect(dialogScrollable(tester), isFalse);
      // One Wrap run: the label is vertically inside the fields' row.
      final label = tester.getRect(find.text('MIN : SEC'));
      final field = tester.getRect(dialogMinutes);
      expect(label.top, greaterThanOrEqualTo(field.top));
      expect(label.bottom, lessThanOrEqualTo(field.bottom),
          reason: 'one line: the label did not wrap below the fields');
      await unmountScreen(tester);
    });

    testWidgets('U-E2: zero checked sets: the block line, COMPLETE disabled',
        (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press')], logMode: false);
      await openFinish(tester);
      expect(find.text('0/3 sets logged'), findsOneWidget);
      expect(find.text(WardroomCopy.activeFinishZeroSetBlocked),
          findsOneWidget);
      expect(completeEnabled(tester), isFalse);
      await tester.tap(completeButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.state.isComplete, isFalse);
      await unmountScreen(tester);
    });

    testWidgets('U-E2: one checked set with values: the old dialog',
        (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press')],
          seed: (b) => b.copyWith(
              checkedSets: const {'0-0': true},
              setInputValues: const {'0-0': _v}),
          logMode: false);
      await openFinish(tester);
      expect(find.text(WardroomCopy.activeFinishZeroSetBlocked), findsNothing);
      expect(completeEnabled(tester), isTrue);
      expect(dialogScrollable(tester), isFalse);
      await unmountScreen(tester);
    });

    testWidgets('U-E2: blocked at 320 dp × 2.0 with the keyboard up: no '
        'overflow, the dialog scrolls (R7-01)', (tester) async {
      await narrow(tester, scale: 2.0, keyboard: 300);
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press')], logMode: false);
      await scrollToFinish(tester); // the screen's own buttons, as in U-D3
      tester.takeException();
      await openFinish(tester);
      expect(tester.takeException(), isNull);
      expect(dialogScrollable(tester), isTrue);
      expect(find.text(WardroomCopy.activeFinishZeroSetBlocked),
          findsOneWidget);
      await unmountScreen(tester);
    });
  });
}
