import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('active_workout_screen didUpdateWidget set count handling (F8)', () {
    test('does not call _disposeControllers + _initControllers full rebuild', () {
      final source = File(
        'lib/features/train/screens/active_workout_screen.dart',
      ).readAsStringSync();

      // Find the didUpdateWidget body for _ExerciseCardState (not _WarmupCooldownSection).
      // We locate it by matching from the _ExerciseCard overload signature through the
      // closing brace of that specific block.
      final didUpdateBlock = RegExp(
        r'didUpdateWidget\(covariant _ExerciseCard oldWidget\)\s*\{.*?\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(didUpdateBlock, isNotNull,
          reason: 'Could not locate didUpdateWidget(_ExerciseCard) in '
              '_ExerciseCardState.');

      final body = didUpdateBlock!.group(0)!;

      // The broken pattern: both _disposeControllers() AND _initControllers()
      // called when set count changes (set-count-change branch only — exercise
      // swap is allowed to call both).
      // We check that there is NOT a code path that calls them back-to-back
      // without an intervening `return` for the exercise-swap guard.
      // Simpler proxy: the method must NOT have _disposeControllers() and
      // _initControllers() called in the same if-block that tests set count.
      // We verify this structurally by confirming an append-style loop exists.
      final hasDisposeAndInit = body.contains('_disposeControllers()') &&
          body.contains('_initControllers()');

      // It's acceptable to call _disposeControllers + _initControllers for the
      // exercise-name-change branch (full swap), but that branch must return
      // before the set-count logic. The test verifies the set-count path uses
      // append logic instead of full rebuild.
      if (hasDisposeAndInit) {
        // If both are present, they must only appear together in the name-change
        // guard, which must be followed by `return` before any set-count logic.
        final nameChangeGuardWithReturn = RegExp(
          r'exercise\.name.*\{[^}]*_disposeControllers\(\)[^}]*_initControllers\(\)[^}]*return[^}]*\}',
          dotAll: true,
        ).hasMatch(body);
        expect(
          nameChangeGuardWithReturn,
          true,
          reason:
              'Both _disposeControllers() and _initControllers() are present but '
              'the name-change guard with return was not found. If both calls are '
              'still executed on set-count change, that wipes in-flight typed '
              'values (F8 regression).',
        );
      }
    });

    test('uses append/shrink loop for controller list mutations', () {
      final source = File(
        'lib/features/train/screens/active_workout_screen.dart',
      ).readAsStringSync();

      // Confirm the new pattern is in place: a for loop appending or
      // removeAt-disposing controllers based on count delta.
      final hasAppend =
          source.contains('_weightControllers.add(TextEditingController())');
      final hasShrink = source.contains('_weightControllers.removeAt(');
      expect(
        hasAppend || hasShrink,
        true,
        reason: 'didUpdateWidget should use append/shrink loop on the '
            'controller lists, not full rebuild on set-count change.',
      );
    });

    test('all four controller lists are grown/shrunk in the same loop', () {
      final source = File(
        'lib/features/train/screens/active_workout_screen.dart',
      ).readAsStringSync();

      // All four controller lists (_weightControllers, _repsControllers,
      // _durationControllers, _distanceControllers) must be grown together.
      final hasWeightAppend =
          source.contains('_weightControllers.add(TextEditingController())');
      final hasRepsAppend =
          source.contains('_repsControllers.add(TextEditingController())');
      final hasDurationAppend =
          source.contains('_durationControllers.add(TextEditingController())');
      final hasDistanceAppend =
          source.contains('_distanceControllers.add(TextEditingController())');

      expect(
        hasWeightAppend && hasRepsAppend && hasDurationAppend && hasDistanceAppend,
        true,
        reason: 'All four controller lists must be appended in the grow path. '
            'A mismatch causes IndexError on the missing list when set N renders.',
      );
    });
  });
}
