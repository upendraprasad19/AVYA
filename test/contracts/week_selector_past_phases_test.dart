// test/contracts/week_selector_past_phases_test.dart
//
// Contract — Theme K (closes-diagnose b9d2a8).
//
// Pins the inline past-phase scroll-back extension to WeekSelector.
// Pre-fix the widget showed only the current phase (PHASE I W1-W4) +
// 2 PRO-locked future phases (PHASE II W5-8, PHASE III W9-12). After
// Theme H protected past phase data from planGenerator overwrite, we
// extend the strip LEFT with one _PastPhaseGroup per completed past
// phase reading schedule_* Hive entries.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src;

  setUpAll(() {
    src = _strip(
        File('lib/features/train/widgets/week_selector.dart')
            .readAsStringSync());
  });

  test('imports HiveService for direct schedule_* read', () {
    expect(
      src.contains(
          "import 'package:icanbefitter/core/services/hive_service.dart'"),
      isTrue,
      reason: 'WeekSelector must import HiveService to walk workoutBox '
          'for past schedule_* entries.',
    );
  });

  test('walks workoutBox for schedule_* keys', () {
    expect(
      src.contains("startsWith('schedule_')"),
      isTrue,
      reason: 'past-phase loader must filter workoutBox entries by '
          'keys starting with `schedule_`.',
    );
  });

  test('skips entries within current plan window (date >= planStart)', () {
    expect(
      RegExp(r'planStart\s*!=\s*null\s*&&\s*!\s*date\.isBefore\(planStart\)')
          .hasMatch(src),
      isTrue,
      reason: 'past-phase loader must skip entries whose date is in or '
          'after the current plan window — those belong to the active '
          'phase, not history.',
    );
  });

  test('groups past entries into 28-day buckets (phase = 4 weeks)', () {
    expect(
      src.contains('~/ 28'),
      isTrue,
      reason: 'past entries must bucket by phase-length (28 days) so '
          'each _PastPhase holds exactly one phase of completed data.',
    );
  });

  test('_PastPhaseGroup renders LEFT of PHASE I', () {
    // The for-in over pastPhases must appear BEFORE the PHASE I
    // _PhaseGroup in the build() row children.
    final phase1Idx = src.indexOf("label: 'PHASE I'");
    final pastLoopIdx = src.indexOf('for (final past in pastPhases)');
    expect(phase1Idx, greaterThan(-1));
    expect(pastLoopIdx, greaterThan(-1));
    expect(pastLoopIdx < phase1Idx, isTrue,
        reason: 'past-phase groups must render LEFT of (before) the '
            'PHASE I _PhaseGroup so scrolling LEFT reveals history.');
  });

  test('past chips visually distinct — textDim border (not accent)', () {
    // _PastWeekChip uses AppColors.textDim border, NOT AppColors.accent.
    final pastChipIdx = src.indexOf('class _PastWeekChip');
    expect(pastChipIdx, greaterThan(-1));
    final body = src.substring(pastChipIdx, pastChipIdx + 3000);
    expect(
      body.contains('AppColors.textDim'),
      isTrue,
      reason: 'past chips must use textDim styling to visually '
          'distinguish from current-phase chips (accent).',
    );
  });

  test('past chips show ✓ glyph when ≥1 day is status=completed', () {
    expect(
      src.contains('hasCompletedDayInWeek'),
      isTrue,
      reason: 'past chip must compute completed-day-present predicate '
          'via _PastPhase.hasCompletedDayInWeek to decide whether to '
          'render the check_circle glyph.',
    );
    expect(
      src.contains('Icons.check_circle'),
      isTrue,
      reason: 'completed-day glyph must be check_circle.',
    );
  });

  test('tapping a past chip opens _PastWeekSheet (modal bottom sheet)', () {
    expect(
      src.contains('showModalBottomSheet'),
      isTrue,
      reason: 'past chip tap must surface a modal bottom sheet, not '
          'navigate the train screen (preserves current selectedWeek).',
    );
    expect(
      src.contains('_PastWeekSheet'),
      isTrue,
      reason: 'modal builder must instantiate _PastWeekSheet showing '
          'the 7-day breakdown for the tapped past week.',
    );
  });

  test('_PastWeekSheet reads entriesForWeek + renders completed status',
      () {
    final idx = src.indexOf('class _PastWeekSheet');
    expect(idx, greaterThan(-1));
    final body = src.substring(idx, idx + 3000);
    expect(
      body.contains('entriesForWeek'),
      isTrue,
      reason: 'sheet must filter past phase entries to the tapped '
          'week via _PastPhase.entriesForWeek.',
    );
    expect(
      body.contains("status == 'completed'") ||
          src.contains("e.status == 'completed'"),
      isTrue,
      reason: 'sheet (or the helper) must check status==completed to '
          'differentiate completed vs not-completed days.',
    );
  });

  test('forward-phase scroll behaviour unchanged (PHASE I/II/III intact)',
      () {
    expect(
      src.contains("label: 'PHASE I'"),
      isTrue,
      reason: 'PHASE I _PhaseGroup must still render.',
    );
    expect(
      src.contains("label: 'PHASE II'"),
      isTrue,
      reason: 'PHASE II _PhaseGroup must still render with isPaywalled.',
    );
    expect(
      src.contains("label: 'PHASE III'"),
      isTrue,
      reason: 'PHASE III _PhaseGroup must still render with isPaywalled.',
    );
  });

  test('public widget signature preserved (totalWeeks, selectedWeek, onSelect)',
      () {
    // Existing call-sites must continue to compile.
    expect(
      RegExp(r'final\s+int\s+totalWeeks').hasMatch(src),
      isTrue,
      reason: 'WeekSelector must keep `int totalWeeks` field.',
    );
    expect(
      RegExp(r'final\s+int\s+selectedWeek').hasMatch(src),
      isTrue,
      reason: 'WeekSelector must keep `int selectedWeek` field.',
    );
    expect(
      RegExp(r'final\s+ValueChanged<int>\s+onSelect').hasMatch(src),
      isTrue,
      reason: 'WeekSelector must keep `ValueChanged<int> onSelect` callback.',
    );
  });
}
