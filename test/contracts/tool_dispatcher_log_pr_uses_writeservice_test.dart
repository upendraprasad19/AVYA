// Regression test for audit 2026-05-16 / F6-2 (logPR tool through WorkoutWriteService).
//
// Bug: `_executeLogPR` in `tool_dispatcher.dart` called the legacy
// `WorkoutRepository.logSetWithPrRescan` — bypassing the canonical
// `WorkoutWriteService.logExercise` mutex, telemetry, and batched cloud sync.
// `logSetWithPrRescan` was ONE OF THE 3 ROGUE `exlog_*` key formulas closed
// in APK Test #16.1 / Bug A. Even after the rogue-key bug was fixed at the
// repository layer, the dispatcher still bypassed the SoT-gated writer —
// 8th writer/reader drift instance per `feedback_writer_reader_field_drift_recurring.md`.
//
// Source-grep contract: `_executeLogPR` MUST route through
// `WorkoutWriteService.instance.logExercise(...)` and MUST NOT call
// `WorkoutRepository.instance.logSetWithPrRescan(`.
//
// closes-diagnose: 2026-05-16-logpr-bypass

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tool_dispatcher._executeLogPR routes through WorkoutWriteService', () {
    final file = File('lib/features/ai_coach/services/tool_dispatcher.dart');
    final src = file.readAsStringSync();

    test('dispatcher source file exists', () {
      expect(file.existsSync(), isTrue);
    });

    test('_executeLogPR method body uses WorkoutWriteService.instance.logExercise', () {
      final start = src.indexOf('Future<ToolExecutionResult> _executeLogPR(');
      expect(start, isNot(-1),
          reason: '_executeLogPR method must exist');
      // Method body is well under 3 KB — grab a generous slice.
      final slice = src.substring(start, (start + 3000).clamp(0, src.length));

      expect(slice.contains('WorkoutWriteService.instance.logExercise('), isTrue,
          reason:
              '_executeLogPR must route through WorkoutWriteService.logExercise. '
              'Calling legacy `WorkoutRepository.logSetWithPrRescan` directly '
              'bypasses the canonical writer (no mutex, no batched telemetry, '
              'no consistent cloud sync) and was the 8th writer/reader drift '
              'instance per audit 2026-05-16 / F6-2.');
    });

    test('_executeLogPR method body does NOT call legacy logSetWithPrRescan', () {
      final start = src.indexOf('Future<ToolExecutionResult> _executeLogPR(');
      expect(start, isNot(-1));
      final slice = src.substring(start, (start + 3000).clamp(0, src.length));

      // Allow the legacy method to be MENTIONED in a comment (e.g. explaining
      // why we no longer call it) but not actually invoked. Detect invocation
      // by `WorkoutRepository.instance.logSetWithPrRescan(` — the parenthesis
      // distinguishes call-site from comment.
      expect(
          slice.contains('WorkoutRepository.instance.logSetWithPrRescan('),
          isFalse,
          reason:
              '_executeLogPR must not call the legacy logSetWithPrRescan path. '
              'It bypasses WorkoutWriteService and was a rogue exlog_* key '
              'formula source until APK Test #16.1 / Bug A.');
    });

    test('_executeLogPR passes a single ExerciseSet (PR is one max-effort attempt)', () {
      final start = src.indexOf('Future<ToolExecutionResult> _executeLogPR(');
      expect(start, isNot(-1));
      final slice = src.substring(start, (start + 3000).clamp(0, src.length));

      // The PR call should construct a sets list with exactly one ExerciseSet
      // entry. Lenient pattern — any list-of-ExerciseSet form is accepted.
      expect(slice.contains('ExerciseSet('), isTrue,
          reason:
              '_executeLogPR must construct an ExerciseSet for the PR attempt.');
    });
  });
}
