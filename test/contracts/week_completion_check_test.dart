// test/contracts/week_completion_check_test.dart
//
// Obs 3 (2026-06-05) — two sub-fixes on the Train week strip:
//   3a: current/forward week chips show the same ✓ as past-phase chips when a
//       week has ≥1 completed scheduled day (the current-phase _WeekChip had NO
//       checkmark logic at all).
//   3b: the strip auto-scrolls to the current phase on open + a contextual
//       "TODAY →" pill fades in only when the current phase is scrolled out of
//       view (was a bare SingleChildScrollView with no controller).
//
// Source-grep with comment-stripping (the established pattern for this file —
// see week_selector_past_phases_test.dart), per
// `feedback_source_grep_strip_comments_first.md`. Behavioral coverage is the
// device walk on the next APK.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src; // week_selector.dart
  late String svc; // workout_schedule_read_service.dart

  setUpAll(() {
    src = _strip(File('lib/features/train/widgets/week_selector.dart')
        .readAsStringSync());
    svc = _strip(File('lib/core/services/workout_schedule_read_service.dart')
        .readAsStringSync());
  });

  group('Obs 3a — current/forward week chips show ✓ for completed weeks', () {
    test('service exposes completedWeekNumbers (any completed day that week)',
        () {
      expect(svc.contains('Set<int> completedWeekNumbers('), isTrue);
      // Delegates to the pure helper that the behavioral group below covers
      // (Hermes L1/L37) — pin the delegation + the completed-status rule, not
      // the old `sched` local (which the carry-forward refactor inlined).
      expect(svc.contains('completedWeekNumbersFrom('), isTrue,
          reason: 'delegates to the pure, behaviorally-tested helper');
      expect(svc.contains("== 'completed'"), isTrue,
          reason: 'same "any completed day that week" rule as past-phase chips');
    });

    test('parent computes completedWeeks + threads it into every _PhaseGroup',
        () {
      expect(src.contains('service.completedWeekNumbers()'), isTrue);
      expect(src.contains('completedWeeks: completedWeeks'), isTrue);
    });

    test('_PhaseGroup passes per-week completion to _WeekChip', () {
      expect(src.contains('hasCompletedDay: completedWeeks.contains(w)'), isTrue);
    });

    test('_WeekChip renders check_circle for a completed, non-locked week', () {
      final idx = src.indexOf('class _WeekChip');
      expect(idx, greaterThan(-1));
      final body = src.substring(idx);
      expect(
        RegExp(r'hasCompletedDay\s*&&\s*!isLocked').hasMatch(body),
        isTrue,
        reason: 'check shows only when completed AND not a locked/preview week',
      );
      expect(body.contains('Icons.check_circle'), isTrue);
    });
  });

  group('Obs 3b — auto-scroll to current week + contextual TODAY pill', () {
    test('strip has a ScrollController + auto-scrolls on open (post-frame)', () {
      expect(src.contains('ScrollController'), isTrue);
      expect(src.contains('addPostFrameCallback'), isTrue);
      expect(src.contains('Scrollable.ensureVisible'), isTrue);
      expect(src.contains('_scrollToCurrent('), isTrue);
    });

    test('current phase group carries the scroll-anchor key', () {
      expect(src.contains('key: _currentPhaseKey'), isTrue);
    });

    test('contextual TODAY pill fades in + taps back to the current week', () {
      expect(src.contains('_showTodayPill'), isTrue);
      expect(src.contains('AnimatedOpacity'), isTrue);
      expect(src.contains("'TODAY'"), isTrue);
      expect(src.contains('onTap: _scrollToCurrent'), isTrue);
    });

    test('controller is disposed (no leak)', () {
      expect(src.contains('_scrollCtrl.dispose()'), isTrue);
    });
  });

  // Behavioral coverage for the pure decision behind Obs 3a (Hermes L1/L37 —
  // completedWeekNumbers was source-grep-only; rule 21 needs a behavioral test).
  // completedWeekNumbersFrom takes planStart + an isCompletedOn predicate so it
  // runs with no Hive.
  group('Obs 3a — completedWeekNumbersFrom (behavioral, pure)', () {
    final planStart = DateTime(2026, 5, 25); // week 1 = May 25–31

    test('"any completed day that week" marks the week', () {
      // One completed day in week 1 (May 27) + one in week 3 (Jun 9).
      final done = {DateTime(2026, 5, 27), DateTime(2026, 6, 9)};
      final weeks = WorkoutScheduleReadService.completedWeekNumbersFrom(
        planStart,
        (d) => done.contains(DateTime(d.year, d.month, d.day)),
        maxWeek: 4,
      );
      expect(weeks, {1, 3});
    });

    test('a week with no completed day is excluded', () {
      expect(
        WorkoutScheduleReadService.completedWeekNumbersFrom(
            planStart, (_) => false, maxWeek: 4),
        isEmpty,
      );
    });

    test('null planStart → empty (no plan yet)', () {
      expect(
        WorkoutScheduleReadService.completedWeekNumbersFrom(null, (_) => true),
        isEmpty,
      );
    });

    test('maxWeek bounds the scan (a completed day in week 5 is ignored)', () {
      final done = {DateTime(2026, 6, 24)}; // week 5 (May 25 + 30 days)
      expect(
        WorkoutScheduleReadService.completedWeekNumbersFrom(
            planStart, (d) => done.contains(DateTime(d.year, d.month, d.day)),
            maxWeek: 4),
        isEmpty,
      );
    });
  });
}
