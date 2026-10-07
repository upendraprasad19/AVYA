import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression pin for a B-pass finding on bug e2b8a4 (round 2, 2026-09-19):
/// `MusterScreen._onSubmit()` set `_submitting = true` before awaiting
/// `InductionService.recordMusterAnswer`, with no catch. `recordMusterAnswer`
/// can genuinely throw a `StateError` — `HiveService.instance.coachBox`
/// resolves through `GuardedBox`, whose `put`/`rawBox` throw during the
/// documented auth/Hive owner-disagreement race window (the same
/// `GuardedBox.empty` mechanism the `auth_hive_owner_agreement` SoT concept
/// already tests elsewhere — this file does not re-prove that mechanism,
/// only that MusterScreen HANDLES it). Without a catch, `_submitting` never
/// resets on that throw, and `_onSubmit`'s own guard
/// (`if (_physiqueFocus == null || _submitting) return;`) then makes every
/// future tap of CONTINUE a silent no-op forever, with no error shown —
/// found by review, not by widget-testing it, live.
///
/// **Why source-grep instead of widget render:** `MusterScreen` uses
/// `WardButton`, which uses `GoogleFonts.getFont('Fraunces', ...)` — in unit
/// tests this attempts a network fetch that throws a late-arriving exception
/// that fails the test even when assertions pass (see
/// `muster_question_count_test.dart`'s identical note, same file, same
/// constraint). A pure source-grep avoids the widget render while still
/// pinning the fix's structure.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/muster_screen.dart')
        .readAsStringSync()
        // Strip comments first so a stale comment mentioning `_submitting =
        // false` can't produce a false pass (feedback_source_grep_strip_
        // comments_first.md).
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
  });

  test('_onSubmit wraps recordMusterAnswer in a try block', () {
    final onSubmit = RegExp(
      r'Future<void>\s+_onSubmit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src);
    expect(onSubmit, isNotNull,
        reason:
            'e2b8a4 round 2: _onSubmit must still exist at this name — if '
            'it moved, repoint this regex rather than deleting the test');

    expect(onSubmit!.group(0), contains('try {'),
        reason: 'e2b8a4 round 2 B-pass finding: _onSubmit must wrap the '
            'recordMusterAnswer await in a try block — without one, a '
            'thrown StateError (GuardedBox.put during the auth/Hive '
            'disagreement race window) leaves _submitting latched true '
            'forever, permanently disabling CONTINUE with no error shown');
  });

  test('_onSubmit resets _submitting to false inside a catch block', () {
    final onSubmit = RegExp(
      r'Future<void>\s+_onSubmit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src)!;
    final body = onSubmit.group(0)!;

    final catchBlock = RegExp(
      r'catch\s*\([^)]*\)\s*\{([\s\S]*?)\n    \}',
    ).firstMatch(body);
    expect(catchBlock, isNotNull,
        reason:
            'e2b8a4 round 2: _onSubmit must have a catch block, not just a '
            'bare try — a try with no catch still propagates the throw '
            'uncaught, leaving _submitting latched exactly as before');

    expect(catchBlock!.group(1), contains('_submitting = false'),
        reason: 'e2b8a4 round 2 B-pass finding: the catch block must reset '
            '_submitting = false — otherwise CONTINUE stays permanently '
            'disabled after the first failed submit, with no way to retry');
  });

  test('_onSubmit surfaces the failure to the user, not just a silent reset',
      () {
    final onSubmit = RegExp(
      r'Future<void>\s+_onSubmit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src)!;

    expect(
        onSubmit.group(0),
        anyOf(contains('ScaffoldMessenger'), contains('SnackBar')),
        reason: 'e2b8a4 round 2: a failed submit must show SOME visible '
            'error (this repo\'s own pattern lesson: every save action must '
            'give a confirmation OR failure signal, never fail silently) — '
            'resetting _submitting alone would let the user retry, but with '
            'no idea why the first tap silently did nothing');
  });
}
