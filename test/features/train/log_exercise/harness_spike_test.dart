// Harness spike (plan docs/plans/active-workout-log-exercise.md §6 gate):
// proves the private `_ExerciseCard` can be pumped through
// `debugExerciseCardHostForTest` with the real activeWorkoutProvider, and a
// tap on it reaches the provider.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';

import '../../../helpers/hive_test_setup.dart';

class _SeededNotifier extends ActiveWorkoutNotifier {
  _SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

// ORDER IS LOAD-BEARING (precedent test/contracts/exercise_plate_widgets_test.dart):
// the first test renders every AppTypography family with NO path_provider mock,
// so GoogleFonts fails and caches the failure the ordinary way; Hive is then
// opened inside `runAsync` (real disk I/O never completes in fake async).
Directory? _dir;

/// A tap whose handler writes Hive (`_persistActiveState` ->
/// `ActiveWorkoutPersistence.writeState`) must run in the REAL zone: a `put`
/// started in the fake-async zone never completes and then blocks
/// `HiveUserSession.closeAll` in tearDownAll forever (measured: the file hangs
/// with the tap, passes without it).
Future<void> tapWithRealIo(WidgetTester tester, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

void main() {
  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  testWidgets('fonts degrade before any Hive mock', (tester) async {
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
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('card pumps and a set tap reaches the provider', (tester) async {
    await tester.runAsync(() async {
      _dir = await setUpHiveForTests();
    });
    const ex = ExerciseData(
      name: 'Bench Press',
      sets: '3',
      reps: '8',
      weight: '0kg',
      rest: '90s',
      loggingType: 'weight_reps',
    );
    final container = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(kTestUserId),
      activeWorkoutProvider.overrideWith(
          () => _SeededNotifier(const ActiveWorkoutData(exercises: [ex]))),
      lastPerformanceProvider.overrideWith(
          (ref, name) => const LastPerformanceData(lastWeight: 60, lastReps: 8)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: debugExerciseCardHostForTest(exerciseIndex: 0),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6));
    // Post-frame seed captured every set (exercise_card.dart _initControllers).
    expect(container.read(activeWorkoutProvider).setInputValues.length, 3);
    expect(container.read(activeWorkoutProvider).setInputValues['0-0']?.weight,
        60);

    // Tap the first check tile (OFF path) and see the provider change.
    final tiles = find.byWidgetPredicate((w) =>
        w is GestureDetector &&
        w.onTap != null &&
        switch (w.child) {
          final Container c => c.constraints?.maxWidth == 28,
          _ => false,
        });
    expect(tiles, findsWidgets);
    await tapWithRealIo(tester, tiles.first);
    expect(container.read(activeWorkoutProvider).isSetChecked(0, 0), isTrue);
  });
}
