import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// 7d3f0a — workout_log_exercises.reps is a CUMULATIVE (summed-across-sets)
/// total, NOT a per-set value. The cloud CHECK `wle_reps_realistic` must
/// therefore allow totals well above any single-set realism bound (60).
///
/// Surfaced by the 2026-05-31 year-simulation harness:
/// `WorkoutWriteService.logExercise` records
///   reps_completed = Σ set.reps           (cumulative)
/// and `SyncService._syncExerciseLogs` maps that straight into
///   workout_log_exercises.reps
/// The old CHECK capped reps at 60 (a per-SET bound), so any exercise
/// totaling > 60 reps (5×15 = 75, 3×25 bodyweight = 75) violated the
/// constraint with PostgrestException 23514. The catch swallowed it →
/// the per-exercise SUMMARY row silently never reached cloud, undercounting
/// high-volume exercises for AI snapshot / weekly report / analytics.
///
/// Fix = migration 080 widened the cap to reps <= 1000 (a single exercise
/// tops out ~10 sets × 60 = 600). Per-set realism stays on workout_log_sets.
///
/// This contract pins THREE things so the bug cannot silently regress:
///   1. The writer computes reps_completed as a CUMULATIVE sum (fold over
///      every set's reps) — not the first/max set.
///   2. The sync projection maps workout_log_exercises.reps from the
///      cumulative `reps_completed`, NOT a per-set reps field.
///   3. Migration 080 widened wle_reps_realistic to allow reps far above 60.
///
/// closes-diagnose: 2026-05-31-workout-log-exercises-cumulative-reps-constraint-7d3f0a
void main() {
  group('workout_log_exercises cumulative reps semantic (7d3f0a)', () {
    test('writer computes reps_completed as a cumulative sum over sets', () {
      final writerSrc =
          File('lib/core/services/workout_write_service.dart').readAsStringSync();

      // The canonical writer folds every merged set's reps into a single
      // total. The exact line (workout_write_service.dart:134):
      //   final totalReps = mergedSets.fold<int>(0, (a, s) => a + s.reps);
      final hasFold = RegExp(
        r'mergedSets\.fold<int>\(\s*0\s*,\s*\(a,\s*s\)\s*=>\s*a\s*\+\s*s\.reps\)',
      ).hasMatch(writerSrc);
      expect(
        hasFold,
        isTrue,
        reason:
            'WorkoutWriteService.logExercise must compute reps_completed as a '
            'CUMULATIVE fold over set.reps. If this drifts to a per-set value '
            '(e.g. sets.first.reps), the cloud reps column semantic changes '
            'and the wle_reps_realistic cap meaning flips. closes-diagnose: '
            '7d3f0a',
      );

      // And that cumulative total must be assigned to the canonical
      // reps_completed key in the persisted Hive map.
      expect(
        writerSrc.contains("'reps_completed': totalReps"),
        isTrue,
        reason:
            "persisted exlog map must set 'reps_completed' to the cumulative "
            'totalReps. The cloud projection reads this field directly.',
      );
    });

    test('sync projection maps cloud reps from cumulative reps_completed', () {
      final syncSrc = loadSyncServiceSource().readAsStringSync();

      // Scope to the workout_log_exercises upsert projection block so a
      // coincidental match elsewhere doesn't pass the test.
      final upsertMarker = "from('workout_log_exercises').upsert(";
      final upsertStart = syncSrc.indexOf(upsertMarker);
      expect(upsertStart, greaterThan(0),
          reason: 'workout_log_exercises upsert call must exist');
      final blockEnd = syncSrc.indexOf('}, onConflict:', upsertStart);
      expect(blockEnd, greaterThan(upsertStart));
      final projectionBlock = syncSrc.substring(upsertStart, blockEnd);

      expect(
        projectionBlock.contains("'reps': log['reps_completed']"),
        isTrue,
        reason:
            "workout_log_exercises.reps must be sourced from the cumulative "
            "log['reps_completed'] field — NOT a per-set reps value. This is "
            'the field whose cumulative semantic forced the wle_reps_realistic '
            'cap to be widened (migration 080). closes-diagnose: 7d3f0a',
      );
    });

    test('migration 080 widened wle_reps_realistic above the per-set cap', () {
      final migration = File(
        'supabase/migrations/080_relax_wle_reps_realistic_cumulative.sql',
      );
      expect(migration.existsSync(), isTrue,
          reason: 'migration 080 must exist (the schema fix for 7d3f0a)');

      final sql = migration.readAsStringSync();

      // The active (non-commented) ADD CONSTRAINT must allow reps up to 1000.
      // Strip the inline-rollback comment block (lines beginning with `--`)
      // so we only assert on the live DDL.
      final liveDdl = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');

      expect(
        liveDdl.contains('wle_reps_realistic'),
        isTrue,
        reason: 'migration must (re)create the wle_reps_realistic constraint',
      );
      expect(
        RegExp(r'reps\s*<=\s*1000').hasMatch(liveDdl),
        isTrue,
        reason:
            'the live ADD CONSTRAINT must allow cumulative totals (reps <= 1000). '
            'A reps <= 60 cap is the per-set bound that silently dropped '
            'high-volume summary rows. closes-diagnose: 7d3f0a',
      );
      expect(
        RegExp(r'reps\s*<=\s*60\b').hasMatch(liveDdl),
        isFalse,
        reason:
            'forbidden — the live constraint must NOT cap cumulative reps at 60 '
            '(that is the pre-080 per-set bound that caused the 23514 silent '
            'sync loss). The 0..60 form may only appear in the commented '
            'rollback block.',
      );
    });
  });
}
