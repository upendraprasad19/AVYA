// Regression test for diagnose (this batch, Observation 3): a PRO user
// paging ahead into a phase group beyond their actual current phase saw the
// generic "No workouts scheduled" empty state — which reads like a bug/
// glitch rather than the intentional gate it actually is (that phase
// genuinely has no generated schedule until the current one finishes).
//
// The pure decision (`isFutureUngeneratedPhase`) and copy
// (`futurePhaseUnlockCopy`) are behaviorally covered in
// `hold_week_labels_test.dart`. This file pins the WIRING — that
// `screen.dart` actually computes and passes them, and that
// `empty_states.dart` actually branches its rendering on them — via
// source-grep, since `empty_states.dart` is a `part of 'screen.dart'` file
// with no independent constructor surface a plain widget test can drive in
// isolation without standing up the whole Train screen's provider graph.
//
// Run: flutter test test/contracts/train_phase_lock_empty_state_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final m = RegExp(r'(?<!:)//').firstMatch(l);
      return m == null ? l : l.substring(0, m.start);
    })
    .join('\n');

void main() {
  late String screenSrc;
  late String emptyStatesSrc;

  setUpAll(() {
    screenSrc =
        _strip(File('lib/features/train/screens/train/screen.dart')
            .readAsStringSync());
    emptyStatesSrc = _strip(
      File('lib/features/train/screens/train/empty_states.dart')
          .readAsStringSync(),
    );
  });

  group('screen.dart wires the phase-lock decision into _buildEmptyWeek', () {
    test('the empty-week call site passes isFutureUngeneratedPhase(selectedWeek) '
        'and the REAL current phase (plan.phase)', () {
      final i = screenSrc.indexOf('if (weekDays.isEmpty)');
      expect(i, isNot(-1));
      final body = screenSrc.substring(i, i + 250);
      expect(body, contains('_buildEmptyWeek('));
      expect(
        body,
        contains('isFutureUngeneratedPhase(selectedWeek)'),
        reason: 'must be the PURE, tested function — not a re-derived '
            'inline (selectedWeek - 1) ~/ 4 that could drift from the one '
            'behaviorally tested in hold_week_labels_test.dart',
      );
      expect(body, contains('currentPhase: plan.phase'),
          reason: 'must be the REAL current phase, not a hardcoded 1 — a '
              'wrong phase number here would tell the user to complete the '
              'wrong phase');
    });
  });

  group('screen.dart suppresses the pre-existing "Week N hasn\'t started '
      'yet" status card for a future-PHASE week, but ONLY when the '
      'phase-lock card below is guaranteed to render in its place '
      '(plan-review rounds 1+2, obs-batch-2026-09-16)', () {
    test('the status-card branch is gated by isFutureUngeneratedPhase(selectedWeek) '
        'AND weekDays.isEmpty together, not isFutureUngeneratedPhase alone', () {
      final i = screenSrc.indexOf(
          'else if (!(isFutureUngeneratedPhase(selectedWeek) &&');
      expect(i, isNot(-1),
          reason: 'without the isFutureUngeneratedPhase half, "Week N hasn\'t '
              'started yet" (this card\'s own condition is ALWAYS true for '
              'weeks 5-12, since plan.currentWeek is hard-clamped to [1,4]) '
              'renders in the same scroll view as the new "Complete Phase X '
              'to unlock Phase Y" lock card below it — two un-reconciled '
              'messages about the identical condition. Without the '
              'weekDays.isEmpty half (round 2 finding): a future-phase week '
              'that already has data (e.g. a hold row extending past week 4) '
              'would hit neither this card\'s original branch nor the '
              'hero-card branch above, leaving the top of the screen '
              'silently blank — the phase-lock card only renders '
              '`if (weekDays.isEmpty)`, so suppressing this card on '
              'isFutureUngeneratedPhase ALONE is not safe.');
      final body = screenSrc.substring(i, i + 110);
      expect(body, contains('weekDays.isEmpty'));
      final wardCardBody = screenSrc.substring(i, i + 900);
      expect(wardCardBody, contains('WardCard'));
    });
  });

  group('empty_states.dart branches on the phase-lock params instead of '
      'always rendering the generic empty state', () {
    test('_buildEmptyWeek accepts isFutureUngeneratedPhase and currentPhase',
        () {
      final i = emptyStatesSrc.indexOf('Widget _buildEmptyWeek(');
      expect(i, isNot(-1));
      final body = emptyStatesSrc.substring(i, i + 300);
      expect(body, contains('bool isFutureUngeneratedPhase'));
      expect(body, contains('int currentPhase'));
    });

    test('when locked, uses futurePhaseUnlockCopy and a lock icon — not the '
        'generic dumbbell "No workouts scheduled" copy', () {
      final i = emptyStatesSrc.indexOf('Widget _buildEmptyWeek(');
      final body = emptyStatesSrc.substring(i);
      expect(body, contains('futurePhaseUnlockCopy(currentPhase)'));
      expect(body, contains('Icons.lock_open_outlined'));
      // The old unconditional copy must still exist as the FALLBACK
      // (same-phase empty week, a separate and rarer case this fix does
      // not attempt to re-explain) — not deleted outright.
      expect(body, contains("'No workouts scheduled'"));
      expect(body, contains("'This week has no workouts in your plan.'"));
    });
  });
}
