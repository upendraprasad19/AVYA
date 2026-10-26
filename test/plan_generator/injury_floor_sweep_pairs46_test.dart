@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 4 of 5: PAIRS, the same 15 pairs as injury_floor_sweep_pairs_test.dart, 4 and 6 days, phase 1.
// See injury_floor_sweep_test.dart for the five blocks and test/helpers/injury_floor_sweep_lib.dart for the harness and gates.
// No day is thin (under 3 exercises) in any tier: this block used to be ratcheted at 6 scan days (the 6-day plans of
// shoulder + lower_back, bodyweight, beginner, OI-408) until Batch C1's rows.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  for (final tier in kSweepTiers) {
    test('pairs 4/6 days [$tier]: all 15 pairs, goals x levels x 4/6 days, phase 1', () {
      final sw = Stopwatch()..start();
      final t = h.runPairs(tier, const [4, 6]);
      h.report('pairs46 $tier', t, sw);
      expect(t.runs, 360);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
