// Behavioral contract for diagnose 9b1e7a — swapping a timed exercise for a
// weight/reps one kept showing the timed UI until removed and re-added.
//
// THE BUG (founder, internal-testing batch, session 2, 2026-09-15, Obs 6):
// three-part chain, all in the swap-picker path (`_showSwapSheet`, NOT the
// `+ ADD EXERCISE` path, which was always correct — `_showExercisePickerSheet`
// reads the picked exercise's OWN logging_type):
//   1. `SwapExerciseData` (exercise_swap_sheet.dart) never carried a
//      `logging_type` field at all.
//   2. `_showSwapSheet`'s onSelect (swap_sheets.dart) therefore fell back to
//      `currentExercise.loggingType` — the OUTGOING exercise's type — when
//      building the replacement `ExerciseData`.
//   3. `LoggingTypeResolver.resolve()` trusts a non-empty direct value
//      VERBATIM (never validates it against the exercise name), so the wrong
//      but non-empty outgoing type was never corrected by the by-name
//      library lookup that exists precisely for this case.
//
// THE FIX: `SwapExerciseData` now carries `loggingType` (threaded from the
// picker row's `logging_type` at both real construction sites in
// exercise_swap_sheet.dart); `_showSwapSheet`'s onSelect reads
// `swapEx.loggingType ?? ''` (an EMPTY STRING floor, never the outgoing
// exercise's type — an empty string is exactly what `LoggingTypeResolver`
// treats as "no direct value, fall through to library lookup").
//
// This file proves TWO legs behaviorally, through the real
// `ActiveWorkoutNotifier.swapExercise()` + `LoggingTypeResolver` machinery:
//   (a) a correct, non-empty loggingType from the swapped-in exercise is
//       trusted and actually flips the active exercise's UI type — the "must
//       actually work end-to-end" half.
//   (b) an EMPTY loggingType (never the outgoing exercise's real type) falls
//       through to a by-name library lookup rather than silently keeping
//       whatever the caller might otherwise have defaulted to — the half
//       that makes '' the correct floor instead of `currentExercise.loggingType`.
// The third leg — that `swap_sheets.dart`'s onSelect actually reads
// `swapEx.loggingType` rather than `currentExercise.loggingType` — is a
// private-widget call site (`part of 'screen.dart'`) with no public seam to
// pump; it is pinned by a source-grep in the third group below.
//
// MUTATION-PROVEN: reverting swap_sheets.dart's onSelect to
// `loggingType: currentExercise.loggingType` reddens the source-grep test
// (group 3) — see the diagnose-doc for the exact mutation + count.
//
// Run: flutter test test/contracts/swap_exercise_logging_type_behavioral_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SwapExerciseData — carries the swapped-in exercise\'s own type', () {
    test('loggingType is a real, storable field', () {
      const swapEx = SwapExerciseData(
        name: 'Push Up',
        detail: 'Chest',
        loggingType: 'bodyweight_reps',
      );
      expect(swapEx.loggingType, 'bodyweight_reps');
    });

    test('defaults to null (never a silently-wrong non-empty value)', () {
      const swapEx = SwapExerciseData(name: 'Push Up', detail: 'Chest');
      expect(swapEx.loggingType, isNull);
    });
  });

  group('ActiveWorkoutNotifier.swapExercise — logging-type resolution '
      '(integration)', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;
    late ProviderContainer container;

    setUpAll(() async {
      tempDir =
          await Directory.systemTemp.createTemp('test_swap_logging_type');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      for (final name in [
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        HiveService.exerciseBoxName,
        'userBox_aaaaaaaa',
        'workoutBox_aaaaaaaa',
        'nutritionBox_aaaaaaaa',
        'healthBox_aaaaaaaa',
        'coachBox_aaaaaaaa',
        'customBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      await Hive.openBox(HiveService.exerciseBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await HiveUserSession.closeAll();
    });

    const original = WorkoutDayData(
      dayNumber: 1,
      name: 'Full Body',
      exercises: [
        ExerciseData(name: 'Plank', loggingType: 'timed', sets: '3'),
      ],
    );

    test('(a) a correct swapped-in type is trusted and actually flips the '
        'active exercise — the reported bug, fixed', () {
      container.read(activeWorkoutProvider.notifier).startWorkout(original);

      // Mirrors the FIXED swap_sheets.dart onSelect: loggingType comes from
      // the swapped-in exercise (swapEx.loggingType), never the outgoing one.
      container.read(activeWorkoutProvider.notifier).swapExercise(
            0,
            const ExerciseData(
              name: 'Push Up',
              loggingType: 'bodyweight_reps',
              sets: '3',
            ),
          );

      final result = container.read(activeWorkoutProvider).exercises[0];
      expect(result.name, 'Push Up');
      expect(
        result.loggingType,
        'bodyweight_reps',
        reason: 'THE FOUNDER BUG — pre-fix this stayed "timed" (the '
            'OUTGOING exercise\'s type) until the exercise was removed and '
            're-added.',
      );
    });

    test('(b) an empty swapped-in type falls through to a by-name library '
        'lookup — proves \'\' is the correct floor, not the outgoing type',
        () async {
      // Seed the library with the swapped-in exercise's REAL type, distinct
      // from both the outgoing exercise\'s type ("timed") and the resolver\'s
      // ultimate default ("weight_reps") — so landing on it proves the
      // by-name lookup actually ran.
      await HiveService.instance.exerciseBox.put('ex_pushup', {
        'name': 'Push Up',
        'logging_type': 'bodyweight_reps',
      });

      container.read(activeWorkoutProvider.notifier).startWorkout(original);

      // Mirrors swap_sheets.dart when the picker row carries no
      // logging_type: the FIX passes '' (never currentExercise.loggingType).
      container.read(activeWorkoutProvider.notifier).swapExercise(
            0,
            const ExerciseData(
              name: 'Push Up',
              loggingType: '',
              sets: '3',
            ),
          );

      final result = container.read(activeWorkoutProvider).exercises[0];
      expect(
        result.loggingType,
        'bodyweight_reps',
        reason: 'an empty direct value must fall through to the by-name '
            'library lookup, not silently inherit the outgoing exercise\'s '
            'type (which a `?? currentExercise.loggingType` floor would do).',
      );
    });
  });

  group('swap_sheets.dart source — the swap onSelect reads the SWAPPED-IN '
      'type', () {
    test('never falls back to currentExercise.loggingType', () {
      final source = File(
        'lib/features/train/screens/active_workout/swap_sheets.dart',
      ).readAsStringSync();

      // Locate the _showSwapSheet onSelect block specifically (not
      // _openCreateAndAutoSwap, which has its own, already-correct,
      // loggingType resolution from the newly-created exercise's own data).
      final showSwapSheetBlock = RegExp(
        r'void _showSwapSheet\(.*?\n\}',
        dotAll: true,
      ).firstMatch(source);
      expect(showSwapSheetBlock, isNotNull,
          reason: 'Could not locate _showSwapSheet in swap_sheets.dart.');
      final body = showSwapSheetBlock!.group(0)!;

      expect(
        body.contains('loggingType: currentExercise.loggingType'),
        isFalse,
        reason: 'THE BUG — using the OUTGOING exercise\'s loggingType for '
            'the SWAPPED-IN exercise. Must read swapEx.loggingType instead.',
      );
      expect(
        body.contains('swapEx.loggingType'),
        isTrue,
        reason: 'the swap onSelect must read the swapped-in exercise\'s own '
            'loggingType.',
      );
    });
  });
}
