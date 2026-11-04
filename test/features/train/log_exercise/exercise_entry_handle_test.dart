// Batch M2b Part B, Task B1: the card's table header + set rows + LOG row as
// builders over the card's OWN controllers (`ExerciseEntryHandle`), so a second
// host (the logging viewer) edits the same boxes and logs through the same
// path. Plan docs/plans/2026-11-03-library-batch-m2b-viewer.md (B1).
//
// The mounted host below stands in for the viewer: a NON-opaque route on the
// harness Navigator (an opaque one would pause the covered card's Riverpod
// watches, `overlay.dart:868-889`, and no controller would ever be appended)
// whose page is a bare `Consumer` with ITS OWN FocusNodes.
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_entry_handle.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

import '../../../helpers/fake_exercise_media_repository.dart';
import '../../../helpers/hive_test_setup.dart';
import 'card_harness.dart';

class _HostPage extends StatefulWidget {
  const _HostPage(this.handle, {required this.afterLogged});
  final ExerciseEntryHandle handle;
  final VoidCallback afterLogged;

  @override
  State<_HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<_HostPage> {
  final _nodes = <(int, SetField), FocusNode>{};

  FocusNode? _nodeFor(int setIdx, SetField field) =>
      _nodes.putIfAbsent((setIdx, field), FocusNode.new);

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      final data = ref.watch(activeWorkoutProvider);
      return Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(children: [
            widget.handle.buildRows(ctx, data, _nodeFor),
            widget.handle.buildLogRow(ctx, data, _nodeFor, widget.afterLogged),
          ]),
        ),
      );
    });
  }
}

class _Rig {
  late CardHarness h;
  ExerciseEntryHandle? handle;
  int afterLoggedCalls = 0;
}

/// The host's own boxes (the route has no Scaffold) and the card's boxes (the
/// harness page is the only Scaffold).
Finder _hostFields() =>
    find.descendant(of: find.byType(_HostPage), matching: find.byType(TextField));
Finder _cardFields() =>
    find.descendant(of: find.byType(Scaffold), matching: find.byType(TextField));
Finder _hostText(String t) =>
    find.descendant(of: find.byType(_HostPage), matching: find.text(t));
TextEditingController _ctrl(WidgetTester tester, Finder f) =>
    tester.widget<TextField>(f).controller!;

