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
    // UPDATED 2026-08-07 (diagnose c9e4b7): the selector now goes through the
    // DISPLAY wrapper, which still delegates to the same bucketing SoT for the
    // strict path. It must not re-bucket schedule_* itself either way.
    expect(
      src.contains('pastPhaseBlocksForDisplay('),
      isTrue,
      reason: 'WeekSelector must read the shared '
          'WorkoutScheduleReadService.pastPhaseBlocksForDisplay() SoT, not '
          're-bucket schedule_* itself (avoids drift with '
          'PhaseProgressReconciler).',
    );
    expect(
      svc.contains('pastPhaseBlocks()'),
      isTrue,
      reason: 'the display wrapper must still delegate to the strict '
          'pastPhaseBlocks() for its primary path — the recovery is a '
          'fallback, not a replacement.',
    );
  });

  test('PhaseProgressReconciler must NOT use the display wrapper', () {
    // The load-bearing separation behind c9e4b7. pastPhaseBlocksForDisplay
    // recovers blocks the strict filter misses, which is right for RENDERING
    // and wrong for the reconciler: it advances current_phase MONOTONICALLY,
    // and its own comment calls a monotonic over-advance "unrecoverable"
    // (phase_progress_reconciler.dart). Feeding it the wider set could promote
    // a user on evidence the strict filter deliberately rejected, with no way
    // back. If this ever fails, the fix is to give the reconciler its own
    // strict call — NOT to relax this assertion.
    final rec = _strip(
        File('lib/core/services/phase_progress_reconciler.dart')
            .readAsStringSync());
    expect(
      rec.contains('pastPhaseBlocksForDisplay'),
      isFalse,
      reason: 'the reconciler must feed on the STRICT pastPhaseBlocks() only.',
    );
  });

  test('the SoT walks schedule_* + skips the current plan window + buckets 28d',
      () {
    expect(svc.contains("startsWith(_schedulePrefix)") ||
        svc.contains("startsWith('schedule_')"), isTrue,
        reason: 'pastPhaseBlocks() filters workoutBox by the schedule_ prefix.');
    // UPDATED 2026-08-07 (c9e4b7): the walk + cutoff filter moved into the
    // shared `_scheduleRowsBefore(DateTime? cutoff)` so the strict path and the
    // display-recovery path parse a row identically (they differ ONLY in the
    // cutoff they pass). The filter itself is unchanged — strictly-before.
    expect(
      RegExp(r'cutoff\s*!=\s*null\s*&&\s*!\s*date\.isBefore\(cutoff\)')
          .hasMatch(svc),
      isTrue,
      reason: 'the shared row walk must skip entries in/after the cutoff '
          '(those belong to the active phase, not history).',
    );
    expect(
      svc.contains('_scheduleRowsBefore(getPlanStartDate())'),
      isTrue,
      reason: 'the STRICT pastPhaseBlocks() must pass plan_start as its cutoff '
          '— that is what makes it strict.',
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
