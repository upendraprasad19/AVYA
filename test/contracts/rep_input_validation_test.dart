import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bug E — reps input validation + bounds.
///
/// Pre-fix: active_workout_screen accepted any int into the reps field.
/// Founder's May 7 bulk-completion had 3 rows with set_number=15 +
/// reps=110-150 (aggregate values mistyped into per-set fields). They
/// resurfaced as "LAST: 50KG · 135 REPS" above today's Leg Extension
/// entry, completely confusing the founder.
///
/// Fix — two layers:
///   1. Cloud: migration 060 adds CHECK (reps BETWEEN 0 AND 60) and
///      CHECK (set_number BETWEEN 0 AND 10) on workout_log_exercises.
///      The cloud is the canonical defender — any write violating these
///      bounds 23514s.
///   2. Client: active_workout_screen._validateRepsBound (called from
///      _validateSetInputs for weight_reps / bodyweight_reps /
///      weighted_bodyweight) surfaces the bound inline so the user sees
///      "Reps must be ≤ 60 per set. Typo?" instead of a confusing sync
///      failure later.
///
/// closes-diagnose: 2026-05-12-rep-validation-e6a2d4
void main() {
  late String activeWorkoutSrc;
  late String migrationSrc;

  setUpAll(() {
    activeWorkoutSrc =
        File('lib/features/train/screens/active_workout_screen.dart')
            .readAsStringSync();
    migrationSrc = File(
            'supabase/migrations/060_workout_log_exercises_realistic_bounds.sql')
        .readAsStringSync();
  });

  group('Layer 1 — cloud CHECK constraints (migration 060)', () {
    test('migration 060 SQL file exists with reps + set_number bounds', () {
      expect(
        migrationSrc.contains('wle_reps_realistic') &&
            migrationSrc.contains('reps BETWEEN 0 AND 60'),
        isTrue,
        reason:
            'migration 060 must add wle_reps_realistic CHECK constraint '
            'bounding reps to [0, 60]. closes-diagnose: '
            '2026-05-12-rep-validation-e6a2d4',
      );
      expect(
        migrationSrc.contains('wle_set_number_realistic') &&
            migrationSrc.contains('set_number BETWEEN 0 AND 10'),
        isTrue,
        reason:
            'migration 060 must add wle_set_number_realistic CHECK '
            'constraint bounding set_number to [0, 10].',
      );
    });
  });

  group('Layer 2 — client _validateRepsBound', () {
    test('_repsMin + _repsMax constants present', () {
      expect(
        activeWorkoutSrc.contains('static const int _repsMin = 1;') &&
            activeWorkoutSrc.contains('static const int _repsMax = 60;'),
        isTrue,
        reason:
            'active_workout_screen must declare _repsMin and _repsMax '
            'constants so the bound is named + easy to align with cloud '
            'CHECK constraint values.',
      );
    });

    test('_validateRepsBound method exists', () {
      expect(
        activeWorkoutSrc.contains('String? _validateRepsBound(int reps)'),
        isTrue,
        reason:
            'active_workout_screen must define _validateRepsBound(int reps) '
            'so weight_reps / bodyweight_reps / weighted_bodyweight share '
            'the same bound check (DRY).',
      );
    });

    test('_validateRepsBound rejects values above _repsMax with clear copy',
        () {
      expect(
        activeWorkoutSrc.contains('Reps must be ≤ \$_repsMax per set'),
        isTrue,
        reason:
            'when reps > _repsMax, error message must include the bound + '
            'hint at typo so user understands why the input is rejected.',
      );
    });

    test('all 3 reps-bearing logging types route through _validateRepsBound',
        () {
      // weight_reps, bodyweight_reps, weighted_bodyweight all use reps.
      // Each should call _validateRepsBound in _validateSetInputs.
      final marker = 'String? _validateSetInputs(int setIdx) {';
      final start = activeWorkoutSrc.indexOf(marker);
      expect(start, greaterThan(0));
      final end = (start + 2500).clamp(0, activeWorkoutSrc.length);
      final body = activeWorkoutSrc.substring(start, end);
      // Count occurrences of _validateRepsBound — should be at least 3
      // (or 4 if combined paths use it once each).
      final occurrences = RegExp(r'_validateRepsBound\(').allMatches(body).length;
      expect(occurrences >= 3, isTrue,
          reason:
              '_validateSetInputs must route weight_reps / bodyweight_reps '
              '/ weighted_bodyweight through _validateRepsBound. Found '
              '$occurrences references; need ≥3.');
    });
  });
}
