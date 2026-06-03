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

    test('past phases come from the shared pastPhaseBlocks() SoT', () {
      expect(sel.contains('pastPhaseBlocks()'), isTrue);
    });
  });
}