Future<void> _pushHost(
  WidgetTester tester,
  ExerciseEntryHandle handle,
  VoidCallback afterLogged,
) async {
  final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
  unawaited(nav.push(PageRouteBuilder<void>(
    opaque: false,
    maintainState: true,
    pageBuilder: (_, _, _) => _HostPage(handle, afterLogged: afterLogged),
  )));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<_Rig> _pumpRig(
  WidgetTester tester, {
  LogExerciseCallback? onLogExercise,
  LastPerformanceData lastPerf = const LastPerformanceData(),
  bool mountHost = true,
}) async {
  final rig = _Rig();
  rig.h = await pumpCard(tester,
      seed: ActiveWorkoutData(exercises: [exercise()]),
      logMode: true,
      lastPerf: lastPerf,
      onLogExercise: onLogExercise,
      onHandleForTest: (hd) => rig.handle = hd);
  expect(rig.handle, isNotNull,
      reason: 'the seam hands over the handle after the first frame');
  if (mountHost) {
    await _pushHost(tester, rig.handle!, () => rig.afterLoggedCalls++);
  }
  return rig;
}

/// The number of set rows `buildRows` returned, read WITHOUT mounting it.
int _setRowCount(Widget rows) {
  expect(rows, isA<Column>(), reason: 'buildRows returns a Column');
  return (rows as Column).children.whereType<Padding>().length;
}

/// A card plus a flag that flips the LOG mode off and a switch that takes the
/// card out of the tree, on a container the test owns.
class _Flip {
  final enabled = ValueNotifier<bool>(true);
  final showCard = ValueNotifier<bool>(true);
  late ProviderContainer container;
  ExerciseEntryHandle? handle;
  int afterLoggedCalls = 0;
}

Future<_Flip> _pumpFlippable(WidgetTester tester) async {
  await ensureHive(tester);
  await seedLibrary(tester);
  final f = _Flip();
  addTearDown(f.enabled.dispose);
  addTearDown(f.showCard.dispose);
  f.container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(
        () => SeededNotifier(ActiveWorkoutData(exercises: [exercise()]))),
    lastPerformanceProvider.overrideWith(
        (ref, name) => const LastPerformanceData(lastWeight: 60, lastReps: 8)),
    ...mediaOverrides(FakeExerciseMediaRepository()),
  ]);
  addTearDown(f.container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: f.container,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([f.enabled, f.showCard]),
            builder: (_, _) => f.showCard.value
                ? debugExerciseCardHostForTest(
                    exerciseIndex: 0,
                    onLogExercise:
                        f.enabled.value ? (_) => LogOutcomeKind.logged : null,
                    onHandleForTest: (hd) => f.handle ??= hd,
                  )
                : const SizedBox(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  expect(f.handle, isNotNull);
  await _pushHost(tester, f.handle!, () => f.afterLoggedCalls++);
  return f;
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('typing and focus in the second host', () {
    testWidgets('a value typed in the host is the card box value, and the '
        'mirror and the provider follow', (tester) async {
      final rig = await _pumpRig(tester);
      await tester.enterText(_hostFields().at(0), '55');
      await tester.pump();
      expect(_ctrl(tester, _cardFields().at(0)).text, '55');
      // Batch 2 mirror: set 1's weight fills the blank sets 2 and 3 (card
      // controllers, so the host's boxes show it too).
      expect(_ctrl(tester, _cardFields().at(2)).text, '55');
      expect(_ctrl(tester, _cardFields().at(4)).text, '55');
      expect(_ctrl(tester, _hostFields().at(2)).text, '55');
      final state = rig.h.state;
      expect(state.setInputValues['0-0']?.weight, 55);
      expect(state.setInputValues['0-2']?.weight, 55);
      expect(state.suggestedInputs.contains(suggestedKey(0, 1, SetField.weight)),
          isTrue,
          reason: 'a mirrored box is app-filled until the user types');
      expect(state.suggestedInputs.contains(suggestedKey(0, 0, SetField.weight)),
          isFalse,
          reason: 'the box the user typed in is not');
    });

    testWidgets('a blocked LOG in the host focuses the HOST field, not the '
        'card field', (tester) async {
      final rig = await _pumpRig(tester);
      expect(_hostText('Add weight'), findsOneWidget);
      await tester.tap(_hostText('Add weight'));
      await tester.pump();
      expect(tester.widget<TextField>(_hostFields().at(0)).focusNode!.hasFocus,
          isTrue);
      expect(tester.widget<TextField>(_cardFields().at(0)).focusNode!.hasFocus,
          isFalse);
      expect(rig.h.logCalls, isEmpty);
    });
  });

  group('the count guard (the frame between a +/- and the controller resize)',
      () {
    testWidgets('grow: data says 4, controllers say 3: 3 rows, no throw, then '
        '4', (tester) async {
      final rig = await _pumpRig(tester, mountHost: false);
      final ctx = tester.element(find.byType(Scaffold).first);
      Widget rows() => rig.handle!.buildRows(
          ctx, rig.h.container.read(activeWorkoutProvider), (_, _) => null);
      rig.h.container.read(activeWorkoutProvider.notifier).addSet(0);
      // BEFORE any pump: the provider says 4, the card still owns 3 controllers.
      expect(rig.h.state.exercises[0].sets, '4');
      expect(_setRowCount(rows()), 3);
      await tester.pump();
      await tester.pump();
      expect(_setRowCount(rows()), 4);
    });

    testWidgets('shrink: data says 2, controllers say 3: 2 rows, no throw',
        (tester) async {
      final rig = await _pumpRig(tester, mountHost: false);
      final ctx = tester.element(find.byType(Scaffold).first);
      Widget rows() => rig.handle!.buildRows(
          ctx, rig.h.container.read(activeWorkoutProvider), (_, _) => null);
      rig.h.container.read(activeWorkoutProvider.notifier).removeLastSet(0);
      expect(rig.h.state.exercises[0].sets, '2');
      expect(_setRowCount(rows()), 2);
      await tester.pump();
      expect(_cardFields().evaluate().length, 4, reason: '2 sets x KG + REPS');
    });

    testWidgets('a mounted host follows + to 4 rows and keeps the card in step',
        (tester) async {
      final rig = await _pumpRig(tester,
          lastPerf: const LastPerformanceData(lastWeight: 60, lastReps: 8));
      expect(_hostFields().evaluate().length, 6);
      expect(_hostText('LOG 3 SETS ✓'), findsOneWidget);
      rig.h.container.read(activeWorkoutProvider.notifier).addSet(0);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_hostFields().evaluate().length, 8);
      expect(_cardFields().evaluate().length, 8);
      expect(_hostText('LOG 4 SETS ✓'), findsOneWidget);
    });
  });

  group('afterLogged runs only when the LOG really logged', () {
    testWidgets('logged: once', (tester) async {
      final rig = await _pumpRig(tester,
          lastPerf: const LastPerformanceData(lastWeight: 60, lastReps: 8),
          onLogExercise: (_) => LogOutcomeKind.logged);
      await tapWithRealIo(tester, _hostText('LOG 3 SETS ✓'));
      expect(rig.h.logCalls, hasLength(1));
      expect(rig.afterLoggedCalls, 1);
    });

    for (final outcome in [
      LogOutcomeKind.ignored,
      LogOutcomeKind.noop,
      LogOutcomeKind.reopened,
    ]) {
      testWidgets('$outcome: never', (tester) async {
        final rig = await _pumpRig(tester,
            lastPerf: const LastPerformanceData(lastWeight: 60, lastReps: 8),
            onLogExercise: (_) => outcome);
        await tapWithRealIo(tester, _hostText('LOG 3 SETS ✓'));
        expect(rig.h.logCalls, hasLength(1),
            reason: 'the LOG path itself ran');
        expect(rig.afterLoggedCalls, 0);
      });
    }

    testWidgets('a blocked LOG (set 1 blank): never, and nothing was logged',
        (tester) async {
      final rig = await _pumpRig(tester,
          onLogExercise: (_) => LogOutcomeKind.logged);
      await tapWithRealIo(tester, _hostText('Add weight'));
      expect(rig.h.logCalls, isEmpty);
      expect(rig.afterLoggedCalls, 0);
    });
  });

  group('a host that outlives the state it borrows from', () {
    testWidgets('the LOG flag flips off under a mounted host: its LOG does '
        'not throw', (tester) async {
      final f = await _pumpFlippable(tester);
      f.enabled.value = false;
      await tester.pump();
      await tapWithRealIo(tester, _hostText('LOG 3 SETS ✓'));
      expect(tester.takeException(), isNull);
      expect(f.afterLoggedCalls, 0);
    });

    testWidgets('the card is disposed under a mounted host: the host '
        'rebuilds to nothing instead of mounting fields on disposed '
        'controllers', (tester) async {
      final f = await _pumpFlippable(tester);
      expect(_hostFields(), findsWidgets);
      f.showCard.value = false;
      await tester.pump();
      f.container.read(activeWorkoutProvider.notifier).setElapsedSeconds(5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_hostFields(), findsNothing);
    });
  });
}
