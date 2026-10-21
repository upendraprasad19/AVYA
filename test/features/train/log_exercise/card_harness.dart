// Shared harness for the one-LOG-per-exercise card tests. See
// harness_spike_test.dart for the two load-bearing harness facts (fonts before
// any path_provider mock; Hive-writing taps inside runAsync).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';
import 'package:icanbefitter/features/train/services/swap_move_hint.dart';

import '../../../helpers/hive_test_setup.dart';

class SeededNotifier extends ActiveWorkoutNotifier {
  SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

ExerciseData exercise(
        {String name = 'Bench Press',
        String sets = '3',
        String type = 'weight_reps',
        String weight = '0kg'}) =>
    ExerciseData(
        name: name,
        sets: sets,
        reps: '8',
        weight: weight,
        rest: '90s',
        loggingType: type);

Directory? hiveDir;

Future<void> renderFontsFirst(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Column(children: [
      Text('a', style: AppTypography.h2),
      Text('b', style: AppTypography.h3),
      Text('c', style: AppTypography.mono),
      Text('d', style: AppTypography.monoXs),
      Text('e', style: AppTypography.bodySm),
      Text('f', style: AppTypography.body),
      Text('g', style: AppTypography.numeric),
      Text('h', style: AppTypography.h1),
    ]),
  ));
}

Future<void> ensureHive(WidgetTester tester) async {
  if (hiveDir != null) return;
  await tester.runAsync(() async {
    hiveDir = await setUpHiveForTests();
  });
}

Future<void> closeHive() async {
  if (hiveDir != null) await tearDownHiveForTests(hiveDir!);
  hiveDir = null;
}

/// A tap whose handler writes Hive must run in the real zone.
Future<void> tapWithRealIo(WidgetTester tester, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

class CardHarness {
  CardHarness(this.container, this.logCalls, this.app);
  final ProviderContainer container;
  final List<Set<int>> logCalls;

  /// The pumped tree, so a test can dispose the card (pump something else)
  /// and re-pump it on the SAME container: a card re-init (flip §2 P5).
  final Widget app;
  int reopenCalls = 0;
  ActiveWorkoutData get state => container.read(activeWorkoutProvider);
}

/// Disposes the card and pumps it again on the same container (re-entry).
Future<void> repumpCard(WidgetTester tester, CardHarness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(h.app);
  await tester.pump();
}

/// Pumps the real card. [logMode] passes an `onLogExercise` that behaves like
/// the screen: `logSets` on the real notifier.
Future<CardHarness> pumpCard(
  WidgetTester tester, {
  required ActiveWorkoutData seed,
  required bool logMode,
  LastPerformanceData lastPerf =
      const LastPerformanceData(lastWeight: 60, lastReps: 8),
}) async {
  await ensureHive(tester);
  final calls = <Set<int>>[];
  final container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(() => SeededNotifier(seed)),
    lastPerformanceProvider.overrideWith((ref, name) => lastPerf),
  ]);
  addTearDown(container.dispose);
  LogOutcomeKind onLog(Set<int> idxs) {
    calls.add(idxs);
    container.read(activeWorkoutProvider.notifier).logSets(0, idxs);
    return LogOutcomeKind.logged;
  }

  late final CardHarness h;
  // Like the screen: RE-OPEN unchecks every checked set (no guard here; the
  // guard is the controller's, tested there).
  void onReopen() {
    h.reopenCalls++;
    final data = container.read(activeWorkoutProvider);
    final n = int.tryParse(data.exercises[0].sets) ?? 3;
    container.read(activeWorkoutProvider.notifier).unlogSets(
        0, {for (var i = 0; i < n; i++) if (data.isSetChecked(0, i)) i},
        exerciseName: data.exercises[0].name, reopened: true);
  }

  final app = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: debugExerciseCardHostForTest(
            exerciseIndex: 0,
            onLogExercise: logMode ? onLog : null,
            onReopenExercise: logMode ? onReopen : null,
          ),
        ),
      ),
    ),
  );
  h = CardHarness(container, calls, app);
  await tester.pumpWidget(app);
  await tester.pump();
  return h;
}

