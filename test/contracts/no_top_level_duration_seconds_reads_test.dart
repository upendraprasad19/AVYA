// test/contracts/no_top_level_duration_seconds_reads_test.dart
//
// Drift-fix batch 2026-05-24 / F2 workout (P1).
// REWRITTEN Unit 7 / OI-50 2026-08-02 (diagnose d4e7c2) — see below.
//
// THE CONTRACT (corrected 2026-08-02):
//   An `exlog_*` row's top-level `duration_seconds` is real, but only ONE
//   of its two writers emits it:
//     - WorkoutWriteService.logExercise  → NEVER (per-set `sets[].duration_sec`)
//     - the cloud-restore writer         → ALWAYS (sync_workout.dart:766), and
//       it writes `sets[]` only when the workout_log_sets join was non-empty
//   So a bare `log['duration_seconds']` read is wrong for modern rows, and
//   ignoring the field outright is wrong for restored rows. Exactly one place
//   is allowed to reconcile that: `WorkoutReadService`.
//
// WHY THIS TEST WAS REWRITTEN. Its previous failure message said:
//     "Use `WorkoutReadService.bestPerSetDuration(log) ?? 0` instead."
// That is the per-set MAX, and following it is what produced OI-50's second
// defect — the edit sheet used it for a TOTAL, so a restored multi-set timed
// row rendered blank and saving wiped the real duration to 0. A gate whose
// remediation advice reproduces the bug it guards is worse than no gate. The
// message now distinguishes the two semantics by name.
//
// Pick by SEMANTIC, not by habit:
//   - "best single set"  → WorkoutReadService.bestPerSetDuration(log)
//   - "total / cumulative" → WorkoutReadService.aggregateDurationSeconds(log)
//
// SCOPE. Previously `lib/features/train/` only, which is why the Unit 7 fix
// could legally reintroduce the read one directory away. Now also covers
// `lib/core/services/`, with two named exemptions, so the invariant is
// "only the canonical reader touches this field" rather than "not in the
// train folder".
//
// Scope history: the drift-fix batch hardcoded 5 file paths; after
// `train_screen.dart` was split into a sibling `train/` folder (6ed2d9a) the
// dead reads moved and the hardcoded list went blind, so it became a
// recursive scan.
//
// Strips block + line comments per
// feedback_source_grep_strip_comments_first.md so explanatory comments about
// the old pattern don't false-positive.

import 'dart:io';

import 'package:test/test.dart';

/// Directories scanned for a bare top-level `log['duration_seconds']` read.
const _scanRoots = <String>[
  'lib/features/train',
  'lib/core/services',
];

/// Files permitted to read the field directly, each for a stated reason.
/// Adding an entry here means adding a SECOND reconciliation of the
/// two-writer asymmetry — which is precisely the drift OI-50 was. Don't.
const _exempt = <String, String>{
  'lib/core/services/workout_read_service.dart':
      'THE canonical reader — bestPerSetDuration (per-set MAX, single-set '
          'fallback) and aggregateDurationSeconds (total, top-level fallback). '
          'Every other reader delegates here.',
  'lib/core/services/sync/sync_workout.dart':
      'Push projection for the `wlog_*` WORKOUT-LOG row, where a top-level '
          'duration_seconds is the correct and only shape. Not an exlog read.',
};

void main() {
  test('only WorkoutReadService reads top-level log[duration_seconds]', () {
    final pattern = RegExp(r"""log\s*\[\s*['"]duration_seconds['"]\s*\]""");
    final hits = <String>[];

    for (final rootPath in _scanRoots) {
      final root = Directory(rootPath);
      expect(root.existsSync(), isTrue,
          reason: 'Expected scan root to exist: $rootPath');

      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final relPath = entity.path.replaceAll('\\', '/');
        if (relPath.contains('/test/') || relPath.endsWith('.g.dart')) continue;
        if (_exempt.containsKey(relPath)) continue;

        final lines = _stripComments(entity.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            hits.add('$relPath:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Found ${hits.length} bare top-level duration_seconds read(s). '
          'Only WorkoutReadService may reconcile this field — the modern '
          'writer never emits it and the restore writer always does, so a '
          'bare read is wrong for one of them either way.\n'
          'Choose by SEMANTIC:\n'
          '  best single set  -> WorkoutReadService.bestPerSetDuration(log)\n'
          '  total/cumulative -> WorkoutReadService.aggregateDurationSeconds(log) ?? 0\n'
          'Picking bestPerSetDuration for a TOTAL is diagnose d4e7c2 (OI-50): '
          'it returns 0 for a restored multi-set row, and the edit sheet then '
          'wrote that 0 over the real duration.\n'
          'Hits:\n${hits.join('\n')}',
    );
  });

  test('every exemption names a file that still exists', () {
    for (final path in _exempt.keys) {
      expect(File(path).existsSync(), isTrue,
          reason: 'Stale exemption — $path no longer exists. Remove it, or '
              'the allow-list silently protects nothing.');
    }
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
