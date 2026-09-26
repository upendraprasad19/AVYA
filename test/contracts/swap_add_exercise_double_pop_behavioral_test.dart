// Behavioral contract for diagnose 6c2f91 — the ROOT CAUSE of Obs 5
// (internal-testing batch, session 2, 2026-09-15): tapping "+ ADD EXERCISE"
// INSIDE the swap sheet ejected the founder from the active workout screen
// back to the Train tab, with "all progress lost".
//
// THE BUG, live-verified in Chrome by the founder + agent together:
//   1. `ExerciseSwapSheet`'s own "+ ADD EXERCISE" button
//      (exercise_swap_sheet.dart's onPressed) ALREADY calls
//      `Navigator.of(context).pop()` on itself before invoking `onAdd`.
//   2. `_showSwapSheet`'s `onAdd` handler (swap_sheets.dart, part of
//      screen.dart) THEN called `Navigator.of(ctx).pop()` AGAIN, under the
//      wrong assumption the swap sheet was still on the stack. Since it was
//      already gone, this second pop removed the NEXT route down instead —
//      the active workout screen's own page — ejecting the user to /train.
//   3. `CreateCustomExerciseSheet` then opened on top of the WRONG screen
//      (Train tab instead of active workout).
//   4. Critically, `ActiveWorkoutData` itself was NEVER destroyed by this —
//      live-verified by navigating straight back into /train/active-workout
//      (bypassing START): the session was still there, checked sets and
//      timer intact. The founder's progress was only actually destroyed
//      because the Train tab shows no "resume" affordance, so tapping START
//      again there calls `startWorkout()` — an unconditional, no-
//      confirmation full reset.
//
// THE FIX: delete the redundant `Navigator.of(ctx).pop()` in swap_sheets.dart's
// onAdd handler for the '__ADD_MODE__' sentinel. `_openCreateAndAutoSwap` is
// the only action needed — the sheet already popped itself.
//
// This file proves the mechanism with a REAL Navigator + the REAL, public
// `ExerciseSwapSheet` widget (its "+ ADD EXERCISE" self-pop is unchanged,
// real app code) inside a minimal two-route harness standing in for
// [ActiveWorkoutScreen, ExerciseSwapSheet-as-modal]. The harness's `onAdd`
// callback mirrors the FIXED swap_sheets.dart (no extra pop); a second test
// mirrors the PRE-FIX buggy caller (the mutation) to prove it reddens.
//
// MUTATION-PROVEN: see the second test, which reproduces the exact pre-fix
// caller shape and asserts the active-workout marker is gone.
//
// ⚠ HIVE IS OPENED LAZILY, NOT IN setUpAll, AND TEST ORDER IS LOAD-BEARING —
// same class as test/contracts/exercise_plate_widgets_test.dart's header.
// ExerciseSwapSheet renders AppTypography (GoogleFonts) text, and mocking
// the path_provider channel (required so Hive can open a box) walks
// GoogleFonts into its fetch-and-save-to-device path, where the sandboxed
// network failure surfaces as an UNCAUGHT test exception instead of the
// ordinary silent fallback degrade. Fix: a Hive-free warm-up test renders
// every font family/weight the sheet uses (Fraunces/h2, DM Sans/body,
// JetBrains Mono/mono) FIRST, before any path_provider mock exists, so the
// failure is cached the ordinary way; only THEN does `_ensureHive` install
// the mock, lazily, for the tests that actually need Hive.
//
// Run: flutter test test/contracts/swap_add_exercise_double_pop_behavioral_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/widgets/exercise_swap_sheet.dart';

BuildContext? _pageContext;

