// Shared harness for the one-LOG-per-exercise card tests. See
// harness_spike_test.dart for the two load-bearing harness facts (fonts before
// any path_provider mock; Hive-writing taps inside runAsync).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

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
        String type = 'weight_reps'}) =>
    ExerciseData(
        name: name,
        sets: sets,
        reps: '8',
        weight: '0kg',
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
  CardHarness(this.container, this.logCalls);
  final ProviderContainer container;
  final List<Set<int>> logCalls;
  ActiveWorkoutData get state => container.read(activeWorkoutProvider);
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

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: debugExerciseCardHostForTest(
            exerciseIndex: 0,
            onLogExercise: logMode ? onLog : null,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return CardHarness(container, calls);
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
