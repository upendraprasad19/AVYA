// Card header ⇄ swap / ⇅ move (docs/plans/active-workout-swap-move.md
// Task 5): the icons, the per-role move-mode header (target places, source
// cancels, done is inert), reduce motion, and a 360 dp header. Real card via
// `debugExerciseCardHostForTest`; harness facts in log_exercise/card_harness.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/exercise_move_logic.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

import '../../helpers/hive_test_setup.dart';
import 'log_exercise/card_harness.dart';

class _Calls {
  int focus = 0, swap = 0, move = 0, moveHere = 0, longPress = 0;
}

Future<_Calls> _pumpHeader(
  WidgetTester tester, {
  bool done = false,
  bool logMode = false,
  bool moveModeActive = false,
  MoveRole moveRole = MoveRole.none,
  bool canMove = true,
  bool moveTargetAbove = false,
  bool showHintRing = false,
  bool disableAnimations = false,
  double? width,
  String name = 'Bench Press',
}) async {
  await ensureHive(tester);
  final calls = _Calls();
  final seed = ActiveWorkoutData(
    exercises: [exercise(name: name)],
    checkedSets: done ? const {'0-0': true, '0-1': true, '0-2': true} : const {},
  );
  final container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(() => SeededNotifier(seed)),
    lastPerformanceProvider.overrideWith(
        (ref, name) => const LastPerformanceData(lastWeight: 60, lastReps: 8)),
  ]);
  addTearDown(container.dispose);
  Widget card = debugExerciseCardHostForTest(
    exerciseIndex: 0,
    isExpanded: false,
    onLogExercise: logMode ? (_) => LogOutcomeKind.logged : null,
    onFocus: () => calls.focus++,
    onSwap: () => calls.swap++,
    onMove: () => calls.move++,
    onMoveHere: () => calls.moveHere++,
    onLongPressHeader: () => calls.longPress++,
    moveModeActive: moveModeActive,
    moveRole: moveRole,
    canMove: canMove,
    moveTargetAbove: moveTargetAbove,
    showHintRing: showHintRing,
  );
  if (width != null) card = SizedBox(width: width, child: card);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Align(alignment: Alignment.topLeft, child: card)),
      ),
    ),
  ));
  await tester.pump();
  return calls;
}

Finder get swapIcon => find.bySemanticsLabel(WardroomCopy.activeSwapExerciseLabel);
Finder get moveIcon => find.bySemanticsLabel(WardroomCopy.activeMoveExerciseLabel);
Finder get plate => find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'ExercisePlateThumb');

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('normal: one ⇄ and one ⇅, labelled; no text chip; taps route',
      (tester) async {
    final sem = tester.ensureSemantics();
    final c = await _pumpHeader(tester);
    expect(swapIcon, findsOneWidget);
    expect(moveIcon, findsOneWidget);
    expect(find.text('⇄ SWAP'), findsNothing);
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.tap(find.byIcon(Icons.swap_vert));
    await tester.tap(find.text('Bench Press'));
    expect((c.swap, c.move, c.focus), (1, 1, 1));
    sem.dispose();
  });

  testWidgets('both LOG modes render the icons', (tester) async {
    await _pumpHeader(tester, logMode: true);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    await _pumpHeader(tester, logMode: false);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
  });

  testWidgets('canMove false hides ⇅ only', (tester) async {
    await _pumpHeader(tester, canMove: false);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
  });

  testWidgets('done (normal): DONE chip only; tapping it focuses',
      (tester) async {
    final c = await _pumpHeader(tester, done: true);
    expect(find.text('✓ DONE'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
    await tester.tap(find.text('✓ DONE'));
    expect(c.focus, 1);
  });

  testWidgets('target: MOVE HERE pill, no icons; the whole header places',
      (tester) async {
    final c = await _pumpHeader(tester,
        moveModeActive: true, moveRole: MoveRole.target, moveTargetAbove: true);
    expect(find.text(WardroomCopy.activeMoveHereUp), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
    await tester.tap(find.text('Bench Press'));
    await tester.tap(plate);
    await tester.tap(find.text(WardroomCopy.activeMoveHereUp));
    await tester.pump();
    expect(c.moveHere, 3);
    expect(c.focus, 0);
    expect(find.byType(BottomSheet), findsNothing, reason: 'no plate sheet');
  });

  testWidgets('target below shows the down arrow', (tester) async {
    await _pumpHeader(tester, moveModeActive: true, moveRole: MoveRole.target);
    expect(find.text(WardroomCopy.activeMoveHereDown), findsOneWidget);
  });

  testWidgets('source: ⇄ + filled ⇅ + MOVING; header and ⇅ cancel',
      (tester) async {
    final c = await _pumpHeader(tester,
        moveModeActive: true, moveRole: MoveRole.source);
    expect(find.text(WardroomCopy.activeMovingTag), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    await tester.tap(find.text('Bench Press'));
    await tester.tap(find.byIcon(Icons.swap_vert));
    await tester.tap(find.byIcon(Icons.swap_horiz));
    expect((c.move, c.swap, c.focus), (2, 1, 0));
  });

  testWidgets('done in move mode: dimmed, every tap inert', (tester) async {
    final c = await _pumpHeader(tester,
        done: true, moveModeActive: true, moveRole: MoveRole.none);
    final opacity = tester.widget<Opacity>(find
        .ancestor(of: find.text('Bench Press'), matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, 0.5);
    await tester.tap(find.text('✓ DONE'));
    await tester.tap(find.text('Bench Press'));
    await tester.tap(plate);
    await tester.pump();
    expect((c.focus, c.move, c.moveHere), (0, 0, 0));
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('long-press pairs supersets only outside move mode',
      (tester) async {
    final normal = await _pumpHeader(tester);
    await tester.longPress(find.text('Bench Press'));
    expect(normal.longPress, 1);
    final moving = await _pumpHeader(tester,
        moveModeActive: true, moveRole: MoveRole.target);
    await tester.longPress(find.text('Bench Press'));
    expect(moving.longPress, 0);
  });

  testWidgets('reduce motion: a target glow holds still', (tester) async {
    await _pumpHeader(tester, disableAnimations: true);
    final baseline = tester.binding.transientCallbackCount;
    await _pumpHeader(tester,
        moveModeActive: true, moveRole: MoveRole.target, disableAnimations: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, baseline);

    // Control: with motion allowed the same target pulses.
    await _pumpHeader(tester, moveModeActive: true, moveRole: MoveRole.target);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(baseline));
  });

  testWidgets('reduce motion: the hint ring holds still', (tester) async {
    await _pumpHeader(tester, disableAnimations: true);
    final baseline = tester.binding.transientCallbackCount;
    await _pumpHeader(tester, showHintRing: true, disableAnimations: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, baseline);
  });

  testWidgets('360 dp: a long name and the MOVE HERE pill do not overflow',
      (tester) async {
    await _pumpHeader(tester,
        width: 360,
        name: 'Single-Arm Dumbbell Bench Press',
        moveModeActive: true,
        moveRole: MoveRole.target);
    expect(tester.takeException(), isNull);
    await _pumpHeader(tester, width: 360, name: 'Single-Arm Dumbbell Bench Press');
    expect(tester.takeException(), isNull);
  });
}
