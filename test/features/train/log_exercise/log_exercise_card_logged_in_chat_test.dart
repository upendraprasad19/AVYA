// Coach workout parity 1c (OI-491), the card / screen / dialog half: an
// exercise the coach logged in chat opens DONE (LOGGED IN CHAT, the coach's
// chips, no stepper); RE-OPEN shows new rows numbered after the coach's sets
// and KEEP AS LOGGED while no row is checked. Plan:
// docs/plans/coach-workout-parity-1c.md (C3, C6, widget tests).
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_entry_handle.dart';
import 'package:icanbefitter/features/train/services/chat_logged_exercises.dart';
import 'package:icanbefitter/features/train/widgets/set_input_row.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_set_chips.dart';

import 'card_harness.dart';

ChatLoggedExercise chatEntry(String name,
        {int coach = 1,
        int planned = 3,
        String type = 'weight_reps',
        List<ExerciseSet>? sets}) =>
    ChatLoggedExercise(
      loggedName: name,
      loggingType: type,
      sets: sets ??
          [for (var i = 0; i < coach; i++) const ExerciseSet(weightKg: 60, reps: 8)],
      coachCount: coach,
      plannedSets: planned,
    );

ActiveWorkoutData chatSeed({
  String type = 'weight_reps',
  int coach = 1,
  int planned = 3,
  List<ExerciseSet>? sets,
  Set<String> reopened = const {},
  String exerciseSets = '3',
  bool isSaved = false,
  Map<String, bool> checked = const {},
  Map<String, bool> warmUps = const {},
}) =>
    ActiveWorkoutData(
      exercises: [exercise(type: type, sets: exerciseSets)],
      loggedInChat: {
        'bench press':
            chatEntry('Bench Press', coach: coach, planned: planned, type: type, sets: sets),
      },
      reopenedExercises: reopened,
      isSaved: isSaved,
      checkedSets: checked,
      warmUpSets: warmUps,
    );

