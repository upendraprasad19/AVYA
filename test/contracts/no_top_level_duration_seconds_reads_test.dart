// test/contracts/no_top_level_duration_seconds_reads_test.dart
//
// Drift-fix batch 2026-05-24 / F2 workout (P1).
//
// `WorkoutWriteService` does NOT emit a top-level `duration_seconds`
// field on `exlog_*` rows — per-set duration lives at
// `sets[].duration_sec` only. Reading `log['duration_seconds']` at
// top level silently returns 0 for every modern row.
//
// This test pins that the receipt, train_screen, train_provider,
// workout_repository, and edit_workout_log_sheet do NOT read
// `log['duration_seconds']` at top level. The canonical client-side
// derivation is `WorkoutReadService.bestPerSetDuration(log)`.
// (The cloud projection at sync_workout.dart writes the aggregate
// to `workout_log_exercises.duration_seconds` — that's for
// downstream analytics and is unrelated to client reads.)
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so explanatory
// comments about the old pattern don't false-positive.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('No top-level duration_seconds reads in client', () {
    test('workout_receipt_card.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/widgets/workout_receipt_card.dart',
      );
    });

    test('train_screen.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/screens/train_screen.dart',
      );
    });

    test('train_provider.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/providers/train_provider.dart',
      );
    });

    test('workout_repository.dart does not read log[duration_seconds]', () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/repositories/workout_repository.dart',
      );
    });

    test('edit_workout_log_sheet.dart does not read log[duration_seconds]',
        () {
      _assertNoTopLevelDurationRead(
        'lib/features/train/widgets/edit_workout_log_sheet.dart',
      );
    });
  });
}

void _assertNoTopLevelDurationRead(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue,
      reason: 'Expected file to exist: $relPath');

  final source = file.readAsStringSync();
  final stripped = _stripComments(source);

  // Patterns that read `log['duration_seconds']` or
  // `log["duration_seconds"]` at top level.
  final patterns = <RegExp>[
    RegExp(r"""log\s*\[\s*['"]duration_seconds['"]\s*\]"""),
  ];

  final hits = <String>[];
  final lines = stripped.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final p in patterns) {
      if (p.hasMatch(lines[i])) {
        hits.add('$relPath:${i + 1}: ${lines[i].trim()}');
      }
    }
  }

  expect(
    hits,
    isEmpty,
    reason: 'Found ${hits.length} top-level duration_seconds read(s) '
        'in $relPath. WriteService never emits this field at top '
        'level. Use `WorkoutReadService.bestPerSetDuration(log) ?? 0` '
        'instead. Hits:\n${hits.join('\n')}',
  );
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
