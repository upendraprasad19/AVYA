import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Comment-stripped source-grep (feedback_source_grep_strip_comments_first) so a
// commented-out reference never satisfies (or breaks) an assertion.
String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Pins the two-Phase-1 display fix (diagnose a3f8c1): the week selector derives
/// phase labels from the real current_phase (single SoT) instead of hardcoding
/// PHASE I/II/III.
void main() {
  final sel = _strip(
      File('lib/features/train/widgets/week_selector.dart').readAsStringSync());
  final screen = _strip(
      File('lib/features/train/screens/train/screen.dart').readAsStringSync());

  group('week selector reads current_phase', () {
    test('WeekSelector exposes a currentPhase parameter', () {
      expect(sel.contains('this.currentPhase'), isTrue);
    });

    test('forward phase labels derive from current_phase, not hardcoded', () {
      expect(sel.contains('_phaseRoman(widget.currentPhase'), isTrue);
      // No hardcoded forward-group label literals may remain.
      expect(sel.contains("label: 'PHASE I'"), isFalse);
      expect(sel.contains("label: 'PHASE II'"), isFalse);
      expect(sel.contains("label: 'PHASE III'"), isFalse);
    });

    test('train screen passes the real plan.phase', () {
      expect(screen.contains('currentPhase: plan.phase'), isTrue);
    });

    test('past phases come from the shared bucketing SoT, not a local re-walk',
        () {
      // UPDATED 2026-08-09 (diagnose c9e4b7): the selector now goes through the
      // DISPLAY wrapper. `pastPhaseBlocksForDisplay` still delegates to the
      // strict `pastPhaseBlocks()` for its primary path — the recovery is a
      // fallback, not a replacement — so the point this test pins is unchanged:
      // the selector must NOT re-bucket schedule_* itself, because that is how
      // it drifts from PhaseProgressReconciler.
      //
      // Matching the prefix rather than the exact old string keeps this green
      // for either name while still failing if the selector goes back to
      // walking the box directly.
      expect(sel.contains('pastPhaseBlocks'), isTrue);
      expect(
        sel.contains('pastPhaseBlocksForDisplay('),
        isTrue,
        reason: 'the selector reads the display wrapper (c9e4b7); the strict '
            'pastPhaseBlocks() is reserved for the reconciler, whose '
            'monotonic advance is unrecoverable if over-fed.',
      );
      // Assert on the actual anti-pattern — WALKING the box — not on the
      // `schedule_` string. The widget legitimately parses a date out of a
      // schedule key it was handed (`_labelFor`, week_selector.dart:647), and
      // a targeted `.get('wlog_…')` is fine too. What must not come back is
      // `workoutBox.toMap()` iteration, which is how the widget would drift
      // from the shared bucketing SoT.
      expect(
        sel.contains('workoutBox.toMap()'),
        isFalse,
        reason: 'the widget must not re-walk workoutBox — that is the SoT\'s '
            'job (_scheduleRowsBefore).',
      );
    });
  });
}
