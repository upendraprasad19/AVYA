// test/contracts/no_top_level_distance_km_reads_test.dart
//
// OI-389 Batch 1a (plan docs/plans/cardio-duration-distance.md U3): the km
// twin of no_top_level_duration_seconds_reads_test.dart.
//
// THE CONTRACT. An `exlog_*` row's km has two homes:
//   - per set, `sets[].distance_km` (logExercise, editLog, the move merge);
//   - top level, `distance_km` (the per-set total, a restored row with no
//     per-set list, or the OI-50 F5 shape where per-set entries lack km).
// Exactly one place reconciles them: WorkoutReadService.aggregateDistanceKm
// (per-set sum when > 0, else the top level, rounded to 0.001). A bare
// `log['distance_km']` read shows 0 for a modern row whose total the writer
// left off, or ignores per-set km a sheet edit or a merge wrote.
//
// Strips comments first (feedback_source_grep_strip_comments_first.md).

import 'dart:io';

import 'package:test/test.dart';

const _scanRoots = <String>[
  'lib/features/train',
  'lib/core/services',
];

const _exempt = <String, String>{
  'lib/core/services/workout_read_service.dart':
      'THE canonical reader (aggregateDistanceKm). Every other reader '
          'delegates here.',
  'lib/core/services/workout_write_service.dart':
      'The writer: it computes and writes the total (logExercise, editLog, '
          'the move merge); it never renders it.',
  'lib/core/services/sync/sync_workout.dart':
      'Summary push of the stored total to workout_log_exercises.distance_km '
          'and its restore; not a display read.',
};

void main() {
  test('only WorkoutReadService reads top-level log[distance_km]', () {
    final pattern = RegExp(r"""log\s*\[\s*['"]distance_km['"]\s*\]""");
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
      reason: 'Found ${hits.length} bare top-level distance_km read(s). Use '
          'WorkoutReadService.aggregateDistanceKm(log): per-set km first, '
          'then the top-level total (OI-389).\nHits:\n${hits.join('\n')}',
    );
  });

  test('every exemption names a file that still exists', () {
    for (final path in _exempt.keys) {
      expect(File(path).existsSync(), isTrue,
          reason: 'Stale exemption — $path no longer exists.');
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
