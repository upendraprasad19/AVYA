// Behavioral contract for diagnose swap-undo-snackbar-completion-dismiss
// (2026-09-21, founder Obs 1): the swap-undo SnackBar (swap_sheets.dart,
// `_openCreateAndAutoSwap`) never dismissed on workout completion — it has
// its own 5s auto-dismiss, but nothing dismissed it EARLY on any of the
// screen's 3 exit paths, so a founder who completed a workout within that
// window kept seeing it linger.
//
// THE FIX (screen.dart, `_ActiveWorkoutScreenState`):
//   1. The messenger the SnackBar was shown on is captured on the screen's
//      own State (`_swapUndoMessenger`) at show-time, threaded from the
//      top-level `_openCreateAndAutoSwap` (swap_sheets.dart, a `part of`
//      function with no State of its own) via a new `screenState` parameter.
//   2. A `ref.listen` on the false->true `isComplete` transition dismisses
//      it IMMEDIATELY — completion does NOT unmount this screen (`build()`
//      just switches to `_buildCompleteScreen`), so `dispose()` alone would
//      never fire here.
//   3. `dispose()` dismisses it as a BACKSTOP for every OTHER exit path
//      (the cancel dialog's `context.go('/train')`, and the system
//      back-gesture, which has no PopScope guard at all) — by construction,
//      not by enumerating each path.
//
// `_ActiveWorkoutScreenState`/`_showSwapSheet`/`_openCreateAndAutoSwap` are
// all private, `part of 'screen.dart'`, with no public seam to pump the real
// widget (which also drags in todayWorkoutProvider/currentPlanProvider/
// calendarWeekProvider/restTimerProvider and a real generated plan) — same
// shape as swap_add_exercise_double_pop_behavioral_test.dart and
// swap_exercise_logging_type_behavioral_test.dart before it. This file
// mirrors the exact mechanism (capture-on-show / ref.listen-dismiss /
// dispose-backstop) in a minimal harness to prove it behaviorally across
// all 3 exit paths, paired with a source-grep group pinning that the real
// files actually wire it this way.
//
// MUTATION-PROVEN: see the diagnose-doc for the exact mutation (removing the
// dispose()-backstop call) + the source-grep test it reddens.
//
// Run: flutter test test/features/train/swap_undo_snackbar_dismisses_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Stands in for `activeWorkoutProvider`'s `isComplete` field — the harness
/// only needs the false->true transition shape, not the real provider.
/// Riverpod 3.x has no `StateProvider`; a minimal `Notifier` replaces it.
class _FakeCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void complete() => state = true;
}

final _fakeCompleteProvider =
    NotifierProvider<_FakeCompleteNotifier, bool>(_FakeCompleteNotifier.new);

class _FakeActiveWorkoutScreen extends ConsumerStatefulWidget {
  const _FakeActiveWorkoutScreen();

  @override
  ConsumerState<_FakeActiveWorkoutScreen> createState() =>
      _FakeActiveWorkoutScreenState();
}

/// Mirrors `_ActiveWorkoutScreenState`'s swap-undo-dismissal shape exactly:
/// same field, same dispose()-backstop, same ref.listen-immediate-dismiss.
class _FakeActiveWorkoutScreenState
    extends ConsumerState<_FakeActiveWorkoutScreen> {
  ScaffoldMessengerState? _swapUndoMessenger;
  int disposeCount = 0;

  void _dismissSwapUndoSnackBar() {
    _swapUndoMessenger?.hideCurrentSnackBar();
    _swapUndoMessenger = null;
  }

  @override
  void dispose() {
    disposeCount++;
    _dismissSwapUndoSnackBar();
    super.dispose();
  }

  /// Mirrors `_openCreateAndAutoSwap`'s capture-and-show, with `screenState`
  /// being `this` (in the real code it's threaded through 2 top-level
  /// functions since it's called from `_showSwapSheet`).
  void _showSwapUndoSnackBar(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    _swapUndoMessenger = messenger;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text('SWAP_UNDO_MARKER'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = ref.watch(_fakeCompleteProvider);
    ref.listen<bool>(_fakeCompleteProvider, (previous, next) {
      if (next && previous != true) {
        _dismissSwapUndoSnackBar();
      }
    });

    if (isComplete) {
      return const Scaffold(body: Center(child: Text('COMPLETE_MARKER')));
    }

    return Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ACTIVE_WORKOUT_MARKER'),
          ElevatedButton(
            onPressed: () => _showSwapUndoSnackBar(context),
            child: const Text('SWAP'),
          ),
          ElevatedButton(
            onPressed: () => context.go('/train'),
            child: const Text('CANCEL_DIALOG_GO_TRAIN'),
          ),
        ],
      ),
    );
  }
}

