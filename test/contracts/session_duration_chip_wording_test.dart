// Batch 3 (docs/plans/2026-11-02-session-set-budget-flip.md, D4): the session
// budget fits a day INSIDE the user's minutes and a day can run shorter (a median
// 26 minutes a day stay unused at 90), so the Edit Profile picker must not promise
// the minutes: its chips read `Up to N min`. Unit 2C-b (docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md,
// S4, founder d42 / d47): a 30 / 45-minute day may now run about 5 minutes over, so "Up to" is no longer true and the
// chips read `About N min`.
//
// PRESENCE ONLY (the picker is a private widget method of a 2,000-line screen; no
// widget harness builds it): the behavioural proof of the minutes themselves is
// `session_set_budget_wiring_test.dart` (a day never exceeds the minutes + the
// tolerance). The plan-change summary line stays `Session: 45 min -> 60 min`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the session-duration chips read "About N min"; the summary line is unchanged', () {
    final lines = File('lib/features/profile/screens/edit_profile_screen.dart')
        .readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
        .toList();
    final src = lines.join('\n');

    final start = src.indexOf('Widget _buildSessionDurationSelector()');
    expect(start, greaterThan(0), reason: 'the picker method must exist');
    // End at the next widget-building method (a CODE token: comments are stripped
    // above, so a comment marker can never anchor the slice).
    final end = src.indexOf(RegExp(r'\bWidget _build\w+\('), start + 10);
    expect(end, greaterThan(start), reason: 'the picker slice needs a code end anchor');
    final picker = src.substring(start, end);
    expect(picker.length, lessThan(6000), reason: 'the slice is the picker, not the rest of the file');

    expect(picker.contains(r"'About $min min'"), isTrue,
        reason: 'the chip label is an estimate: a short day may run about 5 minutes over (2C-b)');
    expect(picker.contains(r"'Up to $min min'"), isFalse,
        reason: 'a ceiling is false once the under-60 allowance exists');
    expect(picker.contains(r"'$min min'"), isFalse,
        reason: 'the plain label reads as a promise of N minutes');
    expect(picker.contains('const options = [30, 45, 60, 90];'), isTrue);

    // The change-summary line the reschedule dialog shows is unchanged.
    expect(src.contains(r"d == null ? '—' : '$d min'"), isTrue);
  });
}
