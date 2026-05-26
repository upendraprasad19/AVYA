// test/contracts/no_top_level_duration_seconds_reads_test.dart
//
// Drift-fix batch 2026-05-24 / F2 workout (P1).
//
// `WorkoutWriteService` does NOT emit a top-level `duration_seconds`
// field on `exlog_*` rows — per-set duration lives at
// `sets[].duration_sec` only. Reading `log['duration_seconds']` at
// top level silently returns 0 for every modern row.
//
// This test pins that no file under lib/features/train/ reads
// `log['duration_seconds']` at top level. The canonical client-side
// derivation is `WorkoutReadService.bestPerSetDuration(log)`.
//
// (The cloud projection at sync_workout.dart writes the aggregate
// to `workout_log_exercises.duration_seconds` — that's for
// downstream analytics and is unrelated to client reads.)
//
// Scope evolution: drift-fix batch initially hardcoded 5 files
// (receipt, train_screen, train_provider, workout_repository,
// edit_workout_log_sheet). After merging onto main, `train_screen.dart`
// had been split into a sibling `train/` folder (commit 6ed2d9a) and
// the dead reads moved to `exercise_preview_sheet.dart` +
// `expanded_exercises.dart`. The hardcoded path-list approach was
// brittle to refactors; switched to recursive scan of
// `lib/features/train/` so future file moves can't hide regressions.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so explanatory
// comments about the old pattern don't false-positive.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no top-level log[duration_seconds] reads anywhere under lib/features/train/', () {
    final root = Directory('lib/features/train');
    expect(root.existsSync(), isTrue,
        reason: 'Expected directory to exist: lib/features/train');

    final pattern = RegExp(r"""log\s*\[\s*['"]duration_seconds['"]\s*\]""");
    final hits = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      // Skip test stubs / generated files if any land here accidentally.
      final relPath = entity.path.replaceAll('\\', '/');
      if (relPath.contains('/test/') || relPath.endsWith('.g.dart')) continue;

      final source = entity.readAsStringSync();
      final stripped = _stripComments(source);
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('$relPath:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Found ${hits.length} top-level duration_seconds read(s) '
          'under lib/features/train/. WriteService never emits this '
          'field at top level. Use '
          '`WorkoutReadService.bestPerSetDuration(log) ?? 0` instead. '
          'Hits:\n${hits.join('\n')}',
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
