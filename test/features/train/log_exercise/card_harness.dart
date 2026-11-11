// Shared harness for the one-LOG-per-exercise card tests. See
// harness_spike_test.dart for the two load-bearing harness facts (fonts before
// any path_provider mock; Hive-writing taps inside runAsync).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/active_workout/exercise_entry_handle.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';
import 'package:icanbefitter/features/train/services/swap_move_hint.dart';
import 'package:icanbefitter/shared/providers/exercise_media_provider.dart';

import '../../../helpers/fake_exercise_media_repository.dart';
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

/// Waits in REAL time for disk I/O a tap started, pumping between checks, until
/// [done] says the work happened. The 100 ms in [tapWithRealIo] is a floor, not a
/// wait: on a loaded machine a write finishes later and the next assertion runs
/// first (OI-358, a swap test red in the contract sweep and green alone). So wait
/// on what the work DOES, and load cannot change the result. The limit is only
/// there to fail with a name instead of hanging.
Future<void> pumpUntilRealIoDone(
  WidgetTester tester,
  bool Function() done, {
  required String what,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('$what never finished');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class CardHarness {
  CardHarness(this.container, this.logCalls, this.app,
      {ValueNotifier<bool>? focused, FakeExerciseMediaRepository? mediaRepo})
      : focused = focused ?? ValueNotifier<bool>(false),
        mediaRepo = mediaRepo ?? FakeExerciseMediaRepository();
  final ProviderContainer container;
  final List<Set<int>> logCalls;

  /// The card's `isFocused`, read by the host: a test flips it to move the same
  /// card State between the thumb header and the tile header.
  final ValueNotifier<bool> focused;

  /// The stand-in for the animation repository both helpers override.
  final FakeExerciseMediaRepository mediaRepo;

  /// The pumped tree, so a test can dispose the card (pump something else)
  /// and re-pump it on the SAME container: a card re-init (flip §2 P5).
  final Widget app;
  int reopenCalls = 0;
  int keepCalls = 0;
  bool? keepResult;
  ActiveWorkoutData get state => container.read(activeWorkoutProvider);
}

/// Disposes the card and pumps it again on the same container (re-entry).
Future<void> repumpCard(WidgetTester tester, CardHarness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(h.app);
  await tester.pump();
}

/// Seeds the library rows a test needs into exerciseBox (after clearing it: the
/// harness keeps one Hive dir per file, so rows persist across tests) and resets
/// the animation kill switch, which persists too. Real disk I/O, so it runs in
/// the real zone.
Future<void> seedLibrary(WidgetTester tester,
    {List<Map<String, dynamic>> rows = const [], bool animationsOff = false}) {
  return tester.runAsync(() async {
    final box = HiveService.instance.exerciseBox;
    await box.clear();
    if (rows.isNotEmpty) {
      await box.putAll({for (final r in rows) r['id'] as String: r});
    }
    final config = HiveService.instance.configBox;
    if (animationsOff) {
      await config.put('disable_exercise_animations', true);
    } else {
      await config.delete('disable_exercise_animations');
    }
  });
}

/// The overrides every helper adds: the fake animation repository (a seeded
/// media row must never reach the real Dio client) and the platform switch ON,
/// so a view really asks for its file.
List<Override> mediaOverrides(FakeExerciseMediaRepository repo) => [
      exerciseMediaRepositoryProvider.overrideWithValue(repo),
      exerciseAnimationsPlatformEnabledProvider.overrideWithValue(true),
    ];

/// Pumps the real card. [logMode] passes an onLogExercise that behaves like the
/// screen: logSets on the real notifier.
///
/// M2b: [isFocused] (the tile header, flipped later through
/// CardHarness.focused), [moveModeActive], [isInSupersetGroupMode],
/// [onLongPressHeader], [libraryRows] (seeded into exerciseBox), [animationsOff]
/// (the kill switch), [mediaBytes] (what the fake repository answers; null = no
/// file, the still stays) and [nestedNavigator]: the plain MaterialApp(home: ...)
/// has ONE Navigator, so a root-navigator dialog covers the card's route there;
/// the real Train branch is a nested navigator, and the dialog case needs that
/// shape.
///
/// Part B B1: [onLogExercise] REPLACES the default LOG handler (which runs
/// `logSets` on the real notifier and returns `logged`): no `logSets` runs, the
/// call is still recorded in `CardHarness.logCalls`, and the returned outcome is
/// the test's. [onHandleForTest] receives the card's entry handle after the
/// first frame.
Future<CardHarness> pumpCard(
  WidgetTester tester, {
  required ActiveWorkoutData seed,
  required bool logMode,
  LastPerformanceData lastPerf =
      const LastPerformanceData(lastWeight: 60, lastReps: 8),
  List<Override> overrides = const [],
  bool isExpanded = true,
  bool isFocused = false,
  bool moveModeActive = false,
  bool isInSupersetGroupMode = false,
  VoidCallback? onFocus,
  VoidCallback? onLongPressHeader,
  List<Map<String, dynamic>> libraryRows = const [],
  bool animationsOff = false,
  Uint8List? mediaBytes,
  bool nestedNavigator = false,
  LogExerciseCallback? onLogExercise,
  ValueChanged<ExerciseEntryHandle?>? onHandleForTest,
}) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: libraryRows, animationsOff: animationsOff);
  final calls = <Set<int>>[];
  final mediaRepo = FakeExerciseMediaRepository(bytes: mediaBytes);
  final focused = ValueNotifier<bool>(isFocused);
  final container = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    activeWorkoutProvider.overrideWith(() => SeededNotifier(seed)),
    lastPerformanceProvider.overrideWith((ref, name) => lastPerf),
    ...mediaOverrides(mediaRepo),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  LogOutcomeKind onLog(Set<int> idxs) {
    calls.add(idxs);
    final override = onLogExercise;
    if (override != null) return override(idxs);
    container.read(activeWorkoutProvider.notifier).logSets(0, idxs);
    return LogOutcomeKind.logged;
  }

  late final CardHarness h;
  // Like the screen: RE-OPEN unchecks every checked set (no guard here; the
  // guard is the controller's, tested there).
  void onReopen() {
    h.reopenCalls++;
    final data = container.read(activeWorkoutProvider);
    // Coach workout parity 1c: a chat-done card re-opens through the chat
    // route, as the screen's controller does.
    if (data.isChatLoggedDone(0)) {
      container
          .read(activeWorkoutProvider.notifier)
          .reopenChatLogged(0, data.exercises[0].name);
      return;
    }
    final n = int.tryParse(data.exercises[0].sets) ?? 3;
    container.read(activeWorkoutProvider.notifier).unlogSets(
        0, {for (var i = 0; i < n; i++) if (data.isSetChecked(0, i)) i},
        exerciseName: data.exercises[0].name, reopened: true);
  }

  final page = Scaffold(
    body: SingleChildScrollView(
      child: ValueListenableBuilder<bool>(
        valueListenable: focused,
        builder: (_, focusedNow, _) => debugExerciseCardHostForTest(
          exerciseIndex: 0,
          isExpanded: isExpanded,
          isFocused: focusedNow,
          moveModeActive: moveModeActive,
          isInSupersetGroupMode: isInSupersetGroupMode,
          onFocus: onFocus,
          onLongPressHeader: onLongPressHeader,
          onLogExercise: logMode ? onLog : null,
          onReopenExercise: logMode ? onReopen : null,
          onKeepChatLogged: logMode
              ? () {
                  h.keepCalls++;
                  h.keepResult = container
                      .read(activeWorkoutProvider.notifier)
                      .keepChatLogged(0,
                          container.read(activeWorkoutProvider).exercises[0].name);
                }
              : null,
          onHandleForTest: onHandleForTest,
        ),
      ),
    ),
  );
  final app = UncontrolledProviderScope(
    container: container,
    child: nestedNavigator
        ? MaterialApp(
            home: Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => page),
            ),
          )
        : MaterialApp(home: page),
  );
  h = CardHarness(container, calls, app, focused: focused, mediaRepo: mediaRepo);
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
  List<Override> overrides = const [],
  List<Map<String, dynamic>> libraryRows = const [],
  bool animationsOff = false,
  Uint8List? mediaBytes,
  ActiveWorkoutNotifier Function(ActiveWorkoutData data)? notifierFor,
}) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: libraryRows, animationsOff: animationsOff);
  final mediaRepo = FakeExerciseMediaRepository(bytes: mediaBytes);
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
    activeWorkoutProvider.overrideWith(() {
      final data = seed?.call(base) ?? base;
      return notifierFor?.call(data) ?? SeededNotifier(data);
    }),
    lastPerformanceProvider.overrideWith((ref, name) => lastPerf),
    ...mediaOverrides(mediaRepo),
    ...overrides,
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