/// The per-set path's interactive 28 px check tiles.
Finder get interactiveCheckTiles => find.byWidgetPredicate((w) =>
    w is GestureDetector &&
    w.onTap != null &&
    switch (w.child) {
      final Container c => c.constraints?.maxWidth == 28,
      _ => false,
    });

Finder fieldAt(int i) => find.byType(TextField).at(i);

TextEditingController controllerAt(WidgetTester tester, int i) =>
    tester.widget<TextField>(fieldAt(i)).controller!;

bool hasFocus(WidgetTester tester, int i) =>
    tester.widget<TextField>(fieldAt(i)).focusNode?.hasFocus ?? false;

/// The real `ActiveWorkoutScreen` on a seeded session (flip batch S1/U-D/U-E).
/// [logMode] writes the flag: absent = ON (the flip), `false` = killed.
/// [hintSeen]: the ⇄/⇅ first-use hint is retired by default — its ring
/// pulses forever while it shows, so `pumpAndSettle` would never settle. The
/// hint's own tests (`swap_move_screen_test.dart`) pass `false`.
class ScreenHarness {
  ScreenHarness(this.container);
  final ProviderContainer container;
  ActiveWorkoutData get state => container.read(activeWorkoutProvider);
  ActiveWorkoutNotifier get notifier =>
      container.read(activeWorkoutProvider.notifier);
}

Future<ScreenHarness> pumpScreen(
  WidgetTester tester, {
  required List<ExerciseData> exercises,
  ActiveWorkoutData Function(ActiveWorkoutData base)? seed,
  bool logMode = true,
  bool? hintSeen = true, // null: leave the stored flag as it is
  LastPerformanceData lastPerf =
      const LastPerformanceData(lastWeight: 60, lastReps: 8),
}) async {
  await ensureHive(tester);
  await tester.runAsync(() async {
    final box = HiveService.instance.configBox;
    if (logMode) {
      await box.delete(LogExerciseFlags.key);
    } else {
      await box.put(LogExerciseFlags.key, false);
    }
    if (hintSeen == true) {
      await markSwapMoveHintSeen();
    } else if (hintSeen == false) {
      await HiveService.instance.userBox.delete(kSwapMoveHintSeenKey);
    }
  });
  final base = ActiveWorkoutData(
    workoutDay:
        WorkoutDayData(dayNumber: 1, name: 'Flip Day', exercises: exercises),
    exercises: exercises,
  );
  final container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider
        .overrideWith(() => SeededNotifier(seed?.call(base) ?? base)),
    lastPerformanceProvider.overrideWith((ref, name) => lastPerf),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: ActiveWorkoutScreen()),
  ));
  await tester.pump();
  return ScreenHarness(container);
}

/// Unmounts the screen in the real zone (its dispose writes nothing, but a
/// pending Hive write from a tap must finish before tearDownAll closes Hive).
Future<void> unmountScreen(WidgetTester tester) =>
    tester.runAsync(() => tester.pumpWidget(const SizedBox()));

/// Scrolls the FINISH button into view (the list builds it lazily, and its
/// extent grows as it builds, so jump to the end until it is there).
Future<void> scrollToFinish(WidgetTester tester) async {
  final finish = find.text('✓ FINISH WORKOUT');
  final list = tester.widget<ListView>(find.byType(ListView)).controller!;
  for (var i = 0; i < 20 && finish.evaluate().isEmpty; i++) {
    list.jumpTo(list.position.maxScrollExtent);
    await tester.pump();
  }
  await tester.ensureVisible(finish);
  await tester.pump();
}

/// Scrolls the FINISH button into view and taps it.
Future<void> openFinish(WidgetTester tester) async {
  await scrollToFinish(tester);
  await tester.tap(find.text('✓ FINISH WORKOUT'));
  await tester.pumpAndSettle();
}
