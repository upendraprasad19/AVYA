@Timeout(Duration(minutes: 10))
library;

// Injury floor sweep, block 6 (Unit 1B-F, Ruling 8, founder d23, docs/plans/2026-11-10-generator-1bf-flip.md): the PINNED
// REPEAT over the 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip at 30 MINUTES, beginner only (where the flip's
// 30-minute thin repeat days sit: 301 of 336), every goal and 3-6 days. The pins are the uninjured phase-1 plan at the
// same length. 240 runs per tier plus 16 pin plans. Gates and harness: test/helpers/injury_floor_sweep_lib.dart; its
// thin and one-exercise ceilings (`f_repeat_pairs30 <tier>`) are recorded on the final tree, owned by OI-452 (d23).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/injury_floor_sweep_lib.dart';

void main() {
  final h = SweepHarness.install();

  for (final tier in kSweepTiers) {
    test('repeat pairs at 30 minutes [$tier]: all 15 pairs, goals x beginner x 3-6 days, phase 2 pinned', () {
      final sw = Stopwatch()..start();
      final t = h.runRepeatPairs(tier, minutes: 30);
      h.report('f_repeat_pairs30 $tier', t, sw);
      expect(t.runs, 240);
      h.expectSafe(t);
      h.expectNoThin(t);
    });
  }
}
