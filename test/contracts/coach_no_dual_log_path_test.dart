// test/contracts/coach_no_dual_log_path_test.dart
//
// audit-fixwave 2026-07-02 / F1 + F2 — structural gates for the coach
// dual-path double-log (F1) and the food false-success card (F2). Source is
// COMMENT-STRIPPED first so a fix described only in a comment cannot satisfy
// the gate (feedback_source_grep_strip_comments_first). Behavioral coverage
// lives in coach_single_confirm_per_log_intent_test.dart +
// dispatched_card_filter_test.dart; these gates guard against a future edit
// re-opening the dual-path or reverting the food-result honoring.
//
// closes-diagnose: a1d7c3

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final provider = _strip(File(
          'lib/features/ai_coach/providers/ai_coach_provider.dart')
      .readAsStringSync());
  final handler = _strip(File(
          'lib/features/ai_coach/services/conversational_log_handler.dart')
      .readAsStringSync());

  group('F1 — coach dual-log routing dedup', () {
    test('every addActions call site passes coverage', () {
      final calls = RegExp(r'\.addActions\(').allMatches(provider).length;
      final passed = RegExp(r'coverage:').allMatches(provider).length;
      expect(calls, greaterThanOrEqualTo(3),
          reason: 'expected at least the 3 known addActions call sites');
      expect(passed, greaterThanOrEqualTo(calls),
          reason: 'every addActions(...) call MUST pass a TypedLogCoverage so a '
              'legacy log card covered by a typed intent is dropped (F1). A new '
              'call site without it re-opens the double-log. '
              'calls=$calls passed=$passed');
    });

    test('addActions is exercise-NAME aware (keeps partially-covered drafts)', () {
      // B-pass fix — suppress only when EVERY draft exercise is covered, so a
      // partial multi-exercise draft is kept (no exercise lost).
      expect(provider.contains('fullyCovered'), isTrue,
          reason: 'draft suppressed only when fully covered by log_set intents');
      expect(provider.contains('workoutExerciseNames'), isTrue);
      expect(provider.contains('cov.foodCovered'), isTrue,
          reason: 'log_food dropped when a log_meal_by_text intent covers it');
    });

    test('typedLogCoverage resolves the two typed log tools', () {
      expect(provider.contains("'log_set'"), isTrue);
      expect(provider.contains("'log_meal_by_text'"), isTrue);
      expect(provider.contains('_resolveExerciseNameForDedup'), isTrue,
          reason: 'log_set exerciseId is resolved to a name for coverage');
    });
  });

  group('F2 — coach food log honors the write result', () {
    test('_logFood returns the logFood result success, not a bare true', () {
      final m = RegExp(
              r'Future<bool> _logFood\([^)]*\) async \{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(handler);
      expect(m, isNotNull, reason: '_logFood method body not found');
      final body = m!.group(1)!;
      expect(body.contains('return r.success'), isTrue,
          reason: '_logFood must return the logFood WriteResult.success — a '
              'bare `return true` reports success even on a failed write (the '
              'false "✓ Logged" card, F2)');
      expect(RegExp(r'return\s+true\s*;').hasMatch(body), isFalse,
          reason: '_logFood must NOT unconditionally return true after logFood');
    });
  });
}
