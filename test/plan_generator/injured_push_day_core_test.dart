@Timeout(Duration(minutes: 10))
library;

// Unit 1B-F, Ruling 6 (docs/plans/2026-11-10-generator-1bf-flip.md, founder d13): with the R6 refill deleted, a bodyweight
// shoulder + wrist user's Push-type days (Push, Push + Core, Upper Push, Push A / B) are built from core-pattern rows by
// the thin-day top-up's core pass: every press is contraindicated, so the day's own slots drop. Measured before code over
// the 15-pair grid (phases 1-3 and the repeat): 354 such days, none empty, every row a core row (Plank, Dead Bug, Hollow
// Body Hold, Russian Twist, ...). Pinned here on the real engine for phase 1 of every goal, level and day count.
//
// Mutated (diagnose doc): the thin-day top-up switched off (`disable_thin_day_topup`) leaves the Push days empty (red).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  test('shoulder + wrist, bodyweight: every Push-type day of weeks 1-2 is non-empty, core rows only, injury-safe', () {
    final rows = {
      for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>())
        r['name'] as String: r
    };
    List<String> strs(Object? v) => v is List ? [for (final x in v) '$x'] : const [];
    const injuries = ['shoulder', 'wrist'];
    var pushDays = 0;
    final bad = <String>[];
    for (final goal in kSweepGoals) {
      for (final level in kSweepLevels) {
        for (final days in const [3, 4, 5, 6]) {
          final p = h.gen(tier: 'bodyweight', goal: goal, level: level, days: days, phase: 1, injuries: injuries);
          for (final w in p.weekPlans.take(2)) {
            for (final d in w.workoutDays.where((d) => d.name.contains('Push'))) {
              pushDays++;
              final where = '$goal|$level|${days}d|w${w.weekNumber}|${d.name}';
              if (d.exercises.isEmpty) bad.add('empty: $where');
              for (final e in d.exercises) {
                final r = rows[e.exerciseName];
                if (r == null) {
                  bad.add('not a library row: $where ${e.exerciseName}');
                  continue;
                }
                final pattern = strs(r['movement_pattern']); // the overlays were copied in by seed v27 (Unit 1B-F2)
                if (!pattern.contains('core')) bad.add('not a core row: $where ${e.exerciseName} $pattern');
                if (strs(r['injury_contraindications']).any(injuries.contains)) {
                  bad.add('contraindicated: $where ${e.exerciseName}');
                }
              }
            }
          }
        }
      }
    }
    expect(pushDays, greaterThan(0), reason: 'non-vacuity: no Push-type day was built');
    expect(bad, isEmpty, reason: '${bad.length} violation(s) over $pushDays Push-type day-weeks');
  });
}
