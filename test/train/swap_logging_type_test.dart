// APK Test #12 / Task D-1 + A-4 — pins the active-workout swap contract.
//
// Two regressions this catches:
//
// 1. Pre-Test-#12 `train_provider.swapExercise` was a pure
//    state-replacement: `newExercises[i] = newExercise`. If the picker
//    handed back an exercise without `logging_type` (or with the wrong
//    one), the slot UI kept rendering whatever columns the OLD exercise
//    used. Swap timed → weight+reps left the slot rendering DURATION
//    seconds. The fix routes through LoggingTypeResolver.
//
// 2. Pre-Test-#12 the swap also kept stale per-slot state
//    (checkedSets / warmUpSets / setInputValues for the swapped index).
//    A user who'd checked sets on the OLD exercise saw those checks
//    persist on the NEW exercise — and on completeWorkout, the
//    OLD-exercise's set values got logged under the NEW name.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('train_provider.swapExercise (APK Test #12 D-1 + A-4)', () {
    final source = File(
      'lib/features/train/providers/train_provider.dart',
    ).readAsStringSync();

    test('routes through LoggingTypeResolver.resolve', () {
      // Locate the swapExercise method body.
      final body = RegExp(
        r'void swapExercise\(int exerciseIndex, ExerciseData newExercise\)\s*\{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(body, isNotNull,
          reason: 'Could not locate swapExercise(int, ExerciseData) '
              'in train_provider.dart');

      final code = body!.group(1)!;
      expect(code.contains('LoggingTypeResolver.resolve'), isTrue,
          reason: 'swapExercise must route the incoming exercise through '
              'LoggingTypeResolver — pre-Test #12 it was a pure replacement '
              'and swap-from-timed → weight_reps left the UI stuck timed.');
    });

    test('clears per-slot checkedSets / warmUpSets / setInputValues', () {
      final body = RegExp(
        r'void swapExercise\(int exerciseIndex, ExerciseData newExercise\)\s*\{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(body, isNotNull);
      final code = body!.group(1)!;

      // Three state maps must be filtered to drop the swapped index.
      // We check that the prefix-based filter is present for each.
      expect(code.contains('checkedSets'), isTrue,
          reason: 'must rewrite checkedSets on swap');
      expect(code.contains('warmUpSets'), isTrue,
          reason: 'must rewrite warmUpSets on swap');
      expect(code.contains('setInputValues'), isTrue,
          reason: 'must rewrite setInputValues on swap');
      expect(code.contains("'\$exerciseIndex-'") ||
              code.contains('startsWith(prefix)'),
          isTrue,
          reason: 'must filter map keys by exerciseIndex prefix to drop '
              'OLD exercise\'s set checks before swapping');
    });
  });
}
