// test/contracts/week_selector_past_phases_test.dart
//
// Contract — Theme K (closes-diagnose b9d2a8), UPDATED 2026-06-02 for the
// two-Phase-1 refactor (diagnose a3f8c1).
//
// Pins the past-phase scroll-back feature on WeekSelector. The 2026-06-02
// refactor moved the schedule_* walk + planStart filter + 28-day bucketing into
// the SHARED SoT `WorkoutScheduleReadService.pastPhaseBlocks()` (consumed by both
// the week selector AND PhaseProgressReconciler), and made the phase LABELS
// dynamic (derived from current_phase) instead of hardcoded PHASE I/II/III. This
// test pins the new architecture; `week_selector_reads_current_phase_test.dart`
// pins the dynamic labels + no-duplicate behavior.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src; // week_selector.dart
  late String svc; // workout_schedule_read_service.dart (the bucketing SoT)

  setUpAll(() {
    src = _strip(File('lib/features/train/widgets/week_selector.dart')
        .readAsStringSync());
    svc = _strip(File('lib/core/services/workout_schedule_read_service.dart')
        .readAsStringSync());
  });

  test('week selector delegates past-phase bucketing to the shared SoT', () {
    expect(
      src.contains('pastPhaseBlocks()'),
      isTrue,
      reason: 'WeekSelector must read the shared '
          'WorkoutScheduleReadService.pastPhaseBlocks() SoT, not re-bucket '
          'schedule_* itself (avoids drift with PhaseProgressReconciler).',
    );
  });

  test('the SoT walks schedule_* + skips the current plan window + buckets 28d',
      () {
    expect(svc.contains("startsWith(_schedulePrefix)") ||
        svc.contains("startsWith('schedule_')"), isTrue,
        reason: 'pastPhaseBlocks() filters workoutBox by the schedule_ prefix.');
    expect(
      RegExp(r'planStart\s*!=\s*null\s*&&\s*!\s*date\.isBefore\(planStart\)')
          .hasMatch(svc),
      isTrue,
      reason: 'pastPhaseBlocks() must skip entries in/after the current plan '
          'window (those belong to the active phase, not history).',
    );
    expect(svc.contains('~/ 28'), isTrue,
        reason: 'past entries bucket by phase-length (28 days).');
  });

  test('past groups render LEFT of the current phase group', () {
    final currentGroupIdx = src.indexOf('_phaseRoman(widget.currentPhase)');
    final pastLoopIdx = src.indexOf('for (final past in pastPhases)');
    expect(currentGroupIdx, greaterThan(-1));
    expect(pastLoopIdx, greaterThan(-1));
    expect(pastLoopIdx < currentGroupIdx, isTrue,
        reason: 'past-phase groups must render before the current-phase group '
            'so scrolling LEFT reveals history.');
  });

  test('forward labels are DYNAMIC (current_phase, +1, +2), not hardcoded', () {
    expect(src.contains('_phaseRoman(widget.currentPhase)'), isTrue);
    expect(src.contains('_phaseRoman(widget.currentPhase + 1)'), isTrue);
    expect(src.contains('_phaseRoman(widget.currentPhase + 2)'), isTrue);
    // The pre-fix hardcoded forward labels must be gone (two-Phase-1 root).
    expect(src.contains("label: 'PHASE I'"), isFalse);
    expect(src.contains("label: 'PHASE II'"), isFalse);
    expect(src.contains("label: 'PHASE III'"), isFalse);
  });

  test('past chips visually distinct — textDim styling', () {
    final pastChipIdx = src.indexOf('class _PastWeekChip');
    expect(pastChipIdx, greaterThan(-1));
    final body = src.substring(pastChipIdx, pastChipIdx + 3000);
    expect(body.contains('AppColors.textDim'), isTrue,
        reason: 'past chips use textDim to distinguish from current (accent).');
  });

  test('past chips show ✓ glyph when ≥1 day is status=completed', () {
    expect(src.contains('hasCompletedDayInWeek'), isTrue);
    expect(src.contains('Icons.check_circle'), isTrue);
  });

  test('tapping a past chip opens _PastWeekSheet (modal bottom sheet)', () {
    expect(src.contains('showModalBottomSheet'), isTrue);
    expect(src.contains('_PastWeekSheet'), isTrue);
  });

  test('_PastWeekSheet reads entriesForWeek + renders completed status', () {
    final idx = src.indexOf('class _PastWeekSheet');
    expect(idx, greaterThan(-1));
    final body = src.substring(idx, idx + 3000);
    expect(body.contains('entriesForWeek'), isTrue);
    expect(
      body.contains("status == 'completed'") ||
          src.contains("e.status == 'completed'"),
      isTrue,
    );
  });

  test('public widget signature (totalWeeks, selectedWeek, onSelect, currentPhase)',
      () {
    expect(RegExp(r'final\s+int\s+totalWeeks').hasMatch(src), isTrue);
    expect(RegExp(r'final\s+int\s+selectedWeek').hasMatch(src), isTrue);
    expect(RegExp(r'final\s+ValueChanged<int>\s+onSelect').hasMatch(src), isTrue);
    // The two-Phase-1 fix added the real-phase input.
    expect(RegExp(r'final\s+int\s+currentPhase').hasMatch(src), isTrue);
  });
}
