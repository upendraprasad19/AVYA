// Batch M2b Part B, Task B2: the viewer on a REAL `StatefulShellRoute` (the
// shape the Train tab has in the app): the screen is the CHILD route
// `/train/active-workout` of a branch, with a shell bottom bar above the branch
// navigator. `pumpScreen`'s single Navigator cannot show any of this.
//
// What the branch-navigator hosting (plan call C-a) promises, pinned here:
// the shell's bar stays visible and tappable; Android system back pops the
// viewer first; a re-route inside the branch removes the pageless viewer with
// its page; a branch switch hides it with its branch and it is there when you
// come back; the viewer's navigator is the branch one, not the root.
@Timeout(Duration(minutes: 6))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_header_tile.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_media_viewer.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';
import 'package:icanbefitter/features/train/services/swap_move_hint.dart';

import '../../../helpers/fake_exercise_media_repository.dart';
import '../../../helpers/hive_test_setup.dart';
import 'card_harness.dart';

const _bench = 'Barbell Bench Press';

final _rows = <Map<String, dynamic>>[
  {
    'id': 'R_BENCH',
    'name': _bench,
    'media_slug': '0025-barbell-bench-press',
    'media_version': 1,
    'coaching_cues': ['Keep your wrists stacked'],
  },
];

Finder get _viewer => find.byType(ExerciseMediaViewer);

class _Shell {
  _Shell(this.router, this.container);
  final GoRouter router;
  final ProviderContainer container;
}

/// The real screen at the child route of a two-branch shell with a bottom bar.
Future<_Shell> _pumpShell(WidgetTester tester) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: _rows);
  await tester.runAsync(() async {
    await HiveService.instance.configBox.delete(LogExerciseFlags.key);
    await markSwapMoveHintSeen();
  });
  final ex = [exercise(name: _bench)];
  final container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(() => SeededNotifier(ActiveWorkoutData(
          workoutDay:
              WorkoutDayData(dayNumber: 1, name: 'Flip Day', exercises: ex),
          exercises: ex,
        ))),
    lastPerformanceProvider.overrideWith(
        (ref, name) => const LastPerformanceData(lastWeight: 60, lastReps: 8)),
    ...mediaOverrides(FakeExerciseMediaRepository()),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/train/active-workout',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.fitness_center), label: 'Train'),
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const Text('HOME PAGE')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/train',
              builder: (_, _) => const Text('TRAIN PAGE'),
              routes: [
                GoRoute(
                    path: 'active-workout',
                    builder: (_, _) => const ActiveWorkoutScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return _Shell(router, container);
}

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byType(ExerciseHeaderTile));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  expect(_viewer, findsOneWidget);
}

/// Pumps `seconds` in 500 ms steps. NOT `pumpAndSettle`: the viewer's looping
/// animation never settles.
Future<void> _pumpFor(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('the viewer sits on the BRANCH navigator, not the root one',
      (tester) async {
    await _pumpShell(tester);
    await _openViewer(tester);
    final ctx = tester.element(_viewer);
    expect(Navigator.of(ctx), isNot(same(Navigator.of(ctx, rootNavigator: true))));
    await unmountScreen(tester);
  });

  testWidgets('the shell bottom bar stays visible and tappable under the '
      'viewer', (tester) async {
    await _pumpShell(tester);
    await _openViewer(tester);
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    await unmountScreen(tester);
  });

  testWidgets('a re-route inside the branch (go /train) removes the viewer '
      'with its page, no exception', (tester) async {
    final shell = await _pumpShell(tester);
    await _openViewer(tester);
    shell.router.go('/train');
    await _pumpFor(tester, 3);
    expect(_viewer, findsNothing);
    expect(tester.takeException(), isNull);
    await unmountScreen(tester);
  });

  testWidgets('a branch switch hides the viewer with its branch and it is '
      'there when you come back', (tester) async {
    final shell = await _pumpShell(tester);
    await _openViewer(tester);
    shell.router.go('/home');
    await _pumpFor(tester, 1);
    expect(_viewer, findsNothing, reason: 'offstage with the Train branch');
    expect(find.byType(ExerciseMediaViewer, skipOffstage: false), findsOneWidget,
        reason: 'hidden, not orphaned and not disposed');
    expect(tester.takeException(), isNull);
    shell.router.go('/train/active-workout');
    await _pumpFor(tester, 1);
    expect(_viewer, findsOneWidget);
    await unmountScreen(tester);
  });

  testWidgets('Android system back pops the viewer first and leaves the '
      'screen mounted', (tester) async {
    await _pumpShell(tester);
    await _openViewer(tester);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await _pumpFor(tester, 1);
    expect(_viewer, findsNothing);
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    await unmountScreen(tester);
  });
}
