@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 2 of 5: SINGLES, 4 and 6 days, phase 1. See injury_floor_sweep_test.dart for the five blocks
// and test/helpers/injury_floor_sweep_lib.dart for the harness and gates.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  for (final tier in kSweepTiers) {
    test('singles 4/6 days [$tier]: 9 injuries x goals x levels x 4/6 days x phase 1', () {
      final sw = Stopwatch()..start();
      final t = h.runSingles(tier, const [4, 6], const [1]);
      h.report('singles46 $tier', t, sw);
      expect(t.runs, 216);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
