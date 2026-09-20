import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pin the post-diagnose-e2b8a4 (2026-09-19) question count for
/// `MusterScreen`. Injuries and wake/workout-time were retired as LIVE
/// writer/reader drift (injuries duplicated + silently overwrote Details
/// screen's onboarding answer; wake/workout-time duplicated Edit Profile,
/// which already has full UI for it). Exactly ONE question remains:
/// physique focus — moved to run BEFORE the induction narrative + I COMMIT
/// so nothing is asked after commit.
///
/// Without this lock-down, a future "let's add a question back" change
/// would silently drift the UX and reintroduce the double-ask.
///
/// **Why source-grep instead of widget render:** `MusterScreen` uses
/// `WardButton` which uses `GoogleFonts.getFont('Fraunces', ...)`. In
/// unit tests, google_fonts attempts a network fetch that fails and
/// throws a late-arriving exception that fails the test even when
/// assertions pass — and disabling runtime fetching just changes the
/// failure mode (the bundled fallback isn't shipped in test mode
/// either). A pure source-grep avoids the widget render entirely while
/// still pinning the contract.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/muster_screen.dart')
        .readAsStringSync();
  });

  test('no multi-question progress bar or dispatch switch remain', () {
    expect(
      RegExp(r'List\.generate\(\s*[35]\s*,').hasMatch(src),
      isFalse,
      reason: 'MusterScreen must not render a multi-segment progress bar — '
          'there is exactly one question now, no progression to show.',
    );
    expect(
      src.contains('_buildCurrentQ'),
      isFalse,
      reason:
          'The question-index switch (_buildCurrentQ) must be gone along '
          'with the questions it used to dispatch between.',
    );
  });

  test('injuries and wake/workout-time widgets/handlers removed', () {
    expect(src.contains('_buildQ3'), isFalse,
        reason: '_buildQ3 (injuries) must be removed — retired question.');
    expect(src.contains('_buildQ4'), isFalse,
        reason:
            '_buildQ4 (wake/workout time) must be removed — retired question.');
    expect(src.contains('_onSubmitQ3'), isFalse,
        reason: '_onSubmitQ3 handler must be removed.');
    expect(src.contains('_onSubmitQ4'), isFalse,
        reason: '_onSubmitQ4 handler must be removed.');
    expect(src.contains('_injuriesCtrl'), isFalse,
        reason: '_injuriesCtrl field must be removed.');
    expect(src.contains('_wakeTime'), isFalse,
        reason: '_wakeTime field must be removed.');
    expect(src.contains('_workoutTime'), isFalse,
        reason: '_workoutTime field must be removed.');
    expect(src.contains('injuries or niggles'), isFalse,
        reason: 'Injuries captain-bubble copy must be gone.');
    expect(src.contains('WAKE TIME'), isFalse,
        reason: 'Wake-time tile copy must be gone.');
  });

  test('physique-focus question is the only one, asked unconditionally', () {
    expect(src.contains('_buildQuestion'), isTrue,
        reason:
            'A single _buildQuestion method must render the one remaining '
            'question (physique focus) — no index-based dispatch needed.');
    expect(src.contains('_physiqueFocus'), isTrue,
        reason: 'Physique-focus state must remain.');
    // NOTE: 'extra emphasis' straddles a line break between two adjacent
    // string literals in muster_screen.dart ('...want extra ' +
    // 'emphasis? Pick...') — a raw source-grep for the concatenated phrase
    // never matches even though the RUNTIME string does contain it. Search
    // for a phrase that lives entirely within one literal instead.
    expect(src.contains('Pick one, your plan will weight that area'), isTrue,
        reason: 'Physique-focus captain-bubble copy must be intact.');
  });

  test('completion navigates onward to induction, not to /home directly', () {
    expect(src.contains("context.go('/coach/induction')"), isTrue,
        reason:
            'MusterScreen must hand off to InductionScreen — muster now '
            'runs BEFORE the narrative + I COMMIT (diagnose e2b8a4), so '
            'nothing is asked after commit.');
    expect(src.contains("context.go('/home')"), isFalse,
        reason:
            'MusterScreen must not navigate straight home — that is now '
            'InductionScreen\'s job, after I COMMIT.');
    expect(src.contains('completeMuster'), isFalse,
        reason:
            'MusterScreen must not stamp completion — the terminal '
            'induction_completed_at stamp moved to InductionScreen\'s I '
            'COMMIT handler (renamed completeInduction), since muster is '
            'no longer the last step.');
  });
}