void main() {
  group('swap-undo snackbar dismissal mechanism (harness)', () {
    testWidgets(
        'completion transition: SnackBar dismissed IMMEDIATELY via '
        'ref.listen, without waiting for the screen to unmount or the '
        "SnackBar's own 5s timer", (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _FakeActiveWorkoutScreen()),
      ));

      await tester.tap(find.text('SWAP'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'sanity: the swap must actually show the undo snackbar.');

      // Flip isComplete true — screen stays mounted (switches its own build
      // output), matching the real screen's `if (data.isComplete) return
      // _buildCompleteScreen(...)` shape.
      container.read(_fakeCompleteProvider.notifier).complete();
      await tester.pump();

      expect(find.text('COMPLETE_MARKER'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'THE FOUNDER BUG, FIXED — completion must dismiss the '
              'snackbar immediately, not leave it lingering until its own '
              '5s timer elapses.');
    });

    testWidgets(
        'cancel-dialog exit path (context.go, not Navigator.pop): dispose() '
        'backstop dismisses the snackbar', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(
            path: '/active',
            builder: (_, __) => const _FakeActiveWorkoutScreen()),
        GoRoute(
            path: '/train',
            builder: (_, __) => const Scaffold(
                body: Center(child: Text('TRAIN_TAB_MARKER')))),
      ], initialLocation: '/active');
      addTearDown(router.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));

      await tester.tap(find.text('SWAP'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      // Mirrors the real cancel dialog: navigates via context.go, never
      // calls Navigator.pop.
      await tester.tap(find.text('CANCEL_DIALOG_GO_TRAIN'));
      await tester.pumpAndSettle();

      expect(find.text('TRAIN_TAB_MARKER'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'THE FOUNDER BUG, FIXED — a context.go exit must dismiss '
              'the snackbar via the dispose() backstop, exactly like a '
              'Navigator.pop exit would.');
    });

    testWidgets(
        'system back-gesture pop (no PopScope guard exists — the pop is '
        'unconditional): dispose() backstop dismisses the snackbar',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Push the screen onto the app's OWN root Navigator (rather than a
      // standalone one-route Navigator) so there is a real 2-deep stack for
      // the root back-gesture handler to pop — a single-route stack has
      // nothing to pop and would no-op, proving nothing either way.
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _FakeActiveWorkoutScreen(),
                    ),
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWAP'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      // Simulates the OS back gesture / hardware back button on the root
      // Navigator: a raw pop request with no PopScope in front of it to
      // intercept it — exactly the gap the real screen has today.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('OPEN'), findsOneWidget,
          reason: 'sanity: the back-gesture must have actually popped back '
              'to the previous screen.');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'THE FOUNDER BUG, FIXED — the back-gesture pop has no '
              'PopScope to intercept it, so dispose() must be the backstop '
              'that catches this path.');
    });
  });

  group('screen.dart / swap_sheets.dart source — the fix is actually wired',
      () {
    late String screenSource;
    late String swapSheetsSource;

    setUpAll(() {
      screenSource = File(
        'lib/features/train/screens/active_workout/screen.dart',
      ).readAsStringSync();
      swapSheetsSource = File(
        'lib/features/train/screens/active_workout/swap_sheets.dart',
      ).readAsStringSync();
    });

    test('dispose() calls the dismiss backstop', () {
      final disposeBlock =
          RegExp(r'void dispose\(\) \{.*?\n  \}', dotAll: true)
              .firstMatch(screenSource);
      expect(disposeBlock, isNotNull,
          reason: 'Could not locate dispose() in screen.dart.');
      expect(
        disposeBlock!.group(0)!.contains('_dismissSwapUndoSnackBar()'),
        isTrue,
        reason: 'dispose() must be the backstop for every exit path that '
            'unmounts the screen (cancel dialog, back-gesture).',
      );
    });

    test('build() dismisses immediately on the isComplete false->true '
        'transition via ref.listen', () {
      final listenBlock = RegExp(
        r'ref\.listen<ActiveWorkoutData>\(activeWorkoutProvider,.*?\}\);',
        dotAll: true,
      ).firstMatch(screenSource);
      expect(listenBlock, isNotNull,
          reason: 'Could not locate the completion ref.listen in screen.dart.');
      final body = listenBlock!.group(0)!;
      expect(body.contains('next.isComplete'), isTrue);
      expect(body.contains('_dismissSwapUndoSnackBar()'), isTrue,
          reason: 'completion must dismiss the snackbar immediately — the '
              'screen does not unmount at completion, so dispose() alone '
              'would never fire here.');
    });

    test('_openCreateAndAutoSwap captures the messenger onto screenState '
        'before showing the snackbar', () {
      final fnBlock =
          RegExp(r'void _openCreateAndAutoSwap\(.*?\n\}', dotAll: true)
              .firstMatch(swapSheetsSource);
      expect(fnBlock, isNotNull,
          reason: 'Could not locate _openCreateAndAutoSwap in '
              'swap_sheets.dart.');
      final body = fnBlock!.group(0)!;
      expect(body.contains('screenState._swapUndoMessenger = messenger'),
          isTrue,
          reason: 'the messenger must be captured onto the screen state so '
              'dispose()/ref.listen (which live on that state, not on this '
              'top-level function) can dismiss it later.');
      expect(body.contains('_ActiveWorkoutScreenState screenState'), isTrue);
    });

    test('_showSwapSheet threads screenState through to '
        '_openCreateAndAutoSwap', () {
      final fnBlock = RegExp(r'void _showSwapSheet\(.*?\n\}', dotAll: true)
          .firstMatch(swapSheetsSource);
      expect(fnBlock, isNotNull);
      final body = fnBlock!.group(0)!;
      expect(
        body.contains(
            '_openCreateAndAutoSwap(context, ref, exerciseIndex, screenState)'),
        isTrue,
        reason: 'screenState must reach _openCreateAndAutoSwap unchanged — '
            'losing it here silently breaks the whole mechanism.',
      );
    });
  });
}
