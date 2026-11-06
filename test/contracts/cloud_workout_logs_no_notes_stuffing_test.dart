// test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart
//
// Drift-fix batch 2026-05-25 / F3 workout (P2).
//
// Pre-fix sync_workout.dart stuffed `log['id']` into the cloud
// `workout_logs.notes` column. `log['id']` is never set by
// `WorkoutWriteService` — the projection wrote NULL for every
// modern row, and the comment "store local ID for reference"
// described dead intent.
//
// This test pins that the `workout_logs` upsert projection block
// in sync_workout.dart does NOT contain `'notes': log[`.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('sync_workout.dart does not stuff log[id] into notes', () {
    final file = File('lib/core/services/sync/sync_workout.dart');
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final stripped = _stripComments(source);

    // Disallow:
    //   'notes': log['id']
    //   'notes': log["id"]
    //   "notes": log['id']
    final patterns = <RegExp>[
      RegExp(r"""['"]notes['"]\s*:\s*log\s*\[\s*['"]id['"]\s*\]"""),
    ];

    final hits = <String>[];
    final lines = stripped.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final p in patterns) {
        if (p.hasMatch(lines[i])) {
          hits.add('sync_workout.dart:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Found ${hits.length} site(s) stuffing log[id] into '
          'workout_logs.notes. Remove the projection — the field is '
          'dead. Hits:\n${hits.join('\n')}',
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
