@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 3 of 5: PAIRS, all 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip (the six injuries
// with the most v14 tags), 3 and 5 days, phase 1. See injury_sweep_b_singles_test.dart for the five blocks and
// test/helpers/injury_floor_sweep_lib.dart for the harness and gates. No day is thin (under 3 exercises) in any tier: this
// block used to be ratcheted at 2 scan days (shoulder + lower_back, bodyweight, beginner, OI-408) until Batch C1's rows.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  for (final tier in kSweepTiers) {
    test('pairs [$tier]: all 15 pairs, goals x levels x 3/5 days, phase 1', () {
      final sw = Stopwatch()..start();
      final t = h.runPairs(tier, const [3, 5]);
      h.report('pairs $tier', t, sw);
      expect(t.runs, 360);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
