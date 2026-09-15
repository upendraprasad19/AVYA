// Bug s1n4c0 regression test (APK Test #16.2), REPOINTED 2026-09-15
// (diagnose 6c2f91) — see "Where the pop moved to" below.
//
// Pins the contract that the swap sheet's own modal route is popped
// BEFORE opening CreateCustomExerciseSheet via _openCreateAndAutoSwap.
//
// Pre-s1n4c0-fix, the swap sheet stayed mounted while the create sheet
// opened on top. When create.onCreated fired, the "Swapped X to Y /
// UNDO" snackbar was hosted against a context shadowed by the active
// swap modal route — its 5s dismiss timer never fired on Android, so
// the user had to restart the app to clear the toast.
//
// Where the pop moved to (diagnose 6c2f91, 2026-09-15): s1n4c0's original
// fix added a SECOND pop inside _showSwapSheet's onAdd handler
// (active_workout/swap_sheets.dart), assuming the swap sheet was still on
// the Navigator stack when onAdd ran. It was not: ExerciseSwapSheet's own
// "+ ADD EXERCISE" button (this file) ALREADY pops the swap sheet on
// itself, synchronously, before invoking onAdd — so s1n4c0's second pop
// was a DOUBLE pop that removed the NEXT route down (the active workout
// screen itself), ejecting the user to the Train tab. 6c2f91 removed that
// redundant second pop; THIS self-pop, asserted below, is what has
// satisfied the underlying UNDO-snackbar contract all along and is now
// the ONLY pop in the flow.
//
// This is a source-grep contract test: we scan the widget source file and
// assert the precise ordering of two anchor strings inside the "+ ADD
// EXERCISE" button's onPressed. A widget test would require the full Hive
// + Riverpod harness and is deferred — the source-grep catches any
// reorder regression at zero runtime cost.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      's1n4c0 — "+ ADD EXERCISE" self-pops the swap sheet before invoking onAdd',
      () {
    final src =
        File('lib/features/train/widgets/exercise_swap_sheet.dart')
            .readAsStringSync();

    // Strip block + line comments so the test does not match the
    // explanatory comment that names the anti-pattern. The closing
    // brace below is preserved.
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    final sentinelIdx = stripped.indexOf("'__ADD_MODE__'");
    expect(sentinelIdx, isNonNegative,
        reason:
            'exercise_swap_sheet.dart no longer contains the __ADD_MODE__ sentinel — '
            'flow may have been refactored. Re-baseline this test.');

    // The ADD button's own onPressed closure — the nearest one enclosing
    // the sentinel, so this cannot accidentally match a pop belonging to a
    // different button (e.g. the sheet's close icon or the DELETE button).
    final onPressedIdx =
        stripped.lastIndexOf('onPressed: () {', sentinelIdx);
    expect(onPressedIdx, isNonNegative,
        reason:
            'No enclosing onPressed closure found before the __ADD_MODE__ sentinel — '
            'flow may have been refactored. Re-baseline this test.');

    // Find the self-pop between that onPressed and the sentinel.
    final popIdx =
        stripped.indexOf('Navigator.of(context).pop()', onPressedIdx);
    expect(popIdx, isNonNegative,
        reason:
            's1n4c0 regression — the "+ ADD EXERCISE" onPressed is missing its '
            'self-pop before invoking onAdd. The swap sheet must be popped before '
            'the create sheet opens, otherwise the UNDO snackbar is hosted against a '
            'context shadowed by the active swap modal route and never auto-dismisses.');
    expect(popIdx, lessThan(sentinelIdx),
        reason:
            's1n4c0 regression — Navigator.of(context).pop() appears AFTER the '
            '__ADD_MODE__ sentinel (i.e. after onAdd is invoked). It must come first '
            'so the snackbar emitted from inside the create flow is hosted by the '
            'active workout scaffold, not the swap sheet route.');
  });
}