Finder get chatButton => find.byWidgetPredicate((w) =>
    w is Semantics && w.properties.label == WardroomCopy.activeLoggedInChatSemantics);

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('a chat-done card', () {
    testWidgets('LOGGED IN CHAT button with TAP TO RE-OPEN, the eyebrow, the '
        'coach chips; no stepper, no rows', (tester) async {
      await pumpCard(tester, seed: chatSeed(coach: 2), logMode: true);
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNWidgets(2));
      expect(find.text(WardroomCopy.activeReopenSubline), findsOneWidget);
      final chips = tester.widget<WardSetChips>(find.byType(WardSetChips));
      expect(chips.perSetBreakdown.length, 2);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byType(SetInputRow), findsNothing);
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsNothing);
    });

    for (final type in ['timed', 'cardio']) {
      testWidgets('chips for $type', (tester) async {
        await pumpCard(tester,
            seed: chatSeed(type: type, sets: const [
              ExerciseSet(weightKg: 0, reps: 0, durationSec: 45, distanceKm: 1.2),
            ]),
            logMode: true);
        final chips = tester.widget<WardSetChips>(find.byType(WardSetChips));
        expect(chips.loggingType, type);
        expect(chips.perSetBreakdown.single.durationSeconds, 45);
      });
    }

    testWidgets('Semantics: the button reads "Logged in chat"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester, seed: chatSeed(), logMode: true);
      expect(chatButton, findsOneWidget);
      handle.dispose();
    });

    testWidgets('the chat branch wins over a FORCED validation failure (a '
        'blank weight on a new user)', (tester) async {
      await pumpCard(tester,
          seed: chatSeed(),
          logMode: true,
          lastPerf: const LastPerformanceData());
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNWidgets(2));
      expect(find.textContaining('LOG 3 SETS'), findsNothing);
    });

    testWidgets('mirror: the same new user WITHOUT a chat entry is blocked '
        '(proves the fixture forces a failure)', (tester) async {
      await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          lastPerf: const LastPerformanceData());
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNothing);
      expect(find.text('LOG 3 SETS ✓'), findsNothing);
    });

    testWidgets('review mode: the chat button has no tap and there is no KEEP',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpCard(tester,
          seed: chatSeed(isSaved: true), logMode: true);
      expect(find.text(WardroomCopy.activeReopenSubline), findsNothing);
      final node = tester.getSemantics(chatButton).getSemanticsData();
      expect(node.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.text(WardroomCopy.activeLoggedInChatLabel).last,
          warnIfMissed: false);
      await tester.pump();
      expect(h.reopenCalls, 0);
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsNothing);
      handle.dispose();
    });

    for (final width in [360.0, 1024.0]) {
      testWidgets('lays out at $width dp with no overflow', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpCard(tester, seed: chatSeed(coach: 3), logMode: true);
        expect(tester.takeException(), isNull);
        expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNWidgets(2));
      });
    }
  });

  group('re-open and KEEP', () {
    testWidgets('a tap re-opens: rows, eyebrow, chips, KEEP; the first new row '
        'is numbered coachCount + 1; the meta text shows plannedSets',
        (tester) async {
      final h = await pumpCard(tester, seed: chatSeed(coach: 1), logMode: true);
      await tester.tap(find.text(WardroomCopy.activeLoggedInChatLabel).last);
      await tester.pump();
      await tester.pump();
      expect(h.reopenCalls, 1);
      expect(h.state.reopenedExercises, {'Bench Press'});
      expect(h.state.exercises[0].sets, '2');
      expect(find.byType(WardSetChips), findsOneWidget);
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsOneWidget);
      final rows = tester.widgetList<SetInputRow>(find.byType(SetInputRow));
      expect(rows.map((r) => r.setNumber), [2, 3]);
      expect(find.textContaining('3 sets'), findsOneWidget);
    });

    for (final type in ['timed', 'bodyweight_reps', 'weighted_bodyweight']) {
      testWidgets('meta text shows plannedSets on a re-opened $type card',
          (tester) async {
        await pumpCard(tester,
            seed: chatSeed(
                type: type, reopened: {'Bench Press'}, exerciseSets: '2'),
            logMode: true);
        await tester.pump();
        expect(find.textContaining('3 sets'), findsOneWidget);
        expect(find.textContaining('2 sets'), findsNothing);
      });
    }

    testWidgets('checking a new set hides KEEP', (tester) async {
      final h = await pumpCard(tester,
          seed: chatSeed(reopened: {'Bench Press'}, exerciseSets: '2'),
          logMode: true);
      await tester.pump();
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsOneWidget);
      h.container.read(activeWorkoutProvider.notifier).logSets(0, {0});
      await tester.pump();
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsNothing);
    });

    testWidgets('a checked WARM-UP-only row hides KEEP and keepChatLogged '
        'refuses', (tester) async {
      final h = await pumpCard(tester,
          seed: chatSeed(
              reopened: {'Bench Press'},
              exerciseSets: '2',
              checked: const {'0-0': true},
              warmUps: const {'0-0': true}),
          logMode: true);
      await tester.pump();
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsNothing);
      expect(
          h.container
              .read(activeWorkoutProvider.notifier)
              .keepChatLogged(0, 'Bench Press'),
          isFalse);
    });

    testWidgets('mirror: an UNCHECKED warm-up row shows KEEP and it works',
        (tester) async {
      final h = await pumpCard(tester,
          seed: chatSeed(
              reopened: {'Bench Press'},
              exerciseSets: '2',
              warmUps: const {'0-0': true}),
          logMode: true);
      await tester.pump();
      await tester.tap(find.text(WardroomCopy.activeKeepLoggedInChat));
      await tester.pump();
      await tester.pump();
      expect(h.keepCalls, 1);
      expect(h.keepResult, isTrue);
      expect(h.state.reopenedExercises, isEmpty);
      expect(h.state.exercises[0].sets, '3');
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNWidgets(2));
    });
  });

  group('flag OFF (per-set path)', () {
    testWidgets('a chat entry in state does not change a per-set card '
        '(B-pass S2-F2)', (tester) async {
      await pumpCard(tester, seed: chatSeed(coach: 2), logMode: false);
      await tester.pump();
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNothing);
      expect(find.text(WardroomCopy.activeKeepLoggedInChat), findsNothing);
      expect(find.byType(WardSetChips), findsNothing);
      expect(find.byType(SetInputRow), findsNWidgets(3));
    });
  });

  group('the logging viewer host', () {
    testWidgets('a STALE widget.data (no chat entry) and a fresh data with the '
        'entry: the handle builds the chat state from the fresh data',
        (tester) async {
      ExerciseEntryHandle? handle;
      final h = await pumpCard(tester,
          seed: ActiveWorkoutData(exercises: [exercise()]),
          logMode: true,
          onHandleForTest: (x) => handle = x);
      await tester.pump();
      expect(handle, isNotNull);
      final fresh = h.state.copyWith(loggedInChat: {
        'bench press': chatEntry('Bench Press'),
      });
      final ctx = tester.element(find.byType(Scaffold).first);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            handle!.buildRows(ctx, fresh, (_, _) => null),
            handle!.buildLogRow(ctx, fresh, (_, _) => null, () {}),
          ]),
        ),
      ));
      expect(find.text(WardroomCopy.activeLoggedInChatLabel), findsNWidgets(2));
      expect(find.byType(SetInputRow), findsNothing);
    });
  });

  group('screen and dialog', () {
    testWidgets('header counts the coach sets on both sides', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: (b) => b.copyWith(loggedInChat: {
                'bench press': chatEntry('Bench Press', coach: 2),
              }));
      expect(find.text('2 / 5 SETS'), findsOneWidget);
      await unmountScreen(tester);
    });

    testWidgets('a fully chat-logged day: FINISH shows the F3 line and '
        'COMPLETE is disabled', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: (b) => b.copyWith(loggedInChat: {
                'bench press': chatEntry('Bench Press'),
                'row': chatEntry('Row'),
              }));
      await openFinish(tester);
      expect(find.text(WardroomCopy.activeFinishAllLoggedInChat),
          findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'COMPLETE'))
              .onPressed,
          isNull);
      await unmountScreen(tester);
    });

    testWidgets('the real screen: LOGGED IN CHAT re-opens through '
        'reopenChatLogged, KEEP AS LOGGED undoes it, and a second re-open '
        'starts with the prefill captured and marked (B-pass S2-F1, S2-F3)',
        (tester) async {
      final h = await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press')],
          seed: (b) => b.copyWith(loggedInChat: {
                'bench press': chatEntry('Bench Press'),
              }));
      await tester.pump();
      Future<void> tapChatButton() async {
        await tester.tap(find.text(WardroomCopy.activeLoggedInChatLabel).last);
        await tester.pump();
        await tester.pump();
      }

      await tapChatButton();
      expect(h.state.reopenedExercises, {'Bench Press'});
      expect(h.state.exercises[0].sets, '2');
      expect(find.byType(SetInputRow), findsNWidgets(2));

      await tester.tap(find.text(WardroomCopy.activeKeepLoggedInChat));
      await tester.pump();
      await tester.pump();
      expect(h.state.reopenedExercises, isEmpty);
      expect(h.state.exercises[0].sets, '3');
      expect(find.byType(SetInputRow), findsNothing);

      // The re-open guard runs on a real Stopwatch.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1300)));
      await tapChatButton();
      expect(h.state.reopenedExercises, {'Bench Press'});
      expect(h.state.setInputValues['0-0'], isNotNull);
      expect(h.state.suggestedInputs.where((k) => k.startsWith('0-0-')),
          isNotEmpty);
      // Let the re-open's focus scroll finish before the tree goes.
      await tester.pump(const Duration(seconds: 2));
      await unmountScreen(tester);
    });

    testWidgets('focus skips a chat-done card: the next plain card is the '
        'expanded one (B-pass S2-F1)', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: (b) => b.copyWith(loggedInChat: {
                'bench press': chatEntry('Bench Press'),
              }));
      await tester.pump();
      expect(find.byType(SetInputRow), findsNWidgets(3));
      await unmountScreen(tester);
    });

    testWidgets('a mixed day with nothing new: the F4 line', (tester) async {
      await pumpScreen(tester,
          exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')],
          seed: (b) => b.copyWith(loggedInChat: {
                'bench press': chatEntry('Bench Press'),
              }));
      await openFinish(tester);
      expect(find.text(WardroomCopy.activeFinishNoNewSets), findsOneWidget);
      await unmountScreen(tester);
    });
  });
}
