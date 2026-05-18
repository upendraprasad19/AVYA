// Bug s1n4c0 regression test (APK Test #16.2).
//
// Pins the contract that ExerciseSwapSheet's onAdd "+ ADD EXERCISE"
// handler in active_workout_screen.dart pops the outer swap sheet
// BEFORE opening CreateCustomExerciseSheet via _openCreateAndAutoSwap.
//
// Pre-fix, the swap sheet stayed mounted while the create sheet
// opened on top. When create.onCreated fired, the "Swapped X to Y /
// UNDO" snackbar was hosted against a context shadowed by the active
// swap modal route — its 5s dismiss timer never fired on Android, so
// the user had to restart the app to clear the toast.
//
// This is a source-grep contract test: we scan the screen source
// file and assert the precise ordering of two anchor strings inside
// the onAdd handler. A widget test would require the full Hive +
// Riverpod harness and is deferred — the source-grep catches any
// reorder regression at zero runtime cost.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      's1n4c0 — onAdd "__ADD_MODE__" handler pops outer swap sheet before opening create sheet',
      () {
    final src = File(
            'lib/features/train/screens/active_workout_screen.dart')
        .readAsStringSync();

    // Strip block + line comments so the test does not match the
    // explanatory comment that names the anti-pattern. The closing
    // brace below is preserved.
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    final sentinelIdx = stripped.indexOf("addEx.name == '__ADD_MODE__'");
    expect(sentinelIdx, isNonNegative,
        reason:
            'active_workout_screen.dart no longer contains the __ADD_MODE__ sentinel — '
            'flow may have been refactored. Re-baseline this test.');

    // Find the matching `_openCreateAndAutoSwap(` call after the sentinel.
    final openCreateIdx =
        stripped.indexOf('_openCreateAndAutoSwap(', sentinelIdx);
    expect(openCreateIdx, isNonNegative,
        reason:
            'No call to _openCreateAndAutoSwap found after the __ADD_MODE__ sentinel.');

    // Find the swap-sheet pop between the sentinel and the create-sheet open.
    // Expect EXACTLY: `Navigator.of(ctx).pop();` somewhere inside that range.
    final popIdx = stripped.indexOf('Navigator.of(ctx).pop()', sentinelIdx);
    expect(popIdx, isNonNegative,
        reason:
            's1n4c0 regression — onAdd handler is missing the Navigator.of(ctx).pop() '
            'before _openCreateAndAutoSwap. The swap sheet must be popped before the '
            'create sheet opens, otherwise the UNDO snackbar is hosted against a '
            'context shadowed by the active swap modal route and never auto-dismisses.');
    expect(popIdx, lessThan(openCreateIdx),
        reason:
            's1n4c0 regression — Navigator.of(ctx).pop() appears AFTER _openCreateAndAutoSwap. '
            'It must come first so the snackbar emitted from inside the create flow '
            'is hosted by the active workout scaffold, not the swap sheet route.');
  });
}
