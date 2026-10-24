// test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
//
// Drift-fix batch 2026-05-24 / F1 workout (P1).
//
// Per docs/architecture/sync.md Hive field-name contract: `reps_completed` on
// `exlog_*` is SUM across sets (writer contract). The AI coach PR
// snapshot was reading it as if it were per-set reps, producing
// nonsense like "PR: 100kg x 28 reps" for a 4-set workout.
//
// Fix (founder-locked decision): find the set within `sets[]` whose
// `weight_kg` matches the PR weight (max across sets), report THAT
// set's reps. Legacy rows lacking `sets[]` fall through to
// `reps_completed` (best effort).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  group('PR snapshot uses PR-set reps (not SUM)', () {
    test('finds the set matching PR weight and reports its reps', () {
      // Exlog shape from WorkoutWriteService — pyramid pattern.
      // PR weight = 100 (max). Set #3 hit 100 x 5 → THAT is the PR set.
      final exlog = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'date': '2026-05-24',
        'is_pr': true,
        'weight_kg': 100, // PR weight (max across sets)
        'reps_completed': 28, // SUM: 10+8+5+5 = 28
        'sets': [
          {'weight_kg': 60, 'reps': 10},
          {'weight_kg': 80, 'reps': 8},
          {'weight_kg': 100, 'reps': 5}, // PR set
          {'weight_kg': 100, 'reps': 5},
        ],
      };

      final reps = AiCoachRepository.prSetRepsForExlog(exlog);
      expect(reps, 5,
          reason: 'PR set reps should be 5 (the reps at PR weight 100), '
              'not 28 (SUM across sets) nor 10 (first set). '
              'Got $reps.');
    });

    test('falls through to reps_completed for legacy rows without sets[]', () {
      final legacyExlog = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'date': '2024-01-01',
        'is_pr': true,
        'weight_kg': 100,
        'reps_completed': 5,
        // No `sets[]` field — pre-Test-#6 row.
      };

      final reps = AiCoachRepository.prSetRepsForExlog(legacyExlog);
      expect(reps, 5,
          reason: 'Legacy rows without sets[] should fall through to '
              'reps_completed. Got $reps.');
    });

    test('handles empty sets[] gracefully', () {
      final degenerate = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 100,
        'reps_completed': 5,
        'sets': [],
      };

      final reps = AiCoachRepository.prSetRepsForExlog(degenerate);
      expect(reps, 5,
          reason: 'Empty sets[] should fall through to reps_completed.');
    });

    test('returns null when neither sets[] nor reps_completed has data', () {
      final empty = <String, dynamic>{
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 100,
      };

      final reps = AiCoachRepository.prSetRepsForExlog(empty);
      expect(reps, isNull,
          reason: 'No data sources → null, not 0 (so downstream can '
              'differentiate "missing" from "zero reps").');
    });
  });
}
