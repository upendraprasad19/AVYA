import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pin the post-Phase-2 question count for `MusterScreen`. After dropping
/// Q1 (`why_now`) and Q2 (`definition_of_winning`) per founder direction
/// (APK Test #15.4 / B2a), exactly 3 questions remain: injuries → wake
/// time → physique focus. The progress bar shows 3 dots, and the first
/// question prompt is now the injuries question.
///
/// Without this lock-down, a future "let's add a question back" change
/// would silently drift the UX.
///
/// **Why source-grep instead of widget render:** `MusterScreen` uses
/// `WardButton` which uses `GoogleFonts.getFont('Fraunces', ...)`. In
/// unit tests, google_fonts attempts a network fetch that fails and
/// throws a late-arriving exception that fails the test even when
/// assertions pass — and disabling runtime fetching just changes the
/// failure mode (the bundled fallback isn't shipped in test mode
/// either). A pure source-grep avoids the widget render entirely while
/// still pinning the contract: number of question dots + presence/
/// absence of specific captain-bubble prompts.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/muster_screen.dart')
        .readAsStringSync();
  });

  test('progress bar generates exactly 3 dots, not 5', () {
    expect(
      RegExp(r'List\.generate\(\s*3\s*,').hasMatch(src),
      isTrue,
      reason: 'Expected `List.generate(3, ...)` in `_buildProgress` '
          'so the bar renders 3 dots — one per remaining muster question.',
    );
    expect(
      RegExp(r'List\.generate\(\s*5\s*,').hasMatch(src),
      isFalse,
      reason: 'Found `List.generate(5, ...)` — Q1 (why_now) and Q2 '
          '(definition_of_winning) should be dropped (APK Test #15.4 / B2a). '
          'Update progress bar to 3 dots.',
    );
  });

  test('Q1 (why_now) and Q2 (definition_of_winning) widgets/handlers removed',
      () {
    expect(src.contains('_whyNowCtrl'), isFalse,
        reason:
            '_whyNowCtrl field must be removed (Q1 dropped per founder direction).');
    expect(src.contains('_winningCtrl'), isFalse,
        reason:
            '_winningCtrl field must be removed (Q2 dropped per founder direction).');
    expect(src.contains('_buildQ1'), isFalse,
        reason: '_buildQ1 widget must be removed (Q1 dropped).');
    expect(src.contains('_buildQ2'), isFalse,
        reason: '_buildQ2 widget must be removed (Q2 dropped).');
    expect(src.contains('_onSubmitQ1'), isFalse,
        reason: '_onSubmitQ1 handler must be removed (Q1 dropped).');
    expect(src.contains('_onSubmitQ2'), isFalse,
        reason: '_onSubmitQ2 handler must be removed (Q2 dropped).');
    expect(src.contains('Why now?'), isFalse,
        reason:
            'Captain bubble text "Why now?" must be removed from MusterScreen.');
    expect(src.contains('What does winning'), isFalse,
        reason:
            'Captain bubble text "What does winning..." must be removed.');
  });

  test('injuries / wake / physique-focus questions still present', () {
    expect(src.contains('_buildQ3'), isTrue,
        reason: 'Q3 (injuries) must remain — now the first question.');
    expect(src.contains('_buildQ4'), isTrue,
        reason: 'Q4 (wake / workout time) must remain — now the second.');
    expect(src.contains('_buildQ5'), isTrue,
        reason: 'Q5 (physique focus) must remain — now the third / final.');
    expect(src.contains('injuries or niggles'), isTrue,
        reason: 'Injuries captain bubble copy must be intact.');
  });

  test('switch dispatches Q3/Q4/Q5 in renumbered order (0/1/2)', () {
    // _buildCurrentQ should map case 0 -> Q3, case 1 -> Q4, case 2 -> Q5.
    final dispatchPattern = RegExp(
      r'case\s+0\s*:\s*\n?\s*return\s+_buildQ3\(\)\s*;[\s\S]*?'
      r'case\s+1\s*:\s*\n?\s*return\s+_buildQ4\(\)\s*;[\s\S]*?'
      r'case\s+2\s*:\s*\n?\s*return\s+_buildQ5\(\)\s*;',
    );
    expect(
      dispatchPattern.hasMatch(src),
      isTrue,
      reason:
          '_buildCurrentQ switch must dispatch case 0->_buildQ3, case 1->_buildQ4, '
          'case 2->_buildQ5 after Q1+Q2 drop. The renumbering keeps the original '
          'method names (Q3/Q4/Q5) so coachBox keys stay unchanged.',
    );
  });
}