Widget _harness({required void Function(BuildContext ctx) onAddModeSelected}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        _pageContext = context;
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ACTIVE_WORKOUT_PAGE_MARKER'),
                ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => ExerciseSwapSheet(
                        currentExerciseName: 'Dumbbell Row',
                        category: 'Pull',
                        onSelect: (_) {},
                        onAdd: (addEx) {
                          if (addEx.name == '__ADD_MODE__') {
                            onAddModeSelected(ctx);
                          }
                        },
                      ),
                    );
                  },
                  child: const Text('SWAP'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

const _testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
Directory? _tempDir;

/// Opens Hive + a user session on first call. Idempotent, and deliberately
/// NOT a setUpAll — see the file header.
Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('test_swap_double_pop');
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

  // ---- FIRST, and Hive-free by design (see file header). Primes every
  // GoogleFonts family/weight ExerciseSwapSheet renders before any
  // path_provider mock exists. ----
  testWidgets('warm-up: prime every font family the swap sheet renders',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('h2', style: AppTypography.h2),
          Text('body', style: AppTypography.body),
          Text('mono', style: AppTypography.mono),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  });

  group('ExerciseSwapSheet "+ ADD EXERCISE" — the double-pop regression', () {
    testWidgets(
        'FIXED caller (no extra pop): the underlying page survives and the '
        'create-custom flow opens on top of it', (tester) async {
      await tester.runAsync(_ensureHive);
      await tester.pumpWidget(_harness(
        onAddModeSelected: (ctx) {
          // Mirrors the FIXED swap_sheets.dart onAdd: no extra
          // Navigator.pop() — just open the next sheet.
          showModalBottomSheet(
            context: _pageContext!,
            builder: (_) => const Text('CREATE_CUSTOM_MARKER'),
          );
        },
      ));

      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();
      expect(find.text('+ ADD EXERCISE'), findsOneWidget,
          reason: 'sanity: the real ExerciseSwapSheet must render its own '
              'add-exercise button.');

      await tester.tap(find.text('+ ADD EXERCISE'));
      await tester.pumpAndSettle();

      expect(
        find.text('ACTIVE_WORKOUT_PAGE_MARKER'),
        findsOneWidget,
        reason: 'THE FOUNDER BUG, FIXED — the active workout page must '
            'still be on the Navigator stack, not ejected to Train.',
      );
      expect(
        find.text('CREATE_CUSTOM_MARKER'),
        findsOneWidget,
        reason: 'the create-custom flow must still open on top of the '
            'active workout screen.',
      );
    });

    testWidgets(
        'MUTATION: the PRE-FIX buggy caller (extra pop) ejects the '
        'underlying page — proves the fix is load-bearing', (tester) async {
      await tester.runAsync(_ensureHive);
      await tester.pumpWidget(_harness(
        onAddModeSelected: (ctx) {
          // Mirrors the PRE-FIX swap_sheets.dart onAdd: an extra pop that
          // assumes the swap sheet is still open. It is not (the sheet's
          // own button already popped itself), so this pops the page
          // beneath it instead.
          Navigator.of(ctx).pop();
          showModalBottomSheet(
            context: _pageContext!,
            builder: (_) => const Text('CREATE_CUSTOM_MARKER'),
          );
        },
      ));

      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ ADD EXERCISE'));
      await tester.pumpAndSettle();

      expect(
        find.text('ACTIVE_WORKOUT_PAGE_MARKER'),
        findsNothing,
        reason: 'reproduces THE BUG — the extra pop ejects the underlying '
            'page from the Navigator, exactly like the founder\'s report.',
      );
    });
  });

  group('swap_sheets.dart source — no redundant pop on the __ADD_MODE__ '
      'branch', () {
    test('the onAdd handler for __ADD_MODE__ does not call '
        'Navigator.of(ctx).pop()', () {
      final source = File(
        'lib/features/train/screens/active_workout/swap_sheets.dart',
      ).readAsStringSync();

      final onAddBlock = RegExp(
        r"onAdd: \(addEx\) \{.*?\n      \},",
        dotAll: true,
      ).firstMatch(source);
      expect(onAddBlock, isNotNull,
          reason: 'Could not locate the onAdd handler in swap_sheets.dart.');
      final body = onAddBlock!.group(0)!;

      expect(
        body.contains('Navigator.of(ctx).pop()'),
        isFalse,
        reason: 'THE BUG — a pop here double-pops (the swap sheet already '
            'self-popped) and ejects the active workout screen instead.',
      );
      expect(
        body.contains('_openCreateAndAutoSwap('),
        isTrue,
        reason: 'the __ADD_MODE__ branch must still open the create-custom '
            'flow.',
      );
    });
  });
}
