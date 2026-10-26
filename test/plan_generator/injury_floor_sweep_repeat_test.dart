@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep, block 5 of 5: REPEAT. Phase 1 is generated uninjured, then phase 2 with the injury and that plan's
// names pinned, at 3, 4, 5 and 6 days (the repeat-phase path, where a now-unsafe pin is dropped with no refill,
// exercise_selector.dart buildPinnedDays). See injury_floor_sweep_test.dart for the five blocks and
// test/helpers/injury_floor_sweep_lib.dart for the harness and gates.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  for (final tier in kSweepTiers) {
    test('repeat [$tier]: phase 1 uninjured, then phase 2 with the injury and those pins, 3/4/5/6 days', () {
      final sw = Stopwatch()..start();
      final t = h.runRepeat(tier, const [3, 4, 5, 6]);
      h.report('repeat $tier', t, sw);
      expect(t.runs, 432);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
