// Behavioral contract for the Obs 5 follow-up (diagnose 6c2f91): closing the
// mechanism that ACTUALLY destroyed the founder's logged sets once ejected
// from the active workout screen by any means (the double-pop bug fixed in
// diagnose 6c2f91's PRIMARY fix, or any other unexpected navigation away).
//
// THE GAP: `ActiveWorkoutNotifier.startWorkout()` unconditionally replaces
// `ActiveWorkoutData` with a fresh, empty session — no check for an existing
// live one. Every START button on Train/Home funnels through the SAME single
// entry point, `beginWorkoutWithReadiness` (readiness_sheet.dart) — see the
// comment at `home_screen.dart`'s `TodayWorkoutCard.onStart`, "the only two
// `startWorkout` callsites" (both inside that one function).
//
// THE FIX, two parts:
//   1. `ActiveWorkoutData.hasInProgressSession` (train_provider.dart) — a
//      workout has been started and not yet completed/saved.
//   2. `beginWorkoutWithReadiness` now checks it FIRST: if a live session
//      exists, it shows `showResumeOrDiscardGuard` before doing anything.
//      RESUME (or dismissing the dialog) returns without touching state —
//      the caller's unconditional post-call `context.go(...)` then lands on
//      the UNTOUCHED existing session. DISCARD & START FRESH clears the
//      `ActiveWorkoutPersistence` mid-workout snapshot (A7 parity — fired
//      unawaited, matching `_showCancelDialog`/`_showFinishDialog`'s own
//      sync onPressed callbacks; Hive's in-memory box state reflects a
//      delete synchronously, only the disk flush is async) and falls
//      through to the normal readiness/startWorkout flow.
//   3. The three START buttons (`hero_cards.dart`, `planned_expansion.dart`,
//      `today_workout_card.dart` via `home_screen.dart`) swap their label to
//      RESUME WORKOUT / RESUME when a live session exists, so re-tapping
//      START is never the ONLY path back into an in-progress workout.
//
// This file proves parts 1 and 2 behaviorally, through the REAL,
// unmocked `beginWorkoutWithReadiness` + a real `AlertDialog` interaction.
// Part 3 (button labels) is UI-only, gated on the SAME getter proven here.
//
// Run: flutter test test/contracts/active_workout_resume_guard_behavioral_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/readiness_sheet.dart';

const _testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
Directory? _tempDir;

/// Opens Hive + a user session on first call. Idempotent, and deliberately
/// NOT a setUpAll — same font/path_provider interaction documented in
/// test/contracts/swap_add_exercise_double_pop_behavioral_test.dart and
/// test/contracts/exercise_plate_widgets_test.dart: mocking path_provider
/// (required so Hive can open a box) before any GoogleFonts style has
/// rendered turns the sandboxed network failure into an UNCAUGHT test
/// exception instead of the ordinary silent fallback degrade.
Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('test_resume_guard');
  _tempDir = dir;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  Hive.init(dir.path);
  GuardedBox.testBypassOwnership = true;
  await Hive.openBox(HiveService.configBoxName);
  await Hive.openBox(HiveService.migrationBoxName);
  await Hive.openBox(HiveService.exerciseBoxName);
  HiveService.instance.markInitializedForTests();
  await HiveUserSession.openForUser(_testUser);
  // The readiness flag reads configBox — disable it so
  // beginWorkoutWithReadiness's OWN start path never needs to also drive
  // the (unrelated) readiness check-in sheet; this file is testing the
  // resume/discard guard, not readiness.
  await HiveService.instance.configBox.put('disable_readiness', true);
}

