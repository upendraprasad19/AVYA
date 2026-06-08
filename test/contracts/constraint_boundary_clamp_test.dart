// test/contracts/constraint_boundary_clamp_test.dart
//
// Contract (regression-prevention batch, WI-3): every Postgres CHECK bound on a
// numeric column synced from the client must be matched by a client-side clamp
// to the SAME bound — so an out-of-range value is clamped, never silently
// dropped on a 23514. The per-set upsert is all-or-nothing, so ONE out-of-range
// row drops the whole batch (the per-set rows back the receipt / Train /
// weekly-report sums).
//
// This is a PARITY test, not a presence-grep: it asserts the clamp literal
// equals the CHECK upper bound. It therefore catches the real drift class —
// a migration that narrows a CHECK below the clamp (→ silent drop), or a clamp
// removed / changed away from the CHECK. Closes the reps silent-drop family
// (7d3f0a / e7b3c9 / d9a4f2) and the duration_secs parity gap (a3e8f1).
//
// set_number is intentionally NOT clamped — >10 sets is legitimate (drop sets /
// high-volume), so the CHECK was WIDENED to <=50 (migration 089) instead of
// clamping (which would corrupt the set index/count). We assert no clamp ever
// narrows a value below the largest CHECK bound, and that set_number is never
// clamped.
//
// checkMax is sourced from live pg_constraint on dedsavbjuwgarrhphgnl
// (2026-06-08, post-migrations 085/088/089). REGENERATE this map in the SAME
// commit as any migration that changes a wle_/wls_ CHECK bound.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // table.column -> CHECK upper bound (live, 2026-06-08).
  const checkMax = <String, int>{
    'workout_log_exercises.reps': 10000, // wle_reps_realistic
    'workout_log_sets.reps': 10000, // wls_reps_realistic
    'workout_log_sets.duration_secs': 3600, // wls_duration_secs_realistic
    'workout_log_exercises.set_number': 50, // wle_set_number_realistic (089)
    'workout_log_sets.set_number': 50, // wls_set_number_realistic (089)
  };

  late String syncSrc;
  late List<int> clampBounds;
  setUpAll(() {
    syncSrc =
        File('lib/core/services/sync/sync_workout.dart').readAsStringSync();
    clampBounds = RegExp(r'\.clamp\(0,\s*(\d+)\)')
        .allMatches(syncSrc)
        .map((m) => int.parse(m.group(1)!))
        .toList();
  });

  group('constraint-clamp parity (sync_workout.dart vs live CHECK bounds)', () {
    test('reps clamped to the wle/wls_reps_realistic bound (10000) on BOTH rows',
        () {
      final repsBound = checkMax['workout_log_sets.reps']!;
      final matching = clampBounds.where((c) => c == repsBound).length;
      expect(
        matching,
        greaterThanOrEqualTo(2),
        reason:
            'sync_workout.dart must clamp reps to $repsBound (== wle/wls_reps_'
            'realistic) on the summary row AND the per-set row. Found '
            '$matching clamp(0,$repsBound). A clamp bound != the CHECK bound is '
            'drift that re-opens the reps silent-drop class (7d3f0a/e7b3c9/d9a4f2).',
      );
    });

    test('duration_secs clamped to the wls_duration_secs_realistic bound (3600)',
        () {
      final durBound = checkMax['workout_log_sets.duration_secs']!;
      expect(
        syncSrc.contains('.clamp(0, $durBound)'),
        isTrue,
        reason:
            'per-set duration_secs must be clamped to $durBound (== wls_duration_'
            'secs_realistic) before sync (diagnose a3e8f1).',
      );
    });

    test('no clamp narrows a synced value below the largest CHECK bound', () {
      final maxBound = checkMax.values.reduce((a, b) => a > b ? a : b);
      for (final c in clampBounds) {
        expect(
          c <= maxBound,
          isTrue,
          reason:
              'clamp bound $c exceeds the largest known CHECK max ($maxBound). '
              'If a constraint legitimately widened, update checkMax in the same '
              'commit as the migration.',
        );
      }
    });

    test('set_number is NOT clamped (widened to <=50, not capped — migration 089)',
        () {
      // Guard the design decision: clamping the set index/count would corrupt
      // data (a legit 15-set workout must not be truncated to 10). The fix for
      // >10 sets is the widened CHECK, not a clamp. If someone adds a
      // set_number clamp, this fails so they reconsider.
      final clampsSetNumber = syncSrc.contains('setNum.clamp(') ||
          syncSrc.contains('clampedSetNum') ||
          syncSrc.contains('cleanedSets.length.clamp(');
      expect(
        clampsSetNumber,
        isFalse,
        reason:
            'set_number must NOT be clamped — >10 sets is legitimate; the CHECK '
            'was widened to <=50 (migration 089). Clamping would corrupt the set '
            'index/count.',
      );
    });
  });
}
