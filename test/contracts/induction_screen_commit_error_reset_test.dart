import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression pin for a B-pass finding on bug e2b8a4 (Finding 1, 2026-09-20):
/// `InductionScreen._onCommit()` set `_stage = 7` before awaiting
/// `InductionService.recordCommitment()` + `completeInduction()`, with no
/// catch — the identical unmirrored-guard shape the same finding flagged in
/// `MusterScreen._onSubmit()` (see `muster_screen_submit_error_reset_test.dart`),
/// but WORSE here: `_stage == 7` unconditionally renders "Contract sealed."
/// in the build method, so a throw from either awaited call left the user
/// staring at a FALSE success message, permanently stuck (never reaching
/// `context.go('/home')`), with no error and no way to retry. Both calls can
/// genuinely throw a `StateError` — `HiveService.instance.coachBox` resolves
/// through `GuardedBox`, whose `put`/`rawBox` throw during the documented
/// auth/Hive owner-disagreement race window (the same `GuardedBox.empty`
/// mechanism the `auth_hive_owner_agreement` SoT concept already tests
/// elsewhere — this file does not re-prove that mechanism, only that
/// InductionScreen HANDLES it).
///
/// **Why source-grep instead of widget render:** `InductionScreen` uses
/// `WardButton`, which uses `GoogleFonts.getFont('Fraunces', ...)` — in unit
/// tests this attempts a network fetch that throws a late-arriving exception
/// that fails the test even when assertions pass (same documented constraint
/// as `muster_screen_submit_error_reset_test.dart` and
/// `muster_question_count_test.dart`). A pure source-grep avoids the widget
/// render while still pinning the fix's structure.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/induction_screen.dart')
        .readAsStringSync()
        // Strip comments first so a stale comment mentioning `_stage = 6`
        // can't produce a false pass (feedback_source_grep_strip_comments_
        // first.md).
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
  });

  test('_onCommit wraps recordCommitment + completeInduction in a try block',
      () {
    final onCommit = RegExp(
      r'Future<void>\s+_onCommit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src);
    expect(onCommit, isNotNull,
        reason:
            'e2b8a4: _onCommit must still exist at this name — if it moved, '
            'repoint this regex rather than deleting the test');

    final body = onCommit!.group(0)!;
    expect(body, contains('try {'),
        reason: 'e2b8a4 B-pass finding: _onCommit must wrap the '
            'recordCommitment/completeInduction awaits in a try block — '
            'without one, a thrown StateError (GuardedBox.put during the '
            'auth/Hive disagreement race window) leaves _stage stuck at 7, '
            'which renders "Contract sealed." even though nothing was '
            'actually recorded');
    expect(body, contains('recordCommitment()'),
        reason: 'sanity: the method must still call recordCommitment');
    expect(body, contains('completeInduction()'),
        reason: 'sanity: the method must still call completeInduction');
  });

  test('_onCommit resets _stage away from 7 inside a catch block', () {
    final onCommit = RegExp(
      r'Future<void>\s+_onCommit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src)!;
    final body = onCommit.group(0)!;

    final catchBlock = RegExp(
      r'catch\s*\([^)]*\)\s*\{([\s\S]*?)\n    \}',
    ).firstMatch(body);
    expect(catchBlock, isNotNull,
        reason: 'e2b8a4: _onCommit must have a catch block, not just a bare '
            'try — a try with no catch still propagates the throw uncaught, '
            'leaving _stage latched at 7 exactly as before');

    expect(catchBlock!.group(1), contains('_stage = 6'),
        reason: 'e2b8a4 B-pass finding: the catch block must reset _stage '
            'back to 6 (msg3 + I COMMIT button) — otherwise the screen '
            'stays stuck showing "Contract sealed." forever with no way to '
            'retry a failed commit');
  });

  test(
      '_onCommit surfaces the failure to the user, not just a silent reset',
      () {
    final onCommit = RegExp(
      r'Future<void>\s+_onCommit\(\)[\s\S]*?\n  \}',
    ).firstMatch(src)!;

    expect(
        onCommit.group(0),
        anyOf(contains('ScaffoldMessenger'), contains('SnackBar')),
        reason: 'e2b8a4: a failed commit must show SOME visible error (this '
            'repo\'s own pattern lesson: every save action must give a '
            'confirmation OR failure signal, never fail silently) — '
            'resetting _stage alone would let the user retry, but with no '
            'idea why "Contract sealed." disappeared');
  });
}