const _oldDay = WorkoutDayData(
  dayNumber: 1,
  name: 'Lat Pulldown Day',
  exercises: [
    ExerciseData(name: 'Lat Pulldown', loggingType: 'weight_reps', sets: '4'),
  ],
);
const _newDay = WorkoutDayData(
  dayNumber: 2,
  name: 'Dumbbell Row Day',
  exercises: [
    ExerciseData(name: 'Dumbbell Row', loggingType: 'weight_reps', sets: '3'),
  ],
);

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () =>
                beginWorkoutWithReadiness(context, ref, _newDay),
            child: const Text('START'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    if (_tempDir == null) return;
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (_tempDir!.existsSync()) {
      try {
        _tempDir!.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ---- FIRST, and Hive-free by design. Primes every GoogleFonts
  // family/weight the guard dialog renders (Fraunces/h2, DM Sans/bodySm,
  // JetBrains Mono/mono) before any path_provider mock exists. ----
  testWidgets('warm-up: prime every font family the guard dialog renders',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('h2', style: AppTypography.h2),
          Text('bodySm', style: AppTypography.bodySm),
          Text('mono', style: AppTypography.mono),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  });

  group('ActiveWorkoutData.hasInProgressSession (pure, no Hive)', () {
    test('false for the fresh/default state', () {
      expect(const ActiveWorkoutData().hasInProgressSession, isFalse);
    });

    test('true once a day is started and not yet complete/saved', () {
      const data = ActiveWorkoutData(workoutDay: _oldDay);
      expect(data.hasInProgressSession, isTrue);
    });

    test('false once completed', () {
      const data = ActiveWorkoutData(workoutDay: _oldDay, isComplete: true);
      expect(data.hasInProgressSession, isFalse);
    });

    test('false once saved', () {
      const data = ActiveWorkoutData(workoutDay: _oldDay, isSaved: true);
      expect(data.hasInProgressSession, isFalse);
    });
  });

  group('beginWorkoutWithReadiness — the discard guard (integration)', () {
    late ProviderContainer container;

    setUp(() async {
      await _ensureHive();
      container = ProviderContainer();
    });

    // NOT a tearDown: startWorkout() creates a periodic Timer on the
    // notifier, and the framework's end-of-test pending-timer assertion
    // fires BEFORE tearDown runs. Every test that reaches startWorkout()
    // (directly or via the guard) disposes the container itself as its
    // last action instead.

    testWidgets(
        'no live session: starts immediately, no dialog shown',
        (tester) async {
      await tester.pumpWidget(_harness(container));
      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final state = container.read(activeWorkoutProvider);
      expect(state.workoutDay, _newDay);
      container.dispose();
    });

    testWidgets(
        'RESUME: THE FIX — the existing session survives untouched, the '
        'new day is never started', (tester) async {
      container.read(activeWorkoutProvider.notifier).startWorkout(_oldDay);
      container.read(activeWorkoutProvider.notifier).toggleSet(0, 0);
      expect(
        container.read(activeWorkoutProvider).hasInProgressSession,
        isTrue,
        reason: 'sanity: seeding must actually produce an in-progress '
            'session for the guard to have anything to protect.',
      );

      await tester.pumpWidget(_harness(container));
      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'a live session must trigger the guard.');

      await tester.tap(find.text('RESUME'));
      await tester.pumpAndSettle();

      final state = container.read(activeWorkoutProvider);
      expect(
        state.workoutDay,
        _oldDay,
        reason: 'THE FOUNDER BUG, FIXED — RESUME must never call '
            'startWorkout() over a live session.',
      );
      expect(state.checkedSets, isNotEmpty,
          reason: 'the logged set must survive.');
      container.dispose();
    });

    testWidgets(
        'dismissing the dialog (barrier tap) is treated as RESUME — the '
        'safe default that never silently discards', (tester) async {
      container.read(activeWorkoutProvider.notifier).startWorkout(_oldDay);
      container.read(activeWorkoutProvider.notifier).toggleSet(0, 0);

      await tester.pumpWidget(_harness(container));
      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap a screen corner, well outside the AlertDialog's centered,
      // inset-padded card, to dismiss the barrier without choosing.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      final state = container.read(activeWorkoutProvider);
      expect(state.workoutDay, _oldDay);
      expect(state.checkedSets, isNotEmpty);
      container.dispose();
    });

    testWidgets(
        'DISCARD & START FRESH: starts the new day, dropping the discarded '
        'session\'s checked sets', (tester) async {
      // No ActiveWorkoutPersistence read/write here — its clearing is a
      // real Hive disk write, and this SUITE's own history (see the source-
      // grep group below) is that ANY real disk I/O reachable from a widget
      // interaction inside a testWidgets body — awaited OR merely
      // unawaited-but-in-flight — leaves the fake-async zone unable to tear
      // down cleanly, hanging the PROCESS even once every assertion has
      // already passed. That call site is pinned by source-grep instead.
      container.read(activeWorkoutProvider.notifier).startWorkout(_oldDay);
      container.read(activeWorkoutProvider.notifier).toggleSet(0, 0);

      await tester.pumpWidget(_harness(container));
      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'a live session must trigger the guard.');

      await tester.tap(find.text('DISCARD & START FRESH'));
      await tester.pumpAndSettle();

      final state = container.read(activeWorkoutProvider);
      expect(state.workoutDay, _newDay);
      expect(state.checkedSets, isEmpty,
          reason: 'a genuine fresh start must not carry over the discarded '
              'session\'s checked sets.');
      container.dispose();
    });
  });

  group('beginWorkoutWithReadiness source — the discard branch clears '
      'ActiveWorkoutPersistence (A7 parity)', () {
    test('calls ActiveWorkoutPersistence.clearState() on discard', () {
      final source = File(
        'lib/features/train/widgets/readiness_sheet.dart',
      ).readAsStringSync();

      final guardBlock = RegExp(
        r'if \(ref\.read\(activeWorkoutProvider\)\.hasInProgressSession\) \{'
        r'.*?\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(guardBlock, isNotNull,
          reason: 'Could not locate the hasInProgressSession guard block in '
              'readiness_sheet.dart.');
      final body = guardBlock!.group(0)!;

      expect(
        body.contains('ActiveWorkoutPersistence.clearState()'),
        isTrue,
        reason: 'the discard branch must clear the AI-coach mid-workout '
            'snapshot for the session being discarded (A7 parity with '
            '_showCancelDialog/_showFinishDialog), so it never outlives '
            'the state it describes.',
      );
    });
  });
}
