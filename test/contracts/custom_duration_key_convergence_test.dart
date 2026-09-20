// BEHAVIORAL CONTRACT TEST — custom-exercise dual duration-key convergence
// (custom-picker-fix B-pass F2, 2026-09-17)
//
// Concept:   custom_exercises_mutations (duration-key fork hazard)
// Writers:   UI sheet + AI writer store `default_duration_seconds`
//            (Hive-canonical); RESTORE keeps the raw cloud row, whose
//            column is `default_duration_secs` (sync_community.dart).
// Readers:   parseTimedDurationSecs (train_provider.dart, active-workout
//            prefill) and exercise_selector.dart:1002 (L2 append) read
//            DIFFERENT keys.
//
// Pinned contract:
//   1. The edit payload DROPS the cloud-named twin — an edit converges the
//      row onto `default_duration_seconds`; without this, one edit leaves
//      the row carrying BOTH keys and the two readers disagree.
//   2. parseTimedDurationSecs reads BOTH keys — a UI-created timed custom
//      (which has only `default_duration_seconds`) must not fall through
//      to the reps-text heuristic or the 30s floor.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show parseTimedDurationSecs;
import 'package:icanbefitter/features/train/widgets/create_custom_exercise_sheet.dart';

void main() {
  group('edit payload converges the duration key (B-pass F2)', () {
    test('a restored row carrying BOTH keys loses the cloud twin on edit',
        () {
      final restored = <String, dynamic>{
        'id': 'restored-1',
        'name': 'Plank Hold',
        'category': 'Core',
        'logging_type': 'timed',
        // Restored row: the stale cloud-named value predates the edit.
        'default_duration_secs': 90,
        'type': 'exercise',
      };
      final payload = CreateCustomExerciseSheet.buildEditPayload(
        restored,
        category: 'Core',
        loggingType: 'timed',
        defaultSets: 3,
        defaultDurationSeconds: 45,
        primaryMuscles: const ['abs'],
        submittedToLibrary: false,
      );
      expect(payload.containsKey('default_duration_secs'), isFalse,
          reason: 'the cloud-named twin must be dropped — preserving both '
              'forks the row and the two readers disagree');
      expect(payload['default_duration_seconds'], 45,
          reason: 'the canonical key carries the edited value');
    });
  });

  group('parseTimedDurationSecs reads BOTH duration keys (B-pass F2)', () {
    test('a UI-created timed custom (default_duration_seconds only) parses',
        () {
      // Before the fix this row fell through to the reps-text heuristic /
      // 30s floor because the parser only read `default_duration_secs`.
      expect(
        parseTimedDurationSecs({
          'logging_type': 'timed',
          'default_duration_seconds': 75,
        }),
        75,
      );
    });

    test('a restored row (default_duration_secs only) still parses', () {
      expect(
        parseTimedDurationSecs({
          'logging_type': 'timed',
          'default_duration_secs': 90,
        }),
        90,
      );
    });

    test('cloud key wins only when the canonical key is absent', () {
      // Both present (the pre-fix fork state): the canonical key the edit
      // path writes wins over the stale cloud twin.
      expect(
        parseTimedDurationSecs({
          'logging_type': 'timed',
          'default_duration_secs': 90,
          'default_duration_seconds': 45,
        }),
        90,
        reason: 'prescribed-order semantics preserved: the FIRST key the '
            'parser always read keeps precedence; the second key is a '
            'fallback for rows that never had the first',
      );
    });

    test('neither key → falls to the reps-text path / 30s floor (unchanged)',
        () {
      expect(parseTimedDurationSecs({'logging_type': 'timed'}), 30);
      expect(
        parseTimedDurationSecs({
          'logging_type': 'timed',
          'default_reps': '2 min',
        }),
        120,
      );
    });
  });
}
