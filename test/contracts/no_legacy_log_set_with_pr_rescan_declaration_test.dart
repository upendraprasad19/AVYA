// test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
//
// Drift-fix batch 2026-05-24 / F5 workout (P2).
//
// Per APK Test #16.1, `WorkoutRepository.logSetWithPrRescan` was
// one of three rogue exlog_* key writers and was migrated off. With
// zero active callers (verified at deletion time), the method has
// been deleted.
//
// This test pins that the method declaration does not reappear.
//
// (The AI coach `logPR` tool that previously logged PRs was removed
// entirely on 2026-05-31 — PRs are derived from logSet's auto-rescan.
// See `test/contracts/derive_only_tool_surface_test.dart`.)
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so docstring-style
// references in surrounding deprecation comments don't trigger
// a false positive.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('logSetWithPrRescan method declaration is deleted from workout_repository', () {
    final file = File(
      'lib/features/train/repositories/workout_repository.dart',
    );
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final stripped = _stripComments(source);

    // Pattern: method declaration `Future<String> logSetWithPrRescan(`.
    final pattern = RegExp(
      r"""Future\s*<\s*String\s*>\s+logSetWithPrRescan\s*\(""",
    );

    expect(
      pattern.hasMatch(stripped),
      isFalse,
      reason: 'Found `logSetWithPrRescan` method declaration in '
          'workout_repository.dart. The legacy method was deleted '
          'in the 2026-05-24 drift-fix batch (F5). If reinstating, '
          'route through WorkoutWriteService.logExercise and update '
          'this test.',
    );
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
